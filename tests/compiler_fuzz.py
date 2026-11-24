#!/usr/bin/env python3
"""Bounded, local smoke corpus; VOLT_COMPILER can select another binary."""
import os
from pathlib import Path
import random
import re
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
VOLT = Path(os.environ.get("VOLT_COMPILER", ROOT / "volt")).resolve()
SEED = 0x564F4C54
ROUNDS = 8
TIMEOUT = 5
PRINT_EDITS = (
    # The parser accepts unresolved names, but a full compilation must not.
    ("extra-comma", "print(,", (False, False)),
    ("unknown-name", "print(not_declared, ", (True, False)),
    ("unclosed-string", 'print("', (False, False)),
    ("extra-argument", "print(17, ", (True, True)),
)


def expression(rng, atoms=(), depth=2):
    if depth == 0 or rng.randrange(3) == 0:
        return rng.choice((*atoms, str(rng.randrange(1, 20))))
    left = expression(rng, atoms, depth - 1)
    right = expression(rng, atoms, depth - 1)
    return f"({left} {rng.choice(('+', '-', '*'))} {right})"


def corpus():
    rng = random.Random(SEED)
    for round_id in range(ROUNDS):
        programs = (
            ("flow", f"""fn score(x: i64) -> i64:
    let total = {expression(rng, ('x',))}
    for i in 0..{rng.randint(1, 5)}:
        if i < x: total += i
        else: total -= i
    return total
print(score({rng.randint(1, 5)}))
"""),
            ("slice", f"""fn identity<T>(value: T) -> T:
    return value
let values: [3]i64 = [{', '.join(expression(rng) for _ in range(3))}]
let view: []i64 = values[0..{rng.randint(1, 3)}]
print(identity(view[0]), len(view))
"""),
            ("record", f"""struct Pair:
    left: i64
    right: i64
# String escapes and indented branches share this fixture.
let name = "pair\\t{round_id}"
let point = Pair({expression(rng)}, {expression(rng)})
if point.left < point.right:
    print(name, point.left)
else:
    print(point.right)
"""),
        )
        for family, program in programs:
            name = f"{round_id:02d}-{family}"
            yield f"{name}-valid", program, (True, True)
            edit, replacement, accepted = rng.choice(PRINT_EDITS)
            yield f"{name}-{edit}", program.replace("print(", replacement, 1), accepted


class CompilerFuzz(unittest.TestCase):
    def check_corpus(self, parse_only):
        with tempfile.TemporaryDirectory(prefix="volt-fuzz-") as directory:
            tmp = Path(directory)
            env = {"PATH": "", "TMPDIR": directory}
            for name, program, (parse_ok, build_ok) in corpus():
                source = tmp / f"{name}.volt"
                output = tmp / name
                source.write_text(program, encoding="utf-8")
                args = ["--parse"] if parse_only else ["--quiet", "-o", output]
                # A timeout aborts this mode instead of waiting on the rest of the corpus.
                try:
                    result = subprocess.run([VOLT, source, *args], cwd=tmp, env=env, capture_output=True,
                                            encoding="utf-8", errors="replace", timeout=TIMEOUT)
                except subprocess.TimeoutExpired:
                    self.fail(f"{name} (seed {SEED:#x}): compiler exceeded {TIMEOUT} s")
                with self.subTest(seed=hex(SEED), case=name):
                    if not (parse_ok if parse_only else build_ok):
                        self.assertEqual(result.returncode, 1, result.stderr)
                        self.assertRegex(result.stderr, rf"(?m)^{re.escape(str(source))}:\d+: ошибка: \S")
                        self.assertFalse(output.exists(), "rejected input left an executable")
                    else:
                        self.assertEqual((result.returncode, result.stderr), (0, ""))
                        if parse_only:
                            self.assertTrue(result.stdout.startswith("Program(") and result.stdout.endswith(")\n"),
                                            result.stdout)
                        else:
                            self.assertTrue(os.access(output, os.X_OK), "no executable output")
                            with output.open("rb") as executable:
                                self.assertEqual(executable.read(4), b"\x7fELF")

    def test_parser(self):
        self.check_corpus(parse_only=True)

    def test_compiler(self):
        self.check_corpus(parse_only=False)


if __name__ == "__main__":
    unittest.main()
