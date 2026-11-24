#!/usr/bin/env python3
"""Measure compile time, not the execution time of the resulting program."""
import argparse
from pathlib import Path
import statistics
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parents[1]
WORKLOADS = ("browser/browser.volt", "compiler/volt_main.volt")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", default=ROOT / "volt", type=Path)
    parser.add_argument("--against", type=Path, help="alternate with this baseline compiler")
    parser.add_argument("--warmups", default=1, type=int)
    parser.add_argument("--repeats", default=5, type=int)
    args = parser.parse_args()
    if args.warmups < 0 or args.repeats < 1:
        parser.error("warmups must be >= 0 and repeats >= 1")
    compilers = [args.compiler.resolve()]
    if args.against:
        compilers.insert(0, args.against.resolve())
    with tempfile.TemporaryDirectory(prefix="volt-compiler-bench-") as directory:
        for source in WORKLOADS:
            samples = [[] for _ in compilers]
            outputs = [Path(directory) / f"out-{i}" for i in range(len(compilers))]
            for step in range(args.warmups + args.repeats):
                # Alternate which compiler goes first to reduce ordering bias.
                order = range(len(compilers)) if step % 2 == 0 else reversed(range(len(compilers)))
                for i in order:
                    start = time.perf_counter()
                    result = subprocess.run([str(compilers[i]), source, "-o", str(outputs[i]), "--quiet"],
                                            cwd=ROOT, capture_output=True, text=True, timeout=60)
                    elapsed = time.perf_counter() - start
                    if result.returncode:
                        raise SystemExit(result.stderr or result.stdout or f"{compilers[i]} failed")
                    if step >= args.warmups:
                        samples[i].append(elapsed)
            for compiler, measurements in zip(compilers, samples):
                print(f"{source} ({compiler}): median {statistics.median(measurements):.3f} s; "
                      f"range {min(measurements):.3f}–{max(measurements):.3f} s")
            if len(outputs) == 2:
                ratio = statistics.median(samples[0]) / statistics.median(samples[1])
                print(f"  baseline/current: {ratio:.3f}×; "
                      f"ELF byte-identical: {outputs[0].read_bytes() == outputs[1].read_bytes()}")


if __name__ == "__main__":
    main()
