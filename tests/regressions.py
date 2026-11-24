#!/usr/bin/env python3
"""Focused regression tests for the VOLT review findings."""
import concurrent.futures
import contextlib
import importlib.util
import io
import os
import pty
import select
import shutil
import signal
import subprocess
import sys
import termios
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
VCC = os.path.join(ROOT, "volt")
SNAKE = os.path.join(ROOT, "apps", "snake.volt")


class VoltReviewRegressions(unittest.TestCase):
    def test_generic_function_monomorphization_and_inference(self):
        result = self.compile_run('''fn identity<T>(value: T) -> T:
    return value
print(identity(42), identity(true))
''')
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "42 true\n", ""))

    def test_generic_type_conflict_is_diagnostic(self):
        self.assert_compile_error('''fn same<T>(a: T, b: T) -> T:
    return a
print(same(1, true))
''', "конфликт")
        self.assert_compile_error('''fn same<T>(a: T, b: T) -> T:
    return a
print(same('A', 65 as u8))
''', "конфликт")

    def test_generic_structs_infer_layout_and_function_types(self):
        result = self.compile_run('''struct Entry<T, U>:
    tag: U
    value: T

struct Chain<T>:
    entry: Entry<T, u8>
    next: ptr<Chain<T>>

fn value_of<T, U>(entry: Entry<T, U>) -> T:
    return entry.value

unsafe fn store<T>(chain: ptr<Chain<T>>, value: T):
    chain.entry.value = value

fn sample() -> Entry<i64, u8>:
    return Entry(2, 11)

let chain: Chain<i64>
let pair = Entry(true, 42)
let wide: Entry<i64, u8> = Entry(3, 4)
let small: Entry<u8, u8> = Entry(5, 6)
let values: [2]Entry<i64, u8> = [sample(), Entry(7, 12)]
unsafe:
    chain.next = &chain
    store(chain.next, 9)
print(sizeof(Entry<i64, u8>), sizeof(Entry<u8, u8>), alignof(Chain<i64>))
print(value_of(pair), value_of(wide), value_of(small), values[1].value, chain.entry.value)
''')
        self.assertEqual((result.returncode, result.stdout, result.stderr),
                         (0, "16 2 8\n42 4 6 12 9\n", ""))

    def test_invalid_generic_structs_produce_diagnostics(self):
        cases = (
            ("struct Box<T, T>:\n    value: T\n", "указан дважды"),
            ("struct Box<T>:\n    value: T\nlet box: Box\n", "требует 1 аргумент"),
            ("struct Box<T>:\n    value: T\nlet box: Box<i64, u8>\n", "требует 1 аргумент"),
            ("struct Box:\n    value: i64\nlet box: Box<i64>\n", "требует 0 аргумент"),
            ("struct Node<T>:\n    next: Node<T>\nlet node: Node<i64>\n", "рекурсия по значению"),
            ("struct Node<T>:\n    next: Node<Node<T>>\nlet node: Node<i64>\n", "глубина"),
            ("struct Box<T>:\n    value: T\nlet a: Box<i64>\nlet b: Box<u64>\na = b\n", "недопустимо"),
            ("unsafe fn count<T>(p: ptr<T>) -> i64:\n    return sizeof(T)\nlet item: i64\nprint(count(&item))\n", "вызов unsafe-функции"),
            ("struct Box<T>:\n    value: T\nfn expand<T>(value: T):\n    expand(Box(value))\nexpand(1)\n", "глубина вложенности аргументов"),
            ("unsafe fn expand<T>(value: T):\n    expand(&value)\nunsafe: expand(1)\n", "глубина специализации"),
            ("fn count<T>(items: T) -> i64:\n    return sizeof(T)\nlet items: [2]i64\nprint(count(items))\n", "массив нельзя передавать по значению"),
            ("struct Box<T>:\n    value: T\nextern fn foreign(value: Box<i64>) -> i64\n", "структуры по значению"),
            ("struct Box<T>:\n    value: T\nfn empty():\n    return\nlet box = Box(empty())\n", "для аргумента требуется значение"),
            ("struct Box<T>:\n    value: T\nfn empty():\n    return\nlet box: Box<i64> = Box(empty())\n", "для аргумента требуется значение"),
        )
        for source, message in cases:
            with self.subTest(message=message):
                self.assert_compile_error(source, message)

    def test_generic_struct_copies_preserve_constructor_arguments(self):
        result = self.compile_run('''struct Box<T>:
    value: T

fn keep<T>(value: T) -> T:
    return value

fn index() -> i64:
    let copy = keep(Box(19))
    return copy.value - 19

fn first(values: []i64) -> i64:
    return values[0]

let box = Box(7)
box = Box(box.value + 1)
let boxes: [2]Box<i64> = [Box(0), Box(1)]
boxes[index()] = box
let nums: [2]i64 = [3, 12]
let holder = Box(nums)
let answer = Box(first(nums[0..1]))
print(box.value, boxes[0].value, holder.value[1], answer.value)
''')
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "8 8 12 3\n", ""))

    def test_generic_type_cast_can_precede_less_than(self):
        result = self.compile_run('''fn less<T>(value: T, limit: T) -> bool:
    return value as T<limit

print(less(3, 7))
''')
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "true\n", ""))

    def test_nested_struct_layout_is_independent_of_declaration_order(self):
        structs = [f"struct Layer{i}:\n    inner: Layer{i + 1}\n" for i in range(100)]
        structs.append("struct Layer100:\n    inner: i64\n")
        for declarations in (structs, list(reversed(structs))):
            result = self.compile_run("\n".join(declarations) + "print(sizeof(Layer0), alignof(Layer0))\n")
            self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "8 8\n", ""))

    def test_large_struct_frames_are_checked_before_assembly(self):
        self.assert_compile_error('''struct Box<T>:
    value: T
let first: Box<[1100000000]char>
let second: Box<[1100000000]char>
''', "размер кадра стека превышает лимит")

        with tempfile.TemporaryDirectory(prefix="volt-frame-") as tmp:
            source = os.path.join(tmp, "main.volt")
            output = os.path.join(tmp, "main")
            with open(source, "w", encoding="utf-8") as f:
                f.write("struct Box<T>:\n    value: T\nlet item: Box<[1100000000]char>\n")
            result = subprocess.run([VCC, source, "-o", output],
                                    capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_slice_range_index_and_function_argument(self):
        result = self.compile_run('''fn sum(values: []i64) -> i64:
    let total = 0
    for i in 0..len(values):
        total += values[i]
    return total
let values: [4]i64 = [10, 20, 30, 40]
let middle: []i64 = values[1..3]
print(len(middle), middle[0], middle[1], sum(middle))
''')
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "2 20 30 50\n", ""))

    def test_slice_invalid_range_panics_and_mutable_slice_rejected(self):
        result = self.compile_run('let values: [2]i64 = [1, 2]\nlet bad: []i64 = values[2..1]\n')
        self.assertEqual((result.returncode, result.stderr), (1, "volt: invalid slice range\n"))
        self.assert_compile_error('''fn bad(values: []mut i64):
    return
''', "изменяемый slice пока не реализован")

    def test_array_write_while_slice_active_is_rejected(self):
        self.assert_compile_error('''let values: [2]i64 = [1, 2]
let view: []i64 = values[0..2]
values[0] = 9
''', "нельзя менять массив, пока slice ссылается на него")

    def test_char_literal_escape_diagnostics(self):
        self.assert_compile_error("'\\", "main.volt:1: ошибка: незакрытый симв. литерал")
        self.assert_compile_error("'\\q'", "main.volt:1: ошибка: неизвестный escape")
        result = self.compile_run("print('\\n')\n")
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "\n\n", ""))

    def test_string_literals_reject_embedded_nul(self):
        self.assert_compile_error('print("a\\0b")\n', "строковый литерал не может содержать NUL")

    def compile_run(self, source, modules=None, timeout=15):
        with tempfile.TemporaryDirectory(prefix="volt-test-") as tmp:
            for name, text in (modules or {}).items():
                with open(os.path.join(tmp, name + ".volt"), "w", encoding="utf-8") as f:
                    f.write(text)
            src = os.path.join(tmp, "main.volt")
            with open(src, "w", encoding="utf-8") as f:
                f.write(source)
            return subprocess.run([VCC, src, "--run"],
                                  capture_output=True, text=True, timeout=timeout)

    def test_volt_cli_reports_full_version(self):
        result = subprocess.run([os.path.join(ROOT, "volt"), "--version"],
                                capture_output=True, text=True, timeout=5)
        self.assertEqual((result.returncode, result.stdout, result.stderr),
                         (0, "VOLT Language v0.3.0\n", ""))

    def test_native_compiler_and_outputs_work_without_tools_on_path(self):
        with tempfile.TemporaryDirectory(prefix="volt-native-") as tmp:
            with open(VCC, "rb") as compiler:
                self.assertEqual(compiler.read(4), b"\x7fELF")
            for source, expected in (("hello.volt", "Hello, VOLT!\n"), ("c_ffi.volt", "4 7\n")):
                with self.subTest(source=source):
                    exe = os.path.join(tmp, source.removesuffix(".volt"))
                    env = {"PATH": ""}
                    result = subprocess.run([VCC, os.path.join(ROOT, "apps", source), "-o", exe],
                                            env=env, capture_output=True, text=True, timeout=15)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    with open(exe, "rb") as binary:
                        self.assertEqual(binary.read(4), b"\x7fELF")
                    program = subprocess.run([exe], env=env, capture_output=True, text=True, timeout=5)
                    self.assertEqual((program.returncode, program.stdout, program.stderr), (0, expected, ""))

    def test_source_filename_can_contain_spaces_and_unicode(self):
        with tempfile.TemporaryDirectory(prefix="volt-filename-") as tmp:
            src = os.path.join(tmp, "пример + имя.volt")
            with open(src, "w", encoding="utf-8") as f:
                f.write('fn main():\n    print("works")\n')
            result = subprocess.run([VCC, src, "--run"], capture_output=True, text=True, timeout=15)
            self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "works\n", ""))

    def test_cli_target_defaults_and_accepts_linux_x86_64(self):
        with tempfile.TemporaryDirectory(prefix="volt-target-") as tmp:
            src = os.path.join(tmp, "main.volt")
            with open(src, "w", encoding="utf-8") as f:
                f.write('print("target ok")\n')
            for target_args in ([], ["--target", "linux-x86_64"],
                                ["--target=linux-x86_64"]):
                result = subprocess.run([VCC, *target_args, src, "--run"],
                                        capture_output=True, text=True, timeout=15)
                self.assertEqual((result.returncode, result.stdout, result.stderr),
                                 (0, "target ok\n", ""))

    def test_cli_writes_executable_to_a_different_filesystem_from_assembly(self):
        if not os.access("/dev/shm", os.W_OK):
            self.skipTest("/dev/shm unavailable")
        with tempfile.TemporaryDirectory(prefix="volt-output-") as work, \
                tempfile.TemporaryDirectory(prefix="volt-output-", dir="/dev/shm") as output:
            if os.stat(work).st_dev == os.stat(output).st_dev:
                self.skipTest("assembly and executable need different filesystems")
            src = os.path.join(ROOT, "apps", "hello.volt")
            asm = os.path.join(work, "hello.s")
            exe = os.path.join(output, "hello")
            result = subprocess.run([VCC, src, "-S", asm, "-o", exe],
                                    capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue(os.path.isfile(asm))
            with open(exe, "rb") as binary:
                self.assertEqual(binary.read(4), b"\x7fELF")
            self.assertTrue(os.stat(exe).st_mode & 0o111)

    def test_cli_rejects_unsupported_or_missing_target_before_compilation(self):
        for target_args, diagnostic in ((["--target", "windows-x86_64"], "windows-x86_64"),
                                        (["--target", "unknown"], "unknown"),
                                        (["--target"], "--target требует значение")):
            with self.subTest(target_args=target_args):
                result = subprocess.run([VCC, *target_args,
                                          "missing-source.volt"], capture_output=True,
                                         text=True, timeout=5)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(diagnostic, result.stdout + result.stderr)
                self.assertNotIn("не найден", result.stdout + result.stderr)

    def test_c_abi_calls_libc(self):
        result = subprocess.run(
            [VCC, os.path.join(ROOT, "apps", "c_ffi.volt"), "--run"],
            capture_output=True, text=True, timeout=15,
        )
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "4 7\n", ""))

    def test_native_code_normalizes_narrow_returns_and_reads_intel_literals(self):
        result = self.compile_run('''native fn signed_result() -> i32:
{
    MOV EAX, -7
}
native fn byte_result() -> u8:
{
    mov rax, 0x1200; add rax, 064
}
native fn bool_result() -> bool:
{
    mov eax, 256
}
unsafe:
    let signed: i64 = signed_result()
    let byte: i64 = byte_result()
    if bool_result(): panic("nonzero bits outside bool result")
    print(signed, byte)
''')
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "-7 52\n", ""))

    @unittest.skipUnless(shutil.which("cc"), "A C compiler is needed for the shared-library fixtures")
    def test_entry_library_has_priority_over_imported_library(self):
        with tempfile.TemporaryDirectory(prefix="volt-link-order-") as tmp:
            for name, value in (("entry", 1), ("dependency", 2)):
                library = os.path.join(tmp, f"lib{name}.so")
                subprocess.run(["cc", "-shared", "-fPIC", "-o", library, "-x", "c", "-"],
                               input=f"int selected(void) {{ return {value}; }}", text=True, check=True, timeout=15)
            with open(os.path.join(tmp, "dependency.volt"), "w", encoding="utf-8") as f:
                f.write('link "-ldependency"\n')
            src = os.path.join(tmp, "main.volt")
            with open(src, "w", encoding="utf-8") as f:
                f.write('use dependency\nlink "-L. -lentry"\nextern fn selected() -> i32\nprint(selected())\n')
            result = subprocess.run([VCC, src, "--run"], cwd=tmp, env={"PATH": "", "LD_LIBRARY_PATH": tmp},
                                    capture_output=True, text=True, timeout=15)
            self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "1\n", ""))

    @unittest.skipUnless(shutil.which("cc"), "A C compiler is needed for the versioned shared-library fixture")
    def test_shared_library_uses_the_default_symbol_version(self):
        with tempfile.TemporaryDirectory(prefix="volt-link-version-") as tmp:
            versions = os.path.join(tmp, "versions.map")
            with open(versions, "w", encoding="utf-8") as f:
                f.write("RATES_1 {};\nRATES_2 {} RATES_1;\n")
            library = os.path.join(tmp, "libvolt-rates.so")
            subprocess.run(["cc", "-shared", "-fPIC", f"-Wl,--version-script={versions}",
                            "-o", library, "-x", "c", "-"],
                           input='''int old_rate(void) { return 11; }
int new_rate(void) { return 22; }
__asm__(".symver old_rate,get_rate@RATES_1");
__asm__(".symver new_rate,get_rate@@RATES_2");
''', text=True, check=True, timeout=15)
            src = os.path.join(tmp, "main.volt")
            with open(src, "w", encoding="utf-8") as f:
                f.write('link "-L. -l:libvolt-rates.so"\nextern fn get_rate() -> i32\nprint(get_rate())\n')
            result = subprocess.run([VCC, src, "--run"], cwd=tmp, env={"PATH": "", "LD_LIBRARY_PATH": tmp},
                                    capture_output=True, text=True, timeout=15)
            self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "22\n", ""))

    def test_process_arguments_from_initial_stack(self):
        source = '''use process
fn show(index: i64):
    match arg_at(index):
        Ok(value): print(index, value)
        Err(error): print(index, "err", error)
fn main() -> i64:
    print("argc", argc())
    show(0)
    show(1)
    show(2)
    show(3)
    show(4)
    show(-1)
    show(99)
    return 0
'''
        with tempfile.TemporaryDirectory(prefix="volt-process-") as tmp:
            src = os.path.join(tmp, "main.volt")
            exe = os.path.join(tmp, "process")
            with open(src, "w", encoding="utf-8") as f:
                f.write(source)
            built = subprocess.run([VCC, src, "-o", exe],
                                   capture_output=True, text=True, timeout=15, cwd=ROOT)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            result = subprocess.run([exe, "", "space argument", "tail"],
                                    capture_output=True, text=True, timeout=5, cwd=ROOT)
        self.assertEqual((result.returncode, result.stderr), (0, ""))
        lines = result.stdout.splitlines()
        self.assertEqual(lines[0], "argc 4")
        self.assertTrue(lines[1].startswith("0 "))
        self.assertIn(exe, lines[1])
        self.assertEqual(lines[2:], [
            "1 ",
            "2 space argument",
            "3 tail",
            "4 err 22",
            "-1 err 22",
            "99 err 22",
        ])

    def assert_compile_error(self, source, message, modules=None):
        result = self.compile_run(source, modules)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(message, result.stdout + result.stderr)
        self.assertNotIn("Traceback", result.stdout + result.stderr)

    def test_stage1_const_size_and_defer_lifo_return_value(self):
        source = '''struct Layout:
    tag: u8
    value: i64
const BASE: i64 = sizeof(Layout) + alignof(Layout)
fn run() -> i64:
    const LOCAL: i64 = BASE + 1
    let value = 4
    defer print("first", value)
    defer value = value + 1
    return LOCAL + value
print(run())
'''
        result = self.compile_run(source)
        self.assertEqual((result.returncode, result.stdout, result.stderr),
                         (0, "first 5\n29\n", ""))

    def test_stage1_defer_loop_cleanup_scopes(self):
        source = '''let i = 0
while i < 3:
    i += 1
    defer print("body", i)
    if i == 2:
        continue
    if i == 3:
        break
'''
        result = self.compile_run(source)
        self.assertEqual((result.returncode, result.stdout, result.stderr),
                         (0, "body 1\nbody 2\nbody 3\n", ""))

    def test_stage1_const_and_defer_diagnostics(self):
        self.assert_compile_error("const X = 1\nX = 2\n", "нельзя изменить")
        self.assert_compile_error(
            "fn bad():\n    defer print(later)\n    let later = 1\nbad()\n",
            "объявленную после defer",
        )
        self.assert_compile_error(
            "fn bad():\n    defer return\nbad()\n",
            "без flow-control",
        )

    def test_stage1_alignof_respects_struct_layout(self):
        source = '''struct Mixed:
    a: u8
    b: f64
print(sizeof(Mixed), alignof(Mixed))
'''
        result = self.compile_run(source)
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "16 8\n", ""))

    def test_link_directive_cannot_run_shell_commands(self):
        with tempfile.TemporaryDirectory(prefix="volt-link-") as tmp:
            marker = os.path.join(tmp, "marker")
            source = f'link "; touch {marker}; #"\nprint("safe")\n'
            result = self.compile_run(source)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(os.path.exists(marker))
            self.assertNotIn("Traceback", result.stdout + result.stderr)

    def test_panic_writes_only_the_message(self):
        result = self.compile_run('panic("x")\n')
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stderr, "x")

    def test_array_length_type_and_copy_checks(self):
        self.assert_compile_error(
            "let canary: i64 = 777\nlet a: [2]i64 = [1, 2, 3]\n",
            "инициализатор содержит 3 элементов",
        )
        self.assert_compile_error(
            'let a: [1]i64 = ["wrong"]\n',
            "элемент массива",
        )
        result = self.compile_run(
            "let a: [2]i64 = [7, 9]\nlet b: [2]i64 = a\nprint(b[0], b[1])\n"
        )
        self.assertEqual((result.returncode, result.stdout), (0, "7 9\n"))

    def test_fixed_array_bounds_are_checked(self):
        result = self.compile_run(
            "let a: [3]i64 = [4, 5, 6]\nprint(a[0], a[2])\n"
        )
        self.assertEqual((result.returncode, result.stdout), (0, "4 6\n"))
        for declaration, index in (("", "-1"), ("let n: i64 = 2\n", "n"),
                                  ("let n: u64 = 2\n", "n")):
            source = "let a: [2]i64 = [4, 5]\n" + declaration + "print(a[" + index + "])\n"
            result = self.compile_run(source)
            self.assertEqual(result.returncode, 1)
            self.assertEqual(result.stderr, "volt: array index out of bounds\n")

    def test_raw_pointers_are_explicitly_unsafe_and_strings_are_bounded(self):
        self.assert_compile_error(
            "let value: i64 = 7\nlet p: ptr<i64> = &value\nprint(*p)\n",
            "разыменование raw-указателя требует unsafe",
        )
        self.assert_compile_error(
            "unsafe fn first(p: ptr<i64>) -> i64:\n    return p[0]\n"
            "let value: i64 = 7\nprint(first(&value))\n",
            "вызов unsafe-функции first требует unsafe",
        )
        result = self.compile_run(
            "fn main() -> i64:\n"
            "    let s: string = \"VOLT\"\n"
            "    print(s[0], s == \"VOLT\", s != \"volt\")\n"
            "    return 0\n"
        )
        self.assertEqual((result.returncode, result.stdout), (0, "V true true\n"))
        result = self.compile_run(
            "use str\nfn main() -> i64:\n"
            "    let empty: string\n"
            "    print(empty == \"\", str_len(empty))\n"
            "    return 0\n"
        )
        self.assertEqual((result.returncode, result.stdout), (0, "true 0\n"))
        result = self.compile_run("let empty: string\npanic(empty)\n")
        self.assertEqual((result.returncode, result.stderr), (1, ""))
        result = self.compile_run('let s: string = "VOLT"\nprint(s[4])\n')
        self.assertEqual((result.returncode, result.stderr),
                         (1, "volt: string index out of bounds\n"))
        self.assert_compile_error(
            'let s: string = "VOLT"\ns[0] = \'x\'\n',
            "string неизменяем",
        )

    def test_enums_are_typed_integer_discriminants(self):
        result = self.compile_run(
            "use blocks\n"
            "struct Chunk:\n"
            "    block: Block\n"
            "fn identity(block: Block) -> Block:\n"
            "    return block\n"
            "let values: [2]Block = [Block.Air, Block.Stone]\n"
            "let chunk = Chunk(identity(values[1]))\n"
            "print(chunk.block == Block.Stone, values[0] == Block.Air, default_block == Block.Dirt, chunk.block as i64, Block.Unknown as i64)\n",
            {"blocks": "enum Block:\n"
                      "    Unknown = -1\n"
                      "    Air\n"
                      "    Dirt = 4\n"
                      "    Stone\n"
                      "let default_block: Block = Block.Dirt\n"},
        )
        self.assertEqual((result.returncode, result.stdout), (0, "true true true 5 -1\n"))
        self.assert_compile_error(
            "enum Block:\n    Air\nlet raw: i64 = Block.Air\n",
            "нельзя присвоить",
        )
        self.assert_compile_error(
            "enum Block:\n    Air\nlet block: Block = 1 as Block\n",
            "нельзя привести",
        )
        self.assert_compile_error(
            "enum Block:\n    Air\nenum State:\n    Air\n"
            "print(Block.Air == State.Air)\n",
            "enum можно сравнивать",
        )

    def test_float32_arithmetic_and_abi(self):
        result = self.compile_run(
            "fn add(a: f32, b: f32) -> f32:\n"
            "    return a + b\n"
            "let x: f32 = add(1.25 as f32, 2.5 as f32)\n"
            "let y: f64 = x as f64\n"
            "if y != 3.75:\n"
            "    panic(\"f32\")\n"
            "print(x, y)\n"
        )
        self.assertEqual((result.returncode, result.stdout, result.stderr),
                         (0, "3.750000 3.750000\n", ""))

    def test_fixed_ffi_arity_is_checked_with_stack_arguments(self):
        declaration = "extern fn fixed(a: i64, b: i64, c: i64, d: i64, e: i64, f: i64, g: i64) -> i64\n"
        self.assert_compile_error(declaration + "print(fixed(1, 2, 3, 4, 5, 6))\n", "6 аргумента вместо 7")
        self.assert_compile_error(declaration + "print(fixed(1, 2, 3, 4, 5, 6, 7, 8))\n", "8 аргумента вместо 7")

    def test_unused_array_returns_are_rejected_at_signature_check(self):
        for declaration in (
            "extern fn array_result() -> [3]i64\n",
            "native fn array_result() -> [3]i64:\n{\n    NOP\n}\n",
            # The bad signature must be diagnosed before checking any body.
            "fn earlier():\n    missing()\nfn array_result() -> [3]i64:\n    return\n",
        ):
            with self.subTest(declaration=declaration):
                self.assert_compile_error(declaration, "функции не могут возвращать массивы")

    def test_c_callback_checks_signature_and_uses_the_system_v_abi(self):
        declaration = ('link "-lc"\n'
                       'unsafe extern fn qsort(data: ptr<i32>, count: u64, size: u64, '
                       'compare: fnptr<(ptr<char>, ptr<char>) -> i32>)\n')
        result = self.compile_run(declaration + '''unsafe fn compare(a: ptr<char>, b: ptr<char>) -> i32:
    let left: i32 = *(a as ptr<i32>)
    let right: i32 = *(b as ptr<i32>)
    if left < right: return -1
    return (left > right) as i32

let values: [4]i32 = [19, -4, 6, 0]
unsafe:
    let sorter: fnptr<(ptr<char>, ptr<char>) -> i32> = callback(compare)
    qsort(&values[0], 4 as u64, 4 as u64, sorter)
print(values[0], values[1], values[2], values[3])
''')
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "-4 0 6 19\n", ""))
        self.assert_compile_error(declaration + '''unsafe fn wrong(a: ptr<char>, b: ptr<char>) -> i64:
    return 0
let values: [1]i32
unsafe: qsort(&values[0], 1 as u64, 4 as u64, callback(wrong))
''', "вместо fnptr<(ptr<char>, ptr<char>) -> i32>")

    def test_c_callback_requires_unsafe_and_rejects_aggregate_abi(self):
        self.assert_compile_error('''fn named() -> i32:
    return 1
let address = callback(named)
''', "callback требует unsafe")
        self.assert_compile_error('''struct Item:
    value: i64
fn named(v: Item) -> i32:
    return v.value as i32
unsafe:
    let address = callback(named)
''', "callback поддерживает только скалярный ABI")

    def test_existing_function_named_callback_keeps_its_call_semantics(self):
        result = self.compile_run('''fn callback(n: i64) -> i64:
    return n + 1

print(callback(41))
''')
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "42\n", ""))

    def test_munmap_releases_mmap_region(self):
        result = self.compile_run(
            "unsafe:\n"
            "    let p: ptr<char> = mmap(4096)\n"
            "    if (p as i64) < 0:\n"
            "        panic(\"mmap\")\n"
            "    p[0] = 'V'\n"
            "    if p[0] != 'V':\n"
            "        panic(\"mapping\")\n"
            "    if munmap(p, 4096) != 0:\n"
            "        panic(\"munmap\")\n"
            "    print(\"ok\")\n"
        )
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "ok\n", ""))

    def test_byte_buffer_reads_binary_files_across_growth(self):
        payload = bytes(range(256)) * 17
        with tempfile.NamedTemporaryFile(prefix="volt-bytes-", delete=False) as f:
            f.write(payload)
            path = f.name.replace("\\", "\\\\").replace('"', '\\"')
        try:
            result = self.compile_run(
                "use bytes\n"
                "fn main() -> i64:\n"
                "    unsafe:\n"
                "        let buf: ByteBuffer\n"
                "        bytes_init(&buf)\n"
                f'        let status: i64 = bytes_read_file(&buf, "{path}")\n'
                "        if status != 0 or buf.len != 4352 or buf.cap < buf.len:\n"
                "            panic(\"read size\")\n"
                "        if bytes_get(&buf, 0) != 0 or bytes_get(&buf, 255) != 255:\n"
                "            panic(\"read first block\")\n"
                "        if bytes_get(&buf, 4096) != 0 or bytes_get(&buf, 4351) != 255:\n"
                "            panic(\"read second block\")\n"
                "        print(status, buf.len, buf.cap >= buf.len, bytes_get(&buf, 0), bytes_get(&buf, 255))\n"
                "        status = bytes_free(&buf)\n"
                "        print(status, buf.len, buf.cap)\n"
                "        return 0\n"
            )
        finally:
            os.unlink(f.name)
        self.assertEqual((result.returncode, result.stdout, result.stderr),
                         (0, "0 4352 true 0 255\n0 0 0\n", ""))

    def test_byte_buffer_rejects_invalid_capacity_and_index(self):
        result = self.compile_run(
            "use bytes\n"
            "fn main() -> i64:\n"
            "    unsafe:\n"
            "        let buf: ByteBuffer\n"
            "        bytes_init(&buf)\n"
            "        print(bytes_reserve(&buf, -1), bytes_free(&buf))\n"
            "        return 0\n"
        )
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "-22 0\n", ""))
        result = self.compile_run(
            "use bytes\n"
            "fn main() -> i64:\n"
            "    unsafe:\n"
            "        let buf: ByteBuffer\n"
            "        bytes_init(&buf)\n"
            "        bytes_push(&buf, 7 as u8)\n"
            "        print(bytes_get(&buf, 1))\n"
            "        return 0\n"
        )
        self.assertEqual((result.returncode, result.stderr), (1, "ByteBuffer index"))

    def test_string_repeat_overflow_is_rejected_before_writing(self):
        result = self.compile_run('print("xx" * 9223372036854775807)\n')
        self.assertEqual(result.returncode, 1)
        self.assertIn("volt: string too large", result.stderr)
        self.assertIn("arena", result.stderr)

    def test_integer_overflow_and_invalid_float_casts_trap(self):
        cases = (
            "let value: i64 = 9223372036854775807\nvalue = value + 1\nprint(value)\n",
            "let value: u64 = 18446744073709551615\nvalue = value + 1\nprint(value)\n",
            "let value: i8 = 127\nvalue += 1\nprint(value)\n",
            "print((-9223372036854775808) / -1)\n",
            "print(1 / 0)\n",
            "print(abs(-9223372036854775808))\n",
            "let value: i64 = 1\nprint(value << 64)\n",
            "let value: i8 = 128\nprint(value)\n",
            "use math\nprint(fact(21))\n",
        )
        for source in cases:
            result = self.compile_run(source)
            self.assertEqual(result.returncode, 1, source + result.stdout + result.stderr)
            self.assertIn("volt:", result.stderr)
        self.assertIn("integer overflow", self.compile_run(cases[0]).stderr)
        self.assertIn("division by zero", self.compile_run(cases[4]).stderr)
        result = self.compile_run("print(1e300 as i64)\n")
        self.assertEqual(result.returncode, 1)
        self.assertIn("float-to-int out of range", result.stderr)
        result = self.compile_run("print(1e19 as u64)\n")
        self.assertEqual((result.returncode, result.stdout), (0, "10000000000000000000\n"))
        self.assert_compile_error(
            "use constants\n",
            "целочисленное переполнение в const",
            {"constants": "let impossible: i64 = 9223372036854775807 + 1\n"},
        )

    def test_compound_assignment_evaluates_index_once(self):
        result = self.compile_run(
            "use counter\n"
            "let a: [2]i64 = [10, 20]\n"
            "a[next_index()] += 1\n"
            "print(calls, a[0], a[1])\n",
            {"counter": "let calls: i64 = 0\n"
                        "fn next_index() -> i64:\n"
                        "    calls += 1\n"
                        "    return calls - 1\n"},
        )
        self.assertEqual((result.returncode, result.stdout), (0, "1 11 20\n"))

    def test_module_initializers_run_after_dependencies_and_string_prelude(self):
        result = self.compile_run(
            "use a\nprint(\"entry\")\n",
            {
                "b": "let value: i64 = 0\n"
                     "fn init_value():\n"
                     "    value = 42\n"
                     "init_value()\n",
                "a": "use b\nprint(value, \"a\" + \"b\")\n",
            },
        )
        self.assertEqual((result.returncode, result.stdout), (0, "42 ab\nentry\n"))

    def test_unsigned_64_converts_to_float_in_cast_assignment_and_call(self):
        result = self.compile_run(
            "fn show(x: f64):\n"
            "    print(x)\n"
            "let u: u64 = 9223372036854775807\n"
            "u = u + 1\n"
            "let f: f64 = u\n"
            "print(u as f64, f)\n"
            "show(u)\n"
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout, "9.223372e18 9.223372e18\n9.223372e18\n")

    def test_unsigned_64_rounds_once_to_destination_precision(self):
        halves = [(64, 1 << 63, 1 << 11), (32, 1 << 63, 1 << 40),
                  (32, 1 << 62, 1 << 39)]
        source = ["fn same64(a: f64, b: f64) -> bool:\n    return a == b",
                  "fn same32(a: f32, b: f32) -> bool:\n    return a == b"]
        for bits, base, step in halves:
            for parity in (0, 1):
                low = base + parity * step
                midway = low + step // 2
                for delta in (-1, 0, 1):
                    value = midway + delta
                    expected = low + (step if delta > 0 or (delta == 0 and parity) else 0)
                    i = len(source)
                    source.extend((f"const c{i}: f{bits} = ({value} as u64) as f{bits}",
                                   f"const d{i}: f{bits} = {value} as u64",
                                   f"let u{i}: u64 = {value}",
                                   f"let f{i}: f{bits} = u{i}",
                                   f"print(c{i} == {expected}.0 as f{bits}, d{i} == c{i}, f{i} == c{i}, "
                                   f"u{i} as f{bits} == c{i}, same{bits}(u{i}, c{i}))"))
        result = self.compile_run("\n".join(source) + "\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "true true true true true\n" * 18)

    def test_mixed_signed_unsigned_comparisons_are_symmetric(self):
        result = self.compile_run(
            "let a: i32 = -1\nlet b: u32 = 1\n"
            "let c: i64 = -1\nlet d: u64 = 1\n"
            "let e: i64 = -1\nlet f: u32 = 1\n"
            "print(a < b, b > a, c < d, d > c, e < f, f > e)\n"
        )
        self.assertEqual((result.returncode, result.stdout), (0, "false false false false true true\n"))

    def test_compound_shifts_use_the_left_operand_signedness(self):
        result = self.compile_run(
            "let u: u8 = 128\nu >>= 1\n"
            "let s: i8 = -2\ns >>= 1\n"
            "print(u, s)\n"
        )
        self.assertEqual((result.returncode, result.stdout), (0, "64 -1\n"))

    def test_shifts_preserve_sign_on_right_and_discard_left_overflow_bits(self):
        result = self.compile_run(
            "let signed: i8 = -8\n"
            "let unsigned: u8 = 128\n"
            "let shifted: i8 = 64\n"
            "print(signed >> 1, unsigned >> 1, shifted << 1)\n"
        )
        self.assertEqual((result.returncode, result.stdout), (0, "-4 64 -128\n"))

    def test_global_constants_use_normal_typechecking_and_folding(self):
        result = self.compile_run(
            "use constants\nprint(f, b, empty_truth)\n",
            {"constants": "let f: f64 = 7.0 / 2.0\n"
                         "let b: bool = true and false\n"
                         "let empty_truth: bool = \"\" or false\n"},
        )
        self.assertEqual((result.returncode, result.stdout), (0, "3.500000 false true\n"))
        self.assert_compile_error(
            "use bad\n",
            "арифметика над bool и i64 недопустима",
            {"bad": "let value: i64 = true + 1\n"},
        )

    def test_repeated_log2_does_not_leak_x87_stack(self):
        result = self.compile_run(
            "let i: i64 = 0\n"
            "while i < 100:\n"
            "    if log2(2.0) != 1.0:\n"
            "        panic(\"bad log2\")\n"
            "    i = i + 1\n"
            "print(\"ok\")\n"
        )
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "ok\n", ""))

    def test_bad_indentation_native_return_and_len_arity_are_diagnostics(self):
        self.assert_compile_error(
            "fn main():\n"
            "    if true:\n"
            "    print(1)\n",
            "тело блока должно иметь отступ",
        )
        self.assert_compile_error("native fn bad():\n{\n    RET\n}\n", "native-тело не должно содержать ret")
        self.assert_compile_error("print(len())\n", "len: 0 аргумента(ов)")
        self.assert_compile_error("let a: [1]i64 = [1]\nprint(len(a, 2))\n", "len: 2 аргумента(ов)")

    def test_nested_if_does_not_capture_outer_else(self):
        result = self.compile_run(
            "let value: i64 = 0\n"
            "if false:\n"
            "    value = 1\n"
            "elif false:\n"
            "    if true:\n"
            "        value = 2\n"
            "else:\n"
            "    value = 3\n"
            "print(value)\n"
        )
        self.assertEqual((result.returncode, result.stdout), (0, "3\n"))

    def test_exponent_literals_and_malformed_exponents(self):
        result = self.compile_run("print(1e2 + 3.0, 1e2+3.0)\n")
        self.assertEqual((result.returncode, result.stdout), (0, "103.000000 103.000000\n"))
        self.assert_compile_error("print(1e)\n", "в экспоненте ожидаются цифры")

    def test_print_respects_signedness_char_and_wide_float(self):
        result = self.compile_run(
            "let neg: i8 = -1\n"
            "let u: u64 = 9223372036854775807\n"
            "u = u + 9223372036854775807\n"
            "u = u + 1\n"
            "print(neg, u, 1e20, 'A')\n"
            "print(u as f64)\n"
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout, "-1 18446744073709551615 1.000000e20 A\n1.844674e19\n")

    def test_numeric_conversions_are_checked_in_calls_and_returns(self):
        result = self.compile_run(
            "fn take(value: i8) -> i64:\n"
            "    return value\n"
            "fn from_float(value: f64) -> i64:\n"
            "    return value\n"
            "fn from_float_arg(value: i64) -> i64:\n"
            "    return value\n"
            "fn literal_return() -> i64:\n"
            "    return 3.9\n"
            "print(literal_return(), from_float(3.9), from_float_arg(3.9))\n"
        )
        self.assertEqual((result.returncode, result.stdout), (0, "3 3 3\n"))

        with tempfile.NamedTemporaryFile("w", suffix=".volt", delete=False) as source:
            source.write(
                "fn take(value: i8) -> i64:\n"
                "    return value\n"
                "print(take(1000))\n"
            )
            path = source.name
        try:
            result = subprocess.run(
                [VCC, path, "--run"],
                capture_output=True,
                text=True,
                timeout=15,
            )
        finally:
            os.unlink(path)
        self.assertEqual(result.returncode, 1)
        self.assertIn("integer overflow", result.stderr)
        with tempfile.NamedTemporaryFile("w", suffix=".volt", delete=False) as source:
            source.write(
                "fn result() -> i8:\n"
                "    return 1000\n"
                "print(result())\n"
            )
            path = source.name
        try:
            result = subprocess.run(
                [VCC, path, "--run"],
                capture_output=True,
                text=True,
                timeout=15,
            )
        finally:
            os.unlink(path)
        self.assertEqual(result.returncode, 1)
        self.assertIn("integer overflow", result.stderr)

    def test_nan_is_false_in_scalar_logic_and_char_assignment_keeps_type(self):
        result = self.compile_run(
            "let nan: f64 = 0.0 / 0.0\n"
            "if nan:\n"
            "    print(\"bad-if\")\n"
            "if 1.0 and nan:\n"
            "    print(\"bad-and\")\n"
            "if nan or 0.0:\n"
            "    print(\"bad-or\")\n"
            "if not nan:\n"
            "    print(\"not-nan\")\n"
            "while nan:\n"
            "    print(\"bad-while\")\n"
            "let c: char = 'A'\n"
            "let n: u8 = c\n"
            "print(c, n)\n"
            "fn identity<T>(value: T) -> T:\n"
            "    return value\n"
            "print(identity('B'), identity(66 as u8))\n"
        )
        self.assertEqual((result.returncode, result.stdout), (0, "not-nan\nA 65\nB 66\n"))

    def test_nan_truthiness_matches_for_compile_time_constants(self):
        result = self.compile_run(
            "const NAN_VALUE: f64 = 0.0 / 0.0\n"
            "const POS_INF: f64 = 1.0 / 0.0\n"
            "if NAN_VALUE or 0.0:\n"
            "    print(\"bad\")\n"
            "if not NAN_VALUE and POS_INF:\n"
            "    print(\"ok\")\n"
        )
        self.assertEqual((result.returncode, result.stdout), (0, "ok\n"))

    def test_exp_accuracy_and_scaled_hypot(self):
        result = self.compile_run(
            "use math\n"
            "if abs(exp(4.9) - 134.28977968493552) > 0.000000000001:\n"
            "    panic(\"exp\")\n"
            "if hypot(1e200, 1e200) < 1.4e200 or hypot(1e200, 1e200) > 1.5e200:\n"
            "    panic(\"hypot\")\n"
            "print(\"ok\")\n"
        )
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "ok\n", ""))

    def test_integer_power_is_logarithmic_and_handles_negative_minimum(self):
        result = self.compile_run(
            "use math\n"
            "if powi(1.0, -9223372036854775808) != 1.0:\n"
            "    panic(\"powi\")\n"
            "if ipowi(2, -2) != 0 or ipowi(-1, -3) != -1:\n"
            "    panic(\"ipowi\")\n"
            "print(\"ok\")\n"
        )
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "ok\n", ""))

    def test_ranges_are_half_open_and_never_descend_implicitly(self):
        result = self.compile_run(
            "let start: i64 = 3\nlet stop: i64 = 0\nlet count: i64 = 0\n"
            "for i in start..stop:\n"
            "    count += 1\n"
            "print(count)\n"
        )
        self.assertEqual((result.returncode, result.stdout), (0, "0\n"))
        signed_bounds = self.compile_run(
            "let start: i8 = -2\nlet stop: i16 = 1\nlet total = 0\n"
            "for i in start..stop:\n    total += i\n"
            "let edge: i64 = 9223372036854775807\n"
            "for i in edge - 1..edge:\n    total += 1\n"
            "print(total)\n"
        )
        self.assertEqual((signed_bounds.returncode, signed_bounds.stdout), (0, "-2\n"))
        unsigned_bounds = self.compile_run(
            "let start: u8 = 1\nlet stop: u8 = 4\nlet total = 0\n"
            "for i in start..stop:\n    total += i\n"
            "print(total)\n"
        )
        self.assertEqual((unsigned_bounds.returncode, unsigned_bounds.stdout), (0, "6\n"))
        out_of_range = self.compile_run(
            "let stop: u64 = 18446744073709551615\nfor i in 0..stop:\n    print(i)\n"
        )
        self.assertEqual(out_of_range.returncode, 1)
        self.assertIn("integer overflow", out_of_range.stderr)

    def test_duplicate_and_by_value_recursive_structs_are_rejected(self):
        self.assert_compile_error(
            "struct X:\n    a: i64\nstruct X:\n    b: i64\n",
            "struct X определён дважды",
        )
        self.assert_compile_error(
            "struct Node:\n    next: Node\n",
            "бесконечная рекурсия по значению",
        )
        result = self.compile_run("struct Node:\n    next: ptr<Node>\nprint(\"ok\")\n")
        self.assertEqual((result.returncode, result.stdout), (0, "ok\n"))

    def test_struct_constructor_can_be_passed_to_function(self):
        result = self.compile_run(
            "struct Point:\n    x: i64\n"
            "fn get_x(p: Point) -> i64:\n    return p.x\n"
            "print(get_x(Point(7)))\n"
        )
        self.assertEqual((result.returncode, result.stdout), (0, "7\n"))

    def test_logical_not_evaluates_operand_once(self):
        result = self.compile_run('''fn effect() -> bool:
    print("called")
    return true
print(not effect())
''')
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "called\nfalse\n", ""))

    def test_struct_return_sret_initialization_forwarding_and_defer_snapshot(self):
        result = self.compile_run('''struct Point:
    x: i64
    y: i64
fn make() -> Point:
    return Point(3, 4)
fn forward(point: Point) -> Point:
    return point
fn nested(point: Point) -> Point:
    return forward(forward(point))
fn changed() -> Point:
    let point = Point(8, 9)
    defer point.x = 99
    return point
let first: Point = make()
let second: Point = forward(first)
let third: Point = nested(second)
let saved: Point = changed()
third = make()
print(first.x, first.y, second.x, second.y, third.x, third.y, saved.x, saved.y)
''')
        self.assertEqual((result.returncode, result.stdout, result.stderr),
                         (0, "3 4 3 4 3 4 8 9\n", ""))

    def test_struct_return_is_rejected_at_c_abi_boundary(self):
        for declaration in (
            "extern fn foreign() -> Point\n",
            "native fn foreign() -> Point:\n{\n    NOP\n}\n",
        ):
            with self.subTest(declaration=declaration):
                self.assert_compile_error(
                    "struct Point:\n    x: i64\n" + declaration,
                    "возврат struct запрещён в extern/native ABI",
                )

    def test_large_output_uses_write_all(self):
        result = self.compile_run('print("x" * 32768)\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "x" * 32768 + "\n")

    def test_float_output_is_byte_exact_for_formatting_edges(self):
        result = self.compile_run(
            "let nan: f64 = 0.0 / 0.0\n"
            "let inf: f64 = 1.0 / 0.0\n"
            "print(nan, inf, 0.0, -0.0)\n"
            "print(1.2345674, 1.2345675, 1.9999996)\n"
            "print(9223372036854775808.0, 1.0e20)\n"
        )
        expected = (b"nan inf 0.000000 0.000000\n"
                    b"1.234567 1.234568 2.000000\n"
                    b"9.223372e18 1.000000e20\n")
        self.assertEqual((result.returncode, result.stdout.encode(), result.stderr),
                         (0, expected, ""))

    @unittest.skipUnless(os.path.exists("/dev/full"), "Linux /dev/full is unavailable")
    def test_float_print_fails_on_write_error(self):
        with tempfile.TemporaryDirectory(prefix="volt-write-error-") as tmp:
            src = os.path.join(tmp, "main.volt")
            with open(src, "w", encoding="utf-8") as f:
                f.write("print(1.25)\n")
            with open("/dev/full", "wb") as full:
                result = subprocess.run([VCC, src, "--run"],
                                        stdout=full, stderr=subprocess.PIPE,
                                        text=True, timeout=15)
        self.assertEqual(result.returncode, 1)
        self.assertIn("volt: write failed", result.stderr)

    @unittest.skipUnless(os.path.exists("/dev/full"), "Linux /dev/full is unavailable")
    def test_print_fails_on_write_error(self):
        with tempfile.TemporaryDirectory(prefix="volt-write-error-") as tmp:
            src = os.path.join(tmp, "main.volt")
            with open(src, "w", encoding="utf-8") as f:
                f.write('print("cannot write")\n')
            with open("/dev/full", "wb") as full:
                result = subprocess.run([VCC, src, "--run"],
                                        stdout=full, stderr=subprocess.PIPE,
                                        text=True, timeout=15)
        self.assertEqual(result.returncode, 1)
        self.assertIn("volt: write failed", result.stderr)

    def test_error_helper_writes_newline_to_stderr(self):
        result = self.compile_run('put_errnl("x")\n')
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "", "x\n"))

    def test_snake_sdl_startup_and_quit_without_a_terminal(self):
        with tempfile.TemporaryDirectory(prefix="volt-snake-") as tmp:
            exe = os.path.join(tmp, "snake")
            built = subprocess.run([VCC, SNAKE, "-o", exe],
                                   capture_output=True, text=True, timeout=30)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            env = {**os.environ, "SDL_NO_SIGNAL_HANDLERS": "0"}
            failure = subprocess.run([exe], env={**env, "SDL_VIDEODRIVER": "invalid"},
                                     stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=5)
            self.assertEqual((failure.returncode, failure.stdout, failure.stderr), (1, "", ""))
            with subprocess.Popen([exe], env={**env, "SDL_VIDEODRIVER": "dummy"},
                                  stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE, text=True) as proc:
                try:
                    deadline = time.monotonic() + 3
                    # SDL turns SIGINT into SDL_QUIT only after installing its handler.
                    while time.monotonic() < deadline and proc.poll() is None:
                        with open(f"/proc/{proc.pid}/status", encoding="utf-8") as status:
                            caught = next(line.split()[1] for line in status if line.startswith("SigCgt:"))
                        if int(caught, 16) & (1 << (signal.SIGINT - 1)):
                            break
                        time.sleep(0.01)
                    else:
                        self.fail("Snake did not initialize SDL")
                    proc.send_signal(signal.SIGINT)
                    out, err = proc.communicate(timeout=3)
                    self.assertEqual((proc.returncode, out, err), (0, "", ""))
                finally:
                    if proc.poll() is None:
                        proc.kill()
                        proc.communicate()

    def test_rift_compiles_and_quit_restores_terminal_settings(self):
        source = os.path.join(ROOT, "apps", "rift.volt")
        with tempfile.TemporaryDirectory(prefix="volt-rift-pty-") as tmp:
            exe = os.path.join(tmp, "rift")
            built = subprocess.run([VCC, source, "-o", exe],
                                   capture_output=True, text=True, timeout=30)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            master, slave = pty.openpty()
            before = termios.tcgetattr(slave)
            proc = None
            output = b""
            try:
                proc = subprocess.Popen([exe], stdin=slave, stdout=slave, stderr=slave,
                                        close_fds=True)
                ready, _, _ = select.select([master], [], [], 3)
                self.assertTrue(ready, "rift did not draw an initial frame")
                output += os.read(master, 8192)
                self.assertIn(b"VOLT RIFT DELVER", output)
                self.assertIn(b"WASD/arrows move", output)
                os.write(master, b"q")
                self.assertEqual(proc.wait(timeout=3), 0)
                while True:
                    ready, _, _ = select.select([master], [], [], 0.1)
                    if not ready: break
                    output += os.read(master, 8192)
                self.assertIn(b"You retreat from the rift", output)
                self.assertEqual(termios.tcgetattr(slave), before)
            finally:
                if proc is not None and proc.poll() is None:
                    proc.kill()
                    proc.wait()
                os.close(master)
                os.close(slave)

    def test_parallel_compiles_do_not_share_runtime_objects(self):
        def build(i):
            return self.compile_run(f'print("build-{i}")\n', timeout=30)

        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            results = list(pool.map(build, range(4)))
        self.assertEqual([r.stdout for r in results], [f"build-{i}\n" for i in range(4)])
        self.assertTrue(all(r.returncode == 0 for r in results))

    def test_test_runner_times_out_and_never_updates_failed_golden(self):
        runner_path = os.path.join(HERE, "run.py")
        spec = importlib.util.spec_from_file_location("volt_test_runner", runner_path)
        runner = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(runner)
        with tempfile.TemporaryDirectory(prefix="volt-runner-") as tmp:
            tests = os.path.join(tmp, "tests")
            gold = os.path.join(tmp, "expected")
            os.makedirs(tests)
            os.makedirs(gold)
            with open(os.path.join(tests, "bad.volt"), "w", encoding="utf-8") as f:
                f.write("unused\n")
            expected = os.path.join(gold, "bad.txt")
            with open(expected, "w", encoding="utf-8") as f:
                f.write("keep this\n")
            fake = os.path.join(tmp, "fake-volt")
            runner.HERE, runner.GOLD, runner.VCC = tests, gold, fake
            old_timeout, old_argv = runner.TEST_TIMEOUT, sys.argv
            try:
                with open(fake, "w", encoding="utf-8") as f:
                    f.write("#!/bin/sh\nexit 1\n")
                os.chmod(fake, 0o700)
                runner.TEST_TIMEOUT = 1
                sys.argv = [runner_path, "--update"]
                with contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(runner.main(), 1)
                with open(expected, encoding="utf-8") as f:
                    self.assertEqual(f.read(), "keep this\n")
                with open(fake, "w", encoding="utf-8") as f:
                    f.write("#!/bin/sh\nexec sleep 5\n")
                runner.TEST_TIMEOUT = 0.05
                with contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(runner.main(), 1)
                with open(expected, encoding="utf-8") as f:
                    self.assertEqual(f.read(), "keep this\n")
            finally:
                runner.TEST_TIMEOUT, sys.argv = old_timeout, old_argv

    def test_local_wrapper_reassignment_canonical_copy_and_variant_transitions(self):
        source = '''use ops
fn option_run() -> i64:
    let o: Option<i64> = Some(71)
    o = None
    match o:
        Some(v): return -1
        None:
            o = Some(next_value())
    o = o
    match o:
        Some(v): return v
        None: return -2
fn result_run() -> i64:
    let r: Result<i64, i32> = Ok(12)
    r = Err(9 as i32)
    match r:
        Ok(v): return -3
        Err(code):
            r = Ok(22)
    match r:
        Ok(v): return v
        Err(code): return -4
print(option_run(), result_run(), calls)
'''
        result = self.compile_run(source, {"ops": "let calls: i64 = 0\n"
                                               "fn next_value() -> i64:\n"
                                               "    calls += 1\n"
                                               "    return 19\n"})
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "19 22 1\n", ""))

    def test_wrapper_reassignment_requires_exact_types_and_local_slot(self):
        cases = [
            ("fn f():\n    let x: Option<i64> = None\n    x = Some(1 as i32)\n", "Some: i32 вместо i64"),
            ("fn f():\n    let x: Result<i64, i32> = Ok(1)\n    x = Err(1 as u32)\n", "Err: u32 вместо i32"),
            ("fn f():\n    let x: Option<i64> = None\n    x = Ok(1)\n", "Ok требует контекста Result<T, E>"),
            ("fn f():\n    let x: Option<i64> = None\n    x += Some(1)\n", "Option/Result поддерживает только присваивание '='"),
            ("struct S:\n    x: Option<i64>\nfn f(s: S):\n    s.x = None\n", "Option/Result нельзя помещать в поля struct"),
            ("fn f():\n    let a: [1]Option<i64> = [None]\n    a[0] = None\n", "Option/Result нельзя помещать в массив"),
        ]
        for source, diagnostic in cases:
            with self.subTest(diagnostic=diagnostic):
                self.assert_compile_error(source, diagnostic)

    def test_option_some_constructor_and_match_binding(self):
        source = '''fn run() -> i64:
    let o: Option<i64> = Some(7)
    match o:
        Some(x):
            return x
        None:
            return 0
return run()
'''
        result = self.compile_run(source)
        self.assertEqual((result.returncode, result.stdout, result.stderr), (7, "", ""))

    def test_option_none_and_result_variants_match_locally(self):
        source = '''fn option_none() -> i64:
    let o: Option<i64> = None
    match o:
        Some(x):
            return x
        None:
            return 2
fn result_ok() -> i64:
    let r: Result<i64, i32> = Ok(3)
    match r:
        Ok(x):
            return x
        Err(code):
            return code as i64
fn result_err() -> i64:
    let r: Result<i64, i32> = Err(4 as i32)
    match r:
        Ok(x):
            return x
        Err(code):
            return code as i64
print(option_none(), result_ok(), result_err())
'''
        result = self.compile_run(source)
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "2 3 4\n", ""))

    def test_entry_root_wrapper_lets_are_locals_but_imported_module_globals_are_rejected(self):
        entry = '''let explicit: Option<i64> = Some(5)
let inferred = Some(6)
match explicit:
    Some(x):
        print(x)
    None:
        print(0)
match inferred:
    Some(x):
        print(x)
    None:
        print(0)
'''
        result = self.compile_run(entry)
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "5\n6\n", ""))
        imported_globals = [
            ("let explicit: Option<i64> = None\n", "глобальная let в модуле требует константу"),
            ("let inferred = Some(1)\n", "глобальная let в модуле требует константу"),
        ]
        for module_source, diagnostic in imported_globals:
            with self.subTest(module_source=module_source):
                result = self.compile_run('use bad\nprint("entry")\n', modules={"bad": module_source})
                self.assertNotEqual(result.returncode, 0)
                output = result.stdout + result.stderr
                self.assertIn(diagnostic, output)
                self.assertIn("bad.volt:", output)
                self.assertNotIn("Traceback", output)

    def test_wrapper_function_abi_option_result_calls_and_defers(self):
        source = '''
fn wrap(x: Option<i64>) -> Option<i64>:
    defer print("last")
    defer print("defer", 4)
    match x:
        Some(v): return Some(v + 1)
        None: return None
fn identity(x: Result<i64, i32>) -> Result<i64, i32>:
    return x
fn relay(x: Option<i64>) -> Option<i64>:
    return wrap(x)
let a: Option<i64> = relay(Some(4))
let b: Result<i64, i32> = identity(Ok(9))
match a:
    Some(v): print(v)
    None: panic("none")
match b:
    Ok(v): print(v)
    Err(e): panic("err")
'''
        result = self.compile_run(source)
        self.assertEqual((result.returncode, result.stdout, result.stderr),
                         (0, "defer 4\nlast\n5\n9\n", ""))

    def test_wrapper_abi_result_err_float_and_defer_snapshot(self):
        source = '''
fn err4(code: i32) -> Result<i32, i32>:
    return Err(code)
fn forward1(x: Result<i32, i32>) -> Result<i32, i32>:
    return x
fn forward2(x: Result<i32, i32>) -> Result<i32, i32>:
    return forward1(x)
fn float_forward1(x: Option<f64>) -> Option<f64>:
    return x
fn float_forward2(x: Option<f64>) -> Option<f64>:
    return float_forward1(x)
fn snapshot(x: i64) -> Option<i64>:
    defer x = 99
    return Some(x)
let failed: Result<i32, i32> = forward2(err4(7))
let floating: Option<f64> = float_forward2(Some(3.5))
let saved: Option<i64> = snapshot(5)
match failed:
    Ok(v): panic("expected Err")
    Err(code): print(code)
match floating:
    Some(v): print(v)
    None: panic("expected Some")
match saved:
    Some(v): print(v)
    None: panic("expected Some")
'''
        result = self.compile_run(source)
        self.assertEqual((result.returncode, result.stdout, result.stderr),
                         (0, "7\n3.500000\n5\n", ""))

    def test_wrapper_abi_boundary_and_float_registers(self):
        # sret consumes one of six integer-class registers; floats have their own eight.
        ok = '''
fn f(a: Option<i64>, b: i64, c: i64, d: i64, e: i64) -> Option<i64>:
    return a
let x: Option<i64> = f(Some(7), 1, 2, 3, 4)
match x:
    Some(v): print(v)
    None: panic("none")
'''
        result = self.compile_run(ok)
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "7\n", ""))
        mixed = '''
fn g(a: f64, b: f64, c: f64, d: f64, e: f64, f: f64, g: f64, h: f64, x: Option<i64>) -> Option<i64>:
    return x
let y: Option<i64> = g(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, Some(11))
match y:
    Some(v): print(v)
    None: panic("none")
'''
        result = self.compile_run(mixed)
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "11\n", ""))
        self.assert_compile_error(
            "fn f(x: Option<i64>) -> i64:\n    return 0\nlet wrong: Result<i64, i32> = Ok(1)\nprint(f(wrong))\n",
            "аргумент 'x': Result<i64, i32> вместо Option<i64>",
        )
        stack_with_sret = '''
fn f(a: i64, b: i64, c: i64, d: i64, e: i64, x: Option<i64>) -> Option<i64>:
    return x
match f(1, 2, 3, 4, 5, Some(13)):
    Some(v): print(v)
    None: panic("none")
'''
        result = self.compile_run(stack_with_sret)
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "13\n", ""))
        floats = '''
fn f(a: f64, b: f64, c: f64, d: f64, e: f64, f: f64, g: f64, h: f64) -> f64:
    return a + h
print(f(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0))
'''
        result = self.compile_run(floats)
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "9.000000\n", ""))
        stack_float = '''
fn f(a: f64, b: f64, c: f64, d: f64, e: f64, f: f64, g: f64, h: f64, i: f64, n: i64) -> f64:
    return a + 2.0 * h + 3.0 * i + n as f64
print(f(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.5, 11))
'''
        result = self.compile_run(stack_float)
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "56.500000\n", ""))

    def test_wrapper_containment_diagnostics_preserve_source_location(self):
        source = '''fn f() -> i64:
    let p: Option<ptr<Option<i64>>> = None
    return 0
'''
        result = self.compile_run(source)
        output = result.stdout + result.stderr
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("main.volt:2:", output)
        self.assertIn("ptr не может скрывать Option/Result", output)
        self.assertNotIn("Traceback", output)

    def test_postfix_question_option_propagates_and_runs_defers_lifo(self):
        source = '''fn identity(x: Option<i64>) -> Option<i64>:
    return x
fn nested(x: Option<i64>) -> Option<i64>:
    defer print("outer-first", 1)
    defer print("outer-last", 2)
    let y = Some(identity(x)?)
    return y
let some: Option<i64> = nested(Some(7))
let none: Option<i64> = nested(None)
match some:
    Some(value): print("some", value)
    None: print("bad-some")
match none:
    Some(value): print("bad-none", value)
    None: print("none")
'''
        result = self.compile_run(source)
        self.assertEqual((result.returncode, result.stdout, result.stderr),
                         (0, "outer-last 2\nouter-first 1\nouter-last 2\nouter-first 1\nsome 7\nnone\n", ""))

    def test_postfix_question_result_success_type_may_change(self):
        source = '''fn identity(x: Result<i64, i32>) -> Result<i64, i32>:
    return x
fn widen_success(x: Result<i64, i32>) -> Result<f64, i32>:
    return Ok((identity(x)? as f64) + 0.5)
let ok: Result<f64, i32> = widen_success(Ok(4))
let err: Result<f64, i32> = widen_success(Err(8 as i32))
match ok:
    Ok(value): print("ok", value)
    Err(code): print("bad-ok", code)
match err:
    Ok(value): print("bad-err", value)
    Err(code): print("err", code)
'''
        result = self.compile_run(source)
        self.assertEqual((result.returncode, result.stdout, result.stderr),
                         (0, "ok 4.500000\nerr 8\n", ""))

    def test_postfix_question_result_propagates_error_and_supports_nested_arguments(self):
        source = '''fn identity(x: Result<i64, i32>) -> Result<i64, i32>:
    return x
fn add(a: i64, b: i64) -> i64:
    return a + b
fn nested(x: Result<i64, i32>) -> Result<i64, i32>:
    defer print("cleanup", 1)
    defer print("cleanup", 2)
    return Ok(add(identity(x)?, 3))
let ok: Result<i64, i32> = nested(Ok(4))
let err: Result<i64, i32> = nested(Err(8 as i32))
match ok:
    Ok(value): print("ok", value)
    Err(code): print("bad-ok", code)
match err:
    Ok(value): print("bad-err", value)
    Err(code): print("err", code)
'''
        result = self.compile_run(source)
        self.assertEqual((result.returncode, result.stdout, result.stderr),
                         (0, "cleanup 2\ncleanup 1\ncleanup 2\ncleanup 1\nok 7\nerr 8\n", ""))

    def test_postfix_question_type_errors_are_located(self):
        cases = [
            ("fn bad(x: Option<i64>) -> i64:\n    return x?\n", "? несовместим с типом результата функции"),
            ("fn bad(x: Result<i64, i32>) -> Result<i64, u32>:\n    return x?\n", "? несовместим с типом результата функции"),
            ("fn bad() -> Option<i64>:\n    return 7?\n", "постфиксный ? требует Option или Result"),
        ]
        for source, diagnostic in cases:
            with self.subTest(source=source):
                result = self.compile_run(source)
                output = result.stdout + result.stderr
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(diagnostic, output)
                self.assertIn("main.volt:", output)
                self.assertNotIn("Traceback", output)

    def test_wrapper_unsupported_contexts_are_semantic_errors(self):
        cases = [
            ("extern fn f(x: Option<i64>) -> i64\n", "Option/Result параметры запрещены в extern/native"),
            ("native fn f() -> Option<i64>:\n{\n    NOP\n}\n", "Option/Result результаты запрещены в extern/native"),
            ("fn f() -> i64:\n    return Some(1)\n", "Option/Result return требует сигнатуру с тем же wrapper-типом"),
            ("fn f() -> i64:\n    match Some(1):\n        Some(x):\n            return x\n        None:\n            return 0\n", "match временного wrapper-конструктора пока не поддерживается"),
            ("struct S:\n    value: Option<i64>\n", "Option/Result нельзя помещать в поля struct"),
            ("struct S:\n    value: ptr<Option<i64>>\n", "ptr не может скрывать Option/Result"),
            ("let p: Option<ptr<Option<i64>>> = None\n", "ptr не может скрывать Option/Result"),
            ("fn f(p: ptr<Option<i64>>) -> i64:\n    return 0\n", "ptr не может скрывать Option/Result"),
            ("fn f() -> i64:\n    let a: [1]Option<i64> = [None]\n    return 0\n", "Option/Result нельзя помещать в массив"),
            ("fn f() -> i64:\n    let x: Option<i64>\n    return 0\n", "Option/Result нельзя обнулять автоматически"),
        ]
        for source, message in cases:
            with self.subTest(message=message):
                self.assert_compile_error(source, message)

    def test_payload_free_enum_match_and_duplicate_discriminant(self):
        source = '''enum Color:
    Red
    Blue
fn run() -> i64:
    let c: Color = Color.Blue
    match c:
        Color.Red:
            return 1
        Color.Blue:
            return 2
return run()
'''
        result = self.compile_run(source)
        self.assertEqual((result.returncode, result.stdout, result.stderr), (2, "", ""))
        duplicate = '''enum Bad:
    First = 4
    Second = 4
print("unreachable")
'''
        self.assert_compile_error(duplicate, "повторный discriminant")

    def test_wrapper_in_condition_is_rejected(self):
        # раньше `if opt:` компилировался и был всегда истинен (адрес != 0)
        self.assert_compile_error(
            "fn run() -> i64:\n"
            "    let o: Option<i64> = None\n"
            "    if o:\n"
            "        return 1\n"
            "    return 0\n"
            "print(run())\n",
            "Option/Result в условии всегда истинен",
        )

    def test_min_max_mixed_width_traps_instead_of_truncating(self):
        # раньше max(5 as i8, 1000) молча печатал -24
        result = self.compile_run("print(max(5 as i8, 1000))\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("volt: integer overflow", result.stdout + result.stderr)
        ok = self.compile_run("print(max(5 as i8, 7))\nprint(min(5 as i8, 7))\n")
        self.assertEqual(ok.returncode, 0)
        self.assertEqual(ok.stdout, "7\n5\n")

    def test_match_arm_non_identifier_is_clean_diagnostic(self):
        # раньше компилятор падал с AttributeError на None.startswith
        self.assert_compile_error(
            "enum Color:\n"
            "    Red\n"
            "fn run() -> i64:\n"
            "    let c = Color.Red\n"
            "    match c:\n"
            "        5:\n"
            "            return 0\n"
            "    return 1\n"
            "print(run())\n",
            "ожидался вариант, Some(x)/Ok(x)/Err(x) или _",
        )

    def test_hex_float_literal_is_clean_diagnostic(self):
        # раньше лексер падал с AttributeError на m2.group
        self.assert_compile_error(
            "let x = 0x1.5\nprint(x)\n",
            "точка допустима только в десятичном литерале",
        )

    def test_non_ascii_char_literal_is_rejected(self):
        # раньше 'я' молча обрезалась до байта и печатала мусор
        self.assert_compile_error("let c = 'я'\nprint(c)\n", "char — один байт")

    def test_struct_array_literals_and_ctor_assignment(self):
        source = '''struct Point:
    x: i64
    y: i64
fn run() -> i64:
    let a = Point(1, 2)
    let pts = [Point(3, 4), a]
    pts[0] = Point(5, 6)
    let typed: [2]Point = [a, pts[1]]
    return typed[0].x + typed[0].y + pts[0].x + pts[0].y
print(run())
'''
        result = self.compile_run(source)
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "14\n", ""))

    def test_for_loop_last_iteration_does_not_wrap(self):
        source = "let n = 0\nfor i in 0..3:\n    n += i\nprint(n)\n"
        result = self.compile_run(source)
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "3\n", ""))

    def test_constant_encoding_preserves_signed_zero_and_checks_literal_range(self):
        result = self.compile_run('print(1.0 / 0.0, 1.0 / -0.0)\n')
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "inf -inf\n", ""))
        self.assert_compile_error('print(-9223372036854775809)\n', "main.volt:1: ошибка: целочисленный литерал выходит за диапазон i64")

    def test_float_unary_minus_flips_runtime_zero_sign(self):
        result = self.compile_run('''fn negate64(value: f64) -> f64:
    return -value

fn negate32(value: f32) -> f32:
    return -value

let one: f32 = 1.0
print(1.0 / negate64(0.0), 1.0 / negate64(-0.0))
print(one / negate32(0.0), one / negate32(-0.0))
print(negate64(2.5), negate32(-1.5))
''')
        self.assertEqual((result.returncode, result.stdout, result.stderr),
                         (0, "-inf inf\n-inf inf\n-2.500000 1.500000\n", ""))

    def test_abs_clears_the_sign_bit_in_each_float_width(self):
        result = self.compile_run('let narrow: f32 = -1.5\nprint(abs(narrow), abs(-2.5))\n')
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "1.500000 2.500000\n", ""))

    def test_inclusive_for_range_has_one_evaluation_and_handles_i64_max(self):
        result = self.compile_run('''fn bound(label: string, value: i64) -> i64:
    print(label)
    return value
let sum = 0
for i in bound("start", 2)..=bound("stop", 4):
    sum += i
for i in 4..=3: panic("descending range")
for i in -9223372036854775808..=-9223372036854775808:
    print(i)
for i in 9223372036854775806..=9223372036854775807:
    defer print(i)
    continue
print(sum)
''')
        self.assertEqual((result.returncode, result.stdout, result.stderr),
                         (0, "start\nstop\n-9223372036854775808\n9223372036854775806\n9223372036854775807\n9\n", ""))

    def test_native_bss_alignment_applies_to_runtime_addresses(self):
        result = self.compile_run('''native fn alignment_remainder() -> i64:
{
    .data
    .balign 4096
    .byte 1
    .bss
    .balign 4096
aligned_cell:
    .space 8
    .text
    lea rax, [rip + aligned_cell]
    and rax, 4095
}
unsafe: print(alignment_remainder())
''')
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "0\n", ""))

    @unittest.skipUnless(shutil.which("readelf"), "readelf is not installed")
    def test_generated_elf_has_non_executable_stack(self):
        with tempfile.TemporaryDirectory(prefix="volt-elf-") as tmp:
            src = os.path.join(tmp, "main.volt")
            exe = os.path.join(tmp, "program")
            with open(src, "w", encoding="utf-8") as f:
                f.write('print("ok")\n')
            result = subprocess.run([VCC, src, "-o", exe],
                                    capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            headers = subprocess.run(["readelf", "-W", "-l", exe],
                                     capture_output=True, text=True, check=True).stdout
            self.assertNotIn("INTERP", headers)
            stack = next(line for line in headers.splitlines() if "GNU_STACK" in line)
            self.assertIn("RW", stack)
            self.assertNotIn("RWE", stack)


if __name__ == "__main__":
    unittest.main()
