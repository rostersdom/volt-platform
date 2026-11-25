#!/usr/bin/env python3
"""Ownership checks driven by random programs and an independent Python model.

tests/compiler_ownership.py hand-writes a few programs and the exact
drop/defer trace they must print. This suite instead *generates* short random
VOLT programs (deterministic per seed) from a small ownership grammar:

  - owner declarations via owned_buffer_new, moves through let / pass /
    consume / return Ok(...)
  - Result<OwnedBuffer, i64> values via make_ok / make_err / might_fail /
    scenK calls, moved through let / idr
  - match over an owned Result with Ok / Err / _ arms (the wildcard arm
    discards a live payload at the end of the arm, after its defer actions)
  - `?` propagation inside scenK functions, including aborted argument
    evaluation (consume2(might_fail(...)?, make_err(...)?))
  - defer markers and defer reads that borrow an owner
  - nested blocks: if/else, match arms, for loops with break/continue

The generator only emits programs it can prove well-formed (no use after a
move, no move while borrowed, no move of an outer owner on a path to the next
loop iteration), so every program must compile.

The expected stdout (drop/defer trace) is computed by Model below: a
standalone interpreter of the generated AST that re-implements the ownership
rules (per scope: defer LIFO, then drops of live owners in reverse slot
order; consumption by match/?; wildcard discard; per-iteration loop cleanup)
without using any compiler code. The program is compiled with the freshly
built ./volt against an instrumented vstd drop hook and its stdout must equal
the model trace exactly, so both a missing drop and a duplicated drop are
caught (see test_mutations_are_detected).

On any compile error or trace mismatch the program source plus both traces
are saved next to the temporary directory and the seed is reported.

Set VOLT_OWNERSHIP_MODEL_SEED / VOLT_OWNERSHIP_MODEL_COUNT to reproduce or
resize the run.
"""
import os
import random
import string
from dataclasses import dataclass, replace
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
VOLT = Path(os.environ.get("VOLT_COMPILER", ROOT / "volt")).resolve()

SEED_BASE = int(os.environ.get("VOLT_OWNERSHIP_MODEL_SEED", "20261126"))
COUNT = int(os.environ.get("VOLT_OWNERSHIP_MODEL_COUNT", "300"))
MAX_FAILURES = 5


# ---------------------------------------------------------------------------
# AST of generated programs
# ---------------------------------------------------------------------------

@dataclass
class CondLit:
    value: bool

@dataclass
class CondParam:
    pass

@dataclass
class CondCmp:
    var: str
    op: str
    value: int

@dataclass
class NewBuf:
    tag: str

@dataclass
class MakeOk:
    tag: str

@dataclass
class MakeErr:
    code: int

@dataclass
class MightFail:
    cond: object
    tag: str

@dataclass
class ScenCall:
    fn: str
    cond: object

@dataclass
class VarRef:
    name: str

@dataclass
class PassCall:
    src: object

@dataclass
class IdrCall:
    src: object

@dataclass
class LetBuf:
    name: str
    tag: str

@dataclass
class LetRes:
    name: str
    expr: object

@dataclass
class LetMove:
    dst: str
    src: str

@dataclass
class LetPass:
    dst: str
    src: str

@dataclass
class LetIdr:
    dst: str
    src: str

@dataclass
class Question:
    dst: str
    expr: object

@dataclass
class Consume:
    src: str

@dataclass
class ConsumeAbort:
    tag: str
    code: int

@dataclass
class DeferMark:
    text: str

@dataclass
class DeferRead:
    text: str
    name: str

@dataclass
class PrintMark:
    text: str
    name: object = None

@dataclass
class If:
    cond: object
    then: list
    else_: object

@dataclass
class For:
    var: str
    count: int
    body: list

@dataclass
class Break:
    pass

@dataclass
class Continue:
    pass

@dataclass
class Arm:
    pattern: str   # "ok" | "err" | "wild"
    name: object
    body: list

@dataclass
class MatchRes:
    scrut: object
    arms: list

@dataclass
class ReturnOk:
    tag: str

@dataclass
class ReturnOkVar:
    name: str

@dataclass
class ReturnErr:
    code: int

@dataclass
class ExprStmt:
    expr: object

@dataclass
class FnDef:
    name: str
    body: list

@dataclass
class Program:
    fns: list
    main: list


def stmt_diverges(st):
    # ConsumeAbort always propagates Err at run time, but statically `?` only
    # maybe-propagates, so it does not terminate a block for the compiler.
    if isinstance(st, (Break, Continue, ReturnOk, ReturnOkVar, ReturnErr)):
        return True
    if isinstance(st, If) and st.else_ is not None:
        return block_diverges(st.then) and block_diverges(st.else_)
    if isinstance(st, MatchRes) and st.arms:
        return all(block_diverges(arm.body) for arm in st.arms)
    return False


def block_diverges(stmts):
    return bool(stmts) and stmt_diverges(stmts[-1])


# ---------------------------------------------------------------------------
# VOLT source emission
# ---------------------------------------------------------------------------

