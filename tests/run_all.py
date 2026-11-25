#!/usr/bin/env python3
"""Run the golden, compiler regression, and integration suites."""
import os
from pathlib import Path
import subprocess
import sys

SUITES = (
    "compiler_bootstrap", "run", "regressions", "abi_integration", "compiler_fnptr",
    "compiler_lifetimes", "compiler_buffer_borrow", "compiler_manifest",
    "compiler_sum_types", "compiler_modules", "compiler_ownership", "compiler_slice_borrows",
    "compiler_eq_constraint", "compiler_c_struct", "vstd_text_view",
    "compiler_debug", "compiler_fuzz", "vstd_io", "vstd_arena", "vstd_threads", "vstd_channel",
    "http_integration", "sdl_integration",
    "browser_navigation", "browser_navigation_controller", "browser_https",
    "browser_launch", "volt_launcher_integration", "browser_javascript", "browser_visual", "browser_media",
    "browser_search",
)


def main():
    tests = Path(__file__).resolve().parent
    build = subprocess.run(["make", "compiler"], cwd=tests.parent)
    if build.returncode:
        return build.returncode
    env = {**os.environ, "SDL_VIDEODRIVER": "dummy", "VOLT_COMPILER": str(tests.parent / "volt")}
    failures = []
    for suite in SUITES:
        script = suite + ".py"
        print(f"\n=== tests/{script} ===", flush=True)
        result = subprocess.run([sys.executable, str(tests / script)], cwd=tests.parent, env=env)
        if result.returncode:
            failures.append(script)
    print(f"\n{len(SUITES) - len(failures)}/{len(SUITES)} suites passed", flush=True)
    if failures:
        print("Failed: " + ", ".join(failures), file=sys.stderr)
    return int(bool(failures))


if __name__ == "__main__":
    sys.exit(main())
