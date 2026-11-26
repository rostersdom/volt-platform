#!/usr/bin/env python3
"""Arithmetic checks driven by random programs and an independent Python model.

tests/compiler_ownership_model.py does this for ownership; this suite does it
for integer arithmetic, so it verifies the generated *machine code* (the
checks it emits and the values it computes), not just the fact an ELF is
produced. It generates short random VOLT programs (deterministic per seed)
over the eight integer types i8/u8/i16/u16/i32/u32/i64/u64:

  - `let` declarations with explicit types (the initialiser conversion is
    range-checked at run time);
  - expressions with + - * / % << >>, comparisons, `and`/`or`/`not`,
    unary `-` and narrowing/widening `as` casts;
  - `probe(tag, cond)` calls (a prelude function that prints "call <tag>"),
    placed on the right-hand side of `and`/`or` so that short-circuiting is
    observable in stdout;
  - `if`/`else` statements whose conditions use all of the above.

The expected behaviour (full stdout, exit status and stderr) is computed by
Model below: a standalone interpreter of the generated AST that re-implements
the documented semantics (docs/language.md §1-2, all confirmed by probes
against the built compiler) without using any compiler code:

  * every integer operation is performed in the *common type* of its
    operands: same signedness -> wider type; mixed -> the unsigned type when
    its width is >= the signed width, otherwise the (wider) signed type.
    Operand conversion to the common type is a *wrapping* bit-truncation
    (u8(0) + i8(-1) == 255), it never traps;
  * + - * and unary - panic "volt: integer overflow" when the exact result
    does not fit the common type (unsigned included);
  * / and % panic "volt: division by zero" on a zero divisor; division
    truncates toward zero (C-style: -7/3 == -2, -7%3 == -1); a quotient out
    of range panics "volt: integer overflow" (min / -1 at every width);
  * quirk reproduced by the model: min % -1 panics only for 64-bit ints
    (the compiler's explicit min/-1 check is emitted at width 64 only); at
    widths 8/16/32 the hardware idiv produces remainder 0 and no trap;
  * << >> keep the *left* operand's type and width: the shift count (any
    integer type) must lie in [0, width of the left type) or the program
    panics "volt: invalid shift count"; << drops the bits shifted out
    without trapping ((64 as i8) << 1 == -128); >> is arithmetic for signed
    types and logical for unsigned;
  * comparisons convert both operands to the common type and compare there
    (i8(-1) < u8(0) is false: -1 wraps to 255), result is bool;
  * `and`/`or` yield bool and evaluate the right operand only when needed
    (visible via probe); `not` yields bool; zero is false, nonzero is true;
  * `expr as T` and `let x: T = expr` are *checked* conversions: the value
    must fit T (any width/sign change), otherwise panic
    "volt: integer overflow";
  * `print` evaluates and prints its arguments one at a time, left to
    right (cce_emit_print), so the marker and the separator are already on
    stdout when a later argument panics, and a probe call inside an argument
    prints its "call N" line *between* the marker and the value;
  * a panic writes its message to stderr and exits the process with
    status 1.

Compile-time errors are avoided *by construction*: every literal is emitted
as `(value as T)` with value inside T's range (negative literals are built
as `((0 - |v|) as T)` so that no out-of-range positive literal ever appears),
so the "integer literal out of range" compile error can never trigger and
every generated program must compile; a compile failure fails the test.

The boundary-value coverage comes from the literal generator, which picks
type min/max and width boundaries (2^k-1, 2^(k-1), negatives) with high
probability rather than only uniform random values, and from the shift-count
generator biased toward 0/1/7/8/15/16/31/32/63/64/65/-1.

On any compile error or behaviour mismatch the program source plus the
expected and actual runs are saved next to the temporary directory and the
seed is reported.

Set VOLT_ARITH_MODEL_SEED / VOLT_ARITH_MODEL_COUNT to reproduce or resize
the run.
"""
import os
import random
from dataclasses import dataclass
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
VOLT = Path(os.environ.get("VOLT_COMPILER", ROOT / "volt")).resolve()

SEED_BASE = int(os.environ.get("VOLT_ARITH_MODEL_SEED", "20261126"))
COUNT = int(os.environ.get("VOLT_ARITH_MODEL_COUNT", "300"))
MAX_FAILURES = 5

