#!/usr/bin/env python3
"""Rebuild VOLT from a clean, static seed with no external tools on PATH."""
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class Bootstrap(unittest.TestCase):
    def assert_static_elf(self, path):
        data = path.read_bytes()
        self.assertEqual(data[:7], b"\x7fELF\x02\x01\x01")
        self.assertEqual(struct.unpack_from("<HH", data, 16), (2, 62))
        start = struct.unpack_from("<Q", data, 32)[0]
        size, count = struct.unpack_from("<HH", data, 54)
        segments = [struct.unpack_from("<I", data, start + i * size)[0] for i in range(count)]
        self.assertIn(1, segments)  # PT_LOAD
        self.assertNotIn(2, segments)  # PT_DYNAMIC
        self.assertNotIn(3, segments)  # PT_INTERP

    def test_seed_rebuilds_two_matching_generations_without_other_toolchains(self):
        with tempfile.TemporaryDirectory(prefix="volt-bootstrap-") as tmp:
            tree = Path(tmp)
            (tree / "compiler").mkdir()
            (tree / "bootstrap").mkdir()
            (tree / "vstd").mkdir()
            for source in (ROOT / "compiler").glob("*.volt"):
                shutil.copyfile(source, tree / "compiler" / source.name)
            for source in (ROOT / "vstd").glob("*.volt"):
                shutil.copyfile(source, tree / "vstd" / source.name)
            seed = tree / "bootstrap" / "volt-linux-x86_64"
            shutil.copy2(ROOT / "bootstrap" / seed.name, seed)
            env = {"PATH": "", "TMPDIR": tmp}

            def invoke(compiler, *args):
                result = subprocess.run([compiler, *args], cwd=tree, env=env,
                                        capture_output=True, text=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(result.stderr, "")
                return result.stdout

            self.assert_static_elf(seed)
            first, second = tree / "first", tree / "second"
            invoke(seed, "compiler/volt_main.volt", "-o", first)
            invoke(first, "compiler/volt_main.volt", "-o", second)
            self.assert_static_elf(second)
            self.assertTrue(first.read_bytes() == second.read_bytes(), "different compiler generations")

            demo = tree / "hello.volt"
            demo.write_text('for i in 1..=3: print(i)\n', encoding="utf-8")
            self.assertEqual(invoke(second, demo, "--run"), "1\n2\n3\n")


if __name__ == "__main__":
    unittest.main()