PRELUDE = '''use owned_buffer

fn pass(input: OwnedBuffer) -> OwnedBuffer:
    return input

fn consume(input: OwnedBuffer):
    return

fn consume2(first: OwnedBuffer, second: OwnedBuffer):
    return

fn make_ok(tag: string) -> Result<OwnedBuffer, i64>:
    return Ok(owned_buffer_new(tag))

fn make_err(code: i64) -> Result<OwnedBuffer, i64>:
    return Err(code)

fn might_fail(fail: bool, tag: string) -> Result<OwnedBuffer, i64>:
    if fail: return Err(7)
    return Ok(owned_buffer_new(tag))

fn idr(input: Result<OwnedBuffer, i64>) -> Result<OwnedBuffer, i64>:
    return input
'''


def emit_cond(cond):
    if isinstance(cond, CondLit):
        return "true" if cond.value else "false"
    if isinstance(cond, CondParam):
        return "fail"
    if isinstance(cond, CondCmp):
        return f"{cond.var} {cond.op} {cond.value}"
    raise AssertionError(cond)


def emit_expr(expr):
    if isinstance(expr, NewBuf):
        return f'owned_buffer_new("{expr.tag}")'
    if isinstance(expr, MakeOk):
        return f'make_ok("{expr.tag}")'
    if isinstance(expr, MakeErr):
        return f"make_err({expr.code})"
    if isinstance(expr, MightFail):
        return f'might_fail({emit_cond(expr.cond)}, "{expr.tag}")'
    if isinstance(expr, ScenCall):
        return f"{expr.fn}({emit_cond(expr.cond)})"
    if isinstance(expr, VarRef):
        return expr.name
    if isinstance(expr, PassCall):
        return f"pass({emit_expr(expr.src)})"
    if isinstance(expr, IdrCall):
        return f"idr({emit_expr(expr.src)})"
    raise AssertionError(expr)


def emit_stmt(st, level, lines):
    pad = "    " * level
    if isinstance(st, LetBuf):
        lines.append(f'{pad}let {st.name} = owned_buffer_new("{st.tag}")')
    elif isinstance(st, LetRes):
        lines.append(f"{pad}let {st.name} = {emit_expr(st.expr)}")
    elif isinstance(st, LetMove):
        lines.append(f"{pad}let {st.dst} = {st.src}")
    elif isinstance(st, LetPass):
        lines.append(f"{pad}let {st.dst} = pass({st.src})")
    elif isinstance(st, LetIdr):
        lines.append(f"{pad}let {st.dst} = idr({st.src})")
    elif isinstance(st, Question):
        lines.append(f"{pad}let {st.dst} = {emit_expr(st.expr)}?")
    elif isinstance(st, Consume):
        lines.append(f"{pad}consume({st.src})")
    elif isinstance(st, ConsumeAbort):
        lines.append(f'{pad}consume2(might_fail(false, "{st.tag}")?, make_err({st.code})?)')
    elif isinstance(st, DeferMark):
        lines.append(f'{pad}defer print("{st.text}")')
    elif isinstance(st, DeferRead):
        lines.append(f'{pad}defer print("{st.text}", owned_buffer_get(&{st.name}, 0) as char)')
    elif isinstance(st, PrintMark):
        if st.name is None:
            lines.append(f'{pad}print("{st.text}")')
        else:
            lines.append(f'{pad}print("{st.text}", {st.name})')
    elif isinstance(st, If):
        lines.append(f"{pad}if {emit_cond(st.cond)}:")
        emit_block(st.then, level + 1, lines)
        if st.else_ is not None:
            lines.append(f"{pad}else:")
            emit_block(st.else_, level + 1, lines)
    elif isinstance(st, For):
        lines.append(f"{pad}for {st.var} in 0..{st.count}:")
        emit_block(st.body, level + 1, lines)
    elif isinstance(st, Break):
        lines.append(f"{pad}break")
    elif isinstance(st, Continue):
        lines.append(f"{pad}continue")
    elif isinstance(st, MatchRes):
        lines.append(f"{pad}match {emit_expr(st.scrut)}:")
        for arm in st.arms:
            if arm.pattern == "ok":
                head = f"Ok({arm.name})"
            elif arm.pattern == "err":
                head = f"Err({arm.name})"
            else:
                head = "_"
            lines.append(f"{pad}    {head}:")
            emit_block(arm.body, level + 2, lines)
    elif isinstance(st, ReturnOk):
        lines.append(f'{pad}return Ok(owned_buffer_new("{st.tag}"))')
    elif isinstance(st, ReturnOkVar):
        lines.append(f"{pad}return Ok({st.name})")
    elif isinstance(st, ReturnErr):
        lines.append(f"{pad}return Err({st.code})")
    elif isinstance(st, ExprStmt):
        lines.append(f"{pad}{emit_expr(st.expr)}")
    else:
        raise AssertionError(st)


def emit_block(stmts, level, lines):
    for st in stmts:
        emit_stmt(st, level, lines)


def emit_program(program):
    parts = [PRELUDE]
    for fn in program.fns:
        lines = [f"fn {fn.name}(fail: bool) -> Result<OwnedBuffer, i64>:"]
        emit_block(fn.body, 1, lines)
        parts.append("\n".join(lines))
    lines = []
    emit_block(program.main, 0, lines)
    parts.append("\n".join(lines))
    return "\n\n".join(parts) + "\n"


