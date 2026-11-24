#!/usr/bin/env python3
"""Exercise opt-in pthreads using native VOLT ELF output and its own _start."""
import os
from pathlib import Path
import platform
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests" / "fixtures"
VOLT = Path(os.environ.get("VOLT_COMPILER", ROOT / "volt")).resolve()


def supports_pthreads():
    try:
        libc = os.confstr("CS_GNU_LIBC_VERSION")
    except (AttributeError, OSError, ValueError):
        return False
    if not libc:
        return False
    name, version = libc.split()
    return name == "glibc" and tuple(map(int, version.split(".")[:2])) >= (2, 34)


@unittest.skipUnless(sys.platform == "linux" and platform.machine() == "x86_64"
                     and struct.calcsize("P") == 8, "requires Linux x86-64 LP64")
class VoltThreads(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        directory = tempfile.TemporaryDirectory(prefix="volt-vstd-threads-")
        cls.addClassCleanup(directory.cleanup)
        cls.tmp = Path(directory.name)

    def compile(self, source, output):
        binary = self.tmp / output
        result = subprocess.run([VOLT, source, "-o", binary], cwd=self.tmp,
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return binary

    def run_elf(self, binary, expected, **env):
        result = subprocess.run([binary], cwd=self.tmp, env=env, capture_output=True,
                                text=True, timeout=15)
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, expected, ""))

    def segments(self, binary):
        elf = binary.read_bytes()
        self.assertEqual(elf[:7], b"\x7fELF\x02\x01\x01")
        self.assertEqual(struct.unpack_from("<HH", elf, 16), (2, 62))  # ET_EXEC, EM_X86_64
        offset, = struct.unpack_from("<Q", elf, 32)
        size, count = struct.unpack_from("<HH", elf, 54)
        return {struct.unpack_from("<I", elf, offset + i * size)[0] for i in range(count)}

    def test_plain_volt_stays_static(self):
        source = self.tmp / "pure.volt"
        source.write_text('print("no pthread import")\n', encoding="utf-8")
        binary = self.compile(source, "pure")
        self.run_elf(binary, "no pthread import\n")
        segments = self.segments(binary)
        self.assertIn(1, segments)  # PT_LOAD
        self.assertNotIn(2, segments)  # PT_DYNAMIC
        self.assertNotIn(3, segments)  # PT_INTERP

    @unittest.skipUnless(supports_pthreads(), "requires glibc >= 2.34")
    def test_real_threads_join_and_mutex(self):
        binary = self.compile(FIXTURES / "vstd_thread_workers.volt", "workers")
        self.assertTrue({2, 3}.issubset(self.segments(binary)))
        for trial in range(3):
            with self.subTest(trial=trial):
                self.run_elf(binary, "4 24 192000\n")

    @unittest.skipUnless(supports_pthreads(), "requires glibc >= 2.34")
    def test_condition_bounded_queue_stress(self):
        binary = self.compile(FIXTURES / "vstd_thread_queue.volt", "queue")
        for trial in range(5):
            with self.subTest(trial=trial):
                self.run_elf(binary, "4 24 49152\n")

    @unittest.skipUnless(supports_pthreads(), "requires glibc >= 2.34")
    def test_condition_timed_wait_and_lifecycle(self):
        binary = self.compile(FIXTURES / "vstd_thread_timed_wait.volt", "timed_wait")
        for trial in range(3):
            with self.subTest(trial=trial):
                self.run_elf(binary, "condition timeout ok\n")

    @unittest.skipUnless(supports_pthreads(), "requires glibc >= 2.34")
    def test_concurrent_string_allocations_keep_contents(self):
        binary = self.compile(FIXTURES / "str_threads.volt", "strings")
        for trial in range(3):
            with self.subTest(trial=trial):
                self.run_elf(binary, "thread strings ok\n")

    @unittest.skipUnless(supports_pthreads(), "requires glibc >= 2.34")
    def test_pthread_errors_preserve_slot_state(self):
        cc = shutil.which("cc")
        if not cc:
            self.skipTest("pthread ABI/error fixture requires cc and glibc headers")
        library = self.tmp / "pthread_errors.so"
        subprocess.run([cc, "-std=c11", "-Wall", "-Wextra", "-Werror", "-shared", "-fPIC",
                        FIXTURES / "vstd_thread_errors.c", "-o", library],
                       cwd=self.tmp, check=True, timeout=30)
        binary = self.compile(FIXTURES / "vstd_thread_errors.volt", "errors")
        self.run_elf(binary, "pthread errors preserved\n", LD_PRELOAD=str(library))


if __name__ == "__main__":
    unittest.main()
