#!/usr/bin/env python3
"""Test value-only channels through the public API and real pthread producers."""
import os
from pathlib import Path
import platform
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest

from vstd_threads import supports_pthreads

ROOT = Path(__file__).resolve().parents[1]
VOLT = Path(os.environ.get("VOLT_COMPILER", ROOT / "volt")).resolve()


@unittest.skipUnless(sys.platform == "linux" and platform.machine() == "x86_64"
                     and struct.calcsize("P") == 8 and supports_pthreads(),
                     "requires Linux x86-64 LP64 with glibc >= 2.34")
class ChannelIntegration(unittest.TestCase):
    def check_fixture(self, name, output, repeats, cc=None):
        with tempfile.TemporaryDirectory(prefix="volt-channel-") as folder:
            binary = Path(folder) / "channel"
            env = {}
            if cc:
                library = Path(folder) / "libvolt_channel_waiters.so"
                subprocess.run([cc, "-std=c11", "-Wall", "-Wextra", "-Werror", "-shared", "-fPIC",
                                ROOT / "tests/fixtures/vstd_channel_waiters.c", "-o", library],
                               cwd=folder, check=True, capture_output=True, timeout=15)
                env["LD_LIBRARY_PATH"] = folder
            built = subprocess.run([VOLT, ROOT / "tests" / "fixtures" / name, "-o", binary],
                                   cwd=folder, env={"PATH": ""}, capture_output=True, text=True, timeout=20)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            for trial in range(repeats):
                with self.subTest(trial=trial):
                    result = subprocess.run([binary], cwd=folder, env=env, capture_output=True,
                                            text=True, timeout=10)
                    self.assertEqual((result.returncode, result.stdout, result.stderr), (0, output, ""))

    def test_lifecycle_and_concurrent_producers(self):
        self.check_fixture("vstd_channel.volt", "channel moved 2000 values exactly once\n", 6)

    def test_close_and_drop_wake_blocked_waiters(self):
        cc = shutil.which("cc")
        if not cc:
            self.skipTest("the condition wait probe requires a C compiler")
        self.check_fixture("vstd_channel_waiters.volt", "blocked channel waiters woke up\n", 6, cc=cc)

    def test_threaded_indirect_call_and_borrow_lifecycle(self):
        self.check_fixture("core_threaded_borrow.volt", "threaded borrow and ABI ok\n", 3)

    def test_payload_cannot_be_a_pointer_or_string(self):
        with tempfile.TemporaryDirectory(prefix="volt-channel-types-") as folder:
            path = Path(folder) / "bad.volt"
            for send in ("channel_i64_try_send", "channel_i64_send"):
                for payload in ("&value", '"text"'):
                    with self.subTest(send=send, payload=payload):
                        path.write_text(f"use channel\nlet value = 1\n"
                                        f"{send}(channel_i64_new(), {payload})\n", encoding="utf-8")
                        result = subprocess.run([VOLT, path, "-o", path.with_suffix("")],
                                                cwd=folder, env={"PATH": ""}, capture_output=True,
                                                text=True, timeout=10)
                        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                        self.assertIn("вместо i64", result.stderr)


if __name__ == "__main__":
    unittest.main()
