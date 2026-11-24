#!/usr/bin/env python3
"""Reproducible float output workload; timing is informational, not gated."""
import argparse
import os
import statistics
import subprocess
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VCC = os.path.join(ROOT, "volt")
SOURCE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "float_output.volt")
ITERATIONS = 100_000
LINE = b"1.234567 1.000000e20\n"
EXPECTED_BYTES = ITERATIONS * len(LINE)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--warmups", type=int, default=2)
    parser.add_argument("--repeats", type=int, default=7)
    args = parser.parse_args()
    if args.warmups < 0 or args.repeats < 1:
        parser.error("warmups must be >= 0 and repeats must be >= 1")

    with tempfile.TemporaryDirectory(prefix="volt-float-bench-") as tmp:
        exe = os.path.join(tmp, "float_output")
        built = subprocess.run([VCC, SOURCE, "-o", exe], cwd=ROOT,
                               capture_output=True, text=True, timeout=30)
        if built.returncode:
            raise RuntimeError(built.stderr or built.stdout)
        # Validate exact output once; the timing runs avoid subprocess pipe overhead.
        checked = subprocess.run([exe], cwd=ROOT, stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE, timeout=30)
        if checked.returncode or checked.stdout != LINE * ITERATIONS:
            raise RuntimeError(
                f"wrong output: rc={checked.returncode}, bytes={len(checked.stdout)}"
            )

        samples = []
        for _ in range(args.warmups):
            with open(os.devnull, "wb") as sink:
                subprocess.run([exe], cwd=ROOT, stdout=sink, check=True, timeout=30)
        for _ in range(args.repeats):
            with open(os.devnull, "wb") as sink:
                start = time.perf_counter()
                subprocess.run([exe], cwd=ROOT, stdout=sink, check=True, timeout=30)
                samples.append(time.perf_counter() - start)

    median = statistics.median(samples)
    print(f"VOLT float output: {ITERATIONS:,} lines, two floats/line")
    print(f"verified bytes: {EXPECTED_BYTES:,}; formatter write calls: 2 per line (one per float)")
    print(f"median: {median * 1000:.3f} ms; range: {min(samples) * 1000:.3f}–{max(samples) * 1000:.3f} ms")
    print("timings are informational; build and correctness check excluded")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as ex:
        print(f"float benchmark failed: {ex}", file=sys.stderr)
        sys.exit(1)
