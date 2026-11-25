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
        ran = subprocess.run([self.tmp / "program"], cwd=self.tmp, capture_output=True, text=True, timeout=5)
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

    def test_result_moves_through_ok_call_return_match_and_propagation(self):
        self.check_run('''use fs

fn checked_buffer(path: string) -> Result<OwnedBuffer, fs.IoError>:
    let info = fs.stat(path)?
    let buffer = owned_buffer_new("a")
    defer print("checked")
    return Ok(buffer)

fn relay(result: Result<OwnedBuffer, fs.IoError>) -> Result<OwnedBuffer, fs.IoError>:
    let next = result
    return identity(next)

fn identity<T>(value: T) -> T:
    return value

fn read_first(result: Result<OwnedBuffer, fs.IoError>) -> Result<i64, fs.IoError>:
    defer print("read_first")
    let buffer = result?
    defer print("read", owned_buffer_get(&buffer, 0) as char)
    return Ok(owned_buffer_len(&buffer))

match relay(checked_buffer(".")):
    Ok(buffer):
        defer print("match", owned_buffer_get(&buffer, 0) as char)
    Err(error): panic("expected buffer")
match read_first(relay(checked_buffer("."))):
    Ok(size): print(size)
    Err(error): panic("expected size")
match read_first(relay(checked_buffer("missing"))):
    Ok(size): panic("expected error")
    Err(error): print(fs.errno(error))
''', "checked\nmatch a\ndrop a\nchecked\nread a\nread_first\ndrop a\n1\nread_first\n2\n")

    def test_option_moves_some_through_let_argument_return_match_and_propagation(self):
        self.check_run('''fn pass(input: Option<OwnedBuffer>) -> Option<OwnedBuffer>:
    return input

fn make(value: string) -> Option<OwnedBuffer>:
    return Some(owned_buffer_new(value))

fn relay(input: Option<OwnedBuffer>) -> Option<OwnedBuffer>:
    let buffer = input?
    return Some(buffer)

fn empty() -> Option<OwnedBuffer>:
    return None

let direct: Option<OwnedBuffer> = None
let moved = make("a")
let again = pass(moved)
match relay(again):
    Some(buffer): defer print("match", owned_buffer_get(&buffer, 0) as char)
    None: panic("expected buffer")
match relay(empty()):
    Some(buffer): panic("expected none")
    None: print("propagated none")
''', "match a\ndrop a\npropagated none\n")

    def test_option_drops_only_live_some_after_arm_defers(self):
        self.check_run('''fn make(value: string) -> Option<OwnedBuffer>:
    return Some(owned_buffer_new(value))

match make("a"):
    _: defer print("wildcard")
match make("b"):
    None: panic("unexpected none")
    _: defer print("second")
match make("c"):
    Some(buffer): print("some", owned_buffer_get(&buffer, 0) as char)
    None: panic("unexpected none")
let empty: Option<OwnedBuffer> = None
print("end")
''', "wildcard\ndrop a\nsecond\ndrop b\nsome c\ndrop c\nend\n")

    def test_option_rejects_second_move_and_unsupported_storage(self):
        header = '''fn make() -> Option<OwnedBuffer>:
    return Some(owned_buffer_new("a"))

fn consume(option: Option<OwnedBuffer>):
    return

let option = make()
'''
        for source, expected in (
            ("let next = option\nconsume(option)", "после переноса"),
            ("match option:\n    Some(buffer): print(1)\n    None: print(0)\nconsume(option)", "после переноса"),
            ("option = make()", "нельзя копировать"),
            ("defer consume(option)", "defer не может переносить"),
            ("let nested: Option<Option<OwnedBuffer>> = None", "недопустимый тип payload"),
            ("let wrong: Result<Option<OwnedBuffer>, i64> = Err(1)", "недопустимый тип payload"),
            ("struct Bag:\n    owner: Option<OwnedBuffer>", "нельзя хранить в struct"),
            ("let array = [option]", "нельзя хранить в массиве"),
            ("extern fn external() -> Option<OwnedBuffer>", "запрещены в extern/native"),
        ):
            with self.subTest(source=source):
                built = self.build(header + source + "\n")
                self.assertEqual(built.returncode, 1, built.stdout + built.stderr)
                self.assertIn(expected, built.stderr)

    def test_result_drops_only_live_ok_after_scope_and_arm_defers(self):
        self.check_run('''fn make(value: string) -> Result<OwnedBuffer, i64>:
    return Ok(owned_buffer_new(value))

fn error() -> Result<OwnedBuffer, i64>:
    return Err(23)

fn scoped():
    let live = make("a")
    let failed = error()
    defer print("scope")
    return

make("x")
error()
scoped()
match make("b"):
    Err(code): print(code)
    _: defer print("wildcard")
match error():
    _: defer print("wildcard error")
for i in 0..3:
    let pending = make("c")
    defer print("loop", i)
    match make("d"):
        Ok(buffer):
            defer print("arm", owned_buffer_get(&buffer, 0) as char)
            if i == 0: continue
            break
        Err(code): panic("unexpected error")
''', ("drop x\nscope\ndrop a\nwildcard\ndrop b\nwildcard error\n"
      "arm d\ndrop d\nloop 0\ndrop c\narm d\ndrop d\nloop 1\ndrop c\n"))

    def test_result_and_extracted_owner_survive_aborted_argument_evaluation(self):
        self.check_run('''fn make(value: string) -> Result<OwnedBuffer, i64>:
    return Ok(owned_buffer_new(value))

fn checked(fail: bool) -> Result<i64, i64>:
    if fail: return Err(7)
    return Ok(10)

fn consume(a: Result<OwnedBuffer, i64>, b: OwnedBuffer, c: Result<OwnedBuffer, i64>, n: i64) -> i64:
    defer print("called")
    return n

fn attempt(fail: bool) -> Result<i64, i64>:
    let local = make("a")
    defer print("caller")
    return Ok(consume(local, make("b")?, Ok(owned_buffer_new("c")), checked(fail)?))

match attempt(true):
    Ok(n): panic("expected error")
    Err(code): print(code)
match attempt(false):
    Ok(n): print(n)
    Err(code): panic("expected success")
''', ("caller\ndrop c\ndrop b\ndrop a\n7\n"
      "called\ndrop c\ndrop b\ndrop a\ncaller\n10\n"))

    def test_result_rejects_second_move_and_unsupported_storage(self):
        header = '''fn make() -> Result<OwnedBuffer, i64>:
    return Ok(owned_buffer_new("a"))

fn consume(result: Result<OwnedBuffer, i64>):
    return

let result = make()
'''
        for source, expected in (
            ("let next = result\nconsume(result)", "после переноса"),
            ("if true:\n    match result:\n        _: print(1)\nconsume(result)", "после переноса"),
            ("fn bad(value: Result<OwnedBuffer, i64>) -> Result<i64, i64>:\n"
             "    let buffer = value?\n    consume(value)\n    return Ok(0)", "после переноса"),
            ("let buffer = owned_buffer_new(\"b\")\n"
             "let wrapped: Result<OwnedBuffer, i64> = Ok(buffer)\n"
             "print(owned_buffer_len(&buffer))", "после переноса"),
            ("let buffer = owned_buffer_new(\"b\")\n"
             "defer print(owned_buffer_len(&buffer))\n"
             "let wrapped: Result<OwnedBuffer, i64> = Ok(buffer)", "пока он заимствован"),
            ("result = make()", "нельзя копировать"),
            ("defer consume(result)", "defer не может переносить"),
            ("let wrapped: Option<Option<OwnedBuffer>> = None", "недопустимый тип payload"),
            ("let wrapped: Option<Result<OwnedBuffer, i64>> = None", "недопустимый тип payload"),
            ("let wrong: Result<Option<OwnedBuffer>, i64> = Err(1)", "недопустимый тип payload"),
            ("let wrong: Result<i64, OwnedBuffer> = Ok(1)", "недопустимый тип payload"),
            ("struct Bag:\n    owner: Result<OwnedBuffer, i64>", "нельзя хранить в struct"),
            ("let array = [result]", "нельзя хранить в массиве"),
            ("extern fn external() -> Result<OwnedBuffer, i64>", "запрещены в extern/native"),
        ):
            with self.subTest(source=source):
                built = self.build(header + source + "\n")
                self.assertEqual(built.returncode, 1, built.stdout + built.stderr)
                self.assertIn(expected, built.stderr)

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

    def test_slice_reader_borrows_owner_until_block_exit(self):
        self.check_run('''fn count(data: []u8) -> i64:
    let total = 0
    for i in 0..len(data):
        total += data[i]
    return total

let buffer = owned_buffer_new("ab")
if true:
    let bytes = owned_buffer_bytes(&buffer)
    let head = bytes[0..1]
    defer print("defer", bytes[1] as char)
    print(count(bytes), len(bytes), head[0] as char)
let moved = buffer
print("moved", owned_buffer_len(&moved))
''', "195 2 a\ndefer b\nmoved 2\ndrop a\n")

    def test_slice_reader_rejects_move_while_slice_alive(self):
        header = '''fn consume(input: OwnedBuffer):
    return

let buffer = owned_buffer_new("ab")
'''
        for source, expected in (
            ("let bytes = owned_buffer_bytes(&buffer)\nlet moved = buffer", "пока срез заимствует его байты"),
            ("let bytes = owned_buffer_bytes(&buffer)\nconsume(buffer)", "пока срез заимствует его байты"),
            ("if true:\n    let bytes = owned_buffer_bytes(&buffer)\n    let moved = buffer", "пока срез заимствует его байты"),
            ("print(len(owned_buffer_bytes(&buffer)))\nlet moved = buffer", "пока срез заимствует его байты"),
            ("fn tail8(data: []u8) -> []u8 from data:\n    return data[1..len(data)]\n"
             "let rest = tail8(owned_buffer_bytes(&buffer))\nlet moved = buffer", "пока срез заимствует его байты"),
        ):
            with self.subTest(source=source):
                built = self.build(header + source + "\n")
                self.assertEqual(built.returncode, 1, built.stdout + built.stderr)
                self.assertIn(expected, built.stderr)

    def test_slice_reader_rejects_escape_beyond_owner(self):
        for source, expected in (
            ("fn leak(input: []u8) -> []u8 from input:\n"
             "    let local = owned_buffer_new(\"ab\")\n"
             "    return owned_buffer_bytes(&local)", "срез должен происходить из параметра input"),
            ("fn leak() -> []u8:\n"
             "    let local = owned_buffer_new(\"ab\")\n"
             "    return owned_buffer_bytes(&local)", "без явно указанного источника"),
            ("let buffer = owned_buffer_new(\"ab\")\n"
             "let bytes = owned_buffer_bytes(buffer)", "вместо"),
        ):
            with self.subTest(source=source):
                built = self.build(source + "\n")
                self.assertEqual(built.returncode, 1, built.stdout + built.stderr)
                self.assertIn(expected, built.stderr)

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
            ("let wrapped = Some(item)\nconsume(item)", "после переноса"),
        ):
            with self.subTest(source=source):
                result = self.build(header + source + "\n")
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn(expected, result.stderr)