OVERFLOW = "volt: integer overflow\n"
DIVZERO = "volt: division by zero\n"
SHIFTCNT = "volt: invalid shift count\n"


# ---------------------------------------------------------------------------
# Integer types
# ---------------------------------------------------------------------------

class IntType:
    __slots__ = ("name", "bits", "signed")

    def __init__(self, name, bits, signed):
        self.name = name
        self.bits = bits
        self.signed = signed

    @property
    def lo(self):
        return -(1 << (self.bits - 1)) if self.signed else 0

    @property
    def hi(self):
        return (1 << (self.bits - 1)) - 1 if self.signed else (1 << self.bits) - 1

    def contains(self, v):
        return self.lo <= v <= self.hi

    def wrap(self, v):
        """Reinterpret v modulo 2^bits under this type's signedness."""
        v %= 1 << self.bits
        if self.signed and v >= (1 << (self.bits - 1)):
            v -= 1 << self.bits
        return v

    def __repr__(self):
        return self.name


I8 = IntType("i8", 8, True)
U8 = IntType("u8", 8, False)
I16 = IntType("i16", 16, True)
U16 = IntType("u16", 16, False)
I32 = IntType("i32", 32, True)
U32 = IntType("u32", 32, False)
I64 = IntType("i64", 64, True)
U64 = IntType("u64", 64, False)
INT_TYPES = (I8, U8, I16, U16, I32, U32, I64, U64)


class _Bool:
    name = "bool"

    def __repr__(self):
        return "bool"


BOOL = _Bool()


def common_type(a, b):
    """The symmetric common type: unsigned wins at equal or greater width."""
    if a is b:
        return a
    if a.signed == b.signed:
        return a if a.bits >= b.bits else b
    u, s = (a, b) if not a.signed else (b, a)
    return u if u.bits >= s.bits else s


# ---------------------------------------------------------------------------
# AST of generated programs
# ---------------------------------------------------------------------------

@dataclass
class Lit:
    value: int
    t: object           # an IntType; value always inside t's range

@dataclass
class BoolLit:
    value: bool

@dataclass
class Var:
    name: str

@dataclass
class Cast:
    e: object
    t: object

@dataclass
class Neg:
    e: object

@dataclass
class Not:
    e: object

@dataclass
class Arith:
    op: str             # + - * / %
    l: object
    r: object

@dataclass
class Shift:
    op: str             # << >>
    l: object
    r: object

@dataclass
class Cmp:
    op: str             # == != < <= > >=
    l: object
    r: object

@dataclass
class And:
    l: object
    r: object

@dataclass
class Or:
    l: object
    r: object

@dataclass
class Probe:
    tag: int
    arg: object         # bool expression; call prints "call <tag>"

@dataclass
class Let:
    name: str
    t: object
    expr: object

@dataclass
class Print:
    marker: str
    expr: object

@dataclass
class If:
    cond: object
    then: list
    otherwise: object   # list | None


# ---------------------------------------------------------------------------
# VOLT source emission
# ---------------------------------------------------------------------------

PRELUDE = """fn probe(tag: i64, x: bool) -> bool:
    print("call", tag)
    return x
"""


def render_const(value, t):
    """A literal of type t. Negative values are built via subtraction at the
    default i64 width so no out-of-range positive literal is ever written."""
    if value < 0:
        if value == -(1 << 63):
            inner = "(0 - 9223372036854775807 - 1)"
        else:
            inner = f"(0 - {-value})"
        return f"({inner} as {t.name})"
    return f"({value} as {t.name})"


def emit_expr(e):
    if isinstance(e, Lit):
        return render_const(e.value, e.t)
    if isinstance(e, BoolLit):
        return "true" if e.value else "false"
    if isinstance(e, Var):
        return e.name
    if isinstance(e, Cast):
        return f"({emit_expr(e.e)} as {e.t.name})"
    if isinstance(e, Neg):
        return f"(-{emit_expr(e.e)})"
    if isinstance(e, Not):
        return f"(not {emit_expr(e.e)})"
    if isinstance(e, (Arith, Shift, Cmp)):
        return f"({emit_expr(e.l)} {e.op} {emit_expr(e.r)})"
    if isinstance(e, And):
        return f"({emit_expr(e.l)} and {emit_expr(e.r)})"
    if isinstance(e, Or):
        return f"({emit_expr(e.l)} or {emit_expr(e.r)})"
    if isinstance(e, Probe):
        return f"probe({e.tag}, {emit_expr(e.arg)})"
    raise AssertionError(e)


