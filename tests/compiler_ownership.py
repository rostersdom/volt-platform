#!/usr/bin/env python3
"""Check single ownership and the exact drop trace on scope exits."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
VOLT = Path(os.environ.get("VOLT_COMPILER", ROOT / "volt")).resolve()


class Ownership(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        directory = tempfile.TemporaryDirectory(prefix="volt-owned-")
        cls.addClassCleanup(directory.cleanup)
        cls.tmp = Path(directory.name)
        cls.volt = cls.tmp / "volt"
        shutil.copy2(VOLT, cls.volt)
        shutil.copytree(ROOT / "vstd", cls.tmp / "vstd")
        # Observe destructor calls, including accidental duplicate calls that bytes_free
        # alone (idempotent on an empty buffer) would not distinguish.
        owned = cls.tmp / "vstd/owned_buffer.volt"
        text = owned.read_text(encoding="utf-8")
        drop = "fn __volt_owned_buffer_drop(buffer: ptr<OwnedBuffer>):\n"
        if text.count(drop) != 1:
            raise AssertionError("missing vstd drop hook")
        owned.write_text(text.replace(drop, drop + '    print("drop", owned_buffer_get(buffer, 0) as char)\n'), encoding="utf-8")

    def build(self, source):
        path = self.tmp / "main.volt"
        path.write_text("use owned_buffer\n" + source, encoding="utf-8")
        return subprocess.run([self.volt, path, "-o", self.tmp / "program"],
                              capture_output=True, text=True, timeout=15)

    def check_run(self, source, stdout, code=0, stderr=""):
        built = self.build(source)
        self.assertEqual(built.returncode, 0, built.stderr + built.stdout)
        ran = subprocess.run([self.tmp / "program"], capture_output=True, text=True, timeout=5)
        self.assertEqual((ran.returncode, ran.stdout, ran.stderr), (code, stdout, stderr))

    def test_moves_into_arguments_and_results(self):
        self.check_run('''fn pass(input: OwnedBuffer) -> OwnedBuffer:
    return input

fn consume(input: OwnedBuffer):
    defer print("read", owned_buffer_get(&input, 0) as char)

let buffer = owned_buffer_new("a")
let moved = buffer
let again = pass(moved)
consume(again)
owned_buffer_new("z")
''', "read a\ndrop a\ndrop z\n")

    def test_scope_lifo_and_all_normal_exit_paths(self):
        self.check_run('''fn make(fail: bool) -> Result<i64, i64>:
    if fail: return Err(17)
    return Ok(5)

fn check(fail: bool) -> Result<i64, i64>:
    let a = owned_buffer_new("a")
    defer print("outer", owned_buffer_get(&a, 0) as char)
    if true:
        let b = owned_buffer_new("b")
        let c = owned_buffer_new("c")
        defer print("inner", owned_buffer_get(&b, 0) as char)
        defer print("last", owned_buffer_get(&c, 0) as char)
        let n = make(fail)?
        if n == 5: return Ok(n)
    return Ok(0)

match check(true):
    Ok(n): print(n)
    Err(code): print(code)
match check(false):
    Ok(n): print(n)
    Err(code): print(code)
for i in 0..4:
    let loop_buffer = owned_buffer_new("l")
    defer print(i, owned_buffer_len(&loop_buffer))
    if i == 0: continue
    if i == 2: break
''', ("last c\ninner b\ndrop c\ndrop b\nouter a\ndrop a\n17\n"
      "last c\ninner b\ndrop c\ndrop b\nouter a\ndrop a\n5\n"
      "0 1\ndrop l\n1 1\ndrop l\n2 1\ndrop l\n"))

    def test_partial_branch_transfer_and_diverging_branch(self):
        self.check_run('''fn consume(input: OwnedBuffer):
    return

fn may_move(move: bool, input: OwnedBuffer):
    if move: consume(input)
    print("done")

fn disjoint(move: bool, input: OwnedBuffer):
    if move:
        consume(input)
        return
    print(owned_buffer_len(&input))

may_move(true, owned_buffer_new("a"))
may_move(false, owned_buffer_new("b"))
disjoint(true, owned_buffer_new("c"))
disjoint(false, owned_buffer_new("d"))
''', "drop a\ndone\ndone\ndrop b\ndrop c\n1\ndrop d\n")

    def test_argument_move_is_committed_only_on_call(self):
        self.check_run('''fn fail() -> Result<i64, i64>:
    return Err(5)

fn consume(first: OwnedBuffer, second: OwnedBuffer, n: i64) -> i64:
    return n

fn early() -> Result<i64, i64>:
    let outer = owned_buffer_new("a")
    defer print("before drop")
    return Ok(consume(outer, owned_buffer_new("b"), fail()?))

match early():
    Ok(n): print(n)
    Err(code): print(code)
''', "before drop\ndrop b\ndrop a\n5\n")

    def test_process_termination_does_not_unwind(self):
        setup = 'let buffer = owned_buffer_new("a")\ndefer print(owned_buffer_len(&buffer))\n'
        self.check_run(setup + 'panic("stop\\n")\n', "", 1, "stop\n")
        self.check_run(setup + 'exit(7)\n', "", 7)

    def test_string_repetition_reads_owner_before_right_operand_moves_it(self):
        self.check_run('''fn text(input: OwnedBuffer) -> string:
    return "text"

let item = owned_buffer_new("a")
print(owned_buffer_len(&item) * text(item))
''', "drop a\ntext\n")

    def test_rejects_moves_from_maybe_moved_or_borrowed_slots(self):
        header = '''fn consume(input: OwnedBuffer):
    return

fn choose(input: OwnedBuffer) -> i64:
    return 0

let item = owned_buffer_new("a")
'''
        for source, expected in (
            ("let moved = item\nconsume(item)", "после переноса"),
            ("if true: consume(item)\nprint(owned_buffer_len(&item))", "после переноса"),
            ("let choice = false and choose(item)\nprint(owned_buffer_len(&item))", "после переноса"),
            ("for i in 0..3:\n    consume(item)\n    continue", "следующей итерации"),
            ("while true:\n    consume(item)\n    break\nconsume(item)", "после переноса"),
            ("defer print(owned_buffer_len(&item))\nconsume(item)", "пока он заимствован"),
            ("print(owned_buffer_get(&item, choose(item)))", "пока он заимствован"),
            ("defer consume(item)", "defer не может переносить"),
            ("let copy = &item", "адрес OwnedBuffer"),
            ("let bag = [item]", "нельзя хранить в массиве"),
            ("let wrapped = Some(item)", "недопустимый тип payload"),
        ):
            with self.subTest(source=source):
                result = self.build(header + source + "\n")
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn(expected, result.stderr)


if __name__ == "__main__":
    unittest.main()
