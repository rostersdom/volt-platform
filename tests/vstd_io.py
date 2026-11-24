#!/usr/bin/env python3
"""Exercise Linux x86-64 vstd I/O and verify it needs no libc."""
import os
from pathlib import Path
import platform
import stat
import struct
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests" / "fixtures"
VOLT = Path(os.environ.get("VOLT_COMPILER", ROOT / "volt")).resolve()


@unittest.skipUnless(platform.system() == "Linux" and platform.machine() == "x86_64",
                     "vstd I/O uses the Linux x86-64 syscall ABI")
class VstdIO(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        tmp = tempfile.TemporaryDirectory(prefix="volt-vstd-io-")
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

    def test_path_mutations_and_symlinks(self):
        with tempfile.TemporaryDirectory(dir=self.build, prefix="fs-") as tmp:
            cwd = Path(tmp)
            (cwd / "source").write_text("source data")
            (cwd / "occupied").write_text("keep me")
            (cwd / "discard").touch()
            (cwd / "target").mkdir()
            (cwd / "empty").mkdir()
            (cwd / "source-link").symlink_to("occupied")
            (cwd / "dir-link").symlink_to("target", target_is_directory=True)
            (cwd / "dangling").symlink_to("absent")

            self.run_fixture("vstd_fs_paths", cwd, "fs paths ok")

            self.assertEqual(stat.S_IMODE((cwd / "moved").stat().st_mode), 0o750)
            self.assertEqual((cwd / "occupied").read_text(), "keep me")
            self.assertEqual((cwd / "moved-file").read_text(), "source data")
            self.assertEqual((cwd / "moved-link").readlink(), Path("occupied"))
            self.assertTrue((cwd / "target" / "child").is_dir())
            self.assertEqual({p.name for p in cwd.iterdir()},
                             {"moved", "occupied", "moved-file", "moved-link", "target"})

    def test_nonblocking_stream_and_timer_readiness(self):
        with tempfile.TemporaryDirectory(dir=self.build, prefix="event-") as tmp:
            self.run_fixture("vstd_event_stream", tmp, "event stream ok")


if __name__ == "__main__":
    unittest.main()
