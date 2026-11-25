#!/usr/bin/env python3
"""Exercise static generic Eq bounds through the compiler CLI."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
VOLT = Path(os.environ.get("VOLT_COMPILER", ROOT / "volt")).resolve()
LIBRARY = '''struct Record:
    value: i64

fn contains<T: Eq>(values: []T, needle: T) -> bool:
    for i in 0..len(values):
        if values[i] == needle:
            return true
    return false

fn forward<T>(values: []T, needle: T) -> bool:
    return contains(values, needle)

fn relay<T>(values: []T, needle: T) -> bool:
    return forward(values, needle)
'''


class EqConstraint(unittest.TestCase):
    def invoke(self, source, *args, library=LIBRARY, importer=None):
        with tempfile.TemporaryDirectory(prefix="volt-eq-", dir=ROOT) as tmp:
            path = Path(tmp)
            (path / "eq_lib.volt").write_text(library, encoding="utf-8")
            if importer is not None:
                (path / "importer.volt").write_text(importer, encoding="utf-8")
            main = path / "main.volt"
            main.write_text(source, encoding="utf-8")
            return subprocess.run([VOLT, main, *args], cwd=path, text=True, capture_output=True,
                                  env={**os.environ, "TMPDIR": tmp}, timeout=15)

    def assert_bound_error(self, result, source_line, function, type_name):
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        diagnostic = result.stderr.splitlines()[0]
        self.assertIn(f"/{source_line}: ошибка: ", diagnostic)
        self.assertIn(function, diagnostic)
        self.assertIn("T: Eq", diagnostic)
        self.assertIn(type_name, diagnostic)

    def test_contains_on_ints_and_strings(self):
        result = self.invoke('''use eq_lib
let ints = [2, 4, 6]
let words = ["volt", "core"]
print(contains(ints[0..3], 4), contains(ints[0..3], 5))
print(relay(words[0..2], "v" + "olt"), relay(words[0..2], "other"))
''', "--run")
        self.assertEqual((result.returncode, result.stdout, result.stderr),
                         (0, "true false\ntrue false\n", ""))

    def test_other_supported_types_and_mixed_type_parameters(self):
        result = self.invoke('''enum Kind:
    One
    Two

fn same<T: Eq, U, V: Eq>(a: T, b: T, value: U, c: V, d: V) -> bool:
    return a != b and c == d

print(same('a', 'b', true, Kind.Two, Kind.Two))
print(same(8 as u16, 9 as u16, true, Kind.One, Kind.Two))
''', "--run")
        self.assertEqual((result.returncode, result.stdout, result.stderr),
                         (0, "true\nfalse\n", ""))

    def test_error_is_at_the_call_after_successful_specialization(self):
        result = self.invoke('''use eq_lib
let ints = [1, 2]
print(contains(ints[0..2], 2))
let records = [Record(7), Record(8)]
print(contains(
    records[0..2], records[0]))
''', "-o", "program")
        self.assert_bound_error(result, "main.volt:5", "contains", "Record")

    def test_transitive_call_reports_outer_importer(self):
        result = self.invoke("use importer\n", "-o", "program", importer='''use eq_lib
fn check():
    let ints = [1, 2]
    print(relay(ints[0..2], 2), relay(ints[0..2], 1))
    let records = [Record(7), Record(8)]
    relay(records[0..2], records[0])

check()
''')
        self.assert_bound_error(result, "importer.volt:6", "contains", "Record")

    def test_imported_module_initializer_keeps_its_file(self):
        result = self.invoke("use importer\n", "-o", "program", library='''fn require_eq<T: Eq>(value: T):
    return
''', importer='''use eq_lib

require_eq(true)
''')
        self.assert_bound_error(result, "importer.volt:3", "require_eq", "bool")

    def test_non_eq_types_fail_even_without_comparison_in_body(self):
        for value, type_name in (("true", "bool"), ("1.0", "f64"),
                                 ("0 as ptr<i64>", "ptr<i64>"), ("items", "[1:i64]"),
                                 ("items[0..1]", "[]i64"), ("Some(1)", "Option<i64>"),
                                 ("callback(probe)", "fnptr")):
            with self.subTest(type_name=type_name):
                result = self.invoke(f'''unsafe fn require_eq<T: Eq>(value: T):
    return
fn probe() -> i64:
    return 1
let items = [1]
unsafe:
    require_eq({value})
''', "-o", "program")
                self.assert_bound_error(result, "main.volt:7", "require_eq", type_name)

    def test_only_eq_bounds_on_function_parameters_are_recognized(self):
        cases = (("fn bad<T: Ord>(value: T):\n    return\n", "Ord"),
                 ("fn bad<T: Eq, T>(value: T):\n    return\n", "указан дважды"),
                 ("struct Bad<T: Eq>:\n    value: T\n", "только у функций"))
        for source, message in cases:
            with self.subTest(source=source):
                result = self.invoke(source, "-o", "program")
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn("/main.volt:1: ошибка: ", result.stderr)
                self.assertIn(message, result.stderr.splitlines()[0])


if __name__ == "__main__":
    unittest.main()
