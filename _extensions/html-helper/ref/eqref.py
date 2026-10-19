#!/usr/bin/env python3
"""Resolve lwarp equation placeholders using Quarto's final equation tags."""
import os
from pathlib import Path
import re
import sys


def process(path):
    path = Path(path)
    if path.suffix.lower() != '.html' or not path.exists():
        return
    html = path.read_text(encoding='utf-8')
    numbers = dict(re.findall(r'<span id="(eq-[^"]+)">(?:(?!<span id="eq-).)*?\\tag\{([^}]+)\}', html, re.S))
    changed, count = re.subn(r'\[(eq-[\w-]+)\]', lambda m: numbers.get(m[1], m[0]), html)
    if changed != html:
        path.write_text(changed, encoding='utf-8')
        print(f'eqref: {path}: resolved equation placeholders ({count} candidates)')


if __name__ == '__main__':
    for filename in sys.argv[1:] or os.environ.get('QUARTO_PROJECT_OUTPUT_FILES', '').splitlines():
        process(filename)
