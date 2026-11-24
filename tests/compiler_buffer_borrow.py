#!/usr/bin/env python3
"""Check scoped typed buffers using a compiler built from compiler/volt_main.volt."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
VOLT = Path(os.environ.get("VOLT_COMPILER", ROOT / "volt")).resolve()


class BufferBorrow(unittest.TestCase):
    def invoke(self, source, *, run=True, use_borrow=True):
        with tempfile.TemporaryDirectory(prefix="volt-buffer-borrow-", dir=ROOT) as tmp:
            path = Path(tmp) / "main.volt"
            path.write_text(("use borrow_buffer\n\n" if use_borrow else "") + source, encoding="utf-8")
            args = ["--run"] if run else ["-o", path.with_suffix("")]
            return subprocess.run([VOLT, path, *args], cwd=ROOT, text=True, capture_output=True,
                                  env={**os.environ, "TMPDIR": tmp}, timeout=15)

    def assert_runs(self, source, stdout, *, use_borrow=True):
        result = self.invoke(source, use_borrow=use_borrow)
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, stdout, ""))

    def assert_rejected(self, source, diagnostic):
        result = self.invoke(source, run=False)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertRegex(result.stderr, r"main\.volt:\d+: ошибка: ")
        self.assertIn(diagnostic, result.stderr)

    def test_readers_block_all_writes_through_owner_aliases(self):
        self.assert_runs('''struct Record:
    tag: u8
    weight: i64

fn set_alias(alias: BorrowBuffer<Record>, record: Record) -> i64:
    return borrow_buffer_set(alias, 0, record)

let initial = [Record(1, 12), Record(2, 30)]
let owner = borrow_buffer_new(initial[0..2])
let alias = owner
let replacement = Record(3, 42)
if true:
    let first = borrow_buffer_read(owner)
    defer print(buffer_read_get(first, 1).weight)
    if true:
        let second = borrow_buffer_read(alias)
        let record = buffer_read_get(second, 0)
        print(buffer_read_len(first), buffer_read_len(second), record.tag, record.weight)
        record.weight = -1
        print(borrow_buffer_reserve(owner, 4096), borrow_buffer_push(alias, replacement))
        print(set_alias(alias, replacement), borrow_buffer_drop(alias))
    print(borrow_buffer_drop(owner), buffer_read_get(first, 0).weight)
print(borrow_buffer_reserve(alias, 4096), set_alias(alias, replacement), borrow_buffer_push(alias, replacement))
if true:
    let view = borrow_buffer_read(alias)
    print(borrow_buffer_len(owner), buffer_read_get(view, 0).weight)
    print(buffer_read_get(view, 1).weight, buffer_read_get(view, 2).weight)
print(borrow_buffer_drop(owner), borrow_buffer_len(alias), borrow_buffer_drop(alias))
''', "2 2 1 12\n-16 -16\n-16 -16\n-16 12\n30\n0 0 0\n3 42\n30 42\n0 -9 -9\n")

    def test_acquisition_captures_handle_instead_of_owner_binding(self):
        self.assert_runs('''let initial = [11, 22]
let owner = borrow_buffer_new(initial[0..1])
let alias = owner
let replacement = borrow_buffer_new(initial[1..2])
if true:
    let view = borrow_buffer_read(owner)
    let second = borrow_buffer_read(alias)
    owner = replacement
    print(borrow_buffer_drop(owner), borrow_buffer_drop(alias))
    print(buffer_read_get(view, 0), buffer_read_get(second, 0))
print(borrow_buffer_drop(alias))
''', "0 -16\n11 11\n0\n")

    def test_cleanup_on_continue_break_return_and_propagation(self):
        self.assert_runs('''fn count<T>(owner: BorrowBuffer<T>) -> i64:
    let view = borrow_buffer_read(owner)
    return buffer_read_len(view)

fn stop() -> Result<i64, i32>:
    return Err(7 as i32)

fn propagate(owner: BorrowBuffer<i64>) -> Result<i64, i32>:
    let view = borrow_buffer_read(owner)
    defer print(buffer_read_get(view, 0))
    let answer = stop()?
    return Ok(answer)

let initial = [42]
let owner = borrow_buffer_new(initial[0..1])
defer print(borrow_buffer_drop(owner))
for i in 0..3:
    let view = borrow_buffer_read(owner)
    if i == 0: continue
    break
print(borrow_buffer_push(owner, 7), count(owner), borrow_buffer_reserve(owner, 4096))
match propagate(owner):
    Ok(value): panic("expected error")
    Err(error): print(error)
print(borrow_buffer_set(owner, 0, 9))
''', "0 2 0\n42\n7\n0\n0\n")

    def test_loop_exits_only_clean_up_loans_in_exited_blocks(self):
        self.assert_runs('''let initial = [42]
let owner = borrow_buffer_new(initial[0..1])
if true:
    let view = borrow_buffer_read(owner)
    for i in 0..4:
        if i == 0: continue
        let view = borrow_buffer_read(owner)
        defer print(i, buffer_read_get(view, 0), borrow_buffer_drop(owner))
        if i == 1: continue
        break
    print(buffer_read_get(view, 0), borrow_buffer_drop(owner))
print(borrow_buffer_drop(owner))
''', "1 42 -16\n2 42 -16\n42 -16\n0\n")

    def test_option_propagation_before_and_after_generic_acquisition(self):
        self.assert_runs('''fn count<T>(owner: BorrowBuffer<T>, before: Option<i64>, after: Option<i64>) -> Option<i64>:
    defer print("released", borrow_buffer_reserve(owner, 2))
    let start = before?
    let view = borrow_buffer_read(owner)
    defer print("reading", buffer_read_len(view), borrow_buffer_drop(owner))
    let end = after?
    return Some(buffer_read_len(view) + start + end)

let initial = [42]
let bytes: [1]u8 = [7]
let owner = borrow_buffer_new(initial[0..1])
let byte_owner = borrow_buffer_new(bytes[0..1])
let missing: Option<i64> = None
let skipped = count(owner, missing, Some(0))
let stopped = count(byte_owner, Some(0), missing)
let finished = count(owner, Some(1), Some(2))
match finished:
    Some(value): print(value)
    None: panic("expected result")
print(borrow_buffer_drop(owner), borrow_buffer_drop(byte_owner))
''', "released 0\nreading 1 -16\nreleased 0\nreading 1 -16\nreleased 0\n4\n0 0\n")

    def test_defer_cannot_propagate_during_borrow_cleanup(self):
        self.assert_rejected('''fn inspect(owner: BorrowBuffer<i64>, index: Option<i64>) -> Option<i64>:
    let view = borrow_buffer_read(owner)
    defer print(buffer_read_get(view, index?))
    return Some(0)
''', "постфиксный ? нельзя использовать в defer")

    def test_invalid_and_stale_handles_cannot_touch_reused_slot(self):
        self.assert_runs('''let empty: BorrowBuffer<u16>
let zero: u16 = 0
print(borrow_buffer_len(empty), borrow_buffer_reserve(empty, 1), borrow_buffer_push(empty, zero))
print(borrow_buffer_set(empty, 0, zero), borrow_buffer_drop(empty))
let initial: [1]u16 = [7]
let owner = borrow_buffer_new(initial[0..0])
let stale = owner
print(borrow_buffer_len(owner), borrow_buffer_drop(owner))
let other_type: [1]i64 = [7]
let reused = borrow_buffer_new(other_type[0..1])
print(borrow_buffer_len(stale), borrow_buffer_drop(stale), borrow_buffer_len(reused))
print(borrow_buffer_reserve(reused, -1), borrow_buffer_reserve(reused, 9223372036854775807))
print(borrow_buffer_set(reused, -1, 0), borrow_buffer_set(reused, 1, 0))
if true:
    let view = borrow_buffer_read(reused)
    print(borrow_buffer_reserve(stale, 2), borrow_buffer_push(stale, zero))
    print(borrow_buffer_set(stale, 0, zero), borrow_buffer_drop(stale))
    print(buffer_read_get(view, 0))
print(borrow_buffer_drop(reused))
''', "-9 -9 -9\n-9 -9\n0 0\n-9 -9 1\n-22 -75\n-34 -34\n-9 -9\n-9 -9\n7\n0\n")
        for setup in (
            "let owner: BorrowBuffer<u16>\n",
            "let initial = [1]\nlet owner = borrow_buffer_new(initial[0..1])\nborrow_buffer_drop(owner)\n",
        ):
            with self.subTest(setup=setup):
                result = self.invoke(setup + "let view = borrow_buffer_read(owner)\n")
                self.assertEqual((result.returncode, result.stdout, result.stderr),
                                 (1, "", "invalid BorrowBuffer handle\n"))

    def test_capacity_and_zero_size_element_failure(self):
        self.assert_runs('''let initial: [1]i64
let active: [64]BorrowBuffer<i64>
for i in 0..64:
    active[i] = borrow_buffer_new(initial[0..0])
    if borrow_buffer_len(active[i]) != 0: panic("missing owner")
print(borrow_buffer_len(borrow_buffer_new(initial[0..0])))
for i in 0..64:
    if borrow_buffer_drop(active[i]) != 0: panic("leaked owner")
let reused = borrow_buffer_new(initial[0..0])
print(borrow_buffer_len(reused), borrow_buffer_drop(reused))
let empties: [1][0]i64
let bad = borrow_buffer_new(empties[0..1])
print(borrow_buffer_len(bad))
''', "-9\n0 0\n-9\n")

    def test_invalid_read_indices_fail_at_runtime(self):
        for index in (-1, 1):
            with self.subTest(index=index):
                result = self.invoke(f'''let initial = [1]
let owner = borrow_buffer_new(initial[0..1])
let view = borrow_buffer_read(owner)
print(buffer_read_get(view, {index}))
''')
                self.assertEqual((result.returncode, result.stdout, result.stderr),
                                 (1, "", "BorrowBuffer index out of bounds\n"))

    def test_read_copies_nested_handles_without_borrowing_their_targets(self):
        self.assert_runs('''let data = [1]
let inner = borrow_buffer_new(data[0..1])
let handles = [inner]
let outer = borrow_buffer_new(handles[0..1])
if true:
    let view = borrow_buffer_read(outer)
    let copy = buffer_read_get(view, 0)
    print(borrow_buffer_push(copy, 2), borrow_buffer_len(inner), borrow_buffer_drop(outer))
    print(borrow_buffer_drop(inner), borrow_buffer_len(copy), buffer_read_len(view))
print(borrow_buffer_drop(outer))
''', "0 2 -16\n0 -9 1\n0\n")

    def test_view_cannot_escape_or_release_early(self):
        local = '''let initial = [1]
let owner = borrow_buffer_new(initial[0..1])
let view = borrow_buffer_read(owner)
'''
        for expression in ("let copy = view", "let array = [view]", "let address = &view",
                           "view = view", "let owner_copy = view.owner"):
            with self.subTest(expression=expression):
                self.assert_rejected(local + expression + "\n", "BufferRead нельзя копировать")
        self.assert_rejected("fn forward<T>(x: T) -> T:\n    return x\n" + local + "forward(view)\n",
                             "BufferRead нельзя копировать")
        self.assert_rejected("struct Holder<T>:\n    value: T\n" + local + "let saved = Holder(view)\n",
                             "BufferRead нельзя копировать")
        self.assert_rejected("fn escape() -> BufferRead<i64>:\n    let view: BufferRead<i64>\n    return view\n",
                             "BufferRead разрешён только как локальное")
        self.assert_rejected("fn inspect(view: BufferRead<i64>):\n    print(buffer_read_len(view))\n",
                             "BufferRead разрешён только как локальное")
        self.assert_rejected("struct Saved:\n    view: BufferRead<i64>\n",
                             "BufferRead разрешён только как локальное")
        self.assert_rejected(local + "unsafe: __volt_buffer_read_end(view)\n", "завершение заимствования автоматическое")
        self.assert_rejected(local + "view = borrow_buffer_read(owner)\n", "BufferRead нельзя копировать")
        self.assert_rejected("let owner: BorrowBuffer<i64>\nborrow_buffer_read(owner)\n", "требует отдельного let")
        self.assert_rejected("""let owner: BorrowBuffer<i64>
