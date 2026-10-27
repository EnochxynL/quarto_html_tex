# Paper previews

Each paper has an HTML entry (`index.qmd`) and a PDF entry sharing Markdown
content under `sections/` (or the source's `Sections/`). Converted source papers
use `paper.qmd` for PDF so Quarto's intermediate `.tex` file cannot overwrite the
original `main.tex` or `root.tex`.

| Paper | HTML | PDF | PDF entry |
| --- | --- | --- | --- |
| TD-MPC (2203.04955v2) | [Preview](arXiv-2203.04955v2/index.html) | [PDF](arXiv-2203.04955v2/paper.pdf) | `paper.qmd` |
| Whole-body motion imitation (2508.00362v1) | [Preview](arXiv-2508.00362v1/index.html) | [PDF](arXiv-2508.00362v1/paper.pdf) | `paper.qmd` |
| Agent-native research artifacts (2604.24658v3) | [Preview](arXiv-2604.24658v3/index.html) | [PDF](arXiv-2604.24658v3/main.pdf) | `main.qmd` |
| SkillOpt (2605.23904v2) | [Preview](arXiv-2605.23904v2/index.html) | [PDF](arXiv-2605.23904v2/main.pdf) | `main.qmd` |
| Agentopia (2606.07513v1) | [Preview](arXiv-2606.07513v1/index.html) | [PDF](arXiv-2606.07513v1/paper.pdf) | `paper.qmd` |
| SuperMimic (2610.28480v1) | [Preview](arXiv-2610.28480v1/index.html) | [PDF](arXiv-2610.28480v1/paper.pdf) | `paper.qmd` |

From the workspace root, run `python tools/render_papers.py` to render all twelve
outputs sequentially. Quarto, MiKTeX, and Python must be available; the script
also finds their standard per-user Windows installation locations. Per-format
logs are saved in each paper directory; `render-report.json` records exit codes.
The root project's render list contains only these twelve entries. Historical
experiments under `_h2test/` and `_tbltest/` retain their old extension snapshots
and are excluded from normal paper rendering.
After rendering HTML, `python tools/check_html_refs.py` checks fragment links,
unresolved placeholders, and reference numbers against native headings/captions
and Quarto references. `python _regression/html-refs/run.py` covers the
unified reference consumer, including custom categories, subreferences, math,
literal code/comments, and missing-target diagnostics.

The newly converted PDF entries retain their original publication templates.
TD-MPC's algorithm syntax is migrated from `algorithmic` to `algpseudocode` in the
shared body, since lwarp does not support the old package. The original source
and local style files are preserved. The humanoid paper's supplied bibliography
is preserved as `bibliography.tex` for PDF and as CSL records in `references.json`
for HTML; no missing bibliographic metadata is invented.

Paper tables use raw LaTeX shared between the original PDF templates and the
`html-tex` lwarp path. PDF entries do not require a table-conversion extension;
Agentopia retains its paper-local `pdf-layout.lua` for sizing. Ara's five former
Markdown tables retain their content, captions and exact labels as LaTeX tables, and
the appended HTML-conversion demonstration has been removed from the paper.
Run `python tools/check_table_term_regression.py` to check raw table environments,
labels, caption placement and inline shortcode output in both formats.

`tools/convert_papers.py` regenerates the two new entries and bodies from their
original sources. It overwrites its generated QMD, Markdown, template, and CSS
files, so rerun it only when intentionally repeating the conversion.

Agentopia retains `berkeley.cls`, its original TeX sources, bibliography, and
figure assets. Shared Markdown sits alongside the source files in `Sections/`;
the full case studies and prompts are included in `Sections/appendix.md`.
Its 45 raw LaTeX tables use the existing lwarp HTML path. Multirow continuation
markers are added only to the generated Markdown and are inert in PDF.
The paper-local `pdf-layout.lua` constrains table bodies to the available width
and 80% of the text height, leaving room for captions on page-sized prompt tables.
The PDF entry uses XeLaTeX with Chinese fonts; its abstract is read from the same
`Sections/0_abstract.md` as HTML, so translated Markdown is used in both outputs.
`python tools/convert_agentopia.py` explicitly regenerates this paper's entries,
template, stylesheet, and Markdown from the original sources.

SuperMimic uses `paper.qmd` with the original CoRL template. Its eight TikZ/PGFPlots
figures now retain drawing source in shared Markdown, with native Quarto figure
IDs and captions. `html-tex/figure/html-tikz.lua` builds PDF then Cairo SVG during
HTML rendering; PDF compiles the raw drawing using the original template.
`figures/tikz-preamble.tex` declares the independent HTML build's drawing context.
Tables and the algorithm retain their LaTeX source. Appendix objects use continuous numbering across both outputs,
instead of the original document's local `A.` counter resets. The supplied
`root.bbl` is preserved as `bibliography.tex` and complete reference text in CSL
records; no unavailable bibliographic metadata is invented.
`python tools/convert_supermimic.py` explicitly regenerates this paper's Markdown,
entries, template, bibliography records and drawing preamble. It no longer runs
a figure compiler. No prebuilt `figures/quarto/` assets are required.
It overwrites generated files; do not run it when only rebuilding edited Markdown.
Use `python tools/render_papers.py --papers arXiv-2610.28480v1` for normal renders,
then `python tools/check_supermimic.py` to check labels, links, math compatibility,
vector assets, and PDF warnings.

`python tools/check_tikz.py` verifies native SVG generation, PDF passthrough,
forward references inside diagrams, nested plots, changed CSV inputs, and
compiler/missing-reference diagnostics.

Local PDF-source images are converted to Cairo SVG by `html-pdf.lua` for HTML;
the PDF output retains its original images. No embedded-reader CSS is needed.
`python tools/check_pdf_images.py` covers native image attributes, captions,
references, nested cells, encoded paths, explicit multi-page selection and errors.
