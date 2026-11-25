#!/usr/bin/env python3
"""Tagged values through the compiler CLI and ordinary VOLT calls."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
VOLT = Path(os.environ.get("VOLT_COMPILER", ROOT / "volt")).resolve()
TOKEN = '''enum Token:
    Number(i64)
    Name(string)
    End
'''


class SumTypes(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="volt-sum-test-")
        self.addCleanup(directory.cleanup)
        self.tmp = Path(directory.name)

    def command(self, *args):
        return subprocess.run(args, cwd=self.tmp, env={"PATH": "", "TMPDIR": str(self.tmp)},
                              capture_output=True, encoding="utf-8", timeout=20)

    def compile_program(self, source):
        path = self.tmp / "main.volt"
        path.write_text(source, encoding="utf-8")
        return self.command(VOLT, path, "-o", self.tmp / "program")

    def assert_runs(self, source, stdout):
        built = self.compile_program(source)
        self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
        self.assertEqual(built.stderr, "")
        result = self.command(self.tmp / "program")
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, stdout, ""))

    def assert_rejected(self, source, diagnostic):
        result = self.compile_program(source)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("main.volt:", result.stderr)
        self.assertIn(diagnostic, result.stderr)

    def test_struct_result_snapshots_success_and_error_before_defers(self):
        self.assert_runs('''struct FileInfo:
    size: i64
    mode: u16
    name: string

struct IoError:
    code: i32
    origin: i32
    offset: i64

fn stat(ok: bool) -> Result<FileInfo, IoError>:
    if ok: return Ok(FileInfo(3456789012, 493, "data"))
    return Err(IoError(5, -9, 6284937535))

fn show(input: Result<FileInfo, IoError>):
    match input:
        Ok(info): print("ok", info.size, info.mode, info.name)
        Err(error): print("err", error.code, error.origin, error.offset)

fn relay(a: i64, b: i64, c: i64, d: i64, e: i64, input: Result<FileInfo, IoError>) -> Result<FileInfo, IoError>:
    defer print("first", a + b + c + d + e)
    defer input = Ok(FileInfo(0, 0, "changed input"))
    defer print("last")
    let info = input?
    defer info.name = "changed success"
    return Ok(info)

fn extract(input: Result<FileInfo, IoError>) -> Result<i32, IoError>:
    defer input = Ok(FileInfo(0, 0, "changed error input"))
    return Ok(input?.mode as i32)

print(sizeof(FileInfo), alignof(FileInfo), sizeof(IoError), alignof(IoError))
print(sizeof(Result<FileInfo, IoError>), alignof(Result<FileInfo, IoError>))
show(relay(1, 2, 3, 4, 5, stat(true)))
show(relay(1, 2, 3, 4, 5, stat(false)))
match extract(stat(false)):
    Ok(mode): panic("expected error")
    Err(error): print("repacked", error.code, error.origin, error.offset)
match extract(stat(true)):
    Ok(mode): print("mode", mode)
    Err(error): panic("expected success")
''', "24 8 16 8\n32 8\nlast\nfirst 15\nok 3456789012 493 data\n"
     "last\nfirst 15\nerr 5 -9 6284937535\nrepacked 5 -9 6284937535\nmode 493\n")

    def test_nested_tags_and_wide_temporaries_do_not_alias(self):
        self.assert_runs('''struct Pair<T>:
    first: T
    last: u8

fn unwrap(input: Option<Result<Pair<u16>, Option<i64>>>) -> Option<Result<Pair<u16>, Option<i64>>>:
    let inner = input?
    return Some(inner)

fn show(input: Option<Result<Pair<u16>, Option<i64>>>):
    match input:
        None: print("outer None")
        Some(inner):
            match inner:
                Ok(pair): print("pair", pair.first, pair.last)
                Err(maybe):
                    match maybe:
                        Some(value): print("error", value)
                        None: print("inner None")

fn compare(first: Option<Result<Pair<u16>, Option<i64>>>, second: Option<Result<Pair<u16>, Option<i64>>>):
    show(first)
    show(second)

fn direct() -> Option<Option<i64>>:
    return Some(Some(9))

print(sizeof(Pair<u16>), alignof(Pair<u16>))
print(sizeof(Option<Pair<u16>>), alignof(Option<Pair<u16>>))
print(sizeof(Result<Pair<u16>, Option<i64>>), alignof(Result<Pair<u16>, Option<i64>>))
print(sizeof(Option<Result<Pair<u16>, Option<i64>>>), alignof(Option<Result<Pair<u16>, Option<i64>>>))
print(sizeof(Option<i64>), alignof(Option<i64>), sizeof(Result<i32, i32>))
let combined: Option<Result<Pair<u16>, Option<i64>>> = Some(Ok(Pair(40321, 143)))
combined = combined
compare(unwrap(combined), unwrap(Some(Err(Some(4612838092)))))
combined = Some(Err(None))
compare(combined, unwrap(None))
match direct():
    Some(inner):
        match inner:
            Some(value): print("direct", value)
            None: panic("expected inner Some")
    None: panic("expected outer Some")
''', "4 2\n16 8\n24 8\n32 8\n16 8 16\npair 40321 143\nerror 4612838092\n"
     "inner None\nouter None\ndirect 9\n")

    def test_direct_propagation_and_nested_error_snapshot(self):
        self.assert_runs('''struct Info:
    first: i64
    last: i64

fn forward(input: Result<Info, Option<Info>>) -> Result<i64, Option<Info>>:
    defer input = Err(None)
    return Ok(input?.last)

fn direct() -> Option<Info>:
    return Some(Some(Info(81, 91))?)

match forward(Err(Some(Info(41, 51)))):
    Ok(value): panic("expected error")
    Err(error):
        match error:
            Some(info): print(info.first, info.last)
            None: panic("expected nested error")
match direct():
    Some(info): print(info.first, info.last)
    None: panic("expected success")
''', "41 51\n81 91\n")

    def test_payload_boundaries_stay_closed(self):
        types = "struct FileInfo:\n    size: i64\n"
        cases = (
            ("extern fn native_stat() -> Result<FileInfo, i32>\n", "результаты запрещены в extern/native"),
            ("native fn take(value: Option<FileInfo>):\n{\n    NOP\n}\n", "параметры запрещены в extern/native"),
            ("unsafe fn take(value: fnptr<(Option<FileInfo>)>):\n    return\n", "только скалярный ABI C"),
            ("let value: Option<[2]i64> = None\n", "недопустимый тип payload"),
            ("let value: Result<i64, []i64> = Ok(7)\n", "недопустимый тип payload"),
            ("struct Node:\n    next: Option<Node>\n", "Option/Result нельзя помещать в поля struct"),
            ("let values = [Some(FileInfo(7))]\n", "Option/Result нельзя помещать в массив"),
            ("let value: Option<Option<FileInfo>> = Some(3)\n", "Some: i64 вместо Option<FileInfo>"),
            ("let value: " + "Option<" * 65 + "FileInfo" + ">" * 65 + " = None\n", "превышена глубина вложенности типов"),
        )
        for source, diagnostic in cases:
            with self.subTest(diagnostic=diagnostic):
                self.assert_rejected(types + source, diagnostic)
        self.assert_rejected("use borrow_buffer\nlet owner: Option<BorrowBuffer<i64>> = None\n", "требует копируемую struct")

    def test_array_length_evaluates_propagation_in_its_argument(self):
        self.assert_runs('''struct Table:
    cells: [2]i64

fn length(input: Result<Table, i64>) -> Result<i64, i64>:
    defer print("cleanup")
    return Ok(len(input?.cells))

let table: Table
match length(Err(7)):
    Ok(n): print("ok", n)
    Err(code): print("err", code)
match length(Ok(table)):
    Ok(n): print("ok", n)
    Err(code): print("err", code)
''', "cleanup\nerr 7\ncleanup\nok 2\n")

    def test_array_length_preserves_constructor_and_index_effects(self):
        self.assert_runs('''struct Table:
    cells: [2]i64
    id: i64

fn note() -> i64:
    print("note")
    return 0

let table: Table
let grid: [2][3]i64
print(len(Table(table.cells, note()).cells as [2]i64))
print(len(grid[note()]))
''', "note\n2\nnote\n3\n")

    def test_copyable_record_with_array_field(self):
        self.assert_runs('''struct Table:
    cells: [2]i64

fn relay(input: Option<Table>) -> Option<Table>:
    return input

let data: Table
data.cells[1] = 51
match relay(Some(data)):
    Some(table): print(table.cells[0], table.cells[1])
    None: panic("missing table")
''', "0 51\n")

    def test_match_payloads_through_internal_enum_calls(self):
        self.assert_runs(TOKEN + '''
fn relay(token: Token) -> Token:
    defer token = Token.End
    return token

fn show(token: Token):
    match token:
        Token.Number(n): print("number", n)
        Token.Name(s): print("name", s)
        Token.End: print("end")

fn make() -> Token:
    return Token.Number(-4294967297)

fn wrap(token: Token) -> Option<Token>:
    return Some(token)

fn unwrap(input: Result<Token, i64>) -> Result<Token, i64>:
    return Ok(input?)

print(sizeof(Token), alignof(Token))
show(relay(make()))
show(relay(Token.Name("token")))
match Token.End:
    Token.End: print("direct end")
    _: panic("expected end")
match wrap(Token.Name("wrapped")):
    Some(token): show(token)
    None: panic("expected value")
match unwrap(Ok(Token.Name("question"))):
    Ok(token): show(token)
    Err(code): panic("expected value")
show(Token.End)
''', "16 8\nnumber -4294967297\nname token\ndirect end\nname wrapped\nname question\nend\n")

    def test_match_must_cover_payload_and_empty_variants(self):
        self.assert_rejected(TOKEN + '''
fn show(token: Token):
    match token:
        Token.Number(n): print(n)
        Token.End: print("end")
''', "match не исчерпывающий: Name")
        self.assert_rejected(TOKEN + '''
match Token.Number(7):
    Token.Number(n): print(n)
    Token.Name(s): print(s)
''', "match не исчерпывающий: End")

    def test_tagged_enum_wide_discriminants(self):
        self.assert_runs('''enum Token:
    Number(i64) = 4294967297
    Name(string) = -4294967298
    End

fn show(token: Token):
    match token:
        Token.Number(n): print(n)
        Token.Name(s): print(s)
        Token.End: print("end")

show(Token.Number(12345678901))
show(Token.Name("wide tag"))
show(Token.End)
''', "12345678901\nwide tag\nend\n")

    def test_tagged_enum_rejects_wrong_constructors_patterns_and_abi(self):
        cases = (
            ("let x = Token.Number\n", "вариант enum требует один аргумент payload"),
            ("let x = Token.Number(1, 2)\n", "вариант enum требует один аргумент payload"),
            ("let x = Token.Number(1 as i32)\n", "i32 вместо i64"),
            ("let x = Token.End()\n", "вариант enum без payload используется без скобок"),
            ("let x = Token.Missing(1)\n", "неизвестный вариант enum Token.Missing"),
            ("match Token.End:\n    Token.Number: panic(\"bad\")\n    _: print(0)\n", "некорректная binding"),
            ("match Token.End:\n    Token.End(data): print(data)\n    _: print(0)\n", "некорректная binding"),
            ("let x: Token\n", "требует явного конструктора"),
            ("let x = Token.End as i64\n", "нельзя привести Token к i64"),
            ("print(Token.End == Token.End)\n", "несравнимые типы Token и Token"),
            ("extern fn read_token() -> Token\n", "enum с payload запрещён в extern/native ABI"),
            ("native fn write_token(value: Token):\n{\n    NOP\n}\n", "enum с payload запрещён в extern/native ABI"),
            ("unsafe fn use_token(f: fnptr<(Token)>):\n    return\n", "только скалярный ABI C"),
            ("fn get() -> Token:\n    return Token.End\nunsafe: let f = callback(get)\n", "только скалярный ABI C"),
            ("let tokens = [Token.End]\n", "нельзя помещать в массив"),
            ("let x = Token.End\nunsafe: let p = &x\n", "ptr не может скрывать enum с payload"),
            ("struct Container:\n    value: Token\n", "нельзя помещать в поля struct"),
            ("enum Recursive:\n    Self(Recursive)\n", "поддерживает только скалярное значение"),
        )
        for source, diagnostic in cases:
            with self.subTest(source=source):
                self.assert_rejected(TOKEN + source, diagnostic)

    def test_payload_free_enum_still_uses_i64_comparison_and_cast(self):
        self.assert_runs('''enum Color:
    Red = -2
    Blue = 77
    Green

fn relay(color: Color) -> Color:
    return color

let color = relay(Color.Green)
const explicit = Color.Blue
print(sizeof(Color), alignof(Color), color as i64, explicit as i64, Color.Red as i64)
print(color == Color.Green, color != Color.Blue)
match color:
    Color.Red: panic("bad tag")
    Color.Blue: panic("bad tag")
    Color.Green: print("green")
''', "8 8 78 77 -2\ntrue true\ngreen\n")


if __name__ == "__main__":
    unittest.main()