# ---------------------------------------------------------------------------
# Independent ownership model: interprets the AST and produces the exact
# expected stdout (drop/defer trace). Shares no code with the compiler.
#
# Rules implemented (cross-checked against docs/owned-buffer.md and probes):
#   * scope exit runs the scope's defer actions LIFO, then drops the still
#     live owner slots in reverse order of slot initialisation;
#   * a live Result drops only an active Ok payload; Err drops silently;
#   * match consumes its scrutinee; Ok(name) binds a fresh owner slot in the
#     arm scope; a "_" arm that matched a live Ok drops the payload at the end
#     of the arm as the arm scope's oldest slot (after the arm's own slots);
#   * `?` on Err saves the error as the return value, then unwinds every
#     enclosing scope; owner arguments already evaluated for an aborted call
#     become temporary slots of the current scope;
#   * a value returned by `return` is saved before any cleanup runs;
#   * a discarded expression-statement result drops at the end of the
#     statement;
#   * each loop iteration is a fresh scope; break/continue unwind only the
#     iteration scope.
# ---------------------------------------------------------------------------

class _Moved:
    def __repr__(self):
        return "MOVED"

MOVED = _Moved()


@dataclass
class Buf:
    tag: str

@dataclass
class Res:
    ok: bool
    tag: str = ""
    err: int = 0


class Cell:
    __slots__ = ("value",)

    def __init__(self, value):
        self.value = value


class Scope:
    __slots__ = ("vars", "slots", "defers")

    def __init__(self):
        self.vars = {}     # name -> Cell
        self.slots = []    # owner/result slot names, in initialisation order
        self.defers = []   # (text, owner_name_or_None)


class BreakSig(Exception):
    pass

class ContinueSig(Exception):
    pass

class ReturnSig(Exception):
    def __init__(self, value):
        self.value = value


