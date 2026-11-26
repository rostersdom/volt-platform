#!/usr/bin/env python3
"""Self-tests for the run_all.py suite runner (no compiler build needed)."""
import importlib.util
import io
import os
from pathlib import Path
import tempfile
import unittest
import unittest.mock

RUN_ALL_PATH = Path(__file__).resolve().parent / "run_all.py"
spec = importlib.util.spec_from_file_location("run_all", RUN_ALL_PATH)
run_all = importlib.util.module_from_spec(spec)
spec.loader.exec_module(run_all)

PASSING = '''
import unittest

class Passing(unittest.TestCase):
    def test_ok(self):
        self.assertTrue(True)

if __name__ == "__main__":
    unittest.main()
'''

PARTIALLY_SKIPPED = '''
import unittest

class Partial(unittest.TestCase):
    def test_runs(self):
        self.assertTrue(True)

    @unittest.skip("demonstrating a partial skip")
    def test_skipped(self):
        self.fail("must be skipped")

if __name__ == "__main__":
    unittest.main()
'''

ALL_SKIPPED = '''
import unittest

@unittest.skipUnless(False, "simulated unsupported platform")
class Skipped(unittest.TestCase):
    def test_never_runs(self):
        self.fail("must be skipped")

if __name__ == "__main__":
    unittest.main()
'''

FAILING = '''
import unittest

class Failing(unittest.TestCase):
    def test_broken(self):
        self.fail("boom")

if __name__ == "__main__":
    unittest.main()
'''

NOISY_FAILING = '''
import sys
import unittest

print("marker on stdout")
print("marker on stderr", file=sys.stderr)

class NoisyFailing(unittest.TestCase):
    def test_broken(self):
        self.fail("boom")

if __name__ == "__main__":
    unittest.main()
'''

SPAM_FAILING = '''
import unittest

for i in range(300):
    print(f"line {i}")

class SpamFailing(unittest.TestCase):
    def test_broken(self):
        self.fail("boom")

if __name__ == "__main__":
    unittest.main()
'''


class Groups(unittest.TestCase):
    def test_groups_partition_suites(self):
        self.assertEqual(sorted(run_all.CORE_SUITES + run_all.BROWSER_SUITES),
                         sorted(run_all.SUITES))
        self.assertEqual(set(run_all.CORE_SUITES) & set(run_all.BROWSER_SUITES),
                         set())
        self.assertNotIn("browser_navigation", run_all.CORE_SUITES)

    def test_sdl_dependent_suites_are_not_in_core(self):
        # Core must run on a bare ubuntu-24.04 runner: no SDL2, no display.
        # sdl_integration links and runs SDL2; volt_launcher_integration
        # compiles apps/browser.volt (browser_window -> vstd/sdl.volt ->
        # `link "-lSDL2"`). Both belong to the browser group.
        for suite in ("sdl_integration", "volt_launcher_integration"):
            self.assertNotIn(suite, run_all.CORE_SUITES)
            self.assertIn(suite, run_all.BROWSER_SUITES)

    def test_headless_suites_are_in_core(self):
        for suite in ("run", "regressions", "http_integration",
                      "vstd_text_view", "vstd_arena", "vstd_threads",
                      "vstd_channel"):
            self.assertIn(suite, run_all.CORE_SUITES)

    def test_linux_x86_64_required_suites_exist_in_core(self):
        for suite in ("compiler_ownership", "compiler_slice_borrows",
                      "abi_integration", "vstd_io", "vstd_fs"):
            self.assertIn(suite, run_all.CORE_SUITES)


