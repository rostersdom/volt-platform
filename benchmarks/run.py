#!/usr/bin/env python3
"""Repeatable VOLT execution benchmark; reports timings without flaky thresholds."""
import argparse
import os
import statistics
import subprocess
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VCC = os.path.join(ROOT, "volt")
BENCH_DIR = os.path.dirname(os.path.abspath(__file__))
WORKLOADS = [
    ("arithmetic + checked array index", "arithmetic_array.volt", "4500000\n", 1_000_000),
    ("checked string index", "string_index.volt", "18961852\n", 200_000),
    ("cached length + unsafe pointer", "string_cached.volt", "18961852\n", 200_000),
    ("string output (440,000 bytes)", "output.volt", "VOLT output benchmark\n" * 20_000, 20_000),
]


def run_checked(command, timeout):
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=timeout)
    if result.returncode != 0:
        raise RuntimeError(result.stderr or result.stdout or f"command exited {result.returncode}")
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--warmups", type=int, default=2)
    parser.add_argument("--repeats", type=int, default=7)
    args = parser.parse_args()
    if args.warmups < 0 or args.repeats < 1:
        parser.error("warmups must be >= 0 and repeats must be >= 1")

    with tempfile.TemporaryDirectory(prefix="volt-bench-") as tmp:
        for label, source, expected, iterations in WORKLOADS:
            exe = os.path.join(tmp, source.removesuffix(".volt"))
            run_checked([VCC, os.path.join(BENCH_DIR, source), "-o", exe], timeout=30)
            for _ in range(args.warmups):
                output = run_checked([exe], timeout=30)
                if output != expected:
                    raise RuntimeError(f"{source}: wrong result/output ({len(output)} chars)")

            samples = []
            for _ in range(args.repeats):
                start = time.perf_counter()
                output = run_checked([exe], timeout=30)
                samples.append(time.perf_counter() - start)
                if output != expected:
                    raise RuntimeError(f"{source}: wrong result/output ({len(output)} chars)")

            median = statistics.median(samples)
            print(f"VOLT {label} ({iterations:,} iterations/work units)")
            print(f"median: {median * 1000:.3f} ms; range: {min(samples) * 1000:.3f}–{max(samples) * 1000:.3f} ms")
            unit = "bytes/s" if source == "output.volt" else "iterations/s"
            print(f"throughput: {iterations / median:,.0f} {unit} (build time excluded)")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as ex:
        print(f"benchmark failed: {ex}", file=sys.stderr)
        sys.exit(1)
