#!/usr/bin/env python3
"""Exercise slice borrow rules through the public compiler CLI."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
VOLT = Path(os.environ.get("VOLT_COMPILER", ROOT / "volt")).resolve()
TAIL = '''fn tail(input: []i64) -> []i64 from input:
    if len(input) == 0: return input
    return input[1..len(input)]

'''


class SliceBorrows(unittest.TestCase):
    def invoke(self, source, *, run):
        with tempfile.TemporaryDirectory(prefix="volt-slice-borrow-") as tmp:
            path = Path(tmp) / "main.volt"
            path.write_text(source, encoding="utf-8")
            args = ["--run"] if run else ["-o", str(path.with_suffix(""))]
            return subprocess.run([VOLT, path, *args], cwd=tmp, capture_output=True,
                                  text=True, timeout=15)

    def assert_runs(self, source, expected):
        result = self.invoke(source, run=True)
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, expected, ""))

    def assert_rejected(self, source, diagnostic):
        result = self.invoke(source, run=False)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertRegex(result.stderr, r"main\.volt:\d+: ошибка: ")
        self.assertIn(diagnostic, result.stderr)

    def assert_panics(self, source, diagnostic):
        result = self.invoke(source, run=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stderr, diagnostic + "\n")

    def test_exclusive_loan_mutates_original_and_ends_after_defer(self):
        self.assert_runs('''struct Point:
    x: i64

let points = [Point(10), Point(20), Point(30)]
if true:
    let view: []mut Point = mut points[1..len(points)]
    if true:
        print(len(view), view[0].x)
        view[1] = Point(31)
    defer print(view[0].x, view[1].x)
    defer view[0].x += 4
points[0].x = 9
let read = points[0..3]
print(read[0].x, read[1].x, read[2].x)
''', "2 20\n24 31\n9 24 31\n")

    def test_whole_array_conflicts_in_both_orders(self):
        cases = (
            ("let first = values[0..1]", "mut values[1..2]", "массив уже заимствован"),
            ("let first = mut values[0..1]", "values[1..2]", "заимствован изменяемым slice"),
            ("let first = mut values[0..1]", "mut values[1..2]", "заимствован изменяемым slice"),
            ("let first = values[0..0]", "mut values[2..2]", "массив уже заимствован"),
        )
        for first, second, diagnostic in cases:
            with self.subTest(first=first, second=second):
                self.assert_rejected(f'''let values = [1, 2]
{first}
if true:
    let second = {second}
''', diagnostic)

    def test_owner_cannot_be_used_after_exclusive_loan(self):
        for use in (
            "print(values[1])", "print(len(values))", "values[1] = 3",
            "let copied = values", "let addr = &values[1]", "values = values",
            "show(values[1..2])", "defer print(values[0])",
        ):
            with self.subTest(use=use):
                self.assert_rejected('''fn show(view: []i64):
    print(len(view))

let values = [1, 2]
let view = mut values[0..1]
if true:
    view[0] += 1
''' + use + "\n", "заимствован изменяемым slice")

    def test_owner_cannot_be_used_after_loan_begins_within_expression(self):
        self.assert_rejected('''fn change(view: []mut i64) -> i64:
    view[0] = 2
    return 0

let values = [1]
print(values[change(mut values[0..1])])
''', "заимствован изменяемым slice")
        self.assert_rejected('''struct Point:
    x: i64

fn show(value: Point, view: []mut Point):
    print(value.x, view[0].x)

let points = [Point(1)]
show(points[0], mut points[0..1])
''', "заимствован изменяемым slice")

    def test_string_repetition_evaluates_operands_left_to_right(self):
        setup = '''fn update(view: []mut i64) -> string:
    view[0] = 3
    return "x"

let values = [2]
'''
        self.assert_runs(setup + '''if true:
    print(values[0] * update(mut values[0..1]))
print(values[0])
''', "xx\n3\n")
        self.assert_rejected(setup + 'print(update(mut values[0..1]) * values[0])\n',
                             "заимствован изменяемым slice")

    def test_earlier_defer_cannot_use_exclusively_borrowed_owner(self):
        for action in (
            "print(values[0])", "values[0] = 3", "other = values[0]",
            "show(values[0..1])", "address = &values[0]",
        ):
            with self.subTest(action=action):
                diagnostic = "массив уже заимствован" if action.startswith("show(") else "заимствован изменяемым slice"
                self.assert_rejected(f'''fn show(view: []i64):
    print(len(view))

let values = [1, 2]
let other = 0
let address: ptr<i64>
defer {action}
let view = mut values[1..2]
''', diagnostic)

    def test_outer_defer_runs_after_inner_exclusive_loan_ends(self):
        self.assert_runs('''let values = [1]
defer print(values[0])
defer values[0] += 10
if true:
    let view = mut values[0..1]
    defer view[0] += 1
''', "12\n")

    def test_continue_and_break_run_defers_before_releasing_loan(self):
        self.assert_runs('''let values = [1, 2]
for i in 0..4:
    let view = mut values[0..2]
    defer print(view[0])
    defer view[0] += i + 10
    if i == 0: continue
    break
values[1] += 1
print(values[0], values[1])
''', "11\n22\n22 3\n")

    def test_mut_slice_parameters_are_scoped_and_distinct(self):
        self.assert_runs('''fn write_views(first: []mut i64, second: []mut i64):
    first[0] += second[0]
    second[0] = 10

fn set_to_len(view: []mut i64):
    view[0] = len(view)

let left = [1]
let right = [2]
if true:
    let view = mut left[0..1]
    write_views(view, mut right[0..1])
    print(view[0])
    defer set_to_len(view)
print(left[0], right[0])
if true:
    defer set_to_len(mut right[0..len(right)])
print(right[0])
''', "3\n1 10\n1\n")
        self.assert_rejected('''fn compare(first: []mut i64, second: []mut i64):
    print(first[0], second[0])

let values = [1]
let view = mut values[0..1]
compare(view, view)
''', "изменяемый slice нельзя передать дважды")

    def test_mut_slice_does_not_alias_or_escape(self):
        for operation, diagnostic in (
            ("let alias = view", "изменяемый slice нельзя копировать"),
            ("let alias: []i64 = view", "нельзя присвоить"),
            ("let alias = view as []mut i64", "приведение изменяемого slice запрещено"),
            ("view = view", "присваивание slice запрещено"),
            ("let contents = [view]", "slice нельзя хранить в массиве"),
            ("let alias: []mut i64", "slice требует инициализатор"),
            ("unsafe:\n    let ptr_to_view = &view", "нельзя взять адрес дескриптора"),
            ("let sub = mut view[0..1]", "slice source должен быть локальным массивом"),
        ):
            with self.subTest(operation=operation):
                self.assert_rejected("let values = [1]\nlet view = mut values[0..1]\n" + operation + "\n", diagnostic)
        for source, diagnostic in (
            ("struct Holder:\n    view: []mut i64\n", "slice нельзя хранить в struct"),
            ("extern fn external(view: []mut i64)\n", "slice не поддерживается в native/extern ABI"),
            ("fn escape(view: []mut i64) -> []mut i64:\n    return view\n", "возврат slice пока запрещён"),
            ("fn escape() -> []mut i64:\n    let values = [1]\n    return mut values[0..1]\n", "возврат slice пока запрещён"),
        ):
            with self.subTest(source=source):
                self.assert_rejected(source, diagnostic)

    def test_mut_slice_runtime_bounds(self):
        self.assert_runs("let values = [3]\nprint(len(mut values[1..1]))\n", "0\n")
        self.assert_panics("let values = [3]\nlet view = mut values[0..2]\n", "volt: invalid slice range")
        self.assert_panics("let values = [3]\nlet view = mut values[0..1]\nview[1] = 5\n",
                           "volt: slice index out of bounds")
        self.assert_panics("let values = [3]\nlet view = mut values[0..3]\nlet got: []i64 = view[0..4]\n",
                           "volt: invalid slice range")

    def test_mut_slice_read_reslice_scoped_to_block(self):
        self.assert_runs('''fn sum(got: []i64) -> i64:
    let total = 0
    for i in 0..len(got):
        total += got[i]
    return total

let data = [10, 20, 30, 40]
if true:
    let buf = mut data[0..4]
    buf[0] = 1
    if true:
        let n = 3
        let got: []i64 = buf[0..n]
        print(len(got), got[0], got[2], buf[1])
        print(sum(got), sum(buf[1..3]))
    buf[0] = 99
    print(buf[0])
print(data[0])
''', "3 1 30 20\n51 50\n99\n99\n")

    def test_mut_slice_parameter_read_reslice(self):
        self.assert_runs('''fn parse(got: []u8) -> i64:
    let total = 0
    for i in 0..len(got):
        total += got[i]
    return total

fn handle(buf: []mut u8, n: i64) -> i64:
    let got: []u8 = buf[0..n]
    return parse(got)

let data: [8]u8 = [0, 0, 0, 0, 0, 0, 0, 0]
if true:
    let buf = mut data[0..8]
    buf[0] = 7
    buf[1] = 8
    print(handle(buf, 2))
    buf[0] = 100
print(data[0])
''', "15\n100\n")

    def test_mut_slice_frozen_while_read_child_alive(self):
        for action in (
            "buf[0] = 5",
            "buf[0] += 1",
            "defer buf[1] = 9",
        ):
            with self.subTest(action=action):
                self.assert_rejected('''let data = [10, 20, 30, 40]
let buf = mut data[0..4]
if true:
    let got: []i64 = buf[0..2]
    ''' + action + '''
    print(got[0])
''', "нельзя писать через изменяемый slice, пока из него создан slice на чтение")
        self.assert_rejected('''let data = [10, 20, 30, 40]
let buf = mut data[0..4]
if true:
    defer buf[0] = 5
    let got: []i64 = buf[0..2]
    print(got[0])
''', "нельзя писать через изменяемый slice, пока из него создан slice на чтение")
        self.assert_rejected('''fn take(view: []mut i64):
    view[0] = 1

let data = [10, 20, 30, 40]
let buf = mut data[0..4]
if true:
    let got: []i64 = buf[0..2]
    take(buf)
    print(got[0])
''', "изменяемый slice нельзя передать как []mut, пока из него создан slice на чтение")


    def test_tail_keeps_original_address_and_supports_empty_results(self):
        self.assert_runs(TAIL + '''let values = [11, 22, 33, 44]
let result = tail(values[1..4])
let alias = result
print(len(alias), alias[0], alias[1])
print(len(tail(values[3..4])), len(tail(values[4..4])))
unsafe:
    print(&alias[0] == &values[2])
''', "2 33 44\n0 0\ntrue\n")

    def test_composed_call_propagates_only_annotated_parameter(self):
        self.assert_runs('''fn forward(other: []i64, input: []i64) -> []i64 from input:
    let alias = input
    return tail(alias)[0..1]

fn first(input: []i64) -> i64:
    return input[0]

''' + TAIL + '''let a = [1, 2, 3, 4]
let b = [99]
let result = forward(b[0..1], a[1..4])
print(result[0], first(tail(a[0..3])), tail(tail(a[0..4]))[0])
''', "3 2 3\n")

    def test_generic_return_and_spilled_source(self):
        self.assert_runs('''fn slide<T>(input: []T) -> []T from input:
    return input[1..len(input)]

fn spill(a: i64, b: i64, c: i64, d: i64, e: i64, input: []i64, n: i64) -> []i64 from input:
    defer print(a + b + c + d + e + n)
    return slide(input)[n..len(input) - 1]

let values = [10, 20, 30, 40, 50]
let result = spill(1, 2, 3, 4, 5, values[0..5], 1)
print(len(result), result[0], result[1])
''', "16\n3 30 40\n")

    def test_result_of_temporary_keeps_array_shared_until_block_exit(self):
        for operation, diagnostic in (
            ("values[0] += 1", "нельзя менять массив, пока slice ссылается на него"),
            ("let exclusive = mut values[0..1]", "массив уже заимствован"),
        ):
            with self.subTest(operation=operation):
                self.assert_rejected(TAIL + "let values = [1, 2, 3]\nlet result = tail(values[0..3])\n"
                                     + operation + "\nprint(result[0])\n", diagnostic)
        self.assert_rejected(TAIL + '''let values = [1, 2, 3]
defer values[0] = 9
let result = tail(values[0..3])
defer print(result[0])
''', "нельзя менять массив, пока slice ссылается на него")

    def test_result_cleanup_releases_temporary_argument_loan(self):
        self.assert_runs(TAIL + '''let values = [11, 22, 33]
for i in 0..3:
    let result = tail(values[0..3])
    defer print(len(result), result[i])
    if i == 0: continue
    break
values[1] = 99
print(values[1])
''', "2 22\n2 33\n99\n")

    def test_bounds_use_actual_slice_length(self):
        for lower, upper in ((-1, 1), (1, 0), (0, 2)):
            with self.subTest(lower=lower, upper=upper):
                self.assert_panics(f'''fn window(input: []i64, low: i64, high: i64) -> []i64 from input:
    return input[low..high]

let values = [1, 2, 3]
let result = window(values[1..2], {lower}, {upper})
print(len(result))
''', "volt: invalid slice range")
        self.assert_panics(TAIL + "let values = [1]\nprint(tail(values[0..1])[0])\n",
                           "volt: slice index out of bounds")

    def test_cannot_return_local_unrelated_or_unproven_slice(self):
        for body in (
            "let local = [1]\n    return local[0..1]",
            "let local = [1]\n    let alias = local[0..1]\n    return alias",
            "return other",
            "return other[0..len(other)]",
            "return tail(other)",
            "let alias = other\n    return alias",
            "return input as []i64",
        ):
            with self.subTest(body=body):
                self.assert_rejected(TAIL + "fn bad(input: []i64, other: []i64) -> []i64 from input:\n    "
                                     + body + "\n", "return: срез должен происходить из параметра input")
        self.assert_rejected(TAIL + '''fn bad(input: []i64) -> []i64 from input:
    let local = [1]
    return tail(local[0..1])
''', "return: срез должен происходить из параметра input")

    def test_signature_requires_one_read_only_source_of_matching_type(self):
        for params, result, diagnostic in (
            ("input: []i64", "[]i64", "без явно указанного источника"),
            ("input: []i64", "[]i64 from unknown", "from называет неизвестный параметр"),
            ("input: []mut i64", "[]i64 from input", "from должен называть параметр неизменяемого slice"),
            ("input: []i32", "[]i64 from input", "from должен называть параметр неизменяемого slice"),
            ("input: i64", "[]i64 from input", "from должен называть параметр неизменяемого slice"),
            ("input: []i64", "i64 from input", "from допустим только"),
            ("input: []i64, other: []i64", "[]i64 from input, other", "ожидалось ':'"),
        ):
            with self.subTest(params=params, result=result):
                self.assert_rejected(f"fn bad({params}) -> {result}:\n    return input\n", diagnostic)

    def test_returned_views_remain_read_only_and_cannot_escape(self):
        for operation, diagnostic in (
            ("result[0] = 9", "неизменяемый slice нельзя изменять"),
            ("let array = [result]", "slice нельзя хранить в массиве"),
            ("result = result", "присваивание slice запрещено"),
        ):
            with self.subTest(operation=operation):
                self.assert_rejected(TAIL + "let values = [1, 2]\nlet result = tail(values[0..2])\n"
                                     + operation + "\n", diagnostic)
        self.assert_rejected("extern fn bad(input: []i64) -> []i64 from input\n",
                             "slice не поддерживается в native/extern ABI")
        self.assert_rejected("unsafe native fn bad(input: []i64) -> []i64 from input:\n{\n}\n",
                             "slice не поддерживается в native/extern ABI")

    def test_temporary_slice_argument_releases_owner_after_statement(self):
        self.assert_runs('''fn fill(view: []mut i64):
    view[0] = 7

fn show(view: []i64) -> i64:
    return view[0]

let values = [1, 2]
fill(mut values[0..2])
values[0] += 1
fill(mut values[0..2])
print(show(values[0..2]), values[0], values[1])
values[1] = 9
print(show(values[0..2]))
''', "7 7 2\n7\n")

    def test_temporary_read_reslice_argument_unfreezes_after_statement(self):
        self.assert_runs('''fn sum(got: []i64) -> i64:
    let total = 0
    for i in 0..len(got):
        total += got[i]
    return total

let data = [10, 20, 30]
let buf = mut data[0..3]
buf[0] = 1
print(sum(buf[0..3]))
buf[0] = 99
print(sum(buf[0..2]), buf[0])
''', "51\n119 99\n")

    def test_temporary_slice_argument_keeps_statement_and_defer_rules(self):
        # A named slice still holds its loan to the end of the block.
        self.assert_rejected('''fn fill(view: []mut i64):
    view[0] = 7

let values = [1, 2]
let view = mut values[0..1]
fill(mut values[0..1])
''', "заимствован изменяемым slice")
        # A defer still holds a temporary slice loan until the block exits.
        self.assert_rejected('''fn fill(view: []mut i64):
    view[0] = 7

let values = [1]
defer fill(mut values[0..1])
values[0] = 3
''', "заимствован изменяемым slice")
        # Two mutable slices of one array in a single call still conflict.
        self.assert_rejected('''fn both(first: []mut i64, second: []mut i64):
    first[0] = second[0]

let values = [1, 2]
both(mut values[0..1], mut values[1..2])
''', "заимствован изменяемым slice")
        # A mutable argument still excludes reading the array in the same call.
        self.assert_rejected('''fn fill_read(view: []mut i64, x: i64):
    view[0] = x

let values = [1, 2]
fill_read(mut values[0..1], values[0])
''', "заимствован изменяемым slice")
        # The loan still covers the rest of the statement's expression.
        self.assert_rejected('''fn change(view: []mut i64) -> i64:
    view[0] = 2
    return 0

let values = [1]
print(values[change(mut values[0..1])])
''', "заимствован изменяемым slice")


if __name__ == "__main__":
    unittest.main()
