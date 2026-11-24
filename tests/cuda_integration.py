#!/usr/bin/env python3
"""CUDA loader, SysV ABI and cleanup checks; real GPU smoke is opt-in."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent
DEMO = ROOT / "apps" / "cuda_smoke.volt"
FIXTURE = ROOT / "tests" / "fixtures" / "cuda_driver.c"
MARKER = "CUDA PTX smoke passed: 19 + 23 = 42\n"
CREATE = "init\ncount\ncontext\nalloc\nHtoD\nmodule\nlaunch\n"
CLEANUP = "unload\nfree\ndestroy\ndlclose\n"


class CudaIntegration(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        directory = tempfile.TemporaryDirectory(prefix="volt-cuda-")
        cls.addClassCleanup(directory.cleanup)
        cls.tmp = Path(directory.name)
        cls.demo = cls.tmp / "cuda-smoke"
        subprocess.run([ROOT / "volt", DEMO, "-o", cls.demo], cwd=ROOT, check=True, timeout=30)

    def fixture(self, directory, define=None, preload=False):
        cc = shutil.which("cc")
        if not cc:
            self.skipTest("CUDA driver fixture requires a C compiler (not nvcc)")
        path = self.tmp / directory
        path.mkdir(exist_ok=True)
        lib = path / ("unavailable.so" if preload else "libcuda.so.1")
        if not lib.exists():
            options = [f"-D{define}"] if define else []
            subprocess.run([cc, "-std=c11", "-Wall", "-Wextra", "-Werror", "-shared", "-fPIC",
                            *options, FIXTURE, "-o", lib], check=True, timeout=15)
        return {"LD_PRELOAD": str(lib)} if preload else {"LD_LIBRARY_PATH": str(path)}

    def run_smoke(self, **overrides):
        env = {**os.environ, "CUDA_CACHE_DISABLE": "1", **overrides}
        return subprocess.run([self.demo], cwd=self.tmp, env=env, capture_output=True,
                              text=True, timeout=25)

    def check_result(self, result, code, stdout, stderr):
        self.assertEqual((result.returncode, result.stderr), (code, stderr), result.stdout)
        self.assertIn(stdout, result.stdout)
        if code != 0:
            self.assertNotIn(MARKER, result.stdout)

    def test_driver_unavailable(self):
        result = self.run_smoke(**self.fixture("absent", "VOLT_TEST_CUDA_NO_LIBRARY", preload=True))
        self.check_result(result, 77, "libcuda.so.1 could not be loaded", "")

    def test_incomplete_driver_closes_without_init(self):
        result = self.run_smoke(**self.fixture("incomplete", "VOLT_TEST_CUDA_MISSING_SYMBOL"))
        self.check_result(result, 1, "missing required Driver API symbols", "dlclose\n")

    def test_no_device_status_and_zero_device_count(self):
        env = self.fixture("driver")
        for mode, trace in [("no-device", "init\ndlclose\n"),
                            ("zero-devices", "init\ncount\ndlclose\n")]:
            with self.subTest(mode=mode):
                result = self.run_smoke(**env, VOLT_TEST_CUDA_MODE=mode)
                self.check_result(result, 77, "CUDA_ERROR_NO_DEVICE", trace)

    def test_sysv_arguments_and_resource_order(self):
        env = self.fixture("driver")
        result = self.run_smoke(**env, VOLT_TEST_CUDA_MODE="success")
        self.check_result(result, 0, MARKER, CREATE + "sync\nDtoH\n" + CLEANUP)
        self.assertIn("CUDA device: fixture GPU", result.stdout)

    def test_launch_failure_still_cleans_up(self):
        result = self.run_smoke(**self.fixture("driver"), VOLT_TEST_CUDA_MODE="launch-fails")
        self.check_result(result, 1, "cuLaunchKernel failed: 701 CUDA_ERROR_LAUNCH_OUT_OF_RESOURCES",
                          CREATE + CLEANUP)

    def test_cleanup_error_does_not_skip_later_releases(self):
        result = self.run_smoke(**self.fixture("driver"), VOLT_TEST_CUDA_MODE="free-fails")
        self.check_result(result, 1, "cuMemFree_v2 failed: 1 CUDA_ERROR_INVALID_VALUE",
                          CREATE + "sync\nDtoH\n" + CLEANUP)

    @unittest.skipUnless(os.environ.get("VOLT_CUDA_GPU") == "1", "set VOLT_CUDA_GPU=1 for real GPU")
    def test_real_driver_ptx_round_trip(self):
        self.check_result(self.run_smoke(), 0, MARKER, "")


if __name__ == "__main__":
    unittest.main()
