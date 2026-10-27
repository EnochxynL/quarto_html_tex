"""Exercise native PDF images, retained attributes, page selection and failures."""
from pathlib import Path
from html.parser import HTMLParser
import atexit
import base64
import os
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
home = Path.home()
env = os.environ.copy()
env["PATH"] = os.pathsep.join(str(home / p) for p in (
    "AppData/Local/Programs/Quarto/bin", "AppData/Local/Programs/MiKTeX/miktex/bin/x64")) + os.pathsep + env["PATH"]
quarto = str(home / "AppData/Local/Programs/Quarto/bin/quarto.exe")
data = root / ".quarto/pdf-fixture"
data.mkdir(parents=True, exist_ok=True)
tex = r'''\documentclass{article}
\usepackage{xcolor}
\usepackage[active,tightpage]{preview}
\begin{document}
\begin{preview}\color{blue}\rule{3cm}{1cm} PAGEONE\end{preview}
\begin{preview}\color{red}\rule{3cm}{1cm} PAGETWO\end{preview}
\end{document}
'''
(data / "multi.tex").write_text(tex, encoding="utf-8")
result = subprocess.run(["pdflatex", "-interaction=nonstopmode", "-halt-on-error", "multi.tex"],
                        cwd=data, env=env, capture_output=True)
assert result.returncode == 0, result.stdout[-1500:]
subprocess.run(["pdfseparate", "-f", "1", "-l", "1", "multi.pdf", "page-%d.pdf"], cwd=data, env=env, check=True)
shutil.copy2(data / "page-1.pdf", data / "source name.pdf")
if os.name != "nt":
    shutil.copy2(data / "source name.pdf", data / "source name.PDF")
stem = root / "_pdf-image-regression"
atexit.register(lambda: stem.with_suffix(".qmd").unlink(missing_ok=True))
fixture = (root / "_regression/pdf-images.qmd").read_text(encoding="utf-8")


class Images(HTMLParser):
    def __init__(self, html):
        super().__init__()
        self.images = []
        self.feed(html)

    def handle_starttag(self, tag, attrs):
        if tag == "img":
            self.images.append(dict(attrs))


def render(source, fmt, name, success=True):
    stem.with_suffix(".qmd").write_text(source, encoding="utf-8")
    result = subprocess.run([quarto, "render", stem.name + ".qmd", "--to", fmt],
                            cwd=root, env=env, capture_output=True, text=True, encoding="utf-8")
    output = result.stdout + result.stderr
    (data / (name + ".log")).write_text(output, encoding="utf-8")
    assert (result.returncode == 0) == success, (name, output[-2000:])
    return output


render(fixture, "html", "html")
html = stem.with_suffix(".html").read_text(encoding="utf-8")
images = Images(html).images
assert len(images) == 3, images
for image in images:
    assert image["src"].startswith("data:image/svg+xml;base64,")
    svg = ET.fromstring(base64.b64decode(image["src"].split(",", 1)[1]))
    assert svg.tag.endswith("svg")
first = images[0]
assert first["alt"] == "Accessible diagram", first
assert first["title"] == "Original title", first
assert "pdf-demo" in first["class"].split(), first
assert first.get("data-example") == "retained", first
assert "40" in first.get("style", "") or "40" in first.get("width", ""), first
assert images[0]["src"] == images[1]["src"], "Repeated images should reuse the same conversion"
assert 'id="fig-pdf"' in html and '<strong>Bold caption</strong>' in html
assert 'href="#fig-pdf">1</a>' in html
assert "<embed" not in html
assert "Download the original PDF" in html
assert 'href=".quarto/pdf-fixture/source%20name.pdf"' in html
assert "never-created.pdf" not in html
cache = root / ".quarto/pdf-images"
logs = [(cache / f"image-{i}.svg.log").read_text(encoding="utf-8") for i in (1, 2)]
assert all(log.count("pdftocairo\n") == 1 for log in logs)
# Independently verify the chosen page's painted color: page two is red.
svg = base64.b64decode(images[2]["src"].split(",", 1)[1]).decode("utf-8")
colors = re.sub(r"\s+", "", svg.lower())
assert "100%,0%,0%" in colors or "rgb(255,0,0)" in colors or "#ff0000" in colors, svg[:500]

before = (cache / "image-1.svg").stat().st_mtime_ns
render(fixture, "pdf", "pdf")
latex = stem.with_suffix(".tex").read_text(encoding="utf-8")
assert "page=2" in latex and "source name.pdf" in latex
assert (cache / "image-1.svg").stat().st_mtime_ns == before
fragment = fixture.replace("multi.pdf){page=2 width=50%}", "multi.pdf#page=2){width=50%}")
render(fragment, "html", "fragment")
render(fixture.replace("source%20name.pdf", "source%20name.PDF"), "html", "uppercase")
assert "explicitly select" in render(fixture.replace("page=2 ", ""), "html", "ambiguous-page", success=False)
assert "invalid PDF image page" in render(fixture.replace("page=2 ", "page=3 "), "html", "invalid-page", success=False)
assert "pdfinfo failed" in render(fixture.replace("source%20name.pdf", "missing.pdf"), "html", "missing", success=False)
# Helper copies must remain identical without introducing a shared import.
helpers = []
for name in ("html-pdf.lua", "html-tikz.lua"):
    source = (root / "_extensions/html-tex/figure" / name).read_text(encoding="utf-8")
    start = source.index("-- Keep this helper identical")
    end = source.index("\nend", source.index("  return svg", start)) + len("\nend")
    helpers.append(source[start:end])
assert helpers[0] == helpers[1]
render(fixture, "html", "final")
print("PASS: Cairo SVG, native attributes/captions/references, nested images, URL paths, page selection, visibility, PDF passthrough and identical helpers")