def emit_stmt(st, level, lines):
    pad = "    " * level
    if isinstance(st, Let):
        lines.append(f"{pad}let {st.name}: {st.t.name} = {emit_expr(st.expr)}")
    elif isinstance(st, Print):
        lines.append(f'{pad}print("{st.marker}", {emit_expr(st.expr)})')
    elif isinstance(st, If):
        lines.append(f"{pad}if {emit_expr(st.cond)}:")
        emit_block(st.then, level + 1, lines)
        if st.otherwise is not None:
            lines.append(f"{pad}else:")
            emit_block(st.otherwise, level + 1, lines)
    else:
        raise AssertionError(st)


def emit_block(stmts, level, lines):
    for st in stmts:
        emit_stmt(st, level, lines)


def emit_program(stmts):
    lines = [PRELUDE]
    emit_block(stmts, 0, lines)
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# Independent arithmetic model: interprets the AST and predicts the exact
# observable behaviour (stdout, exit status, stderr). Shares no code with
# the compiler. See the module docstring for the implemented semantics.
# ---------------------------------------------------------------------------

class Panic(Exception):
    def __init__(self, message):
        super().__init__(message)
        self.message = message


def trunc_divmod(a, b):
    """C-style division: quotient truncated toward zero, remainder takes the
    dividend's sign."""
    q = abs(a) // abs(b)
    if (a < 0) != (b < 0):
        q = -q
    return q, a - q * b


CMP_OPS = {
    "==": lambda a, b: a == b,
    "!=": lambda a, b: a != b,
    "<": lambda a, b: a < b,
    "<=": lambda a, b: a <= b,
    ">": lambda a, b: a > b,
    ">=": lambda a, b: a >= b,
}

# Deliberate model bugs used by test_mutations_are_detected:
#   floor_div      -- / and % use Python floor semantics instead of truncation
#   wrap_overflow  -- + - * and unary - wrap instead of panicking
#   eager_bool     -- and/or always evaluate the right operand
#   logical_shift  -- >> is logical even for signed types
MUTATIONS = ("floor_div", "wrap_overflow", "eager_bool", "logical_shift")