class Model:
    def __init__(self, program):
        self.program = program
        self.fns = {fn.name: fn for fn in program.fns}
        self.out = []
        self.scopes = []
        self.temp_seq = 0

    # -- scope handling ----------------------------------------------------

    def lookup(self, name):
        for sc in reversed(self.scopes):
            if name in sc.vars:
                return sc.vars[name]
        raise AssertionError(f"unknown name {name}")

    def exit_scope(self, sc):
        for text, owner in reversed(sc.defers):
            if owner is None:
                self.out.append(text)
            else:
                value = self.lookup(owner).value
                assert isinstance(value, Buf), f"defer read of {owner}: {value}"
                self.out.append(f"{text} {value.tag}")
        for name in reversed(sc.slots):
            value = sc.vars[name].value
            if value is MOVED:
                continue
            if isinstance(value, Buf):
                self.out.append(f"drop {value.tag}")
            elif isinstance(value, Res) and value.ok:
                self.out.append(f"drop {value.tag}")
            sc.vars[name].value = MOVED

    def run_scoped(self, stmts, setup=None):
        sc = Scope()
        self.scopes.append(sc)
        if setup is not None:
            setup(sc)
        try:
            self.exec_stmts(stmts)
        finally:
            self.exit_scope(sc)
            self.scopes.pop()

    def declare(self, sc, name, value, slot=True):
        sc.vars[name] = Cell(value)
        if slot:
            sc.slots.append(name)

    # -- expression evaluation (moves commit here) --------------------------

    def eval_cond(self, cond):
        if isinstance(cond, CondLit):
            return cond.value
        if isinstance(cond, CondParam):
            return self.lookup("fail").value
        if isinstance(cond, CondCmp):
            left = self.lookup(cond.var).value
            if cond.op == "==":
                return left == cond.value
            if cond.op == "<":
                return left < cond.value
            return left > cond.value
        raise AssertionError(cond)

    def eval_owned(self, expr):
        if isinstance(expr, NewBuf):
            return Buf(expr.tag)
        if isinstance(expr, MakeOk):
            return Res(True, tag=expr.tag)
        if isinstance(expr, MakeErr):
            return Res(False, err=expr.code)
        if isinstance(expr, MightFail):
            if self.eval_cond(expr.cond):
                return Res(False, err=7)
            return Res(True, tag=expr.tag)
        if isinstance(expr, ScenCall):
            return self.call_fn(expr.fn, self.eval_cond(expr.cond))
        if isinstance(expr, VarRef):
            cell = self.lookup(expr.name)
            value = cell.value
            assert value is not MOVED, f"use after move of {expr.name}"
            cell.value = MOVED
            return value
        if isinstance(expr, (PassCall, IdrCall)):
            return self.eval_owned(expr.src)
        raise AssertionError(expr)

    def call_fn(self, name, fail):
        fn = self.fns[name]
        sc = Scope()
        self.scopes.append(sc)
        sc.vars["fail"] = Cell(fail)
        result = None
        try:
            self.exec_stmts(fn.body)
            raise AssertionError(f"{name} fell through without return")
        except ReturnSig as sig:
            result = sig.value
        finally:
            self.exit_scope(sc)
            self.scopes.pop()
        return result

    # -- statement execution -------------------------------------------------

    def exec_stmts(self, stmts):
        for st in stmts:
            self.exec_stmt(st)

    def exec_stmt(self, st):
        sc = self.scopes[-1]
        if isinstance(st, LetBuf):
            self.declare(sc, st.name, Buf(st.tag))
        elif isinstance(st, LetRes):
            value = self.eval_owned(st.expr)
            assert isinstance(value, Res)
            self.declare(sc, st.name, value)
        elif isinstance(st, (LetMove, LetPass, LetIdr)):
            self.declare(sc, st.dst, self.eval_owned(VarRef(st.src)))
        elif isinstance(st, Question):
            value = self.eval_owned(st.expr)
            assert isinstance(value, Res)
            if value.ok:
                self.declare(sc, st.dst, Buf(value.tag))
            else:
                raise ReturnSig(Res(False, err=value.err))
        elif isinstance(st, Consume):
            value = self.eval_owned(VarRef(st.src))
            assert isinstance(value, Buf)
            # The callee owns it now and drops it when it returns: here.
            self.out.append(f"drop {value.tag}")
        elif isinstance(st, ConsumeAbort):
            # consume2(might_fail(false, tag)?, make_err(code)?): the first
            # argument is already evaluated (an owner temporary of this
            # scope) when the second aborts the call and propagates Err.
            temp = f"$temp{self.temp_seq}"
            self.temp_seq += 1
            self.declare(sc, temp, Buf(st.tag))
            raise ReturnSig(Res(False, err=st.code))
        elif isinstance(st, DeferMark):
            sc.defers.append((st.text, None))
        elif isinstance(st, DeferRead):
            sc.defers.append((st.text, st.name))
        elif isinstance(st, PrintMark):
            if st.name is None:
                self.out.append(st.text)
            else:
                self.out.append(f"{st.text} {self.lookup(st.name).value}")
        elif isinstance(st, If):
            if self.eval_cond(st.cond):
                self.run_scoped(st.then)
            elif st.else_ is not None:
                self.run_scoped(st.else_)
        elif isinstance(st, For):
            i = 0
            while i < st.count:
                signal = None
                def setup(sc, i=i):
                    sc.vars[st.var] = Cell(i)
                inner = Scope()
                self.scopes.append(inner)
                setup(inner)
                try:
                    self.exec_stmts(st.body)
                except ContinueSig:
                    signal = "continue"
                except BreakSig:
                    signal = "break"
                finally:
                    self.exit_scope(inner)
                    self.scopes.pop()
                if signal == "break":
                    break
                i += 1
        elif isinstance(st, Break):
            raise BreakSig()
        elif isinstance(st, Continue):
            raise ContinueSig()
        elif isinstance(st, MatchRes):
            self.exec_match(st)
        elif isinstance(st, ReturnOk):
            raise ReturnSig(Res(True, tag=st.tag))
        elif isinstance(st, ReturnOkVar):
            value = self.eval_owned(VarRef(st.name))
            assert isinstance(value, Buf)
            raise ReturnSig(Res(True, tag=value.tag))
        elif isinstance(st, ReturnErr):
            raise ReturnSig(Res(False, err=st.code))
        elif isinstance(st, ExprStmt):
            value = self.eval_owned(st.expr)
            # A discarded result drops at the end of the statement.
            if isinstance(value, Buf):
                self.out.append(f"drop {value.tag}")
            elif isinstance(value, Res) and value.ok:
                self.out.append(f"drop {value.tag}")
        else:
            raise AssertionError(st)

    def exec_match(self, st):
        value = self.eval_owned(st.scrut)
        assert isinstance(value, Res)
        for arm in st.arms:
            if arm.pattern == "ok" and not value.ok:
                continue
            if arm.pattern == "err" and value.ok:
                continue
            def setup(sc, arm=arm, value=value):
                if arm.pattern == "ok":
                    self.declare(sc, arm.name, Buf(value.tag))
                elif arm.pattern == "err":
                    self.declare(sc, arm.name, value.err, slot=False)
                elif value.ok:
                    # "_" discards a live payload at the end of the arm; it
                    # behaves as the arm scope's oldest slot.
                    self.declare(sc, "$wild", Buf(value.tag))
            self.run_scoped(arm.body, setup)
            return
        raise AssertionError("non-exhaustive match")


def interpret(program):
    model = Model(program)
    model.run_scoped(program.main)
    return model.out


# ---------------------------------------------------------------------------
# Generator of provably well-formed random programs.
#
# Flow facts tracked while generating (so the result always compiles):
#   * live/moved per variable; a variable moved on any fall-through path of
#     an if/else join is treated as moved after it;
#   * borrow_block: a defer that reads an owner forbids moving it until the
#     defer's block ends;
#   * loop discipline: inside a loop only owners declared within the current
#     iteration may move, except on a branch that provably exits via break
#     (single enclosing loop) or return; a variable moved on such a path is
#     treated as moved after the loop.
# ---------------------------------------------------------------------------

@dataclass
class GVar:
    name: str
    kind: str            # "buf" | "res" | "int" | "loop" | "bool"
    loop_depth: int
    count: int = 0       # for loop vars: iteration count
    live: bool = True
    borrow_block: int = -1


class GScope:
    _seq = 0

    def __init__(self):
        GScope._seq += 1
        self.sid = GScope._seq
        self.vars = {}


