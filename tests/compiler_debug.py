#!/usr/bin/env python3
"""Check source diagnostics and ELF debug data; set VOLT_COMPILER to select a build."""
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
VOLT = Path(os.environ.get("VOLT_COMPILER", ROOT / "volt")).resolve()


class CompilerDebug(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="volt-debug-")
        self.addCleanup(directory.cleanup)
        self.tmp = Path(directory.name)
        self.env = {"PATH": "", "TMPDIR": directory.name, "LC_ALL": "C", "DEBUGINFOD_URLS": ""}

    def source(self, text, name="debug_entry.volt"):
        path = self.tmp / name
        path.write_bytes(text.encode("utf-8") if isinstance(text, str) else text)
        return path

    def invoke(self, binary, *args):
        return subprocess.run([binary, *args], cwd=self.tmp, env=self.env,
                              capture_output=True, encoding="utf-8", timeout=15)

    def build(self, source, *args, name="program"):
        output = self.tmp / name
        result = self.invoke(VOLT, source, "-o", output, *args)
        self.assertEqual((result.returncode, result.stderr), (0, ""), result.stdout)
        return output

    def diagnostic(self, source, *args):
        result = self.invoke(VOLT, source, "-o", self.tmp / "out", *args)
        self.assertEqual((result.returncode, result.stdout), (1, ""), result.stderr)
        return result.stderr.splitlines()

    def test_lexer_preserves_file_line_and_marks_original_byte_column(self):
        source = self.source(b"fn main() -> i64:\r\n\treturn @\r\n")
        header, excerpt, marker = self.diagnostic(source)
        self.assertEqual(header, f"{source}:2: ошибка: неожиданный символ '@'")
        self.assertEqual(excerpt, "  |     return @")
        self.assertEqual(excerpt.index("@"), marker.index("^"))
        self.assertTrue(marker.endswith("байтовая колонка 9"))

    def test_long_line_is_cropped_around_known_location(self):
        head = 'print("' + "x" * 1024
        source = self.source(head + r"\q" + "y" * 1024 + '")')
        header, excerpt, marker = self.diagnostic(source)
        self.assertIn("неизвестный escape", header)
        self.assertTrue(excerpt.startswith("  | ...") and excerpt.endswith("..."))
        self.assertLessEqual(len(excerpt), 130)
        self.assertEqual(excerpt.index("\\q"), marker.index("^"))
        self.assertTrue(marker.endswith(f"байтовая колонка {len(head) + 1}"))

    def test_escapes_terminal_controls_and_reports_exact_unicode_byte_offset(self):
        head = 'print("é\x1b\u202e") '
        source = self.source(head + "@\n", "file\nname.volt")
        header, excerpt, marker = self.diagnostic(source)
        self.assertIn(r"file\x0aname.volt:1: ошибка:", header)
        self.assertIn(r"é\x1b\xe2\x80\xae", excerpt)
        self.assertEqual(marker, f"  = байтовая колонка {len(head.encode('utf-8')) + 1}")

    def test_input_nul_and_open_comment_point_to_actual_location(self):
        for text, message in ((b"# comment\nabc\x00def\n", "NUL"),
                              (b"# comment\nabc/* open\nmore\n", "незакрытый /* комментарий")):
            with self.subTest(message=message):
                source = self.source(text)
                header, excerpt, marker = self.diagnostic(source)
                self.assertTrue(header.startswith(f"{source}:2: ошибка:"))
                self.assertIn(message, header)
                self.assertEqual(excerpt.index("abc") + 3, marker.index("^"))
                self.assertTrue(marker.endswith("байтовая колонка 4"))

    def test_parser_eof_has_no_column_but_imported_name_error_does(self):
        source = self.source("fn main() -> i64")
        header, excerpt, marker = self.diagnostic(source, "--parse")
        self.assertTrue(header.startswith(f"{source}:1: ошибка:"))
        self.assertEqual((excerpt, marker), ("  | fn main() -> i64", "  = колонка неизвестна"))

        source = self.source("use debug_dependency\n")
        dependency = self.source("fn bad() -> i64:\n    return missing_name\n", "debug_dependency.volt")
        header, excerpt, marker = self.diagnostic(source)
        self.assertTrue(header.startswith(f"{dependency}:2: ошибка:"))
        # Semantic errors show the recorded byte column of the offending name.
        self.assertEqual(excerpt, "  |     return missing_name")
        self.assertEqual(excerpt.index("missing_name"), marker.index("^"))
        self.assertTrue(marker.endswith("байтовая колонка 12"))

    def test_encoder_has_function_location_but_no_source_column(self):
        source = self.source("# native code\nnative fn demo() -> i64:\n{\n    ud6\n}\n")
        header, excerpt, marker = self.diagnostic(source)
        self.assertTrue(header.startswith(f"{source}:2: ошибка: x86-64:"))
        self.assertIn("ud6", header)
        self.assertEqual((excerpt, marker), ("  | native fn demo() -> i64:", "  = колонка неизвестна"))

    def test_does_not_echo_foreign_elf_files_or_unbounded_token_text(self):
        elf = bytearray(64)
        elf[:7] = b"\x7fELF\x02\x01\x01"
        struct.pack_into("<HH", elf, 16, 3, 62)  # ET_DYN, EM_X86_64, no section table
        self.source(elf + b"DO_NOT_SHOW\n", "bad.so")
        messages = self.diagnostic(self.source('link "-L. -l:bad.so"\n'))
        self.assertEqual(len(messages), 1, messages)
        self.assertIn("bad.so:1: ошибка: ELF:", messages[0])

        source = self.source('fn "' + "x" * 4096 + '"')
        header, excerpt, _ = self.diagnostic(source, "--parse")
        self.assertIn("ожидалось", header)
        self.assertLess(len(header), 800)
        self.assertLessEqual(len(excerpt), 130)

    def debug_program(self):
        self.source("# Module\nfn debug_value() -> i64:\n    return 3\n"
                    "\nfn debug_identity<T>(value: T) -> T:\n    return value\n", "debug_dependency.volt")
        return self.source("use debug_dependency\n\nfn main() -> i64:\n"
                           "    print(debug_value(), debug_identity(39))\n    return 0\n")

    def test_debug_sections_are_opt_in_and_repeatable(self):
        source = self.debug_program()
        release_listing, debug_listing = self.tmp / "release.s", self.tmp / "debug.s"
        release = self.build(source, "-S", release_listing, name="release")
        debug = self.build(source, "-S", debug_listing, "-g")
        self.assertEqual(release_listing.read_bytes(), debug_listing.read_bytes())
        for program in (release, debug):
            result = self.invoke(program)
            self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "3 39\n", ""))
        plain_bytes, debug_bytes = release.read_bytes(), debug.read_bytes()
        self.assertNotIn(b".debug_line\0", plain_bytes)
        for name in (b".debug_line\0", b".debug_info\0", b".debug_abbrev\0"):
            self.assertIn(name, debug_bytes)
        self.assertEqual(debug_bytes, self.build(source, "-g", name="repeat").read_bytes())
        # Program headers must remain unchanged: debug sections are not loaded.
        entry_size, entry_count = struct.unpack_from("<HH", plain_bytes, 54)
        self.assertEqual(plain_bytes[64:64 + entry_size * entry_count],
                         debug_bytes[64:64 + entry_size * entry_count])

    def test_g_requires_an_elf_output(self):
        source = self.source("print(42)\n")
        for mode in ("--parse", "--emit-asm"):
            with self.subTest(mode=mode):
                self.assertEqual(self.diagnostic(source, "-g", mode), ["volt: -g требует выходной ELF"])

    def tool(self, name):
        binary = shutil.which(name)
        if not binary:
            self.skipTest(f"{name} is not available")
        return binary

    def test_readelf_maps_precise_function_start_addresses(self):
        readelf = self.tool("readelf")
        debug = self.build(self.debug_program(), "-g")
        symbols = self.invoke(readelf, "--syms", "--wide", debug)
        lines = self.invoke(readelf, "--debug-dump=decodedline", "--wide", debug)
        for result in (symbols, lines):
            self.assertEqual((result.returncode, result.stderr), (0, ""), result.stdout)
        for name, path, line in (("VOLT_f_debug_entry_main", "debug_entry.volt", 3),
                                 ("VOLT_f_debug_dependency_debug_value", "debug_dependency.volt", 2),
                                 (r"VOLT_f_debug_dependency_debug_identity\S*", "debug_dependency.volt", 5)):
            symbol = re.search(rf"^\s*\d+:\s+([0-9a-f]+)\s+.*\s{name}$", symbols.stdout, re.M)
            self.assertIsNotNone(symbol, name)
            address = int(symbol[1], 16)
            self.assertRegex(lines.stdout, rf"{re.escape(path)}\s+{line}\s+0x0*{address:x}(?:\s|$)")

        source = self.source("# Top-level code\n\nprint(42)\n", "top_level.volt")
        top = self.build(source, "-g", name="top")
        lines = self.invoke(readelf, "--debug-dump=decodedline", "--wide", top)
        self.assertEqual((lines.returncode, lines.stderr), (0, ""), lines.stdout)
        self.assertRegex(lines.stdout, r"top_level\.volt\s+3\s+0x[0-9a-f]+")

    def test_gdb_resolves_source_breakpoint(self):
        gdb = self.tool("gdb")
        source = self.debug_program()
        debug = self.build(source, "-g")
        result = self.invoke(gdb, "-nx", "-nh", "-q", "-batch", "-iex", "set auto-load off",
                             "-ex", "info line VOLT_f_debug_entry_main",
                             "-ex", "break debug_entry.volt:3",
                             "-ex", "break debug_entry.volt:4", debug)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f'Line 3 of "{source}" starts at address ', result.stdout)
        # A breakpoint on the declaration line skips the prologue and lands on
        # the first statement; a statement line resolves exactly.
        self.assertRegex(result.stdout, r"Breakpoint 1 at 0x[0-9a-f]+: file .*debug_entry\.volt, line 4\.")
        self.assertRegex(result.stdout, r"Breakpoint 2 at 0x[0-9a-f]+: file .*debug_entry\.volt, line 4\.")

    def test_gdb_next_steps_through_statements(self):
        gdb = self.tool("gdb")
        self.source("fn step_add(x: i64, y: i64) -> i64:\n"
                    "    let total: i64 = x + y\n"
                    "    return total\n", "step_dependency.volt")
        source = self.source("use step_dependency\n"
                             "\n"
                             "fn main() -> i64:\n"
                             "    let a: i64 = step_add(2, 3)\n"
                             "    let b: i64 = a * 2\n"
                             "    print(b)\n"
                             "    return 0\n", "step_entry.volt")
        debug = self.build(source, "-g")
        commands = ["break VOLT_f_step_entry_main", "break step_dependency.volt:2", "run"]
        commands += ["next"] * 5
        args = [gdb, "-nx", "-nh", "-q", "-batch", "-iex", "set auto-load off"]
        for command in commands:
            args += ["-ex", command]
            if command in ("run", "next"):
                args += ["-ex", "frame 0"]
        result = self.invoke(*args, debug)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        stopped = re.findall(r"^#0\s+.*?\sat\s+\S*/(step_\w+\.volt):(\d+)$", result.stdout, re.M)
        self.assertEqual(stopped, [("step_entry.volt", "4"),
                                   ("step_dependency.volt", "2"),
                                   ("step_dependency.volt", "3"),
                                   ("step_entry.volt", "5"),
                                    ("step_entry.volt", "6"),
                                    ("step_entry.volt", "7")], result.stdout)

    def test_gdb_shows_args_locals_and_nested_scopes(self):
        gdb = self.tool("gdb")
        source = self.source("fn measure(a: i64, scale: i64) -> i64:\n"
                             "    let total: i64 = a + scale\n"
                             "    let big: bool = total > 10\n"
                             "    if big:\n"
                             "        let total: i64 = total * 2\n"
                             "        let mark: char = 'H'\n"
                             "        total = total + 1\n"
                             "    let ratio: f64 = 1.5\n"
                             "    return total\n"
                             "\n"
                             "fn main() -> i64:\n"
                             "    let answer: i64 = measure(4, 8)\n"
                             "    let tiny: u8 = 200\n"
                             "    let name: string = \"volt\"\n"
                             "    let pi2: f64 = 3.25\n"
                             "    print(answer, tiny, name, pi2)\n"
                             "    return 0\n", "vars_entry.volt")
        debug = self.build(source, "-g")
        commands = ["break VOLT_f_vars_entry_measure", "run", "info args", "info locals"]
        commands += ["next", "info locals"] * 11
        args = [gdb, "-nx", "-nh", "-q", "-batch", "-iex", "set auto-load off"]
        for command in commands:
            args += ["-ex", command]
        result = self.invoke(*args, debug)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        stops = list(re.finditer(r"(?m)^(\d+)\t ", result.stdout))
        self.assertEqual([int(stop[1]) for stop in stops],
                         [2, 3, 4, 5, 6, 7, 8, 9, 13, 14, 15, 16], result.stdout)
        segments = []
        for index, stop in enumerate(stops):
            end = stops[index + 1].start() if index + 1 < len(stops) else len(result.stdout)
            segments.append(result.stdout[stop.start():end])
        # info args at the entry breakpoint: parameter names and values.
        self.assertIn("a = 4", segments[0])
        self.assertIn("scale = 8", segments[0])
        self.assertNotIn("total =", segments[0])
        # Locals initialized so far, with DWARF base types driving the format.
        self.assertIn("total = 12", segments[1])
        self.assertNotIn("big =", segments[1])
        self.assertIn("big = true", segments[2])
        # At `let total = total * 2`, the right-hand side still sees the outer total.
        self.assertRegex(segments[3], r"(?m)^total = 12$")
        self.assertNotIn("<shadowed>", segments[3])
        # Inside the nested block the inner binding shadows the outer one.
        self.assertIn("total = 24", segments[4])
        self.assertIn("mark = 72 'H'", segments[5])
        self.assertIn("total = 24", segments[5])
        # After the block the outer variable is visible again with its value.
        self.assertIn("total = 12", segments[6])
        self.assertNotIn("total = 24", segments[6])
        self.assertIn("ratio = 1.5", segments[7])
        # Top-level statements are locals of the startup wrapper.
        self.assertIn("answer = 12", segments[8])
        self.assertIn("tiny = 200", segments[9])
        self.assertRegex(segments[10], r'name = 0x[0-9a-f]+ "volt"')
        self.assertIn("pi2 = 3.25", segments[11])

    def test_gdb_shows_loop_and_match_bindings_in_their_bodies(self):
        gdb = self.tool("gdb")
        source = self.source("fn main() -> i64:\n"
                             "    let subject: Option<i64> = Some(7)\n"
                             "    for j in 0..1:\n"
                             "        match subject:\n"
                             "            Some(payload): print(j, payload)\n"
                             "            None: print(0)\n"
                             "    return 0\n", "bindings.volt")
        debug = self.build(source, "-g")
        result = self.invoke(gdb, "-nx", "-nh", "-q", "-batch", "-iex", "set auto-load off",
                             "-ex", "break bindings.volt:5", "-ex", "break bindings.volt:7",
                             "-ex", "run", "-ex", "info locals", "-ex", "continue",
                             "-ex", "info locals", debug)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        body, after = result.stdout.split("Breakpoint 2,", 1)
        self.assertIn("j = 0", body)
        self.assertIn("payload = 7", body)
        self.assertNotIn("j =", after)
        self.assertNotIn("payload =", after)

    def test_debug_allows_generic_pointee_without_a_layout(self):
        source = self.source("struct Box<T>:\n"
                             "    value: T\n"
                             "unsafe fn accept(value: ptr<Box<i64>>):\n"
                             "    print(value == (0 as ptr<Box<i64>>))\n")
        self.build(source, "-g")

    def test_gdb_uses_outer_scope_in_defer_on_nested_return(self):
        gdb = self.tool("gdb")
        source = self.source("fn calculate() -> i64:\n"
                             "    let value = 11\n"
                             "    defer print(value)\n"
                             "    if true:\n"
                             "        let value = 22\n"
                             "        return value\n"
                             "    return 0\n"
                             "print(calculate())\n", "defer_scope.volt")
        debug = self.build(source, "-g")
        result = self.invoke(gdb, "-nx", "-nh", "-q", "-batch", "-iex", "set auto-load off",
                             "-ex", "break defer_scope.volt:3", "-ex", "run",
                             "-ex", "info locals", debug)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertRegex(result.stdout, r"(?m)^value = 11(?:\s|$)")
        self.assertNotIn("value = 22", result.stdout)

    def test_gdb_does_not_show_outer_value_for_unsupported_inner_type(self):
        gdb = self.tool("gdb")
        source = self.source("fn main() -> i64:\n"
                             "    let value: i64 = 11\n"
                             "    if true:\n"
                             "        let value: [2]i64 = [22, 33]\n"
                             "        print(len(value))\n"
                             "    return value\n", "array_scope.volt")
        debug = self.build(source, "-g")
        result = self.invoke(gdb, "-nx", "-nh", "-q", "-batch", "-iex", "set auto-load off",
                             "-ex", "break array_scope.volt:5", "-ex", "run", "-ex", "print value", debug)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertRegex(result.stdout, r"(?m)^\$1 = <(?:optimized out|unavailable)>")


if __name__ == "__main__":
    unittest.main()
