#!/usr/bin/env python3
"""Exercise fs.read_all: bounded whole-file reads into a move-only OwnedBuffer."""
import errno
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

PAYLOAD = bytes([0x00, 0x01, 0x02, 0xFF, 0x0A, 0x00, 0x41])
EXACT = b"abcdef"


@unittest.skipUnless(platform.system() == "Linux" and platform.machine() == "x86_64",
                     "vstd fs uses the Linux x86-64 syscall ABI")
class VstdFs(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        tmp = tempfile.TemporaryDirectory(prefix="volt-vstd-fs-")
        cls.addClassCleanup(tmp.cleanup)
        cls.build = Path(tmp.name)
        cls.env = {"PATH": "", "TMPDIR": tmp.name}

    def run_fixture(self, name, cwd, expected):
        exe = self.build / name
        built = subprocess.run([VOLT, FIXTURES / f"{name}.volt", "-o", exe],
                               cwd=self.build, env=self.env, capture_output=True, text=True, timeout=30)
        self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
        elf = exe.read_bytes()
        self.assertEqual(elf[:7], b"\x7fELF\x02\x01\x01")
        offset = struct.unpack_from("<Q", elf, 32)[0]
        size, count = struct.unpack_from("<HH", elf, 54)
        segments = {struct.unpack_from("<I", elf, offset + i * size)[0] for i in range(count)}
        self.assertIn(1, segments)  # PT_LOAD
        self.assertFalse(segments & {2, 3}, "fixture has PT_DYNAMIC or PT_INTERP")

        result = subprocess.run([exe], cwd=cwd, env=self.env, umask=0o027,
                                capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((result.stdout, result.stderr), (expected + "\n", ""))

    def test_read_all_through_question_mark_without_manual_release(self):
        with tempfile.TemporaryDirectory(dir=self.build, prefix="read-all-") as tmp:
            cwd = Path(tmp)
            (cwd / "payload.bin").write_bytes(PAYLOAD)
            (cwd / "empty.bin").write_bytes(b"")
            (cwd / "exact.bin").write_bytes(EXACT)
            (cwd / "adir").mkdir()

            expected = "\n".join([
                f"ok {len(PAYLOAD)} {sum(PAYLOAD)}",
                f"err {errno.ENOENT}",
                f"err {errno.EFBIG}",
                "ok 0 0",
                f"ok {len(EXACT)} {sum(EXACT)}",
                f"err {errno.EINVAL}",
                f"err {errno.EINVAL}",
                f"err {errno.EISDIR}",
                "done",
            ])
            self.run_fixture("vstd_fs_read_all", cwd, expected)

            # The error paths must not destroy, truncate or create anything.
            self.assertEqual((cwd / "payload.bin").read_bytes(), PAYLOAD)
            self.assertEqual((cwd / "exact.bin").read_bytes(), EXACT)
            self.assertEqual({p.name for p in cwd.iterdir()},
                             {"payload.bin", "empty.bin", "exact.bin", "adir"})


if __name__ == "__main__":
    unittest.main()
