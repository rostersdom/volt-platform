#!/usr/bin/env python3
"""Opt-in small C structs on Linux x86-64 System V."""
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
VOLT = Path(os.environ.get("VOLT_COMPILER", ROOT / "volt")).resolve()
FIXTURE = ROOT / "tests/fixtures/c_struct_abi.c"
LINK = 'link "-L. -lvolt_c_struct_fixture"\n'


@unittest.skipUnless(sys.platform == "linux" and platform.machine() == "x86_64",
                     "requires Linux x86-64 System V ABI")
class CStructABI(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="volt-c-struct-")
        self.addCleanup(directory.cleanup)
        self.tmp = Path(directory.name)
        self.env = {"PATH": "", "TMPDIR": directory.name, "LD_LIBRARY_PATH": directory.name}

    def run_command(self, args, env=None):
        return subprocess.run(args, cwd=self.tmp, env=self.env if env is None else env,
                              capture_output=True, encoding="utf-8", timeout=15)

    def build_fixture(self):
        cc = shutil.which("cc")
        if not cc:
            self.skipTest("C struct fixture requires a system C compiler")
        result = self.run_command(
            [cc, "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", "-shared", "-fPIC",
             FIXTURE, "-o", "libvolt_c_struct_fixture.so"],
            env={**os.environ, "TMPDIR": str(self.tmp)},
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def compile_program(self, source):
        path = self.tmp / "test.volt"
        path.write_text(source, encoding="utf-8")
        return self.run_command([VOLT, path, "-o", self.tmp / "program"])

    def check_program(self, source, stdout, *, link=LINK):
        built = self.compile_program(link + source)
        self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
        self.assertEqual(built.stderr, "")
        result = self.run_command([self.tmp / "program"])
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, stdout, ""))

    def test_one_eightbyte_layout_argument_and_result(self):
        self.build_fixture()
        self.check_program('''extern struct Small:
    code: i8
    delta: i16
    mask: u32
extern fn c_struct_small_layout(size: i64, alignment: i64, code: i64, delta: i64, mask: i64) -> i64
extern fn c_struct_small_arg(value: Small) -> i64
extern fn c_struct_small_result(which: i64) -> Small
unsafe:
    let value = Small(-117, -12345, 4000000001)
    let base = (&value) as i64
    print(c_struct_small_layout(sizeof(Small), alignof(Small),
                                 ((&value.code) as i64) - base, ((&value.delta) as i64) - base,
                                 ((&value.mask) as i64) - base))
    print(c_struct_small_arg(value))
    let result = c_struct_small_result(57)
    print(result.code, result.delta, result.mask)
''', "1\n1\n-101 -23456 3900000001\n")

    def test_mixed_register_classes_and_stack_rollback(self):
        self.build_fixture()
        self.check_program('''extern struct Pair:
    left: i64
    right: i64
extern struct Mixed:
    value: f64
    tag: i32
extern struct Floats:
    a: f64
    b: f64
extern struct Together:
    value: f32
    tag: i32
extern struct Tiny:
    a: u8
    b: u8
    c: u8
extern fn c_struct_pair(value: Pair) -> Pair
extern fn c_struct_mixed(value: Mixed) -> Mixed
extern fn c_struct_floats(value: Floats) -> Floats
extern fn c_struct_merge(value: Together) -> Together
extern fn c_struct_spill(a: i64, b: i64, c: i64, d: i64, e: i64, value: Pair, tail: i64, last: Tiny) -> i64
extern fn c_struct_spill_sse(a: f64, b: f64, c: f64, d: f64, e: f64, f: f64, g: f64, h: f64, value: Mixed, tail: i64) -> i64
fn relay(input: Pair) -> Pair:
    return input
unsafe:
    let pair = relay(c_struct_pair(Pair(57, 21)))
    let mixed = c_struct_mixed(Mixed(1.5, 10))
    let floats = c_struct_floats(Floats(2.5, 3.25))
    let together = c_struct_merge(Together(1.25, 9))
    print(pair.left, pair.right, mixed.value == 2.25, mixed.tag, floats.a == 3.5, floats.b == 3.0)
    print(together.value == (2.5 as f32), together.tag)
    print(c_struct_spill(1, 2, 3, 4, 5, pair, 90, Tiny(123, 12, 45)))
    print(c_struct_spill_sse(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, Mixed(2.5, 90), 55))
''', "31 77 true 14 true true\ntrue 10\n1\n1\n")

    def test_narrow_results_and_arguments_are_snapshots(self):
        self.build_fixture()
        self.check_program('''extern struct Tiny:
    a: u8
    b: u8
    c: u8
extern fn c_struct_tiny(value: Tiny) -> Tiny
extern fn c_struct_snapshot(value: Tiny, n: i64) -> i64
unsafe fn mutate(value: ptr<Tiny>) -> i64:
    value.a = 0
    return 10
unsafe:
    let tiny = c_struct_tiny(Tiny(11, 22, 33))
    print(sizeof(Tiny), alignof(Tiny), tiny.a, tiny.b, tiny.c)
    print(c_struct_snapshot(tiny, mutate(&tiny)), tiny.a)
''', "3 1 33 11 22\n76 0\n")

    def test_libc_div_record_result(self):
        self.check_program('''link "-lc"
extern struct Div:
    quot: i32
    rem: i32
extern fn div(n: i32, d: i32) -> Div
unsafe:
    let answer = div(-99, 7)
    print(answer.quot, answer.rem)
''', "-14 -1\n", link="")

    def test_unsupported_layouts_rejected(self):
        for source, expected in (
            ("extern struct Large:\n    x: i64\n    y: i64\n    z: i64\n", "до 16 байт"),
            ("extern struct StringField:\n    x: string\n", "скалярные поля"),
            ("extern struct ArrayField:\n    x: [1]i64\n", "скалярные поля"),
            ("enum Tag:\n    One\nextern struct EnumField:\n    x: Tag\n", "скалярные поля"),
            ("extern struct Generic<T>:\n    x: T\n", "не поддерживает параметры типа"),
            ("extern struct Unit:\n    x: i64\nunsafe fn bad(f: fnptr<(Unit)>):\n    return\n", "скалярный ABI C"),
        ):
            with self.subTest(source=source):
                result = self.compile_program(source)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn(expected, result.stderr)


if __name__ == "__main__":
    unittest.main()
