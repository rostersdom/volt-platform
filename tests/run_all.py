#!/usr/bin/env python3
"""Run the golden, compiler regression, and integration suites.

Default behavior (no arguments) is unchanged in spirit: every suite runs as a
subprocess and counts as passed when it exits with status 0.

Groups (explicit allow-lists, see CORE_SUITES/BROWSER_SUITES below):
  --group core     the suites that run on a bare ubuntu-24.04 runner: no
                   display, no SDL2, no browser native stack (also runs
                   `make verify-bootstrap` first, as a required step)
  --group browser  the suites that need the native browser stack (SDL2 at
                   link time, plus Cairo, Pango, OpenSSL 3, zlib, libwebp,
                   TurboJPEG 3) and/or a (dummy) display
  --group all      every suite (default; includes verify-bootstrap)

Required suites:
  --require SUITE (repeatable) runs SUITE under a unittest driver that counts
  executed and skipped tests. The whole run fails if a required suite exits
  non-zero, collects no tests at all, or skips every test it has -- so a
  required suite can no longer pass vacuously via @unittest.skipUnless on an
  unsupported platform.
"""
import argparse
from collections import deque
import json
import os
from pathlib import Path
import subprocess
import sys
import threading

# Suite groups are EXPLICIT allow-lists, not name prefixes: a prefix rule
# silently mis-files any suite whose name does not match its dependencies
# (sdl_integration sat in "core" although it needs SDL2). Each entry carries
# the dependency that decides its group; keep the comment in sync when a
# suite gains new system requirements.
#
# CORE_SUITES must pass on a bare ubuntu-24.04 runner: no display, no SDL2,
# no browser native stack.
CORE_SUITES = (
    # Pure compiler suites: build and run generated ELF binaries only.
    "compiler_bootstrap", "compiler_fnptr", "compiler_lifetimes",
    "compiler_buffer_borrow", "compiler_manifest", "compiler_sum_types",
    "compiler_modules", "compiler_ownership", "compiler_ownership_model", "compiler_slice_borrows",
    "compiler_eq_constraint", "compiler_c_struct", "compiler_debug",
    "compiler_fuzz",
    # Golden compile-and-run tests; no native deps.
    "run",
    # Compiler regressions; pure Linux syscall level except one test:
    # test_snake_sdl_startup_and_quit_without_a_terminal builds
    # apps/snake.volt, which does `link "-lSDL2"`, so without libSDL2.so the
    # suite fails. Kept in core because 105 of 106 tests are pure compiler
    # regressions and the suite guards its other optional deps per-test
    # (cc, readelf, /dev/full) -- the snake test needs the same guard, which
    # belongs to the suite file, not to this runner.
    "regressions",
    # Linux x86-64 System V ABI fixtures; skips cleanly without `cc`.
    "abi_integration",
    # vstd suites: Linux x86-64 syscalls/pthreads only, no display, no SDL.
    "vstd_text_view", "vstd_io", "vstd_fs", "vstd_arena", "vstd_threads",
    "vstd_channel",
    # Loopback 127.0.0.1 HTTP/DNS tests; no external network, no display.
    "http_integration",
)

# BROWSER_SUITES need the native browser stack and/or a (dummy) display:
# SDL2 at link time (anything importing vstd/sdl.volt gets `link "-lSDL2"`),
# plus Cairo, Pango, OpenSSL 3, zlib, libwebp and TurboJPEG 3 for the full
# browser app.
BROWSER_SUITES = (
    # browser_* suites exercise the browser app/modules directly.
    "browser_navigation", "browser_navigation_controller", "browser_https",
    "browser_launch", "browser_javascript", "browser_visual", "browser_media",
    "browser_search",
    # SDL2 dummy-driver lifecycle/rendering smoke test: probes SDL2 via
    # pkg-config and skips when absent, but it tests the browser rendering
    # stack, so it belongs here and not in core.
    "sdl_integration",
    # Launcher CLI: its browser-alias tests compile apps/browser.volt, which
    # imports browser_window -> vstd/sdl.volt and therefore links -lSDL2.
    "volt_launcher_integration",
)

SUITES = CORE_SUITES + BROWSER_SUITES
GROUPS = {"core": CORE_SUITES, "browser": BROWSER_SUITES, "all": SUITES}

STATS_PREFIX = "RUN_ALL_STATS "

# How many trailing lines of a failed suite's output are reprinted in the
# failure summary. CI keeps running the remaining suites after a failure, so
# without a recap the relevant output is buried thousands of lines above the
# "Failed:" list.
TAIL_LINES = 40

# Driver for --require suites: loads the suite as a module and runs it under
# unittest, then reports executed/skipped counts on a STATS_PREFIX line so the
# runner can tell "all tests skipped" apart from a real pass. unittest writes
# its progress to stderr; the runner tees both streams through live and keeps
# their tails for the failure recap.
DRIVER = r"""
import importlib.util, json, sys, unittest
spec = importlib.util.spec_from_file_location("volt_required_suite", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
result = unittest.TextTestRunner(verbosity=1).run(
    unittest.defaultTestLoader.loadTestsFromModule(module))
stats = {"testsRun": result.testsRun, "skipped": len(result.skipped),
         "failures": len(result.failures), "errors": len(result.errors)}
print("RUN_ALL_STATS " + json.dumps(stats), flush=True)
sys.exit(0 if result.wasSuccessful() else 1)
"""


class SuiteResult:
    def __init__(self, name, returncode, stats=None, stdout_tail=(), stderr_tail=()):
        self.name = name
        self.returncode = returncode
        self.stats = stats
        self.stdout_tail = tuple(stdout_tail)
        self.stderr_tail = tuple(stderr_tail)


