#!/usr/bin/env python3
"""Check the bounded, non-owning TextView lexer API."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
VOLT = Path(os.environ.get("VOLT_COMPILER", ROOT / "volt")).resolve()


class VstdTextView(unittest.TestCase):
    def assert_output(self, source, stdout="", *, status=0, stderr=""):
        with tempfile.TemporaryDirectory(prefix="volt-text-view-") as tmp:
            path = Path(tmp) / "main.volt"
            path.write_text("use text_view\n\n" + source, encoding="utf-8")
            exe = path.with_suffix("")
            env = {"PATH": "", "TMPDIR": tmp}
            built = subprocess.run([VOLT, path, "-o", exe], cwd=tmp, env=env,
                                   capture_output=True, text=True, timeout=15)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            ran = subprocess.run([exe], cwd=tmp, env=env, capture_output=True,
                                 text=True, timeout=5)
            self.assertEqual((ran.returncode, ran.stdout, ran.stderr), (status, stdout, stderr))

    def test_split_keeps_the_address_of_each_token(self):
        self.assert_output('''fn find_colon(view: text_view.TextView) -> i64:
    for i in 0..text_view.len(view):
        if text_view.get(view, i) == (':' as u8): return i
    return -1

let source = "key:" + "value"
let input = text_view.from_string(source)
let split = find_colon(input)
let key = text_view.slice(input, 0, split)
let value = text_view.slice(input, split + 1, text_view.len(input))
print(sizeof(text_view.TextView), text_view.len(key), text_view.len(value), text_view.get(key, 2), text_view.get(value, 4))
''', "16 3 5 121 101\n")

    def test_ranges_alias_the_original_bytes(self):
        self.assert_output('''let src: [3]char = ['a', 'b', 'c']
unsafe:
    let view = text_view.from_bytes(&src[0], 3)
    let range = text_view.slice(view, 1, 3)
    # Observe aliasing deliberately inside an unsafe test, not in the safe API.
    let bytes = &src[0]
    bytes[1] = 'z'
    print(text_view.get(range, 0))
''', "122\n")

    def test_utf8_ranges_and_indices_count_bytes(self):
        self.assert_output('''let input = text_view.from_string("éz")
let prefix = text_view.slice(input, 0, 2)
let continuation = text_view.slice(prefix, 1, 2)
print(text_view.len(input), text_view.get(input, 0), text_view.get(input, 1))
print(text_view.len(continuation), text_view.get(continuation, 0))
''', "3 195 169\n1 169\n")

    def test_empty_views_need_only_the_c_terminator(self):
        self.assert_output('''let unset: string
let input = text_view.from_string("a")
let out: [1]char = ['!']
unsafe:
    let blank = text_view.slice(text_view.from_string(unset), 0, 0)
    let end = text_view.slice(input, 1, 1)
    print(text_view.len(blank), text_view.len(end))
    print(text_view.copy_cstr(blank, &out[0], 1), out[0] as u8)
    out[0] = '!'
    print(text_view.copy_cstr(end, &out[0], 1), out[0] as u8)
''', "0 0\n0 0\n0 0\n")

    def test_invalid_indices_and_ranges_fail_before_pointer_access(self):
        for end, operation, diagnostic in (
            (2, "text_view.get(view, -1)", "index"),
            (2, "text_view.get(view, 2)", "index"),
            (0, "text_view.get(view, 0)", "index"),
            (2, "text_view.slice(view, -1, 0)", "range"),
            (2, "text_view.slice(view, 2, 1)", "range"),
            (2, "text_view.slice(view, 0, 9223372036854775807)", "range"),
        ):
            with self.subTest(end=end, operation=operation):
                self.assert_output(f'''let input = text_view.from_string("abc")
let view = text_view.slice(input, 0, {end})
{operation}
''', status=1, stderr=f"volt: TextView {diagnostic} out of bounds\n")

    def test_c_string_copy_is_bounded_and_rejects_embedded_nul(self):
        self.assert_output(r'''let input = text_view.from_string("key=value")
let out: [5]char = ['!', '!', '!', '!', '!']
let raw: [3]char = ['a', '\0', 'b']
unsafe:
    let key = text_view.slice(input, 0, 3)
    print(text_view.copy_cstr(key, &out[0], 3), out[0], out[3])
    print(text_view.copy_cstr(key, &out[0], 4), out[3] as u8, out[4])
    if out[3] == '\0': print(((&out[0]) as string) == "key")

    let with_nul = text_view.from_bytes(&raw[0], len(raw))
    print(text_view.get(with_nul, 1), text_view.copy_cstr(with_nul, &out[0], len(out)), out[0])
''', "-28 ! !\n3 0 !\ntrue\n0 -22 k\n")


if __name__ == "__main__":
    unittest.main()
