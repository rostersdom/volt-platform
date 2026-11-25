#!/usr/bin/env python3
"""Self-tests for the run_all.py suite runner (no compiler build needed)."""
import importlib.util
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


class Groups(unittest.TestCase):
    def test_groups_partition_suites(self):
        self.assertEqual(sorted(run_all.CORE_SUITES + run_all.BROWSER_SUITES),
                         sorted(run_all.SUITES))
        self.assertTrue(all(suite.startswith("browser_")
                            for suite in run_all.BROWSER_SUITES))
        self.assertNotIn("browser_navigation", run_all.CORE_SUITES)

    def test_linux_x86_64_required_suites_exist_in_core(self):
        for suite in ("compiler_ownership", "compiler_slice_borrows",
                      "abi_integration", "vstd_io"):
            self.assertIn(suite, run_all.CORE_SUITES)


class ExecuteSuites(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory(prefix="volt-run-all-test-")
        self.addCleanup(tmp.cleanup)
        self.tests_dir = Path(tmp.name)

    def write_suite(self, name, source):
        (self.tests_dir / (name + ".py")).write_text(source, encoding="utf-8")

    def execute(self, names, required=()):
        with open(os.devnull, "w") as devnull, \
             unittest.mock.patch("sys.stdout", devnull), \
             unittest.mock.patch("sys.stderr", devnull):
            return run_all.execute_suites(names, set(required), self.tests_dir,
                                          dict(os.environ), self.tests_dir)

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


if __name__ == "__main__":
    unittest.main()
