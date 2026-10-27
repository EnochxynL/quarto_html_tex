"""Run with Python; requires an unmodified Quarto installation on PATH."""
from pathlib import Path
import shutil
import subprocess
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
for document in ("basic.qmd", "numbering.qmd", "example.qmd", "book"):
    subprocess.run([quarto, "render", document, "--to", "html"], cwd=root, check=True)

# Lua assertions in lookup.lua verify exact numbers, unknown targets, argument
# validation, forward lookup, subreferences and detached return values.
# Also verify that the independently rendered native references agree.
for name, expected in (
    ("basic", "1, I, 1.1, 1, 2 (a), 1, 1."),
    ("numbering", "3, 3.x, 3.y (i)."),
):
    parser = Text()
    parser.feed((root / (name + ".html")).read_text(encoding="utf-8"))
    text = " ".join("".join(parser.parts).split())
    assert "Native references: " + expected in text, name + ": native numbers differ"

example = (root / "example.html").read_text(encoding="utf-8")
assert 'href="#fig-example">1</a>' in example
book = (root / "book/_book/index.html").read_text(encoding="utf-8")
assert "appendix.html#tbl-appendix" in book
parser = Text()
parser.feed(book)
assert "Table A.1" in " ".join("".join(parser.parts).split())
print("Crossref Query: all regression checks passed")
