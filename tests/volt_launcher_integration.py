#!/usr/bin/env python3
"""Integration tests for the VOLT launcher CLI and desktop entry."""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FRONTEND = ROOT / "tools" / "volt_launcher.volt"


class VoltLauncherIntegration(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory(prefix="volt-launcher-tests-")
        cls.frontend = Path(cls.tmp.name) / "volt-launch"
        built = subprocess.run([str(ROOT / "volt"), str(FRONTEND), "-o", str(cls.frontend)],
                               cwd=ROOT, capture_output=True, text=True, timeout=30)
        if built.returncode:
            raise AssertionError(built.stdout + built.stderr)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def invoke(self, *args, env=None):
        merged = os.environ.copy()
        merged["VOLT_COMPILER"] = str(ROOT / "volt")
        if env:
            merged.update(env)
        return subprocess.run([str(self.frontend), *args], cwd=ROOT, env=merged,
                              capture_output=True, text=True, timeout=30)

    def test_exact_arguments(self):
        source = Path(self.tmp.name) / "args.volt"
        source.write_text('''use process\nfn main() -> i64:\n    let i: i64 = 1\n    while i < argc():\n        match arg_at(i):\n            Ok(value): put_str(value)\n            Err(error): return 4\n        put_char('\\n')\n        i += 1\n    return 0\n''')
        result = self.invoke("--", str(source), "space value", "", "-x", "$(touch nope)")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "space value\n\n-x\n$(touch nope)\n")
        self.assertFalse((ROOT / "nope").exists())

    def test_source_errors_and_child_status(self):
        self.assertEqual(self.invoke("missing.volt").returncode, 2)
        bad = Path(self.tmp.name) / "bad.volt"
        bad.write_text("not valid VOLT")
        failed = self.invoke(str(bad))
        self.assertEqual(failed.returncode, 1)
        code = Path(self.tmp.name) / "status.volt"
        code.write_text("fn main() -> i64:\n    return 23\n")
        self.assertEqual(self.invoke(str(code)).returncode, 23)

    def test_missing_compiler_is_reported(self):
        result = self.invoke("--", "missing.volt", env={"VOLT_COMPILER": str(Path(self.tmp.name) / "no-compiler")})
        self.assertEqual(result.returncode, 127)
        self.assertEqual(result.stdout, "")
        self.assertEqual(result.stderr, "")

    def test_temp_executable_is_removed(self):
        source = Path(self.tmp.name) / "ok.volt"
        source.write_text("fn main() -> i64:\n    return 0\n")
        with tempfile.TemporaryDirectory(prefix="volt-launch-output-") as directory:
            result = self.invoke(str(source), env={"TMPDIR": directory})
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(list(Path(directory).iterdir()), [])

    def test_browser_alias_and_desktop_entry(self):
        result = self.invoke("browser", "--check", str(ROOT / "examples" / "page.html"))
        self.assertEqual(result.returncode, 0, result.stderr)
        from_home = subprocess.run([str(self.frontend), "browser", "--check"], cwd=Path.home(),
                                   env={**os.environ, "VOLT_COMPILER": str(ROOT / "volt")},
                                   capture_output=True, text=True, timeout=30)
        self.assertEqual(from_home.returncode, 0, from_home.stderr)
        direct_from_home = subprocess.run([str(self.frontend), str(ROOT / "apps" / "browser.volt"), "--check"],
                                          cwd=Path.home(), env={**os.environ, "VOLT_COMPILER": str(ROOT / "volt")},
                                          capture_output=True, text=True, timeout=30)
        self.assertEqual(direct_from_home.returncode, 0, direct_from_home.stderr)
        desktop = (ROOT / "share" / "applications" / "volt-launcher.desktop").read_text()
        self.assertIn("Exec=volt-launch %f", desktop)
        self.assertIn("Terminal=true", desktop)
        self.assertNotIn("/home/chars/", desktop)
        self.assertIn("%f", desktop)
        self.assertFalse(any(ch in desktop for ch in ("%F", "%U", "%u")))
        self.assertTrue((ROOT / "apps" / "browser.volt").is_file())
        self.assertFalse((ROOT / "examples" / "browser.volt").exists())

    def test_browser_alias_without_demo_uses_builtin_home(self):
        with tempfile.TemporaryDirectory(prefix="volt-no-demo-") as tmp:
            install = Path(tmp)
            shutil.copy2(ROOT / "volt", install / "volt")
            for name in ("browser", "vstd"):
                (install / name).symlink_to(ROOT / name, target_is_directory=True)
            env = {"VOLT_COMPILER": str(install / "volt")}
            fallback = self.invoke("browser", "--check", env=env)
            home = self.invoke("browser", "--check", "about:home", env=env)
            self.assertEqual(fallback.returncode, 0, fallback.stdout + fallback.stderr)
            self.assertEqual(home.returncode, 0, home.stdout + home.stderr)
            self.assertEqual(fallback.stdout, home.stdout)


if __name__ == "__main__":
    unittest.main()
