#!/usr/bin/env python3
"""Run the golden, compiler regression, and integration suites.

By default every suite runs as a subprocess and counts as passed when it
exits with status 0. Unittest skips and their reasons are listed at the end.

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

Required tests:
  --require-test SUITE.ClassName.test_name (repeatable) fails the run when the
  named test did not actually execute: it was skipped (the reason is shown) or
  no such test exists in the suite (unknown identifier). This catches PARTIAL
  skips inside a required suite, which --require alone tolerates. A suite
  named by --require-test is implicitly treated as --require'd.
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
    "compiler_modules", "compiler_ownership", "compiler_ownership_model",
    "compiler_arith_model", "compiler_slice_borrows",
    "compiler_eq_constraint", "compiler_c_struct", "compiler_debug",
    "compiler_fuzz",
    # Golden compile-and-run tests and regressions report optional SDL skips.
    "run",
    "regressions",
    "test_run_all",
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
    "browser_search", "browser_search_bar", "browser_cookies", "browser_dom",
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

# Driver for unittest suites: loads the suite as a module (named after the
# file stem, so unittest test ids come out as "suite.Class.test") and runs it
# under unittest, then reports which tests ran and why others were skipped.
DRIVER = r"""
import importlib.util, json, sys, unittest
from pathlib import Path
path = Path(sys.argv[1])
sys.path.insert(0, str(path.parent))
spec = importlib.util.spec_from_file_location(path.stem, path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)
suite = unittest.defaultTestLoader.loadTestsFromModule(module)

class Result(unittest.TextTestResult):
    def __init__(self, *args):
        super().__init__(*args)
        self.started = set()

    def startTest(self, test):
        self.started.add(test.id())
        super().startTest(test)

result = unittest.TextTestRunner(resultclass=Result).run(suite)
skipped = [{"id": test.id(), "test": getattr(test, "test_case", test).id(),
            "reason": reason} for test, reason in result.skipped]
executed = sorted(result.started - {entry["test"] for entry in skipped})
stats = {"executed": executed, "skippedTests": skipped}
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


def evaluate(result, required, required_tests=None):
    """Return a failure description for a finished suite, or None."""
    if result.returncode:
        return f"{result.name} exited with status {result.returncode}"
    if result.name not in required:
        return None
    stats = result.stats
    if stats is None:
        return f"{result.name} is required but produced no unittest statistics"
    executed = set(stats["executed"])
    if required_tests and result.name in required_tests:
        for ident in sorted(required_tests[result.name]):
            suite, cls, _test = ident.split(".")
            # unittest reports a skipped setup fixture once under its own id,
            # without ever starting the individual tests it covers.
            setups = {f"setUpClass ({suite}.{cls})", f"setUpModule ({suite})"}
            for skip in stats["skippedTests"]:
                if skip["test"] == ident or skip["id"] in setups:
                    return f"required test {ident} was skipped: {skip['reason']}"
            if ident not in executed:
                return f"required test {ident} was not found or did not run"
    if not executed:
        if stats["skippedTests"]:
            return f"{result.name} is required but all tests were skipped"
        return f"{result.name} is required but ran no tests"
    return None


def execute_suites(names, required, tests_dir, env, cwd, required_tests=None,
                   results=None):
    """Run the given suites; return (problem, SuiteResult) pairs for failures.

    Every finished SuiteResult is appended to `results` when a list is given,
    so the caller can build the final skip report.
    """
    failures = []
    for name in names:
        print(f"\n=== tests/{name}.py ===", flush=True)
        # The golden-output runner is a standalone script, not a unittest suite.
        result = run_suite(name, tests_dir, env, cwd, collect_stats=name != "run" or name in required)
        if results is not None:
            results.append(result)
        problem = evaluate(result, required, required_tests)
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


def print_skip_report(results):
    """List every reported unittest skip and its reason."""
    entries = [(entry["id"], entry["reason"])
               for result in results
               if result.stats
               for entry in result.stats["skippedTests"]]
    if not entries:
        return
    print("\nSkipped tests:", flush=True)
    for ident, reason in entries:
        print(f"  {ident}: {reason}", flush=True)


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
    parser.add_argument("--require-test", action="append", default=[],
                        metavar="SUITE.CLASS.TEST", dest="require_test",
                        help="require one test to really execute (repeatable): "
                             "the run fails if SUITE.CLASS.TEST was skipped "
                             "(the reason is shown) or does not exist; SUITE "
                             "must belong to the selected group and is "
                             "implicitly treated as --require'd")
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
    required_tests = {}
    bad_tests = []
    for ident in args.require_test:
        parts = ident.split(".")
        if len(parts) != 3 or not all(parts):
            bad_tests.append(ident)
            continue
        if parts[0] not in names:
            unknown.append(ident)
            continue
        required_tests.setdefault(parts[0], set()).add(ident)
    if bad_tests:
        print("Required test identifier(s) must have the form "
              f"SUITE.ClassName.test_name: {', '.join(bad_tests)}",
              file=sys.stderr)
        return 2
    if unknown:
        print("Required test(s) reference suite(s) not in group "
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
    required = set(args.require) | set(required_tests)
    results = []
    suite_failures = execute_suites(names, required, tests, env, root,
                                    required_tests=required_tests,
                                    results=results)
    failures.extend(problem for problem, _result in suite_failures)
    print(f"\n{len(names) - len(suite_failures)}/{len(names)} suites passed", flush=True)
    print_skip_report(results)
    if failures:
        print("Failed:", file=sys.stderr)
        for problem in failures:
            print(f"  {problem}", file=sys.stderr)
        print_failure_recaps(suite_failures)
    return int(bool(failures))


if __name__ == "__main__":
    sys.exit(main())