@dataclass(frozen=True)
class Ctx:
    in_fn: bool
    loops: tuple = ()
    loop_moved: object = None     # set of the innermost loop
    branch_exit: object = None    # None | "break" | "return"
    depth: int = 0

    def child(self):
        return replace(self, depth=self.depth + 1)

    def child_branch(self, term):
        # The exit a branch provably performs decides which outer owners may
        # move inside it: a return path may move anything, a break path only
        # owners of the single enclosing loop's outside, and a continue path
        # reaches the next iteration, so it grants nothing at all (and cancels
        # an inherited exit: the inherited break/return never happens on it).
        if term == "return":
            exit_ = "return"
        elif term == "break":
            exit_ = "break"
        elif term == "continue":
            exit_ = None
        else:
            exit_ = self.branch_exit
        return replace(self, branch_exit=exit_, depth=self.depth + 1)

    def child_loop(self, moved):
        return replace(self, loops=self.loops + (len(self.loops),),
                       loop_moved=moved, branch_exit=None, depth=self.depth + 1)


class Generator:
    MAX_DEPTH = 3
    MAX_LOOP_NEST = 2

    def __init__(self, seed):
        self.rng = random.Random(seed)
        self.tags = iter(string.ascii_lowercase + string.ascii_uppercase)
        self.var_n = 0
        self.loop_n = 0
        self.mark_n = 0
        self.gscopes = []
        self.fns = []

    # -- names, tags, scopes ------------------------------------------------

    def fresh_var(self):
        name = f"v{self.var_n}"
        self.var_n += 1
        return name

    def fresh_mark(self, prefix):
        text = f"{prefix}{self.mark_n}"
        self.mark_n += 1
        return text

    def push_gscope(self):
        self.gscopes.append(GScope())

    def pop_gscope(self):
        sc = self.gscopes.pop()
        for other in self.gscopes:
            for v in other.vars.values():
                if v.borrow_block == sc.sid:
                    v.borrow_block = -1

    def declare(self, v):
        self.gscopes[-1].vars[v.name] = v

    def find_var(self, name):
        for sc in reversed(self.gscopes):
            if name in sc.vars:
                return sc.vars[name]
        return None

    # -- flow facts ----------------------------------------------------------

    def snapshot(self):
        return {v.name: (v.live, v.borrow_block)
                for sc in self.gscopes for v in sc.vars.values()}

    def restore(self, snap):
        for sc in self.gscopes:
            for v in sc.vars.values():
                if v.name in snap:
                    v.live, v.borrow_block = snap[v.name]

    def movable(self, ctx, kind=None):
        out = []
        for sc in self.gscopes:
            for v in sc.vars.values():
                if not v.live or v.borrow_block != -1:
                    continue
                if v.kind not in ("buf", "res"):
                    continue
                if kind and v.kind != kind:
                    continue
                if ctx.loops and v.loop_depth != len(ctx.loops):
                    if ctx.branch_exit == "return":
                        pass
                    elif (ctx.branch_exit == "break" and len(ctx.loops) == 1
                          and v.loop_depth == 0):
                        pass
                    else:
                        continue
                out.append(v)
        return out

    def mark_moved(self, v, ctx):
        v.live = False
        if ctx.loops and v.loop_depth < len(ctx.loops):
            ctx.loop_moved.add(v.name)

    # -- conditions ------------------------------------------------------------

    def gen_cond(self, ctx):
        loopvars = [(v.name, v.count)
                    for sc in self.gscopes for v in sc.vars.values()
                    if v.kind == "loop"]
        choices = ["lit"]
        if ctx.in_fn:
            choices += ["param", "param"]
        if loopvars:
            choices += ["cmp"] * 4
        pick = self.rng.choice(choices)
        if pick == "param":
            return CondParam()
        if pick == "cmp":
            name, count = self.rng.choice(loopvars)
            return CondCmp(name, self.rng.choice(["==", "<", ">"]),
                           self.rng.randint(0, count))
        return CondLit(self.rng.random() < 0.5)

    # -- result-producing expressions -------------------------------------------

    def gen_res_expr(self, ctx, allow_scen=True):
        choices = ["make_err"]
        if self.tags_has_next():
            choices += ["make_ok", "make_ok", "might_fail"]
        if allow_scen and not ctx.in_fn and self.fns:
            choices += ["scen", "scen"]
        pick = self.rng.choice(choices)
        if pick == "make_err":
            return MakeErr(self.rng.randint(1, 9))
        if pick == "make_ok":
            return MakeOk(self.next_tag())
        if pick == "might_fail":
            return MightFail(self.gen_cond(ctx), self.next_tag())
        fn = self.rng.choice(self.fns)
        return ScenCall(fn.name, self.gen_cond(ctx))

    _tags_probe = None

    def tags_has_next(self):
        if self._tags_probe is not None:
            return True
        tag = next(self.tags, None)
        if tag is None:
            return False
        self._tags_probe = tag
        return True

    def next_tag(self):
        if self._tags_probe is not None:
            tag = self._tags_probe
            self._tags_probe = None
            return tag
        return next(self.tags, None)

    # -- statements -----------------------------------------------------------

    def gen_letbuf(self, ctx):
        if not self.tags_has_next():
            return None
        name = self.fresh_var()
        self.declare(GVar(name, "buf", len(ctx.loops)))
        return LetBuf(name, self.next_tag())

    def gen_letres(self, ctx):
        expr = self.gen_res_expr(ctx)
        name = self.fresh_var()
        self.declare(GVar(name, "res", len(ctx.loops)))
        return LetRes(name, expr)

    def gen_letmove(self, ctx):
        cands = self.movable(ctx)
        if not cands:
            return None
        v = self.rng.choice(cands)
        self.mark_moved(v, ctx)
        name = self.fresh_var()
        self.declare(GVar(name, v.kind, len(ctx.loops)))
        return LetMove(name, v.name)

    def gen_letpass(self, ctx):
        cands = self.movable(ctx, "buf")
        if not cands:
            return None
        v = self.rng.choice(cands)
        self.mark_moved(v, ctx)
        name = self.fresh_var()
        self.declare(GVar(name, "buf", len(ctx.loops)))
        return LetPass(name, v.name)

    def gen_letidr(self, ctx):
        cands = self.movable(ctx, "res")
        if not cands:
            return None
        v = self.rng.choice(cands)
        self.mark_moved(v, ctx)
        name = self.fresh_var()
        self.declare(GVar(name, "res", len(ctx.loops)))
        return LetIdr(name, v.name)

    def gen_consume(self, ctx):
        cands = self.movable(ctx, "buf")
        if not cands:
            return None
        v = self.rng.choice(cands)
        self.mark_moved(v, ctx)
        return Consume(v.name)

    def gen_question(self, ctx):
        cands = self.movable(ctx, "res")
        if cands and self.rng.random() < 0.5:
            v = self.rng.choice(cands)
            src = VarRef(v.name)
            self.mark_moved(v, ctx)
        else:
            src = self.gen_res_expr(ctx, allow_scen=False)
            if src is None:
                return None
        name = self.fresh_var()
        self.declare(GVar(name, "buf", len(ctx.loops)))
        return Question(name, src)

    def gen_consume_abort(self, ctx):
        if not self.tags_has_next():
            return None
        return ConsumeAbort(self.next_tag(), self.rng.randint(1, 9))

    def gen_defermark(self, ctx):
        return DeferMark(self.fresh_mark("d"))

    def gen_deferread(self, ctx):
        cands = [v for sc in self.gscopes for v in sc.vars.values()
                 if v.kind == "buf" and v.live and v.borrow_block == -1]
        if not cands:
            return None
        v = self.rng.choice(cands)
        v.borrow_block = self.gscopes[-1].sid
        return DeferRead(self.fresh_mark("r"), v.name)

    def gen_printmark(self, ctx):
        ints = [v.name for sc in self.gscopes for v in sc.vars.values()
                if v.kind in ("int", "loop")]
        if ints and self.rng.random() < 0.5:
            return PrintMark(self.fresh_mark("m"), self.rng.choice(ints))
        return PrintMark(self.fresh_mark("m"), None)

    def gen_exprstmt(self, ctx):
        choices = []
        if self.tags_has_next():
            choices += ["make_ok", "might_fail"]
        if not ctx.in_fn and self.fns:
            choices += ["scen", "scen"]
        if self.movable(ctx, "buf"):
            choices += ["pass"]
        if self.movable(ctx, "res"):
            choices += ["idr"]
        if not choices:
            return None
        pick = self.rng.choice(choices)
        if pick == "pass":
            v = self.rng.choice(self.movable(ctx, "buf"))
            self.mark_moved(v, ctx)
            return ExprStmt(PassCall(VarRef(v.name)))
        if pick == "idr":
            v = self.rng.choice(self.movable(ctx, "res"))
            self.mark_moved(v, ctx)
            return ExprStmt(IdrCall(VarRef(v.name)))
        return ExprStmt(self.gen_res_expr(ctx))

    def gen_match(self, ctx):
        res_vars = self.movable(ctx, "res")
        if res_vars and self.rng.random() < 0.5:
            v = self.rng.choice(res_vars)
            scrut = VarRef(v.name)
            self.mark_moved(v, ctx)
        else:
            scrut = self.gen_res_expr(ctx)
            if scrut is None:
                return None
        patterns = self.rng.choice([("ok", "err"), ("ok", "wild"),
                                    ("err", "wild"), ("wild",)])
        arms = []
        for pattern in patterns:
            name = None
            self.push_gscope()
            if pattern == "ok":
                name = self.fresh_var()
                self.declare(GVar(name, "buf", len(ctx.loops)))
            elif pattern == "err":
                name = self.fresh_var()
                self.declare(GVar(name, "int", len(ctx.loops)))
            body, _ = self.gen_block(ctx.child(), 1, 4)
            self.pop_gscope()
            arms.append(Arm(pattern, name, body))
        return MatchRes(scrut, arms)

    def pick_terminator(self, ctx):
        opts = [None, None, None, None]
        if ctx.loops:
            opts += ["break", "continue"]
        if ctx.in_fn:
            opts += ["return"]
        return self.rng.choice(opts)

    def make_terminator(self, term, ctx):
        if term == "break":
            return Break()
        if term == "continue":
            return Continue()
        return self.gen_return_stmt(ctx)

    def gen_return_stmt(self, ctx):
        choices = ["err", "new"]
        bufs = self.movable(ctx, "buf")
        if bufs:
            choices += ["var", "var"]
        pick = self.rng.choice(choices)
        if pick == "var":
            v = self.rng.choice(bufs)
            self.mark_moved(v, ctx)
            return ReturnOkVar(v.name)
        if pick == "new" and self.tags_has_next():
            return ReturnOk(self.next_tag())
        return ReturnErr(self.rng.randint(1, 9))

    def gen_if(self, ctx):
        cond = self.gen_cond(ctx)
        has_else = self.rng.random() < 0.6
        then_term = self.pick_terminator(ctx)
        else_term = self.pick_terminator(ctx) if has_else else None
        pre = self.snapshot()
        self.push_gscope()
        tctx = ctx.child_branch(then_term)
        then_body, _ = self.gen_block(tctx, 1, 4)
        if then_term is not None:
            then_body.append(self.make_terminator(then_term, tctx))
        self.pop_gscope()
        then_state = self.snapshot()
        then_div = then_term is not None or block_diverges(then_body)
        self.restore(pre)
        else_body = None
        else_state = None
        else_div = False
        if has_else:
            self.push_gscope()
            ectx = ctx.child_branch(else_term)
            else_body, _ = self.gen_block(ectx, 1, 4)
            if else_term is not None:
                else_body.append(self.make_terminator(else_term, ectx))
            self.pop_gscope()
            else_state = self.snapshot()
            else_div = else_term is not None or block_diverges(else_body)
            self.restore(pre)
        parts = []
        if not then_div:
            parts.append(then_state)
        if has_else:
            if not else_div:
                parts.append(else_state)
        else:
            parts.append(pre)
        if parts:
            for sc in self.gscopes:
                for v in sc.vars.values():
                    if v.name in pre:
                        v.live = all(s[v.name][0] for s in parts)
                        v.borrow_block = pre[v.name][1]
        return If(cond, then_body, else_body)

    def gen_for(self, ctx):
        if len(ctx.loops) >= self.MAX_LOOP_NEST:
            return None
        var = f"i{self.loop_n}"
        self.loop_n += 1
        count = self.rng.randint(1, 3)
        moved = set()
        self.push_gscope()
        self.declare(GVar(var, "loop", len(ctx.loops) + 1, count=count))
        body, _ = self.gen_block(ctx.child_loop(moved), 1, 5)
        self.pop_gscope()
        for name in moved:
            v = self.find_var(name)
            if v is not None:
                v.live = False
        return For(var, count, body)

    # -- blocks ----------------------------------------------------------------

    def gen_stmt(self, ctx):
        handlers = [
            (14, self.gen_letbuf),
            (10, self.gen_letres),
            (8, self.gen_letmove),
            (6, self.gen_letpass),
            (5, self.gen_letidr),
            (7, self.gen_consume),
            (10, self.gen_match),
            (8, self.gen_defermark),
            (7, self.gen_deferread),
            (6, self.gen_printmark),
            (10, self.gen_if),
            (8, self.gen_for),
            (6, self.gen_exprstmt),
        ]
        if ctx.in_fn:
            handlers += [(8, self.gen_question), (3, self.gen_consume_abort)]
        if ctx.depth >= self.MAX_DEPTH:
            handlers = [(w, h) for w, h in handlers
                        if h not in (self.gen_if, self.gen_for, self.gen_match)]
        for _ in range(8):
            total = sum(w for w, _ in handlers)
            r = self.rng.uniform(0, total)
            for w, h in handlers:
                r -= w
                if r <= 0:
                    st = h(ctx)
                    if st is not None:
                        return st, stmt_diverges(st)
                    break
        return self.gen_printmark(ctx), False

    def gen_block(self, ctx, min_stmts, max_stmts):
        n = self.rng.randint(min_stmts, max_stmts)
        stmts = []
        diverged = False
        for _ in range(n):
            st, diverged = self.gen_stmt(ctx)
            stmts.append(st)
            if diverged:
                break
        if not stmts:
            stmts.append(self.gen_printmark(ctx))
        return stmts, block_diverges(stmts)

    # -- whole program ---------------------------------------------------------

    def gen_scen(self, idx):
        self.push_gscope()
        self.declare(GVar("fail", "bool", 0))
        ctx = Ctx(in_fn=True)
        body, diverged = self.gen_block(ctx, 2, 7)
        if not diverged:
            body.append(self.gen_return_stmt(ctx))
        self.pop_gscope()
        return FnDef(f"scen{idx}", body)

    def generate(self):
        fns = []
        for i in range(self.rng.randint(1, 3)):
            fns.append(self.gen_scen(i))
            self.fns = list(fns)
        self.push_gscope()
        main, _ = self.gen_block(Ctx(in_fn=False), 3, 8)
        self.pop_gscope()
        return Program(fns, main)