if true:
    let view = borrow_buffer_read(owner)
print(buffer_read_len(view))
""", "неизвестное имя 'view'")

    def test_views_have_no_public_constructor(self):
        self.assert_rejected("let made = BufferRead()\n", "BufferRead разрешён только как локальное")
        self.assert_rejected('''fn inspect<T>(owner: BorrowBuffer<T>):
    let made = BufferRead(owner)
let owner: BorrowBuffer<i64>
inspect(owner)
''', "BufferRead разрешён только как локальное")

    def test_borrow_requires_its_hidden_cleanup_to_resolve(self):
        self.assert_rejected('''struct __volt_buffer_read_end:
    value: i64

let owner: BorrowBuffer<i64>
let view = borrow_buffer_read(owner)
''', "недоступно завершение заимствования BorrowBuffer")

    def test_owner_representation_is_not_a_public_constructor_or_field(self):
        self.assert_rejected("let owner: BorrowBuffer<i64> = BorrowBuffer(0)\n", "через borrow_buffer_new")
        self.assert_rejected("let owner: BorrowBuffer<i64>\nowner.token = 0\n", "поле дескриптора недоступно")
        self.assert_rejected("fn wrong(owner: BorrowBuffer<i64>) -> BorrowBuffer<u64>:\n    return owner\n",
                             "нельзя привести BorrowBuffer<i64> к BorrowBuffer<u64>")

    def test_owner_representation_cannot_be_retyped_indirectly(self):
        diagnostic = "представление BorrowBuffer нельзя приводить через raw-указатель"
        self.assert_rejected('''struct Holder<T>:
    value: T

fn address_as_integer<T>(value: T) -> i64:
    return &value

let owner: BorrowBuffer<i64>
address_as_integer(Holder(owner))
''', diagnostic)
        self.assert_rejected('''unsafe fn change_element(value: ptr<BorrowBuffer<i64>>) -> ptr<BorrowBuffer<u64>>:
    return value as ptr<BorrowBuffer<u64>>
''', diagnostic)
        self.assert_rejected('''struct Tagged<T>:
    value: T
    owner: BorrowBuffer<i64>

unsafe fn change_tag(value: ptr<Tagged<i64>>) -> ptr<Tagged<u64>>:
    return value as ptr<Tagged<u64>>
''', diagnostic)

    def test_typed_null_owner_pointer_does_not_change_representation(self):
        self.assert_runs('''let absent = 0 as ptr<BorrowBuffer<i64>>
if not absent: print("absent")
''', "absent\n")

    def test_unrelated_symbols_with_the_same_names_are_ordinary(self):
        self.assert_runs('''struct BorrowBuffer<T>:
    value: T

struct BufferRead<T>:
    value: T

fn borrow_buffer_read<T>(owner: BorrowBuffer<T>) -> BufferRead<T>:
    return BufferRead(owner.value)

let owner = BorrowBuffer(42)
let view: BufferRead<i64> = borrow_buffer_read(owner)
let copied = view
print(copied.value)
''', "42\n", use_borrow=False)

    def test_existing_raw_and_byte_view_keep_their_distinct_contracts(self):
        self.assert_runs('''use buffer, bytevec

unsafe:
    let owner: Buffer<i64>
    if buffer_reserve(&owner, 2) != 0 or buffer_push(&owner, 10) != 0: panic("raw setup")
    let copy = owner
    let bytes = owner.storage
    if buffer_push(&owner, 20) != 0: panic("reserved raw push")
    *buffer_at(&owner, 0) = 30
    print(buffer_data(&owner) == buffer_data(&copy), owner.storage.data == bytes.data)
    print(buffer_len(&owner), buffer_len(&copy), owner.storage.len, bytes.len, *buffer_at(&copy, 0))
    # Only the original owns the mapping. Never use the copies after this point.
    print(buffer_free(&owner))

let bytes = byte_vec_new()
if byte_vec_push(bytes, 7 as u8) != 0: panic("ByteVec setup")
let view = byte_vec_view(bytes, 0, 1)
let alias = bytes
print(byte_vec_set(alias, 0, 8 as u8))
match byte_view_get(view, 0):
    Ok(value): print(value)
    Err(error): panic("ByteView should see the write")
for i in 0..1024:
    if byte_vec_push(alias, 0 as u8) != 0: panic("ByteVec growth")
print(byte_vec_len(bytes), byte_view_len(view), byte_vec_drop(alias), byte_view_len(view))
''', "true true\n2 1 16 8 30\n0\n0\n8\n1025 1 0 -9\n")


if __name__ == "__main__":
    unittest.main()
