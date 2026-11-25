#!/usr/bin/env python3
"""Check namespaces, exports, and the legacy flat import path."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
VOLT = Path(os.environ.get("VOLT_COMPILER", ROOT / "volt")).resolve()

FS = '''module fs
pub struct Descriptor:
    fd: i64

pub enum Token:
    Number(i64)
    End

pub const bias: i64 = 7
let state: i64 = 1

fn init():
    state = 3

fn new_descriptor(fd: i64) -> Descriptor:
    return Descriptor(fd)

pub fn open(path: string) -> Result<Descriptor, i64>:
    if path == "": return Err(2)
    return Ok(new_descriptor(state + bias))

pub fn number(handle: Descriptor) -> i64:
    return handle.fd

pub fn tag<T: Eq>(value: T, other: T) -> bool:
    return value == other

init()
'''


class Namespaces(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="volt-module-")
        self.addCleanup(directory.cleanup)
        self.tmp = Path(directory.name)
        self.env = {"PATH": "", "TMPDIR": str(self.tmp)}
        (self.tmp / "fs.volt").write_text(FS, encoding="utf-8")
        (self.tmp / "other.volt").write_text("module other\npub fn open() -> i64:\n    return 25\n", encoding="utf-8")
        (self.tmp / "legacy.volt").write_text("fn legacy() -> i64:\n    return 5\n", encoding="utf-8")

    def build(self, source):
        path = self.tmp / "main.volt"
        path.write_text(source, encoding="utf-8")
        return subprocess.run([VOLT, path, "-o", self.tmp / "program"], cwd=self.tmp,
                              env=self.env, capture_output=True, text=True, timeout=15)

    def test_stdlib_prelude_module_compiles_standalone(self):
        # Compiling vstd/io.volt itself used to fail: the automatic prelude
        # tried to import "io" into io.volt and reported "модуль не найден".
        result = subprocess.run([VOLT, ROOT / "vstd" / "io.volt", "-o", self.tmp / "io_standalone"],
                                cwd=self.tmp, env=self.env, capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_exports_compose_with_sum_types_and_eq(self):
        result = self.build('''module demo
use fs, other as network, legacy
const expected: i64 = fs.bias + 3

fn forward(path: string) -> Result<fs.Descriptor, i64>:
    defer print("cleanup", fs.bias)
    let fd = fs.open(path)?
    return Ok(fd)

fn main():
    match forward("file"):
        Ok(handle): print(fs.number(handle), fs.tag(fs.number(handle), expected), network.open() + legacy())
        Err(code): print(code)
    let token: fs.Token = fs.Token.Number(42)
    match token:
        fs.Token.Number(value): print(value)
        fs.Token.End: print(0)
    print(alignof(fs.Descriptor))
''')
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        ran = subprocess.run([self.tmp / "program"], capture_output=True, text=True, timeout=5)
        self.assertEqual((ran.returncode, ran.stdout, ran.stderr), (0, "cleanup 7\n10 true 30\n42\n8\n", ""))

    def test_module_constructor_uses_resolved_expected_type(self):
        result = self.build('''module demo
struct Box<T>:
    value: T

fn make() -> Box<u16>:
    return Box(42)

fn unbox(box: Box<u8>) -> u8:
    return box.value

fn wrapped() -> Option<Box<u16>>:
    return Some(Box(45))

let local: Box<u8> = Box(43)
print(make().value, local.value, unbox(Box(44)))
match wrapped():
    Some(box): print(box.value)
    None: panic("expected box")
''')
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        ran = subprocess.run([self.tmp / "program"], capture_output=True, text=True, timeout=5)
        self.assertEqual((ran.returncode, ran.stdout, ran.stderr), (0, "42 43 44\n45\n", ""))

    def test_private_values_and_constructors_are_unavailable(self):
        for source, message in (
            ("fs.new_descriptor(3)", "приватное объявление"),
            ("let item = fs.Descriptor(3)", "приватный конструктор"),
            ("let item: fs.Descriptor", "приватный конструктор"),
            ("let items: [2]fs.Descriptor", "приватный конструктор"),
            ("match fs.open(\"x\"):\n    Ok(fd): print(fd.fd)\n    Err(code): print(code)", "приватное поле"),
            ("print(fs.state)", "приватное объявление"),
            ("let item: Descriptor", "неизвестный тип"),
            ("new_descriptor(3)", "неизвестная функция"),
        ):
            with self.subTest(source=source):
                result = self.build("use fs\n" + source + "\n")
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn(message, result.stderr)

    def test_aliases_are_not_reexported(self):
        (self.tmp / "bridge.volt").write_text("module bridge\nuse fs\n", encoding="utf-8")
        result = self.build('use bridge\nlet copy: fs.Descriptor\n')
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("неизвестный тип", result.stderr)

    def test_standard_fs_exposes_an_opaque_descriptor_and_compound_result(self):
        (self.tmp / "fs.volt").unlink()
        (self.tmp / "data").write_bytes(b"volt!")
        result = self.build('''use fs
fn forward(info: Result<fs.FileInfo, fs.IoError>) -> Result<i64, fs.IoError>:
    defer print("cleanup")
    return Ok(fs.size(info?))

match forward(fs.stat("data")):
    Ok(size): print(size)
    Err(error): print(fs.errno(error))
match forward(fs.stat("missing")):
    Ok(size): print(size)
    Err(error): print(fs.errno(error))
match fs.open("data"):
    Ok(fd):
        unsafe:
            match fs.close_file(fd):
                Ok(status): print(status)
                Err(error): print(fs.errno(error))
    Err(error): print(fs.errno(error))
match file_size("data"):
    Ok(size): print(size)
    Err(code): print(code)
''')
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        ran = subprocess.run([self.tmp / "program"], cwd=self.tmp, capture_output=True, text=True, timeout=5)
        self.assertEqual((ran.returncode, ran.stdout, ran.stderr), (0, "cleanup\n5\ncleanup\n2\n0\n5\n", ""))


if __name__ == "__main__":
    unittest.main()
