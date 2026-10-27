"""Exercise native TikZ rendering, reference context, CSV inputs and failures."""
from pathlib import Path
import atexit
import base64
import json
import os
import re
import subprocess
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
home = Path.home()
env = os.environ.copy()
env["PATH"] = os.pathsep.join(str(home / p) for p in (
    "AppData/Local/Programs/Quarto/bin", "AppData/Local/Programs/MiKTeX/miktex/bin/x64")) + os.pathsep + env["PATH"]
quarto = str(home / "AppData/Local/Programs/Quarto/bin/quarto.exe")
stem = root / "_tikz-regression"
atexit.register(lambda: stem.with_suffix(".qmd").unlink(missing_ok=True))
data = root / ".quarto/tikz-fixture"
data.mkdir(parents=True, exist_ok=True)
(data / "preamble.tex").write_text("\\usepackage{tikz,pgfplots}\n\\pgfplotsset{compat=1.18}\n", encoding="utf-8")
csv = data / "data set.csv"
csv.write_text("x,y\n0,0\n1,2\n2,1\n", encoding="utf-8")
fixture = (root / "_regression/tikz.qmd").read_text(encoding="utf-8")
fixture = fixture.replace("  html: default", "  html:\n    html-tex:\n      tikz:\n        preamble-file: .quarto/tikz-fixture/preamble.tex")
fixture = fixture.replace(r"\usepackage{tikz}", r"\input{.quarto/tikz-fixture/preamble.tex}")
fixture += r'''

::: {.nested-plot}

```{=latex}
\begin{tikzpicture}
\begin{axis}[width=7cm,height=4cm]
\addplot table[x=x,y=y,col sep=comma]{.quarto/tikz-fixture/data set.csv};
\end{axis}
\end{tikzpicture}
```

:::
'''


def render(source, fmt, name, success=True):
    stem.with_suffix(".qmd").write_text(source, encoding="utf-8")
    result = subprocess.run([quarto, "render", stem.name + ".qmd", "--to", fmt],
                            cwd=root, env=env, capture_output=True, text=True, encoding="utf-8")
    (data / (name + ".log")).write_text(result.stdout + result.stderr, encoding="utf-8")
    assert (result.returncode == 0) == success, (name, result.stdout[-1500:], result.stderr[-1500:])
    return result.stdout + result.stderr


render(fixture, "html", "html")
html = stem.with_suffix(".html").read_text(encoding="utf-8")
images = re.findall(r'src="data:image/svg\+xml;base64,([^"]+)"', html)
assert len(images) == 2, len(images)
for image in images:
    svg = ET.fromstring(base64.b64decode(image))
    assert svg.tag.endswith("svg") and svg.findall(".//{http://www.w3.org/2000/svg}path")
assert 'href="#fig-tikz">1</a>' in html
assert "html-tex-tikz-pending" not in html
assert "data-html-tex-tikz=" not in html
assert "@@REF:" not in html
cache = root / ".quarto/tikz"
text = subprocess.check_output(["pdftotext", str(cache / "figure-1/figure.pdf"), "-"], env=env).decode("utf-8")
assert "Equation 1" in " ".join(text.split()), text
before = (cache / "figure-1/figure.pdf").stat().st_mtime_ns
render(fixture, "pdf", "pdf")
tex = stem.with_suffix(".tex").read_text(encoding="utf-8")
assert r"\begin{tikzpicture}" in tex
assert r"\label{fig-tikz}" in tex
assert "There were undefined references" not in stem.with_suffix(".log").read_text(encoding="utf-8", errors="replace")
assert (cache / "figure-1/figure.pdf").stat().st_mtime_ns == before, "PDF should not invoke the HTML compiler"

old_svg = re.findall(r'src="data:image/svg\+xml;base64,([^"]+)"', html)[1]
csv.write_text("x,y\n0,0\n1,8\n2,1\n", encoding="utf-8")
render(fixture, "html", "changed-data")
changed_html = stem.with_suffix(".html").read_text(encoding="utf-8")
assert re.findall(r'src="data:image/svg\+xml;base64,([^"]+)"', changed_html)[1] != old_svg, "Changed CSV must invalidate the drawing"
bad_tex = fixture.replace(r"\draw[->,thick]", r"\thisCommandDoesNotExist\draw[->,thick]", 1)
assert "html-tikz" in render(bad_tex, "html", "bad-tex", success=False)
bad_ref = fixture.replace(r"Equation \ref{eq-target}", r"Equation \ref{not-a-real-target}")
assert "unresolved drawing references" in render(bad_ref, "html", "bad-reference", success=False)
render(fixture, "html", "final")
(data / "references.json").write_text(json.dumps([
    {"id": key, "type": "article-journal", "title": key,
     "author": [{"family": key}], "issued": {"date-parts": [[2025]]}}
    for key in ("Alpha", "Beta", "Gamma")
]), encoding="utf-8")
(data / "numeric.csl").write_text('''<?xml version="1.0" encoding="utf-8"?>
<style xmlns="http://purl.org/net/xbiblio/csl" version="1.0" class="in-text">
<info><title>TikZ test</title><id>https://example.org/tikz-test</id><updated>2026-10-27T00:00:00Z</updated></info>
<citation><layout prefix="[" suffix="]" delimiter=", "><group delimiter=", ">
<text variable="citation-number"/><text variable="locator" prefix="p. "/>
</group></layout></citation>
<bibliography><layout><text variable="title"/></layout></bibliography>
</style>''', encoding="utf-8")
cited = fixture.replace("number-sections: true", "number-sections: true\n"
    "bibliography: .quarto/tikz-fixture/references.json\n"
    "csl: .quarto/tikz-fixture/numeric.csl")
cited = cited.replace("Forward:", "First citation [@Alpha].\n\nForward:")
cited = cited.replace(r"Equation \ref{eq-target}",
    r"Equation \ref{eq-target}; Source \cite[see][p.~7]{Gamma}")
cited += "\nLater citation [@Beta]. Repeat drawing source [@Gamma].\n"
render(cited, "html", "citations")
drawing_text = subprocess.check_output(["pdftotext", str(cache / "figure-1/figure.pdf"), "-"], env=env).decode("utf-8")
assert "[see 2, p. 7]" in " ".join(drawing_text.split()), drawing_text
cited_html = stem.with_suffix(".html").read_text(encoding="utf-8")
assert 'data-html-tex-tikz-citation' not in cited_html
assert re.search(r'href="#ref-Gamma"[^>]*>2</a>', cited_html), "Drawing and body must share citation 2"
assert re.search(r'href="#ref-Beta"[^>]*>3</a>', cited_html), "Drawing citation must participate in parent order"
assert "unresolved drawing citation" in render(cited.replace("{Gamma}", "{MissingCitation}"), "html", "bad-citation", success=False)
render(fixture, "html", "final")
print("PASS: native SVG, PDF passthrough, forward numbers, shared citation order/CSL, nested CSV, visibility, data changes and failure diagnostics")
