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

From the workspace root, run `quarto render` to render all twelve outputs.
Quarto, a TeX distribution, and the external tools documented in
`_extensions/html-tex/README.md` must be available. Python is not required.
To render one entry, use `quarto render arXiv-2610.28480v1/index.qmd --to html`
or `quarto render arXiv-2610.28480v1/paper.qmd --to pdf`.
The existing `render-report.json` records earlier development validation;
normal Quarto rendering does not update it.

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
Agentopia retains `berkeley.cls`, its original TeX sources, bibliography, and
figure assets. Shared Markdown sits alongside the source files in `Sections/`;
the full case studies and prompts are included in `Sections/appendix.md`.
Its 45 raw LaTeX tables use the existing lwarp HTML path. Multirow continuation
markers are added only to the generated Markdown and are inert in PDF.
The paper-local `pdf-layout.lua` constrains table bodies to the available width
and 80% of the text height, leaving room for captions on page-sized prompt tables.
The PDF entry uses XeLaTeX with Chinese fonts; its abstract is read from the same
`Sections/0_abstract.md` as HTML, so translated Markdown is used in both outputs.
SuperMimic uses `paper.qmd` with the original CoRL template. Its eight TikZ/PGFPlots
figures now retain drawing source in shared Markdown, with native Quarto figure
IDs and captions. `html-tex/figure/html-tikz.lua` builds PDF then Cairo SVG during
HTML rendering; PDF compiles the raw drawing using the original template.
`figures/tikz-preamble.tex` declares the independent HTML build's drawing context.
Tables and the algorithm retain their LaTeX source. Appendix objects use continuous numbering across both outputs,
instead of the original document's local `A.` counter resets. The supplied
`root.bbl` is preserved as `bibliography.tex` and complete reference text in CSL
records; no unavailable bibliographic metadata is invented.
No prebuilt `figures/quarto/` assets are required.

Local PDF-source images are converted to Cairo SVG by `html-pdf.lua` for HTML;
the PDF output retains its original images. No embedded-reader CSS is needed.
