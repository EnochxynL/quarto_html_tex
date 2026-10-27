"""Run with Python; requires an unmodified Quarto installation on PATH."""
from pathlib import Path
import shutil
import subprocess
import re
from html.parser import HTMLParser


class Text(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts = []

    def handle_data(self, text):
        self.parts.append(text)


root = Path(__file__).resolve().parent
quarto = shutil.which("quarto")
assert quarto, "Put Quarto on PATH before running this regression"
for document in ("basic.qmd", "numbering.qmd", "example.qmd", "html-ref.qmd", "book"):
    subprocess.run([quarto, "render", document, "--to", "html"], cwd=root, check=True)

# Check resolved LaTeX references independently against native references.
for name, expected in (
    ("basic", "1, I, 1.1, 1, 2 (a), 1, 1."),
    ("numbering", "3, 3.x, 3.y (i)."),
):
    parser = Text()
    parser.feed((root / (name + ".html")).read_text(encoding="utf-8"))
    text = " ".join("".join(parser.parts).split())
    assert "Native references: " + expected in text, name + ": native numbers differ"

for name, values in (
    ("basic", {"api-fig": "1", "api-table": "I", "api-section": "1.1", "api-equation": "1", "api-child": "2 (a)", "api-custom": "1", "api-theorem": "1"}),
    ("numbering", {"api-offset": "3", "api-alpha": "3.x", "api-parent": "3.y (i)"}),
):
    html = (root / (name + ".html")).read_text(encoding="utf-8")
    for identifier, expected in values.items():
        match = re.search(r'<span id="' + identifier + r'">(.*?)</span>', html, re.S)
        assert match, identifier
        text = Text()
        text.feed(match[1])
        assert "".join(text.parts) == expected, (identifier, text.parts, expected)

example = (root / "example.html").read_text(encoding="utf-8")
assert 'href="#fig-example">1</a>' in example
book = (root / "book/_book/index.html").read_text(encoding="utf-8")
assert "appendix.html#tbl-appendix" in book
parser = Text()
parser.feed(book)
assert "Table A.1" in " ".join("".join(parser.parts).split())

html = (root / "html-ref.html").read_text(encoding="utf-8")
assert "@@REF:" not in html
assert '<a href="#fig-child">3.2 (a)</a>' in html
assert '<a href="#eq-first">(3.1)</a>' in html
assert '<a href="#external-custom">7</a>' in html
assert html.count('§<a href="#sec-sub">3.1</a>') == 2
assert r'\(x_{3.1} + (3.1)\)' in html
assert r'\(z_{3.1} + (3.1)\)' in html
assert r'<pre>\ref{fig-first}</pre>' in html
assert r'<pre><!-- Literal nested comment: \ref{...}. --></pre>' in html
assert '@@HTMLREF-LITERAL:' not in html
assert r'<code>\ref{tbl-first}</code>' in html
assert r'<!-- Literal documentation: \ref{...}. -->' in html
for text in ('Forward:', 'Nested', 'List', 'Note', 'Caption with'):
    assert text in html
assert '<td><a href="#fig-first">3.1</a></td>' in html
missing = subprocess.run([quarto, "render", "missing.qmd", "--to", "html"],
                         cwd=root, capture_output=True, text=True, encoding="utf-8", check=True)
assert "[html-ref] unresolved targets: another-missing, unregistered-target" in missing.stderr
assert missing.stderr.count("[html-ref] unresolved targets:") == 1
assert 'class="unresolved-ref"' in (root / "missing.html").read_text(encoding="utf-8")
print("HTML references: all regression checks passed")
