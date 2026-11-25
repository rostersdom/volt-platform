#!/usr/bin/env python3
"""Exercise slice lifetimes through the CLI; set VOLT_COMPILER to select a build."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
VOLT = Path(os.environ.get("VOLT_COMPILER", ROOT / "volt")).resolve()


class SliceLifetimes(unittest.TestCase):
    def invoke(self, source, *, run):
        with tempfile.TemporaryDirectory(prefix="volt-borrow-") as tmp:
            path = Path(tmp) / "main.volt"
            path.write_text(source, encoding="utf-8")
            args = ["--run"] if run else ["-o", str(path.with_suffix(""))]
            return subprocess.run([VOLT, path, *args], cwd=tmp, capture_output=True,
                                  text=True, timeout=15)

    def assert_runs(self, source, stdout):
        result = self.invoke(source, run=True)
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, stdout, ""))

    def assert_rejected(self, source, diagnostic):
        result = self.invoke(source, run=False)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertRegex(result.stderr, r"main\.volt:\d+: ошибка: ")
        self.assertIn(diagnostic, result.stderr)

    def test_overlapping_read_only_slices(self):
        self.assert_runs('''fn firsts(left: []i64, right: []i64) -> i64:
    return left[0] + right[0]

let values: [4]i64 = [10, 20, 30, 40]
let left = values[0..3]
let right = values[1..4]
print(firsts(left, right), values[2], firsts(values[1..3], values[2..4]))
''', "30 30 50\n")

    def test_slice_rebinding_is_rejected_before_lowering(self):
        source = '''let values = [1, 2]
let outer = values[0..1]
if true:
    let local = [3, 4]
    let view = local[0..2]
    let alias = view
'''
        for assignment in ("outer = local[0..2]", "outer = alias", "alias = view"):
            with self.subTest(assignment=assignment):
                self.assert_rejected(source + f"    {assignment}\n", "присваивание slice запрещено")

    def test_borrow_ends_after_block_cleanup(self):
        self.assert_runs('''let values = [1, 2]
for i in 0..2:
    if i == 0:
        let view = values[0..2]
        let alias = view
        defer print(alias[0])
    values[0] += 10
print(values[0])
''', "1\n21\n")

    def test_deferred_write_checks_later_loans_in_same_block(self):
        self.assert_rejected('''let values = [1, 2]
defer values[0] = 3
let view = values[0..2]
let alias = view
defer print(alias[0])
''', "нельзя менять массив, пока slice ссылается на него")

    def test_outer_defer_writes_after_inner_block_cleanup(self):
        self.assert_runs('''fn show(view: []i64):
    print(view[0])

let values = [1, 2]
defer print(values[0])
defer values[0] = 3
if true:
    defer show(values[0..2])
''', "1\n3\n")

    def test_loop_exit_cleans_up_before_write(self):
        self.assert_runs('''let values = [1, 2]
for i in 0..3:
    let view = values[0..2]
    defer print(view[i])
    if i == 0: continue
    break
values[0] = 3
print(values[0])
''', "1\n2\n3\n")

    def test_nested_loans_do_not_release_the_ancestor_loan(self):
        self.assert_rejected('''let values = [1, 2]
let outer = values[0..2]
if true:
    let inner = values[0..1]
    let alias = outer
    defer print(inner[0], alias[1])
values[1] = 3
''', "нельзя менять массив, пока slice ссылается на него")

    def test_writes_through_nested_projections_are_rejected(self):
        source = '''struct Point:
    x: i64
let points = [Point(1), Point(2)]
let view = points[0..2]
let alias = view
'''
        for assignment, diagnostic in (
            ("points[0].x += 1", "нельзя менять массив, пока slice ссылается на него"),
            ("view[0].x = 3", "неизменяемый slice нельзя изменять"),
            ("alias[0].x = 3", "неизменяемый slice нельзя изменять"),
            ("points = points", "нельзя менять массив, пока slice ссылается на него"),
        ):
            with self.subTest(assignment=assignment):
                self.assert_rejected(source + assignment + "\n", diagnostic)

    def test_slice_parameter_cannot_be_rebound(self):
        self.assert_rejected('''fn change(view: []i64):
    let local = [1, 2]
    defer view = local[0..1]
''', "присваивание slice запрещено")

    def test_deferred_flow_control_is_rejected(self):
        self.assert_rejected('''enum Choice:
    First
    Second
let choice = Choice.First
defer match choice:
    Choice.First: print(1)
    Choice.Second: print(2)
''', "defer допускает только простой оператор без flow-control")

    def test_slices_cannot_return_from_a_function(self):
        for source in (
            "fn bad(view: []i64) -> []i64:\n    return view\n",
            "fn bad() -> []i64:\n    let data = [1]\n    return data[0..1]\n",
            "fn bad(view: []i64) -> []i64:\n    let alias = view\n    return alias\n",
        ):
            with self.subTest(source=source):
                self.assert_rejected(source, "возврат slice пока запрещён")

    def test_slices_cannot_be_stored_in_arrays(self):
        source = '''let values = [1, 2]
let view = values[0..1]
let alias = view
'''
        for declaration in ("let views = [values[0..1]]", "let views: [1][]i64", "let views = [alias]"):
            with self.subTest(declaration=declaration):
                self.assert_rejected(source + declaration + "\n", "slice нельзя хранить в массиве")

    def test_slice_alias_cannot_be_stored_in_struct(self):
        self.assert_rejected('''struct Holder:
    view: []i64

let values = [1, 2]
let view = values[0..2]
let alias = view
let holder = Holder(alias)
''', "slice нельзя хранить в struct")

    def test_slice_alias_copies_address_and_length(self):
        self.assert_runs('''fn inspect(view: []i64):
    let alias = view
    print(len(alias), alias[0], alias[1])

let values = [10, 20, 30, 40]
let view = values[1..3]
let alias: []i64 = view
inspect(alias)
''', "2 20 30\n")

    def test_slice_alias_preserves_an_empty_range(self):
        self.assert_runs('''fn size(view: []i64) -> i64:
    let alias = view
    return len(alias)

let values = [10, 20]
let view = values[2..2]
let alias = view
print(len(alias), size(alias))
''', "0 0\n")

    def test_defer_keeps_the_slice_alias_visible_before_shadowing(self):
        self.assert_runs('''let values = [11, 22]
let view = values[0..2]
let alias = view
if true:
    defer print(len(alias), alias[0], alias[1])
    let values = [33, 44]
    values[1] += 1
    let view = values[1..2]
    let alias = view
    defer print(len(alias), alias[0])
print(alias[1])
''', "1 45\n2 11 22\n22\n")

    def test_defer_cannot_use_a_slice_alias_declared_after_it(self):
        self.assert_rejected('''let values = [1, 2]
let view = values[0..2]
defer print(len(alias))
let alias = view
''', "объявленную после defer")

    def test_slice_alias_requires_a_name(self):
        self.assert_rejected('''fn inspect(view: []i64):
    let alias = view as []i64
    print(len(alias))
''', "инициализатор slice: нужен диапазон локального массива или имя неизменяемого slice")

    def test_address_from_a_slice_requires_explicit_unsafe(self):
        self.assert_rejected('''fn inspect(view: []i64) -> i64:
    let interface_address = &view[0]
    return len(view)
''', "взятие raw-адреса slice требует unsafe-блок или unsafe-функцию")

    def test_defer_range_checks_local_visibility(self):
        self.assert_rejected('''fn show(view: []i64):
    print(view[0])

defer show(values[0..1])
let values = [1, 2]
''', "объявленную после defer")


if __name__ == "__main__":
    unittest.main()