def generate(seed):
    return Generator(seed).generate()


# ---------------------------------------------------------------------------
# The suite
# ---------------------------------------------------------------------------

def diff_trace(expected_lines, actual_stdout):
    """None when actual equals the model trace, else a short description."""
    actual_lines = actual_stdout.splitlines()
    if actual_lines == expected_lines:
        return None
    common = 0
    for want, got in zip(expected_lines, actual_lines):
        if want != got:
            break
        common += 1
    want = expected_lines[common] if common < len(expected_lines) else "<конец вывода>"
    got = actual_lines[common] if common < len(actual_lines) else "<конец вывода>"
    return (f"строка {common + 1}: модель ожидает {want!r}, "
            f"программа напечатала {got!r} "
            f"(всего строк: модель {len(expected_lines)}, программа {len(actual_lines)})")


class OwnershipModel(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        directory = tempfile.TemporaryDirectory(prefix="volt-ownership-model-")
        cls.addClassCleanup(directory.cleanup)
        cls.tmp = Path(directory.name)
        cls.volt = cls.tmp / "volt"
        shutil.copy2(VOLT, cls.volt)
        shutil.copytree(ROOT / "vstd", cls.tmp / "vstd")
        # Same instrumentation as tests/compiler_ownership.py: make every
        # automatic drop visible on stdout.
        owned = cls.tmp / "vstd/owned_buffer.volt"
        text = owned.read_text(encoding="utf-8")
        drop = "fn __volt_owned_buffer_drop(buffer: ptr<OwnedBuffer>):\n"
        if text.count(drop) != 1:
            raise AssertionError("missing vstd drop hook")
        owned.write_text(text.replace(
            drop, drop + '    print("drop", owned_buffer_get(buffer, 0) as char)\n'),
            encoding="utf-8")
        # Failure artifacts live next to the temporary directory and survive
        # the run for debugging.
        cls.artifacts = cls.tmp.parent / (cls.tmp.name + "-artifacts")
        cls.artifacts.mkdir(exist_ok=True)

    def build_and_run(self, source):
        """(stdout, None) on success; (None, diagnostics) otherwise."""
        path = self.tmp / "main.volt"
        path.write_text(source, encoding="utf-8")
        built = subprocess.run([self.volt, path, "-o", self.tmp / "program"],
                               capture_output=True, text=True, timeout=15)
        if built.returncode != 0:
            return None, f"компиляция завершилась с {built.returncode}:\n{built.stdout}{built.stderr}"
        ran = subprocess.run([self.tmp / "program"], cwd=self.tmp,
                             capture_output=True, text=True, timeout=5)
        if ran.returncode != 0:
            return None, (f"программа завершилась с {ran.returncode}:\n"
                          f"{ran.stdout}{ran.stderr}")
        return ran.stdout, None

    def save_failure(self, seed, source, expected, actual, error):
        base = self.artifacts / f"seed{seed}"
        Path(str(base) + ".volt").write_text(source, encoding="utf-8")
        Path(str(base) + ".expected.txt").write_text(expected, encoding="utf-8")
        Path(str(base) + ".actual.txt").write_text(
            (error or "") + "=== stdout ===\n" + (actual or ""), encoding="utf-8")
        return base

    def check_seed(self, seed):
        """None when the program matches the model, else a failure message."""
        program = generate(seed)
        source = emit_program(program)
        expected_lines = interpret(program)
        expected = "".join(line + "\n" for line in expected_lines)
        actual, error = self.build_and_run(source)
        if error is None and actual == expected:
            return None
        base = self.save_failure(seed, source, expected, actual, error)
        if error is not None:
            return (f"seed {seed}: сгенерированная программа не собралась или упала; "
                    f"кейс сохранён: {base}.volt\n{error}")
        return (f"seed {seed}: {diff_trace(expected_lines, actual)}; "
                f"кейс сохранён: {base}.volt")

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
        """The exact-trace comparison must catch a doubled drop, a missing
        drop and a reordering — the bugs this suite exists to find."""
        checked = 0
        for k in range(60):
            seed = SEED_BASE + 10_000_000 + k
            program = generate(seed)
            source = emit_program(program)
            expected_lines = interpret(program)
            drops = [i for i, line in enumerate(expected_lines)
                     if line.startswith("drop ")]
            swap = next((i for i in range(len(expected_lines) - 1)
                         if expected_lines[i] != expected_lines[i + 1]), None)
            if len(drops) < 2 or swap is None:
                continue
            actual, error = self.build_and_run(source)
            self.assertIsNone(error, f"seed {seed}: {error}")
            with self.subTest(seed=seed, mutation="база совпадает"):
                self.assertIsNone(diff_trace(expected_lines, actual),
                                  f"seed {seed}: базовая трассировка не совпала")
            # Лишний drop: двойное освобождение.
            doubled = (expected_lines[:drops[0] + 1] + [expected_lines[drops[0]]]
                       + expected_lines[drops[0] + 1:])
            with self.subTest(seed=seed, mutation="лишний drop"):
                self.assertIsNotNone(diff_trace(doubled, actual))
            # Пропущенный drop: утечка.
            missing = expected_lines[:drops[-1]] + expected_lines[drops[-1] + 1:]
            with self.subTest(seed=seed, mutation="пропущенный drop"):
                self.assertIsNotNone(diff_trace(missing, actual))
            # Перестановка: неверный порядок освобождения.
            reordered = list(expected_lines)
            reordered[swap], reordered[swap + 1] = reordered[swap + 1], reordered[swap]
            with self.subTest(seed=seed, mutation="перестановка"):
                self.assertIsNotNone(diff_trace(reordered, actual))
            checked += 1
            if checked >= 5:
                break
        self.assertGreaterEqual(checked, 5,
                                "слишком мало программ с богатой трассировкой")


if __name__ == "__main__":
    unittest.main()