def tee_stream(lines, target, tail):
    """Copy a subprocess stream to our own live, keeping the last TAIL_LINES."""
    for line in lines:
        target.write(line)
        target.flush()
        tail.append(line)


def run_suite(name, tests_dir, env, cwd, collect_stats=False):
    """Run one suite, teeing its output; collect unittest stats when asked.

    Both streams are teed live (so a hanging suite still shows progress in CI)
    and their tails are kept in the SuiteResult for the failure summary.
    """
    script = str(tests_dir / (name + ".py"))
    argv = ([sys.executable, "-c", DRIVER, script] if collect_stats
            else [sys.executable, script])
    proc = subprocess.Popen(argv, cwd=cwd, env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True)
    stdout_tail = deque(maxlen=TAIL_LINES)
    stderr_tail = deque(maxlen=TAIL_LINES)
    # stderr carries the unittest progress/failure report; tee it from a
    # thread so neither pipe can deadlock on a full buffer.
    printer = threading.Thread(target=tee_stream,
                               args=(proc.stderr, sys.stderr, stderr_tail),
                               daemon=True)
    printer.start()
    stats = None
    for line in proc.stdout:
        if collect_stats and line.startswith(STATS_PREFIX):
            stats = json.loads(line[len(STATS_PREFIX):])
        else:
            sys.stdout.write(line)
            sys.stdout.flush()
            stdout_tail.append(line)
    printer.join()
    return SuiteResult(name, proc.wait(), stats, stdout_tail, stderr_tail)


def evaluate(result, required):
    """Return a failure description for a finished suite, or None."""
    if result.returncode:
        return f"{result.name} exited with status {result.returncode}"
    if result.name not in required:
        return None
    stats = result.stats
    if stats is None:
        return f"{result.name} is required but produced no unittest statistics"
    if stats["testsRun"] == 0:
        return f"{result.name} is required but ran no tests"
    if stats["skipped"] >= stats["testsRun"]:
        return (f"{result.name} is required but all {stats['testsRun']} "
                f"test(s) were skipped")
    return None


def execute_suites(names, required, tests_dir, env, cwd):
    """Run the given suites; return (problem, SuiteResult) pairs for failures."""
    failures = []
    for name in names:
        print(f"\n=== tests/{name}.py ===", flush=True)
        result = run_suite(name, tests_dir, env, cwd, collect_stats=name in required)
        problem = evaluate(result, required)
        if problem:
            failures.append((problem, result))
            print(f"FAIL: {problem}", file=sys.stderr, flush=True)
    return failures


def print_failure_recaps(suite_failures):
    """Reprint the tail of every failed suite's output at end of run.

    The output was already streamed live, but later suites bury it; the recap
    puts enough context next to the final "Failed:" list to diagnose a CI
    failure without scrolling the whole log.
    """
    for _problem, result in suite_failures:
        print(f"\n==== tail of tests/{result.name}.py output "
              f"(last {TAIL_LINES} lines per stream) ====", file=sys.stderr)
        for label, tail in (("stdout", result.stdout_tail),
                            ("stderr", result.stderr_tail)):
            if tail:
                print(f"---- {label} ----", file=sys.stderr)
                for line in tail:
                    sys.stderr.write(line if line.endswith("\n") else line + "\n")
        if not result.stdout_tail and not result.stderr_tail:
            print("(the suite produced no output)", file=sys.stderr)


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--group", choices=sorted(GROUPS), default="all",
                        help="suites to run: 'core' (the headless bare-ubuntu "
                             "allow-list, plus a required `make "
                             "verify-bootstrap` step), 'browser' (the native "
                             "browser-stack allow-list), or 'all' (default: "
                             "every suite)")
    parser.add_argument("--require", action="append", default=[], metavar="SUITE",
                        help="require SUITE to really run (repeatable): the run "
                             "fails if it errors, collects no tests, or skips "
                             "every test; SUITE must belong to the selected group")
    parser.add_argument("--skip-verify-bootstrap", action="store_true",
                        help="omit the `make verify-bootstrap` step of the core "
                             "group (CI runs it as its own job step)")
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    tests = Path(__file__).resolve().parent
    root = tests.parent
    names = GROUPS[args.group]
    unknown = [suite for suite in args.require if suite not in names]
    if unknown:
        print("Required suite(s) not in group "
              f"'{args.group}': {', '.join(unknown)}\n"
              f"Available: {', '.join(names)}", file=sys.stderr)
        return 2
    build = subprocess.run(["make", "compiler"], cwd=root)
    if build.returncode:
        return build.returncode
    failures = []
    if args.group in ("core", "all") and not args.skip_verify_bootstrap:
        print("\n=== make verify-bootstrap ===", flush=True)
        boot = subprocess.run(["make", "verify-bootstrap"], cwd=root)
        if boot.returncode:
            failures.append(f"make verify-bootstrap exited with status {boot.returncode}")
    env = {**os.environ, "SDL_VIDEODRIVER": "dummy", "VOLT_COMPILER": str(root / "volt")}
    suite_failures = execute_suites(names, set(args.require), tests, env, root)
    failures.extend(problem for problem, _result in suite_failures)
    print(f"\n{len(names) - len(suite_failures)}/{len(names)} suites passed", flush=True)
    if failures:
        print("Failed:", file=sys.stderr)
        for problem in failures:
            print(f"  {problem}", file=sys.stderr)
        print_failure_recaps(suite_failures)
    return int(bool(failures))


if __name__ == "__main__":
    sys.exit(main())
