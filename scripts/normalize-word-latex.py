#!/usr/bin/env python3
"""Strip the cross-reference anchor that blocks LaTeX-to-Word converters.

Quarto's LaTeX writer anchors every cross-reference target as
``\\protect\\phantomsection\\label{...}``, including inside display math.
LaTeX ignores the pair, but a tool that reads LaTeX math directly stops at the
unknown ``\\protect``: pandoc's LaTeX reader prints the equation as raw TeX and
tex2word counts it as unconverted math. Removing the anchor command keeps
``\\label{...}``, so targets still resolve while the math parses.

Only those two commands are removed; the file is otherwise rewritten byte for
byte, so line endings and encoding are preserved.

Usage:
    python scripts/normalize-word-latex.py paper.tex
    python scripts/normalize-word-latex.py paper.tex -o paper-word.tex
    python scripts/normalize-word-latex.py tests/*.tex --report
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

# \protect\phantomsection and any bare \phantomsection, with optional spacing.
ANCHOR = re.compile(r"\\protect\s*\\phantomsection|\\phantomsection")


def normalize(text: str) -> tuple[str, int]:
    """Return the text without cross-reference anchors and how many were removed."""
    return ANCHOR.subn("", text)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("files", nargs="+", type=Path, help="LaTeX files to rewrite")
    parser.add_argument("-o", "--output", type=Path,
                        help="write one result here instead of rewriting in place")
    parser.add_argument("--report", action="store_true",
                        help="print the number of anchors removed per file")
    args = parser.parse_args()

    if args.output and len(args.files) != 1:
        parser.error("--output takes exactly one input file")

    missing = [str(path) for path in args.files if not path.is_file()]
    if missing:
        print("missing input: " + ", ".join(missing), file=sys.stderr)
        return 2

    for path in args.files:
        source = path.read_bytes().decode("utf-8")
        text, removed = normalize(source)
        target = args.output or path
        target.write_bytes(text.encode("utf-8"))
        if args.report or args.output:
            print(f"{path}: {removed} anchor(s) removed -> {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
