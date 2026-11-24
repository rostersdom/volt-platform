#!/usr/bin/env python3
"""Exercise explicit, declarative dependency manifests through the compiler CLI."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
VOLT = Path(os.environ.get("VOLT_COMPILER", ROOT / "volt")).resolve()


class CompilerManifest(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory(prefix="volt-manifest-")
        self.addCleanup(folder.cleanup)
        self.cwd = Path(folder.name)
        self.project = self.cwd / "project"
        self.project.mkdir()
        self.source = self.project / "main.volt"
        self.source.write_text('print("ok")\n', encoding="utf-8")
        self.manifest = self.project / "volt.mod"
        self.output = self.cwd / "output"

    def compile(self, *args):
        return subprocess.run([VOLT, self.source, *args], cwd=self.cwd,
                              env={"PATH": ""}, capture_output=True, encoding="utf-8", timeout=15)

    def test_manifest_links_a_shared_library_relative_to_its_directory(self):
        cc = shutil.which("cc")
        if not cc:
            self.skipTest("native fixture requires a system C compiler")
        library_dir = self.project / "local libs"
        library_dir.mkdir()
        native = self.project / "answer.c"
        native.write_text("int volt_manifest_answer(void) { return 42; }\n", encoding="utf-8")
        subprocess.run([cc, "-shared", "-fPIC", "-o", library_dir / "manifest-answer.so.1", native],
                       check=True, timeout=15, capture_output=True)
        self.source.write_text('link "-lm"\n'
                               "unsafe extern fn modf(value: f64, integer_part: ptr<f64>) -> f64\n"
                               "unsafe extern fn volt_manifest_answer() -> i32\n"
                               "let integer_part: f64\n"
                               "unsafe: print(volt_manifest_answer(), modf(3.5, &integer_part), integer_part)\n",
                               encoding="utf-8")
        self.manifest.write_bytes(b"# Dependencies\r\n\r\n library-dir = local libs\r\n"
                                  b"library = :manifest-answer.so.1\r\n"
                                  b"library = :manifest-answer.so.1\r\n")
        missing = self.compile("-o", self.output)
        self.assertEqual(missing.returncode, 1, missing.stdout + missing.stderr)
        self.assertIn("неопределённый символ", missing.stderr)
        built = self.compile("--manifest", self.manifest.relative_to(self.cwd), "-o", self.output)
        self.assertEqual((built.returncode, built.stderr), (0, ""), built.stdout)
        answer = subprocess.run([self.output], cwd=self.cwd,
                                env={"LD_LIBRARY_PATH": str(library_dir)},
                                capture_output=True, encoding="utf-8", timeout=5)
        self.assertEqual((answer.returncode, answer.stdout, answer.stderr), (0, "42 0.500000 3.000000\n", ""))

    def test_manifest_errors_include_file_and_line(self):
        for text, message in ((b"build = command", "допустимы только"),
                              (b"library = m -lc", "неверное имя"),
                              (b"library-dir = ", "пустой путь"),
                              (b"library m", "ожидалось имя"),
                              (b"library = m\x00", "NUL")):
            with self.subTest(text=text):
                self.manifest.write_bytes(b"# Header\n" + text)
                result = self.compile("--manifest", self.manifest, "-o", self.output)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn(f"{self.manifest}:2: ошибка:", result.stderr)
                self.assertIn(message, result.stderr)
                self.assertFalse(self.output.exists())

    def test_manifest_limits_and_output_protection(self):
        self.manifest.write_bytes(b"#" * 65537)
        oversized = self.compile("--manifest", self.manifest, "-o", self.output)
        self.assertEqual(oversized.returncode, 1)
        self.assertIn("слишком большой файл", oversized.stderr)
        self.manifest.write_text("library = m\n" * 65, encoding="utf-8")
        excessive = self.compile("--manifest", self.manifest, "-o", self.output)
        self.assertEqual(excessive.returncode, 1)
        self.assertIn(":65: ошибка: volt.mod: не более 64", excessive.stderr)
        self.manifest.write_text("# Keep this\n", encoding="utf-8")
        alias = self.cwd / "manifest-alias"
        alias.symlink_to(self.manifest)
        for args in (("-o", alias), ("-S", alias, "-o", self.output)):
            with self.subTest(args=args):
                overwrite = self.compile("--manifest", self.manifest, *args)
                self.assertEqual(overwrite.returncode, 1)
                self.assertIn("нельзя перезаписывать манифест", overwrite.stderr)
                self.assertEqual(self.manifest.read_text(encoding="utf-8"), "# Keep this\n")

    def test_unselected_manifest_does_not_change_static_builds(self):
        self.manifest.write_text("invalid syntax\n", encoding="utf-8")
        reference = self.compile("-o", self.output)
        self.assertEqual((reference.returncode, reference.stderr), (0, ""))
        before = self.output.read_bytes()
        self.manifest.write_bytes(b"# Comment\n" + b"\n" * (65536 - len(b"# Comment\n")))
        built = self.compile("--manifest", self.manifest, "-o", self.output)
        self.assertEqual((built.returncode, built.stderr), (0, ""))
        self.assertEqual(self.output.read_bytes(), before)

    def test_manifest_is_only_for_elf_builds(self):
        self.manifest.write_text("# Empty manifest\n", encoding="utf-8")
        for mode in ("--parse", "--emit-asm"):
            with self.subTest(mode=mode):
                result = self.compile("--manifest", self.manifest, mode)
                self.assertEqual(result.returncode, 1)
                self.assertIn("--manifest требует выходной ELF", result.stderr)

    def test_manifest_path_resolves_symlinks_before_parent_components(self):
        child = self.project / "real" / "child"
        child.mkdir(parents=True)
        chosen = child.parent / "volt.mod"
        chosen.write_text("library = m\n", encoding="utf-8")
        self.manifest.write_text("not the selected manifest\n", encoding="utf-8")
        through = self.project / "through"
        through.symlink_to("real/child", target_is_directory=True)
        spelling = through / ".." / "volt.mod"
        built = self.compile("--manifest", spelling, "-o", self.output)
        self.assertEqual((built.returncode, built.stderr), (0, ""), built.stdout + built.stderr)
        overwrite = self.compile("--manifest", spelling, "-o", chosen)
        self.assertEqual(overwrite.returncode, 1)
        self.assertIn("нельзя перезаписывать манифест", overwrite.stderr)
        self.assertEqual(chosen.read_text(encoding="utf-8"), "library = m\n")

    def test_unavailable_manifest_library_points_at_its_declaration(self):
        self.manifest.write_text("# Diagnostics\n\nlibrary = volt_test_missing_5ef36c\n", encoding="utf-8")
        missing = self.compile("--manifest", self.manifest, "-o", self.output)
        self.assertEqual(missing.returncode, 1)
        self.assertIn(f"{self.manifest}:3: ошибка:", missing.stderr)
        self.assertIn("библиотека x86-64 не найдена", missing.stderr)
        self.assertIn("  | library = volt_test_missing_5ef36c", missing.stderr)
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
