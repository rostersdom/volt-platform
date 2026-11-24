#!/usr/bin/env python3
"""Exercise the Linux x86-64 arena with native, static VOLT binaries."""
import os
from pathlib import Path
import platform
import struct
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests" / "fixtures"
VOLT = Path(os.environ.get("VOLT_COMPILER", ROOT / "volt")).resolve()


@unittest.skipUnless(platform.system() == "Linux" and platform.machine() == "x86_64",
                     "Arena uses the Linux x86-64 syscall ABI")
class VstdArena(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory(prefix="volt-vstd-arena-")
        self.addCleanup(tmp.cleanup)
        self.build = Path(tmp.name)
        self.env = {"PATH": "", "TMPDIR": tmp.name}

    def compile(self, source):
        exe = self.build / source.stem
        result = subprocess.run([VOLT, source, "-o", exe], cwd=self.build,
                                env=self.env, capture_output=True, text=True, timeout=30)
        return exe, result

    def run_static(self, source, expected, optional_syscall=None):
        exe, built = self.compile(source)
        self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
        elf = exe.read_bytes()
        self.assertEqual(elf[:7], b"\x7fELF\x02\x01\x01")
        self.assertEqual(struct.unpack_from("<HH", elf, 16), (2, 62))  # ET_EXEC, EM_X86_64
        offset, = struct.unpack_from("<Q", elf, 32)
        size, count = struct.unpack_from("<HH", elf, 54)
        segments = {struct.unpack_from("<I", elf, offset + i * size)[0] for i in range(count)}
        self.assertIn(1, segments)  # PT_LOAD
        self.assertFalse(segments & {2, 3}, "binary has PT_DYNAMIC or PT_INTERP")

        result = subprocess.run([exe], cwd=self.build, env=self.env,
                                capture_output=True, text=True, timeout=5)
        if optional_syscall and result.returncode == 77:
            self.skipTest(f"{optional_syscall} syscall unavailable")
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, expected, ""))

    def test_aligned_temporary_objects(self):
        self.run_static(FIXTURES / "vstd_arena_lifecycle.volt", "arena lifecycle ok\n")

    def test_failed_munmap_preserves_arena(self):
        self.run_static(FIXTURES / "vstd_arena_munmap_error.volt", "arena munmap error ok\n",
                        optional_syscall="mseal")

    def test_plain_volt_stays_static(self):
        self.run_static(ROOT / "tests" / "hello.volt",
                        (ROOT / "tests" / "expected" / "hello.txt").read_text(encoding="utf-8"))

    def test_alloc_requires_unsafe(self):
        _, result = self.compile(FIXTURES / "vstd_arena_requires_unsafe.volt")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("вызов unsafe-функции arena_alloc требует unsafe", result.stderr)


if __name__ == "__main__":
    unittest.main()