class ExecuteSuites(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory(prefix="volt-run-all-test-")
        self.addCleanup(tmp.cleanup)
        self.tests_dir = Path(tmp.name)

    def write_suite(self, name, source):
        (self.tests_dir / (name + ".py")).write_text(source, encoding="utf-8")

    def execute_full(self, names, required=(), required_tests=None):
        results = []
        with open(os.devnull, "w") as devnull, \
             unittest.mock.patch("sys.stdout", devnull), \
             unittest.mock.patch("sys.stderr", devnull):
            failures = run_all.execute_suites(
                names, set(required) | set(required_tests or ()),
                self.tests_dir, dict(os.environ), self.tests_dir,
                required_tests=required_tests, results=results)
        return failures, results

    def execute(self, names, required=(), required_tests=None):
        failures, _results = self.execute_full(names, required, required_tests)
        return [problem for problem, _result in failures]

    def test_required_suite_with_real_tests_passes(self):
        self.write_suite("fake_pass", PASSING)
        self.assertEqual(self.execute(["fake_pass"], required=["fake_pass"]), [])

    def test_required_suite_fully_skipped_fails(self):
        self.write_suite("fake_skip", ALL_SKIPPED)
        failures = self.execute(["fake_skip"], required=["fake_skip"])
        self.assertEqual(len(failures), 1)
        self.assertIn("fake_skip", failures[0])
        self.assertIn("skipped", failures[0])

    def test_fully_skipped_suite_passes_when_not_required(self):
        self.write_suite("fake_skip", ALL_SKIPPED)
        self.assertEqual(self.execute(["fake_skip"]), [])

    def test_failing_required_suite_fails(self):
        self.write_suite("fake_fail", FAILING)
        failures = self.execute(["fake_fail"], required=["fake_fail"])
        self.assertEqual(len(failures), 1)
        self.assertIn("fake_fail", failures[0])

    def test_required_suite_without_tests_fails(self):
        (self.tests_dir / "fake_empty.py").write_text("X = 1\n", encoding="utf-8")
        failures = self.execute(["fake_empty"], required=["fake_empty"])
        self.assertEqual(len(failures), 1)
        self.assertIn("no tests", failures[0])

    def test_failed_suite_keeps_output_tails_for_the_recap(self):
        self.write_suite("fake_noisy", NOISY_FAILING)
        failures, _results = self.execute_full(["fake_noisy"], required=["fake_noisy"])
        self.assertEqual(len(failures), 1)
        _problem, result = failures[0]
        self.assertIn("fake_noisy", _problem)
        self.assertIn("marker on stdout\n", result.stdout_tail)
        self.assertIn("marker on stderr\n", result.stderr_tail)
        # unittest's own failure report goes to stderr and must be tailed too.
        self.assertTrue(any("FAIL" in line or "Traceback" in line
                            for line in result.stderr_tail))

    def test_tails_are_bounded(self):
        self.write_suite("fake_spam", SPAM_FAILING)
        failures, _results = self.execute_full(["fake_spam"], required=["fake_spam"])
        self.assertEqual(len(failures), 1)
        _problem, result = failures[0]
        self.assertLessEqual(len(result.stdout_tail), run_all.TAIL_LINES)
        self.assertIn("line 299\n", result.stdout_tail)
        self.assertNotIn("line 0\n", result.stdout_tail)

    def test_failure_recap_reprints_tails_to_stderr(self):
        self.write_suite("fake_noisy", NOISY_FAILING)
        failures, _results = self.execute_full(["fake_noisy"], required=["fake_noisy"])
        recap = io.StringIO()
        with unittest.mock.patch("sys.stderr", recap):
            run_all.print_failure_recaps(failures)
        text = recap.getvalue()
        self.assertIn("fake_noisy", text)
        self.assertIn("marker on stdout", text)
        self.assertIn("marker on stderr", text)


class RequiredTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory(prefix="volt-run-all-test-")
        self.addCleanup(tmp.cleanup)
        self.tests_dir = Path(tmp.name)

    def write_suite(self, name, source):
        (self.tests_dir / (name + ".py")).write_text(source, encoding="utf-8")

    def execute(self, names, required=(), required_tests=None):
        with open(os.devnull, "w") as devnull, \
             unittest.mock.patch("sys.stdout", devnull), \
             unittest.mock.patch("sys.stderr", devnull):
            failures = run_all.execute_suites(
                names, set(required) | set(required_tests or ()),
                self.tests_dir, dict(os.environ), self.tests_dir,
                required_tests=required_tests)
        return [problem for problem, _result in failures]

    def test_required_test_that_executes_passes(self):
        self.write_suite("fake_pass", PASSING)
        failures = self.execute(
            ["fake_pass"],
            required_tests={"fake_pass": {"fake_pass.Passing.test_ok"}})
        self.assertEqual(failures, [])

    def test_required_test_skipped_fails_with_reason(self):
        self.write_suite("fake_partial", PARTIALLY_SKIPPED)
        failures = self.execute(
            ["fake_partial"],
            required_tests={"fake_partial": {"fake_partial.Partial.test_skipped"}})
        self.assertEqual(len(failures), 1)
        self.assertIn("fake_partial.Partial.test_skipped", failures[0])
        self.assertIn("skipped", failures[0])
        self.assertIn("demonstrating a partial skip", failures[0])

    def test_required_test_never_started_when_class_setup_skips(self):
        self.write_suite("fake_class_skip", PASSING + '''
class ClassSetup(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        raise unittest.SkipTest("missing fixture for class")

    def test_never_started(self):
        self.fail("must not run")
''')
        failures = self.execute(
            ["fake_class_skip"],
            required_tests={"fake_class_skip": {"fake_class_skip.ClassSetup.test_never_started"}})
        self.assertEqual(len(failures), 1)
        self.assertIn("fake_class_skip.ClassSetup.test_never_started", failures[0])
        self.assertIn("missing fixture for class", failures[0])

    def test_required_test_reports_a_skipped_subtest(self):
        self.write_suite("fake_subtest_skip", PASSING + '''
class Partial(unittest.TestCase):
    def test_runs(self):
        with self.subTest(fixture="C"):
            self.skipTest("missing C fixture")
''')
        failures = self.execute(
            ["fake_subtest_skip"],
            required_tests={"fake_subtest_skip": {"fake_subtest_skip.Partial.test_runs"}})
        self.assertEqual(len(failures), 1)
        self.assertIn("fake_subtest_skip.Partial.test_runs", failures[0])
        self.assertIn("missing C fixture", failures[0])

    def test_required_test_unknown_identifier_fails(self):
        self.write_suite("fake_pass", PASSING)
        failures = self.execute(
            ["fake_pass"],
            required_tests={"fake_pass": {"fake_pass.Passing.test_missing"}})
        self.assertEqual(len(failures), 1)
        self.assertIn("fake_pass.Passing.test_missing", failures[0])
        self.assertIn("not found", failures[0])

    def test_partially_skipped_suite_passes_without_required_tests(self):
        # --require alone tolerates partial skips; --require-test closes that.
        self.write_suite("fake_partial", PARTIALLY_SKIPPED)
        self.assertEqual(self.execute(["fake_partial"], required=["fake_partial"]),
                         [])

    def test_skip_report_lists_reasons_even_for_optional_suites(self):
        self.write_suite("fake_partial", PARTIALLY_SKIPPED)
        results = []
        with open(os.devnull, "w") as devnull, \
             unittest.mock.patch("sys.stdout", devnull), \
             unittest.mock.patch("sys.stderr", devnull):
            run_all.execute_suites(["fake_partial"], set(),
                                   self.tests_dir, dict(os.environ),
                                   self.tests_dir, results=results)
        report = io.StringIO()
        with unittest.mock.patch("sys.stdout", report):
            run_all.print_skip_report(results)
        text = report.getvalue()
        self.assertIn("fake_partial.Partial.test_skipped", text)
        self.assertIn("demonstrating a partial skip", text)
        self.assertNotIn("test_runs", text)


class RequiredTestArgValidation(unittest.TestCase):
    def parse_error(self, argv):
        with unittest.mock.patch("sys.stderr", io.StringIO()) as err:
            code = run_all.main(argv)
        return code, err.getvalue()

    def test_bad_identifier_format_is_rejected(self):
        code, err = self.parse_error(
            ["--group", "core", "--skip-verify-bootstrap",
             "--require-test", "compiler_debug"])
        self.assertEqual(code, 2)
        self.assertIn("SUITE.ClassName.test_name", err)

    def test_suite_outside_the_group_is_rejected(self):
        code, err = self.parse_error(
            ["--group", "browser", "--skip-verify-bootstrap",
             "--require-test", "compiler_debug.CompilerDebug."
                              "test_gdb_next_steps_through_statements"])
        self.assertEqual(code, 2)
        self.assertIn("not in group", err)


if __name__ == "__main__":
    unittest.main()