class OwnedFdOwnership(unittest.TestCase):
    """Same single-ownership rules, but for fs.OwnedFd over close(2)."""
    FCNTL = '''unsafe native fn fcntl_getfd(fd: i64) -> i64:
{
    mov eax, 72
    mov esi, 1
    syscall
}

fn is_open(fd: i64) -> i64:
    let status: i64
    unsafe: status = fcntl_getfd(fd)
    if status < 0: return 0
    return 1

'''

    @classmethod
    def setUpClass(cls):
        directory = tempfile.TemporaryDirectory(prefix="volt-owned-fd-")
        cls.addClassCleanup(directory.cleanup)
        cls.tmp = Path(directory.name)
        cls.volt = cls.tmp / "volt"
        shutil.copy2(VOLT, cls.volt)
        shutil.copytree(ROOT / "vstd", cls.tmp / "vstd")
        # Count every automatic close, including a duplicate close of a reused
        # descriptor that the kernel alone would hide behind EBADF.
        fs = cls.tmp / "vstd/fs.volt"
        text = fs.read_text(encoding="utf-8")
        drop = "fn __volt_owned_fd_close(handle: ptr<OwnedFd>):\n"
        if text.count(drop) != 1:
            raise AssertionError("missing vstd fd drop hook")
        fs.write_text(text.replace(drop, drop + '    print("close", owned_fd_number(handle))\n'), encoding="utf-8")

    def build(self, source):
        path = self.tmp / "main.volt"
        path.write_text("use fs\n" + source, encoding="utf-8")
        return subprocess.run([self.volt, path, "-o", self.tmp / "program"],
                              capture_output=True, text=True, timeout=15)

    def check_run(self, source, stdout, code=0, stderr=""):
        built = self.build(source)
        self.assertEqual(built.returncode, 0, built.stderr + built.stdout)
        ran = subprocess.run([self.tmp / "program"], cwd=self.tmp, capture_output=True, text=True, timeout=5)
        self.assertEqual((ran.returncode, ran.stdout, ran.stderr), (code, stdout, stderr))

    def test_fd_moves_through_let_argument_return_and_propagation(self):
        self.check_run(self.FCNTL + '''fn pass(input: fs.OwnedFd) -> fs.OwnedFd:
    return input

fn consume(input: fs.OwnedFd):
    defer print("read", fs.owned_fd_number(&input))

fn checked(path: string) -> Result<fs.OwnedFd, fs.IoError>:
    let handle = fs.open_owned(path)?
    return Ok(handle)

match checked("main.volt"):
    Ok(handle):
        print("open", fs.owned_fd_number(&handle))
        let moved = pass(handle)
        consume(moved)
        print("after", is_open(3))
    Err(error): panic("open failed")
''', "open 3\nread 3\nclose 3\nafter 0\n")

    def test_fd_closes_once_after_defer_on_propagation(self):
        self.check_run(self.FCNTL + '''fn probe(path: string) -> Result<i64, fs.IoError>:
    let handle = fs.open_owned(path)?
    let raw = fs.owned_fd_number(&handle)
    defer print("defer", is_open(raw))
    let info = fs.stat("missing-file")?
    return Ok(raw)

match probe("main.volt"):
    Ok(raw): panic("expected error")
    Err(error): print("err", fs.errno(error))
''', "defer 1\nclose 3\nerr 2\n")

    def test_fd_reused_after_drop_is_not_closed_twice(self):
        # The dropped descriptor number is immediately reused by the next open;
        # any stale second close would show up as an extra "close" line and
        # would kill the reused descriptor.
        self.check_run(self.FCNTL + '''fn take(path: string) -> Result<i64, fs.IoError>:
    let handle = fs.open_owned(path)?
    return Ok(fs.owned_fd_number(&handle))

match take("main.volt"):
    Ok(raw):
        print("closed", is_open(raw))
        match fs.open_owned("main.volt"):
            Ok(again):
                let reused = fs.owned_fd_number(&again)
                print("reused", reused, is_open(reused))
            Err(error): panic("reopen failed")
        print("final", is_open(raw))
    Err(error): panic("open failed")
''', "close 3\nclosed 0\nreused 3 1\nclose 3\nfinal 0\n")

    def test_fd_option_moves_some_and_closes_only_live_some(self):
        self.check_run(self.FCNTL + '''fn checked(path: string) -> Option<fs.OwnedFd>:
    match fs.open_owned(path):
        Ok(handle): return Some(handle)
        Err(error): return None

fn relay(input: Option<fs.OwnedFd>) -> Option<fs.OwnedFd>:
    let handle = input?
    return Some(handle)

let moved = checked("main.volt")
match relay(moved):
    Some(handle): print("open", fs.owned_fd_number(&handle))
    None: panic("open failed")
match relay(checked("missing-file")):
    Some(handle): panic("expected none")
    None: print("none")
match checked("main.volt"):
    _: defer print("wildcard")
let empty: Option<fs.OwnedFd> = None
print("end", is_open(3))
''', "open 3\nclose 3\nnone\nwildcard\nclose 3\nend 0\n")

    def test_fd_result_wildcard_drops_after_arm_defer(self):
        self.check_run('''match fs.open_owned("main.volt"):
    _: defer print("wildcard")
''', "wildcard\nclose 3\n")

    def test_fd_rejects_moves_copies_and_unsupported_storage(self):
        header = '''fn consume(input: fs.OwnedFd):
    return

fn open_it() -> Result<fs.OwnedFd, fs.IoError>:
    return fs.open_owned("main.volt")

'''
        arm = '''match open_it():
    Ok(item):
'''
        for source, expected in (
            ("        let moved = item\n        consume(item)", "после переноса"),
            ("        consume(item)\n        consume(item)", "после переноса"),
            ("        if true: consume(item)\n        print(fs.owned_fd_number(&item))", "после переноса"),
            ("        for i in 0..3:\n            consume(item)\n            continue", "следующей итерации"),
            ("        defer print(fs.owned_fd_number(&item))\n        consume(item)", "пока он заимствован"),
            ("        defer consume(item)", "defer не может переносить"),
            ("        let copy = &item", "адрес OwnedFd"),
            ("        let bag = [item]", "нельзя хранить в массиве"),
            ("        let wrapped = Some(item)\n        consume(item)", "после переноса"),
            ("        let moved = item\n        moved = moved", "нельзя копировать"),
        ):
            with self.subTest(source=source):
                built = self.build(header + arm + source + "\n    Err(error): panic(\"open failed\")\n")
                self.assertEqual(built.returncode, 1, built.stdout + built.stderr)
                self.assertIn(expected, built.stderr)
        for source, expected in (
            ("let result = open_it()\nlet next = result\nmatch result:\n    _: print(1)", "после переноса"),
            ("fn bad() -> Result<i64, fs.IoError>:\n"
             "    let result = open_it()\n"
             "    let handle = result?\n"
             "    let again = result\n"
             "    return Ok(0)", "после переноса"),
            ("let nested: Option<Option<fs.OwnedFd>> = None", "недопустимый тип payload"),
            ("let wrong: Result<i64, fs.OwnedFd> = Ok(1)", "недопустимый тип payload"),
            ("struct Bag:\n    owner: fs.OwnedFd", "нельзя хранить в struct"),
            ("extern fn external() -> Result<fs.OwnedFd, fs.IoError>", "запрещены в extern/native"),
            ("fn bad(handle: ptr<fs.OwnedFd>):\n    return", "указатель на OwnedFd"),
            ("let missing = fs.open_owned(\"missing-file\")\n"
             "let next = missing\n"
             "match missing:\n"
             "    _: print(1)", "после переноса"),
        ):
            with self.subTest(source=source):
                built = self.build(header + source + "\n")
                self.assertEqual(built.returncode, 1, built.stdout + built.stderr)
                self.assertIn(expected, built.stderr)


if __name__ == "__main__":
    unittest.main()
