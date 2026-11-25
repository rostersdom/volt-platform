#!/usr/bin/env python3
"""Run the golden, compiler regression, and integration suites.

Default behavior (no arguments) is unchanged in spirit: every suite runs as a
subprocess and counts as passed when it exits with status 0.

Groups:
  --group core     every suite except browser_* (also runs `make
                   verify-bootstrap` first, as a required step)
  --group browser  only the browser_* suites (needs the native browser stack:
                   SDL2, Cairo, Pango, OpenSSL 3, zlib, libwebp, TurboJPEG 3)
  --group all      every suite (default; includes verify-bootstrap)

Required suites:
  --require SUITE (repeatable) runs SUITE under a unittest driver that counts
  executed and skipped tests. The whole run fails if a required suite exits
  non-zero, collects no tests at all, or skips every test it has -- so a
  required suite can no longer pass vacuously via @unittest.skipUnless on an
  unsupported platform.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

SUITES = (
    "compiler_bootstrap", "run", "regressions", "abi_integration", "compiler_fnptr",
    "compiler_lifetimes", "compiler_buffer_borrow", "compiler_manifest",
    "compiler_sum_types", "compiler_modules", "compiler_ownership", "compiler_slice_borrows",
    "compiler_eq_constraint", "compiler_c_struct", "vstd_text_view",
    "compiler_debug", "compiler_fuzz", "vstd_io", "vstd_fs", "vstd_arena", "vstd_threads", "vstd_channel",
    "http_integration", "sdl_integration",
    "browser_navigation", "browser_navigation_controller", "browser_https",
    "browser_launch", "volt_launcher_integration", "browser_javascript", "browser_visual", "browser_media",
    "browser_search",
)

BROWSER_SUITES = tuple(suite for suite in SUITES if suite.startswith("browser_"))
CORE_SUITES = tuple(suite for suite in SUITES if suite not in BROWSER_SUITES)
GROUPS = {"core": CORE_SUITES, "browser": BROWSER_SUITES, "all": SUITES}

STATS_PREFIX = "RUN_ALL_STATS "

# Driver for --require suites: loads the suite as a module and runs it under
# unittest, then reports executed/skipped counts on a STATS_PREFIX line so the
# runner can tell "all tests skipped" apart from a real pass. unittest writes
# its progress to stderr, which the runner inherits; stdout is teed through.
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
    def __init__(self, name, returncode, stats=None):
        self.name = name
        self.returncode = returncode
        self.stats = stats


def run_suite(name, tests_dir, env, cwd, collect_stats=False):
    """Run one suite, teeing its output; collect unittest stats when asked."""
    script = str(tests_dir / (name + ".py"))
    if not collect_stats:
        proc = subprocess.run([sys.executable, script], cwd=cwd, env=env)
        return SuiteResult(name, proc.returncode)
    proc = subprocess.Popen([sys.executable, "-c", DRIVER, script],
                            cwd=cwd, env=env, stdout=subprocess.PIPE, text=True)
    stats = None
    for line in proc.stdout:
        if line.startswith(STATS_PREFIX):
            stats = json.loads(line[len(STATS_PREFIX):])
        else:
            sys.stdout.write(line)
            sys.stdout.flush()
    return SuiteResult(name, proc.wait(), stats)


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
    """Run the given suites; return a list of failure descriptions."""
    failures = []
    for name in names:
        print(f"\n=== tests/{name}.py ===", flush=True)
        result = run_suite(name, tests_dir, env, cwd, collect_stats=name in required)
        problem = evaluate(result, required)
        if problem:
            failures.append(problem)
            print(f"FAIL: {problem}", file=sys.stderr, flush=True)
    return failures


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--group", choices=sorted(GROUPS), default="all",
                        help="suites to run: 'core' (all but browser_*, plus a "
                             "required `make verify-bootstrap` step), 'browser' "
                             "(only browser_*), or 'all' (default: every suite)")
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
    failures.extend(suite_failures)
    print(f"\n{len(names) - len(suite_failures)}/{len(names)} suites passed", flush=True)
    if failures:
        print("Failed:", file=sys.stderr)
        for problem in failures:
            print(f"  {problem}", file=sys.stderr)
    return int(bool(failures))


if __name__ == "__main__":
    sys.exit(main())
