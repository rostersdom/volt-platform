#!/usr/bin/env python3
"""Typed indirect calls on Linux x86-64; VOLT_COMPILER selects the compiler."""
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
FIXTURES = ROOT / "tests" / "fixtures"


@unittest.skipUnless(sys.platform == "linux" and platform.machine() == "x86_64",
                     "requires Linux x86-64 System V ABI")
class FnPtrCalls(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="volt-fnptr-")
        self.addCleanup(directory.cleanup)
        self.tmp = Path(directory.name)
        self.env = {"PATH": "", "TMPDIR": directory.name}

    def run_command(self, args, env=None):
        return subprocess.run(args, cwd=self.tmp, env=self.env if env is None else env,
                              capture_output=True, encoding="utf-8", timeout=15)

    def compile_program(self, source):
        if isinstance(source, str):
            path = self.tmp / "test.volt"
            path.write_text(source, encoding="utf-8")
            source = path
        return self.run_command([VOLT, source, "-o", self.tmp / "program"])

    def check_program(self, source, stdout, stderr="", status=0):
        built = self.compile_program(source)
        self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
        self.assertEqual(built.stderr, "")
        result = self.run_command([self.tmp / "program"])
        self.assertEqual((result.returncode, result.stdout, result.stderr), (status, stdout, stderr))

    def test_callback_local_parameter_void_and_defer(self):
        self.check_program(FIXTURES / "compiler_fnptr_callback.volt", "21\nbody\n37\n")

    def test_existing_call_names_take_priority_over_local_fnptr(self):
        self.check_program('''struct Pair:
    value: i64
fn increment(n: i64) -> i64:
    return n + 1
fn identity<T>(value: T) -> T:
    return value
fn double(n: i64) -> i64:
    return n * 2
unsafe:
    let increment = callback(double)
    let identity = callback(double)
    let Pair = callback(double)
    let len = callback(double)
    let pair = Pair(6)
    let values: [3]i64
    print(increment(40), identity(8), pair.value, len(values))
''', "41 8 6 3\n")

    def test_defer_keeps_the_visible_callee_before_a_shadowing_declaration(self):
        self.check_program('''fn outside():
    print("outside")
fn inside():
    print("inside")
unsafe:
    let f = callback(outside)
    if true:
        defer f()
        let f = callback(inside)
        f()
''', "inside\noutside\n")

    def test_void_calls_cannot_be_used_as_conditions(self):
        for expression in ("if f(): print(1)", "while f(): break", "print(not f())",
                           "if true and f(): print(1)", "if noop(): print(1)"):
            with self.subTest(expression=expression):
                source = "fn noop():\n    return\nunsafe:\n    let f = callback(noop)\n    " + expression + "\n"
                result = self.compile_program(source)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn("void нельзя использовать как условие", result.stderr)

    def test_c_pointer_mixed_stack_nested_and_narrow_results(self):
        cc = shutil.which("cc")
        if not cc:
            self.skipTest("C ABI fixture requires a system C compiler")
        result = self.run_command(
            [cc, "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", "-shared", "-fPIC",
             "-fno-omit-frame-pointer", FIXTURES / "compiler_fnptr.c", "-o", "libvolt_fnptr_fixture.so"],
            env={**os.environ, "TMPDIR": str(self.tmp)},
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.env["LD_LIBRARY_PATH"] = str(self.tmp)
        self.check_program(FIXTURES / "compiler_fnptr_c.volt",
                           "-101\n-109 true 4\n60001 false true 37\n-9.750000\n")

    def test_null_pointer_panics_before_evaluating_arguments(self):
        self.check_program('''fn argument() -> i64:
    print(99)
    return 1
unsafe fn invoke(f: fnptr<(i64)>):
    f(argument())
let empty: fnptr<(i64)>
unsafe: invoke(empty)
''', "", "volt: null fnptr call\n", status=1)

    def test_numeric_argument_conversion_checks_range(self):
        # A literal that cannot fit i8 is rejected at compile time.
        literal = self.compile_program('''fn byte(n: i8):
    print(n)
unsafe:
    let f = callback(byte)
    f(128)
''')
        self.assertEqual(literal.returncode, 1, literal.stdout + literal.stderr)
        self.assertIn("целочисленный литерал вне диапазона i8", literal.stderr)
        # A runtime value still traps through the indirect call.
        self.check_program('''fn byte(n: i8):
    print(n)
unsafe:
    let f = callback(byte)
    let big: i64 = 128
    f(big as i16)
''', "", "volt: integer overflow\n", status=1)

    def test_call_diagnostics(self):
        cases = (
            ("let f: fnptr<(i64)>\nf(1)\n", "косвенный вызов fnptr требует unsafe"),
            ("fn accepts(f: fnptr<()>):\n    return\n", "в сигнатуре должна быть объявлена unsafe"),
            ("let f: fnptr<(i64)>\nunsafe: f()\n", "0 аргумента(ов), ожидалось 1"),
            ("let f: fnptr<()>\nunsafe: f(1)\n", "1 аргумента(ов), ожидалось 0"),
            ("let f: fnptr<(i64)>\nunsafe: f(true)\n", "аргумент 1: bool вместо i64"),
            ("let p: ptr<u8>\nlet f: fnptr<(ptr<i8>)>\nunsafe: f(p)\n", "ptr<u8> вместо ptr<i8>"),
            ("fn empty():\n    return\nlet f: fnptr<(i64)>\nunsafe: f(empty())\n", "void вместо i64"),
            ("let f: ptr<char>\nunsafe: f()\n", "вызов требует fnptr, получен ptr<char>"),
            ("let f: fnptr<(string)>\n", "только скалярный ABI"),
            ("let f: fnptr<() -> [1]i64>\n", "только скалярный ABI"),
            ("let raw: ptr<char>\nlet f = raw as fnptr<()>\n", "приведение raw-указателя требует unsafe"),
            ("let raw: ptr<char>\nunsafe: let f: fnptr<()> = raw\n", "нельзя присвоить fnptr"),
            ("let f: fnptr<(i64)>\nunsafe: let other = f as fnptr<(f64)>\n", "нельзя привести fnptr<(i64)> к fnptr<(f64)>"),
            ("unsafe fn run():\n    defer later()\n    let later: fnptr<()>\n", "неизвестная функция 'later'"),
        )
        for source, message in cases:
            with self.subTest(source=source):
                result = self.compile_program(source)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn(message, result.stderr)


if __name__ == "__main__":
    unittest.main()