class Model:
    def __init__(self, mutation=None):
        self.mutation = mutation
        self.out = []               # stdout chunks; print interleaves
                                    # evaluation and output
        self.scopes = [{}]

    def emit(self, text):
        self.out.append(text)

    def lookup(self, name):
        for sc in reversed(self.scopes):
            if name in sc:
                return sc[name]
        raise AssertionError(f"unknown name {name}")

    def check(self, t, v):
        if self.mutation == "wrap_overflow":
            return t.wrap(v)
        if not t.contains(v):
            raise Panic(OVERFLOW)
        return v

    def eval(self, e):
        if isinstance(e, Lit):
            return (e.t, e.value)
        if isinstance(e, BoolLit):
            return (BOOL, 1 if e.value else 0)
        if isinstance(e, Var):
            return self.lookup(e.name)
        if isinstance(e, Cast):
            _, v = self.eval(e.e)
            if not e.t.contains(v):
                raise Panic(OVERFLOW)
            return (e.t, v)
        if isinstance(e, Neg):
            t, v = self.eval(e.e)
            return (t, self.check(t, -v))
        if isinstance(e, Not):
            _, v = self.eval(e.e)
            return (BOOL, 1 if v == 0 else 0)
        if isinstance(e, Arith):
            return self.eval_arith(e)
        if isinstance(e, Shift):
            return self.eval_shift(e)
        if isinstance(e, Cmp):
            tl, vl = self.eval(e.l)
            tr, vr = self.eval(e.r)
            tc = common_type(tl, tr)
            return (BOOL, 1 if CMP_OPS[e.op](tc.wrap(vl), tc.wrap(vr)) else 0)
        if isinstance(e, (And, Or)):
            _, vl = self.eval(e.l)
            short = (vl == 0) if isinstance(e, And) else (vl != 0)
            if short and self.mutation != "eager_bool":
                return (BOOL, vl if isinstance(e, Or) else 0)
            _, vr = self.eval(e.r)
            if isinstance(e, And):
                return (BOOL, 1 if vl != 0 and vr != 0 else 0)
            return (BOOL, 1 if vl != 0 or vr != 0 else 0)
        if isinstance(e, Probe):
            # The argument is evaluated before the callee prints.
            _, v = self.eval(e.arg)
            self.emit(f"call {e.tag}\n")
            return (BOOL, 1 if v != 0 else 0)
        raise AssertionError(e)

    def eval_arith(self, e):
        tl, vl = self.eval(e.l)
        tr, vr = self.eval(e.r)
        tc = common_type(tl, tr)
        a = tc.wrap(vl)
        b = tc.wrap(vr)
        if e.op == "+":
            r = a + b
        elif e.op == "-":
            r = a - b
        elif e.op == "*":
            r = a * b
        elif e.op == "/":
            if b == 0:
                raise Panic(DIVZERO)
            if self.mutation == "floor_div":
                r = a // b
            else:
                r = self.check(tc, trunc_divmod(a, b)[0])
        else:
            assert e.op == "%"
            if b == 0:
                raise Panic(DIVZERO)
            if self.mutation == "floor_div":
                r = a % b
            else:
                # The explicit min/-1 trap exists at width 64 only; at narrow
                # widths idiv yields remainder 0 without trapping.
                if tc.signed and tc.bits == 64 and a == tc.lo and b == -1:
                    raise Panic(OVERFLOW)
                r = trunc_divmod(a, b)[1]
        return (tc, self.check(tc, r))

    def eval_shift(self, e):
        tl, vl = self.eval(e.l)
        _, vr = self.eval(e.r)
        if vr < 0 or vr >= tl.bits:
            raise Panic(SHIFTCNT)
        if e.op == "<<":
            return (tl, tl.wrap(vl << vr))
        if tl.signed and self.mutation != "logical_shift":
            return (tl, vl >> vr)
        return (tl, (vl % (1 << tl.bits)) >> vr)

    def exec_stmts(self, stmts):
        for st in stmts:
            self.exec_stmt(st)

    def exec_stmt(self, st):
        if isinstance(st, Let):
            _, v = self.eval(st.expr)
            if not st.t.contains(v):
                raise Panic(OVERFLOW)
            self.scopes[-1][st.name] = (st.t, v)
        elif isinstance(st, Print):
            # print outputs each argument right after evaluating it, so the
            # marker and the separator precede whatever the expression does.
            self.emit(f"{st.marker} ")
            t, v = self.eval(st.expr)
            text = ("true" if v else "false") if t is BOOL else str(v)
            self.emit(text)
            self.emit("\n")
        elif isinstance(st, If):
            _, v = self.eval(st.cond)
            body = st.then if v != 0 else st.otherwise
            if body is None:
                return
            self.scopes.append({})
            try:
                self.exec_stmts(body)
            finally:
                self.scopes.pop()
        else:
            raise AssertionError(st)


def interpret(stmts, mutation=None):
    """(exit_status, stdout, stderr) predicted for the program."""
    model = Model(mutation)
    try:
        model.exec_stmts(stmts)
    except Panic as p:
        return (1, "".join(model.out), p.message)
    return (0, "".join(model.out), "")


# ---------------------------------------------------------------------------
# Generator of random programs. Expressions are built structurally (only the
# static types of variables are needed); the generator interprets every new
# top-level statement with the base model as it goes and stops the program at
# the first predicted panic, so generated code after a panic never goes
# untested and every program exercises as many statements as possible.
# ---------------------------------------------------------------------------

