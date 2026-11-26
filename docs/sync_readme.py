#!/usr/bin/env python3
"""Embed docs/language.md in the Russian README without breaking relative links.

Documentation policy for the three READMEs (single approach):

- docs/language.md is the only canonical, hand-maintained language
  specification. READMEs never carry a manually edited copy of it.
- README.ru.md embeds the spec automatically between the
  "BEGIN/END VOLT SPEC" markers via this script (`python3 docs/sync_readme.py`
  after editing docs/language.md; `--check` verifies without writing).
- README.md (English) and README.es.md (Spanish) keep only the quick start,
  a brief feature overview and links into docs/*.md; their previous full
  hand-translated copies of the spec were removed because they drifted out
  of sync.
"""

import argparse
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
START = "<!-- BEGIN VOLT SPEC: generated from docs/language.md by docs/sync_readme.py -->\n"
END = "<!-- END VOLT SPEC -->\n"


def embedded_spec():
    spec = (ROOT / "docs/language.md").read_text(encoding="utf-8")
    lines = []
    in_code = False
    for line in spec.splitlines(keepends=True):
        if line.startswith("```"):
            in_code = not in_code
        elif not in_code:
            line = re.sub(r"^(#{1,5} )", r"#\1", line)
            line = re.sub(r"\]\((?!#|/|\w+:)([^)]+)\)",
                          lambda m: f"]({m[1][3:] if m[1].startswith('../') else 'docs/' + m[1]})", line)
        lines.append(line)
    return "".join(lines).rstrip() + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify without writing")
    args = parser.parse_args()
    readme = ROOT / "README.ru.md"
    current = readme.read_text(encoding="utf-8")
    intro, sep, rest = current.partition(START)
    if not sep or rest.count(END) != 1 or rest.count(START) != 0:
        parser.error("invalid VOLT specification markers in README.ru.md")
    _, tail = rest.split(END, 1)
    expected = intro + START + "\n" + embedded_spec() + "\n" + END + tail
    if current != expected:
        if args.check:
            parser.exit(1, "README.ru.md is out of date; run python3 docs/sync_readme.py\n")
        readme.write_text(expected, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
