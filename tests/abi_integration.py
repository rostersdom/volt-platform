#!/usr/bin/env python3
"""Linux x86-64 C ABI interoperability; VOLT_COMPILER can select another binary."""
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
STACK_ARGS = (
    ("i8", "-7"), ("f64", "1.25"), ("u8", "251"), ("f32", "-2.5"),
    ("i16", "-12345"), ("f64", "3.75"), ("u16", "54321"), ("f32", "4.25"),
    ("i32", "-123456789"), ("f64", "-5.5"), ("u32", "4000000001"),
    ("i8", "-101"),  # First GP spill, with three SSE registers still available.
    ("f32", "6.75"), ("f64", "-7.25"), ("f32", "8.5"),
    ("f64", "-9.75"), ("u16", "65521"), ("f32", "10.25"), ("i16", "-23456"),
    ("f64", "11.5"), ("u8", "245"), ("f32", "-12.75"), ("i64", "-1099511627899"),
)
STACK_PARAMS = ", ".join(f"a{i}: {kind}" for i, (kind, _) in enumerate(STACK_ARGS, 1))
STACK_LINK = 'link "-L. -lvolt_abi_fixture"\n'
STACK_OK = 673


@unittest.skipUnless(sys.platform == "linux" and platform.machine() == "x86_64",
                     "requires Linux x86-64 System V ABI")
class AbiIntegration(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="volt-abi-")
        self.addCleanup(directory.cleanup)
        self.tmp = Path(directory.name)
        self.env = {"PATH": "", "TMPDIR": directory.name}

    def build_fixture(self):
        cc = shutil.which("cc")
        if not cc:
            self.skipTest("stack ABI fixture requires a system C compiler")
        library = self.tmp / "libvolt_abi_fixture.so"
        result = subprocess.run([cc, "-std=c11", "-Wall", "-Wextra", "-Werror", "-shared", "-fPIC",
                                 "-fno-omit-frame-pointer", FIXTURES / "abi_stack.c", "-o", library],
                                cwd=self.tmp, env={**os.environ, "TMPDIR": str(self.tmp)},
                                capture_output=True, encoding="utf-8", timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.env["LD_LIBRARY_PATH"] = str(self.tmp)

    def check_program(self, source, expected):
        executable = self.tmp / "program"
        built = subprocess.run([VOLT, source, "-o", executable], cwd=self.tmp, env=self.env,
                               capture_output=True, encoding="utf-8", timeout=15)
        self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
        self.assertEqual(built.stderr, "")
        result = subprocess.run([executable], cwd=self.tmp, env=self.env, capture_output=True,
                                encoding="utf-8", timeout=5)
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, expected, ""), source.name)

    def test_libc_qsort_with_volt_comparator(self):
        self.check_program(FIXTURES / "abi_qsort.volt", "-2147483648 -2147483648 0 6 19 2147483647\n")

    def test_libm_modf_and_modff(self):
        self.check_program(FIXTURES / "abi_modf.volt", "-12.000000 -0.750000\n8.000000 0.625000\n")

    def test_fixed_extern_mixed_stack_arguments(self):
        self.build_fixture()
        values = ", ".join(f"({value}) as {kind}" for kind, value in STACK_ARGS)
        source = self.tmp / "extern_stack.volt"
        source.write_text(STACK_LINK + f"unsafe extern fn volt_abi_check({STACK_PARAMS}) -> i64\n"
                          f"unsafe: print(volt_abi_check({values}))\n", encoding="utf-8")
        self.check_program(source, f"{STACK_OK}\n")

    def test_c_callback_mixed_stack_arguments(self):
        self.build_fixture()
        types = ", ".join(kind for kind, _ in STACK_ARGS)
        checks = "".join(f"    if a{i} != {value}: return {i}\n"
                         for i, (_, value) in enumerate(STACK_ARGS, 1))
        source = self.tmp / "callback_stack.volt"
        source.write_text(STACK_LINK + f"unsafe extern fn volt_abi_invoke(cb: fnptr<({types}) -> i64>) -> i64\n"
                          f"fn receive({STACK_PARAMS}) -> i64:\n{checks}    return {STACK_OK}\n"
                          "unsafe: print(volt_abi_invoke(callback(receive)))\n", encoding="utf-8")
        self.check_program(source, f"{STACK_OK}\n")


if __name__ == "__main__":
    unittest.main()