def boundary_values(t):
    vals = {t.lo, t.lo + 1, -1, 0, 1, 2, t.hi - 1, t.hi, t.hi // 2, t.lo // 2}
    for b in (8, 16, 32, 64):
        vals |= {(1 << (b - 1)) - 1, 1 << (b - 1), (1 << b) - 1,
                 -(1 << (b - 1)), -(1 << (b - 1)) - 1}
    return sorted(v for v in vals if t.contains(v))


class Generator:
    MAX_EXPR_DEPTH = 4
    MAX_IF_DEPTH = 2

    def __init__(self, seed):
        self.rng = random.Random(seed)
        self.var_n = 0
        self.probe_n = 0
        self.mark_n = 0
        self.scopes = [{}]          # name -> IntType (static view)
        self.model = Model()        # dynamic view, fed as statements appear

    # -- names, scopes, variables -------------------------------------------

    def fresh_var(self):
        name = f"v{self.var_n}"
        self.var_n += 1
        return name

    def int_vars(self):
        return [(name, t) for sc in self.scopes for name, t in sc.items()]

    # -- literals -------------------------------------------------------------

    def gen_lit(self, t=None):
        t = t or self.rng.choice(INT_TYPES)
        roll = self.rng.random()
        if roll < 0.55:
            v = self.rng.choice(boundary_values(t))
        elif roll < 0.8:
            v = self.rng.randint(max(t.lo, -100), min(t.hi, 100))
        else:
            v = self.rng.randint(t.lo, t.hi)
        return Lit(v, t)

    # -- integer expressions ----------------------------------------------------

    def gen_int_expr(self, depth):
        choices = ["lit", "lit", "lit"]
        if self.int_vars():
            choices += ["var", "var", "var"]
        if depth < self.MAX_EXPR_DEPTH:
            choices += ["arith", "arith", "shift", "shift", "cast", "neg"]
        pick = self.rng.choice(choices)
        if pick == "lit":
            return self.gen_lit()
        if pick == "var":
            return Var(self.rng.choice(self.int_vars())[0])
        if pick == "arith":
            return self.gen_arith(depth)
        if pick == "shift":
            return self.gen_shift(depth)
        if pick == "cast":
            return Cast(self.gen_int_expr(depth + 1), self.rng.choice(INT_TYPES))
        return Neg(self.gen_int_expr(depth + 1))

    def gen_neg_lit(self):
        """A negative literal of a signed type: feeds truncated division and
        arithmetic right shifts, where the C-style semantics differ from the
        naive unsigned/floor ones."""
        t = self.rng.choice([I8, I16, I32, I64])
        v = self.rng.choice([t.lo, t.lo + 1, t.lo // 2, -1, -2,
                             self.rng.randint(t.lo, -1)])
        return Lit(v, t)

    def gen_arith(self, depth):
        op = self.rng.choice(["+", "+", "-", "-", "*", "*", "/", "/", "%", "%"])
        if op in ("/", "%") and self.rng.random() < 0.35:
            left = self.gen_neg_lit()
        else:
            left = self.gen_int_expr(depth + 1)
        return Arith(op, left, self.gen_int_expr(depth + 1))

    def gen_shift(self, depth):
        op = self.rng.choice(["<<", ">>"])
        if op == ">>" and self.rng.random() < 0.5:
            left = self.gen_neg_lit()
        else:
            left = self.gen_int_expr(depth + 1)
        return Shift(op, left, self.gen_shift_count(depth))

    def gen_shift_count(self, depth):
        if self.rng.random() < 0.7:
            t = self.rng.choice(INT_TYPES)
            cands = [0, 1, 2, 7, 8, 15, 16, 31, 32, 63, 64, 65]
            if t.signed:
                cands.append(-1)
            return Lit(self.rng.choice([c for c in cands if t.contains(c)]), t)
        return self.gen_int_expr(depth + 1)

    # -- boolean expressions ------------------------------------------------------

    def gen_bool_expr(self, depth):
        choices = ["cmp", "cmp", "cmp", "boollit"]
        if depth < self.MAX_EXPR_DEPTH:
            choices += ["and", "or", "not", "probe"]
        pick = self.rng.choice(choices)
        if pick == "cmp":
            op = self.rng.choice(["==", "!=", "<", "<=", ">", ">="])
            return Cmp(op, self.gen_int_expr(depth + 1),
                       self.gen_int_expr(depth + 1))
        if pick == "boollit":
            return BoolLit(self.rng.random() < 0.5)
        if pick == "not":
            return Not(self.gen_bool_expr(depth + 1))
        if pick == "probe":
            return self.gen_probe(depth)
        node = And if pick == "and" else Or
        left = self.gen_bool_expr(depth + 1)
        # Put a probe on the right with high probability: that is what makes
        # short-circuiting (or its absence) visible on stdout.
        if self.rng.random() < 0.7:
            right = self.gen_probe(depth + 1)
        else:
            right = self.gen_bool_expr(depth + 1)
        return node(left, right)

    def gen_probe(self, depth):
        tag = self.probe_n
        self.probe_n += 1
        return Probe(tag, self.gen_bool_expr(depth + 1))

    # -- statements ------------------------------------------------------------

    def gen_let(self, if_depth):
        t = self.rng.choice(INT_TYPES)
        name = self.fresh_var()
        # The initializer is generated before the name becomes visible, so it
        # can never reference the variable it declares.
        expr = self.gen_int_expr(0)
        self.scopes[-1][name] = t
        return Let(name, t, expr)

    def gen_print(self, if_depth):
        marker = f"m{self.mark_n}"
        self.mark_n += 1
        if self.rng.random() < 0.3:
            expr = self.gen_bool_expr(0)
        else:
            expr = self.gen_int_expr(0)
        return Print(marker, expr)

    def gen_if(self, if_depth):
        cond = self.gen_bool_expr(0)
        self.scopes.append({})
        then = self.gen_stmts(self.rng.randint(1, 3), if_depth + 1)
        self.scopes.pop()
        otherwise = None
        if self.rng.random() < 0.5:
            self.scopes.append({})
            otherwise = self.gen_stmts(self.rng.randint(1, 3), if_depth + 1)
            self.scopes.pop()
        return If(cond, then, otherwise)

    def gen_stmt(self, if_depth):
        handlers = [(35, self.gen_let), (45, self.gen_print)]
        if if_depth < self.MAX_IF_DEPTH:
            handlers.append((20, self.gen_if))
        total = sum(w for w, _ in handlers)
        r = self.rng.uniform(0, total)
        for w, h in handlers:
            r -= w
            if r <= 0:
                return h(if_depth)
        return self.gen_print(if_depth)

    def gen_stmts(self, n, if_depth):
        return [self.gen_stmt(if_depth) for _ in range(n)]

    # -- whole program ---------------------------------------------------------

    # A generated statement that already panics in the model is kept (and ends
    # the program) only with this probability; otherwise it is discarded and
    # regenerated, so most programs execute their full statement list and a
    # panic is a deliberate, well-covered endpoint rather than a truncation.
    KEEP_PANIC = 0.3

    def generate(self):
        stmts = []
        for _ in range(self.rng.randint(6, 12)):
            while True:
                gen_snap = [set(sc) for sc in self.scopes]
                model_snap = [set(sc) for sc in self.model.scopes]
                out_len = len(self.model.out)
                st = self.gen_stmt(0)
                try:
                    self.model.exec_stmt(st)
                except Panic:
                    if self.rng.random() < self.KEEP_PANIC:
                        # The program ends in this panic; anything generated
                        # after it would be dead code, so stop here.
                        stmts.append(st)
                        return stmts
                    # Roll the generator and the model back and try another
                    # statement. Name/marker counters are not rewound (gaps
                    # are harmless); variable declarations and emitted chunks
                    # are.
                    for sc, keep in zip(self.scopes, gen_snap):
                        for name in list(sc):
                            if name not in keep:
                                del sc[name]
                    for sc, keep in zip(self.model.scopes, model_snap):
                        for name in list(sc):
                            if name not in keep:
                                del sc[name]
                    del self.model.out[out_len:]
                    continue
                stmts.append(st)
                break
        return stmts


def generate(seed):
    return Generator(seed).generate()


# ---------------------------------------------------------------------------
# The suite
# ---------------------------------------------------------------------------

def diff_lines(expected, actual):
    """None when equal, else a short description of the first difference."""
    want_lines = expected.splitlines()
    got_lines = actual.splitlines()
    common = 0
    for want, got in zip(want_lines, got_lines):
        if want != got:
            break
        common += 1
    want = want_lines[common] if common < len(want_lines) else "<конец вывода>"
    got = got_lines[common] if common < len(got_lines) else "<конец вывода>"
    return (f"строка {common + 1}: модель ожидает {want!r}, "
            f"программа напечатала {got!r} "
            f"(всего строк: модель {len(want_lines)}, программа {len(got_lines)})")


def diff_run(expected, actual):
    """None when (status, stdout, stderr) match exactly, else a description."""
    if expected == actual:
        return None
    rc_e, out_e, err_e = expected
    rc_a, out_a, err_a = actual
    parts = []
    if rc_e != rc_a:
        parts.append(f"код выхода: модель {rc_e}, программа {rc_a}")
    if out_e != out_a:
        parts.append("stdout: " + diff_lines(out_e, out_a))
    if err_e != err_a:
        parts.append(f"stderr: модель {err_e!r}, программа {err_a!r}")
    return "; ".join(parts)


class ArithModel(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        directory = tempfile.TemporaryDirectory(prefix="volt-arith-model-")
        cls.addClassCleanup(directory.cleanup)
        cls.tmp = Path(directory.name)
        cls.volt = cls.tmp / "volt"
        shutil.copy2(VOLT, cls.volt)
        shutil.copytree(ROOT / "vstd", cls.tmp / "vstd")
        # Failure artifacts live next to the temporary directory and survive
        # the run for debugging.
        cls.artifacts = cls.tmp.parent / (cls.tmp.name + "-artifacts")
        cls.artifacts.mkdir(exist_ok=True)

    def build_and_run(self, source):
        """((status, stdout, stderr), None) on success; (None, diagnostics)
        when compilation fails."""
        path = self.tmp / "main.volt"
        path.write_text(source, encoding="utf-8")
        built = subprocess.run([self.volt, path, "-o", self.tmp / "program"],
                               capture_output=True, text=True, timeout=15)
        if built.returncode != 0:
            return None, (f"компиляция завершилась с {built.returncode}:\n"
                          f"{built.stdout}{built.stderr}")
        ran = subprocess.run([self.tmp / "program"], cwd=self.tmp,
                             capture_output=True, text=True, timeout=5)
        return (ran.returncode, ran.stdout, ran.stderr), None

    def save_failure(self, seed, source, expected, actual, error):
        base = self.artifacts / f"seed{seed}"
        Path(str(base) + ".volt").write_text(source, encoding="utf-8")
        Path(str(base) + ".expected.txt").write_text(
            f"код выхода: {expected[0]}\n=== stdout ===\n{expected[1]}"
            f"=== stderr ===\n{expected[2]}", encoding="utf-8")
        Path(str(base) + ".actual.txt").write_text(
            (error or "") + (actual or ""), encoding="utf-8")
        return base

    def check_seed(self, seed):
        """None when the program matches the model, else a failure message."""
        stmts = generate(seed)
        source = emit_program(stmts)
        expected = interpret(stmts)
        actual, error = self.build_and_run(source)
        if error is not None:
            base = self.save_failure(seed, source, expected, None, error)
            return (f"seed {seed}: сгенерированная программа не собралась; "
                    f"кейс сохранён: {base}.volt\n{error}")
        diff = diff_run(expected, actual)
        if diff is None:
            return None
        base = self.save_failure(
            seed, source, expected,
            f"код выхода: {actual[0]}\n=== stdout ===\n{actual[1]}"
            f"=== stderr ===\n{actual[2]}", None)
        return f"seed {seed}: {diff}; кейс сохранён: {base}.volt"

    def test_random_programs_match_model(self):
        failures = 0
        for k in range(COUNT):
            seed = SEED_BASE + k
            message = self.check_seed(seed)
            if message is not None:
                with self.subTest(seed=seed):
                    self.fail(message)
                failures += 1
                if failures >= MAX_FAILURES:
                    break

    def test_mutations_are_detected(self):
        """The exact-behaviour comparison must catch a model with the wrong
        division rounding, with wrapping instead of overflow panics, with
        eager and/or operands and with a logical right shift for signed
        types — the arithmetic bugs this suite exists to find."""
        exercised = {m: 0 for m in MUTATIONS}
        checked = 0
        for k in range(120):
            seed = SEED_BASE + 10_000_000 + k
            stmts = generate(seed)
            source = emit_program(stmts)
            expected = interpret(stmts)
            actual, error = self.build_and_run(source)
            self.assertIsNone(error, f"seed {seed}: {error}")
            with self.subTest(seed=seed, mutation="база совпадает"):
                self.assertIsNone(diff_run(expected, actual),
                                  f"seed {seed}: базовое предсказание не совпало")
            for m in MUTATIONS:
                mutated = interpret(stmts, mutation=m)
                if mutated == expected:
                    continue
                with self.subTest(seed=seed, mutation=m):
                    self.assertIsNotNone(
                        diff_run(mutated, actual),
                        f"seed {seed}: мутация {m} изменила предсказание "
                        f"модели, но сравнение её не поймало")
                exercised[m] += 1
            checked += 1
            if checked >= 12 and all(n >= 3 for n in exercised.values()):
                break
        for m, n in exercised.items():
            self.assertGreaterEqual(
                n, 3, f"мутация {m} почти не встречается в сгенерированных "
                f"программах (сработала {n} раз за {checked} программ)")


if __name__ == "__main__":
    unittest.main()
