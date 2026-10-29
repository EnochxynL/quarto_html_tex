# Paper previews

Each paper has an HTML entry (`index.qmd`) and a PDF entry sharing Markdown
content under `sections/` (or Agentopia's `Sections/`). All six papers load their
publisher or report styles from the root `styles/` directory; see
[the style mapping](styles/README.md). Their unused original TeX manuscripts,
submission metadata, and duplicate style files have been removed. Generated
`paper.tex` are build artifacts, not editable source documents.

| Paper | HTML | PDF | Word experiment |
| --- | --- | --- | --- |
| TD-MPC (2203.04955v2) | [Preview](build/arXiv-2203.04955v2/index.html) | [PDF](build/arXiv-2203.04955v2/paper.pdf) | [DOCX](build/arXiv-2203.04955v2/report.docx) |
| Whole-body motion imitation (2508.00362v1) | [Preview](build/arXiv-2508.00362v1/index.html) | [PDF](build/arXiv-2508.00362v1/paper.pdf) | [DOCX](build/arXiv-2508.00362v1/report.docx) |
| Agent-native research artifacts (2604.24658v3) | [Preview](build/arXiv-2604.24658v3/index.html) | [PDF](build/arXiv-2604.24658v3/paper.pdf) | [DOCX](build/arXiv-2604.24658v3/report.docx) |
| SkillOpt (2605.23904v2) | [Preview](build/arXiv-2605.23904v2/index.html) | [PDF](build/arXiv-2605.23904v2/paper.pdf) | [DOCX](build/arXiv-2605.23904v2/report.docx) |
| Agentopia (2606.07513v1) | [Preview](build/arXiv-2606.07513v1/index.html) | [PDF](build/arXiv-2606.07513v1/paper.pdf) | [DOCX](build/arXiv-2606.07513v1/report.docx) |
| SuperMimic (2610.28480v1) | [Preview](build/arXiv-2610.28480v1/index.html) | [PDF](build/arXiv-2610.28480v1/paper.pdf) | [DOCX](build/arXiv-2610.28480v1/report.docx) |

From the workspace root, run `quarto render` to render twelve HTML/PDF outputs,
six experimental Word reports, and three additional Word template comparisons.
Quarto, a TeX distribution, and the external tools documented in
`_extensions/html-tex/README.md` must be available. HTML/PDF do not require Python.
Word additionally uses uv and locked Python helpers; see
[`docx-tex`](_extensions/docx-tex/README.md).
To render one entry, use `quarto render arXiv-2610.28480v1/index.qmd --to html`
or `quarto render arXiv-2610.28480v1/paper.qmd --to pdf`.
For the Word experiment, use `quarto render arXiv-2508.00362v1/report.qmd --to docx`.
It uses the NEU journal reference DOCX, native OMML equations, editable tables,
and rasterized PDF/SVG figures. The same content and metadata also generate
`report-modern.docx`, `report-classic.docx`, and `report-bachelor.docx`; see
[`report-word.md`](arXiv-2508.00362v1/report-word.md) for scope.
The Word extension carries byte-identical copies of the HTML TeX backend;
HTML5/CSS normalization and Pandoc's HTML reader adapt its output for DOCX.
Word uses reference styles, not the HTML stylesheet, and complete thesis
front-matter assembly and journal multi-column sections are not implemented.

Run `quarto render tests/docx-tex/fixture.qmd --to docx --profile word-test`
for the block-only citation/algorithm/nested-table regression. After the Word
matrix is built, `uv run --no-project python scripts/check_docx_tex.py` records
structural validation under `build/word-validation.json`. On Windows,
`scripts/export-word-previews.ps1` exports read-only Word PDF previews.
The implementation, checks, visual scope and remaining limits are recorded in
[`docs/word-experiment.md`](docs/word-experiment.md).
Outputs are collected under `build/arXiv-*/`. Quarto places HTML, PDF, and their
web resources there. The post-render script `scripts/collect-build.js` archives
retained TeX, auxiliary files, and html-tex's lwarp/TikZ/PDF-image diagnostics
under the same paper directory after compilation. Compilation still runs with
the source paper directory as its working directory, preserving relative paths
to figures and shared styles. Quarto's own root `.quarto/` project state stays
in place. The build directory is ignored by Git.

The existing `render-report.json` records earlier development validation;
normal Quarto rendering does not update it.

The PDF entries retain the paper-specific Quarto template adapters where needed.
TD-MPC's algorithm syntax is migrated from `algorithmic` to `algpseudocode` in the
shared body, since lwarp does not support the old package. The humanoid paper's supplied bibliography
is preserved as `bibliography.tex` for PDF and as CSL records in `references.json`
for HTML; no missing bibliographic metadata is invented.

Paper tables use raw LaTeX shared between the original PDF templates and the
`html-tex` lwarp path. PDF entries do not require a table-conversion extension;
Agentopia defines its table sizing in `example.tex`. Ara's five former
Markdown tables retain their content, captions and exact labels as LaTeX tables, and
the appended HTML-conversion demonstration has been removed from the paper.
Agentopia loads the paper-supplied class from `styles/berkeley/`. Its original
TeX manuscript and local resources are archived there as an example; the active
paper retains its bibliography and figures. Shared Markdown is kept in `Sections/`;
the full case studies and prompts are included in `Sections/appendix.md`.
Its 45 raw LaTeX tables use the existing lwarp HTML path. Multirow continuation
markers are added only to the generated Markdown and are inert in PDF.
The shared tables mark their bodies with `tablebody`. The PDF template defines
this environment using `adjustbox`, constraining bodies to the available width
and 80% of the text height while leaving captions outside. HTML defines the same
environment as a transparent wrapper. No paper-local Lua filter is required.
The PDF entry uses XeLaTeX with Chinese fonts. Both entries load `abstract.yml`;
PDF uses its native abstract metadata, and HTML inserts it with the meta shortcode.
SuperMimic uses `paper.qmd` with the shared CoRL style. Its eight TikZ/PGFPlots
figures now retain drawing source in shared Markdown, with native Quarto figure
IDs and captions. `html-tex/latex/html-latex-tikz.lua` builds PDF then Cairo SVG during
HTML rendering; PDF compiles the raw drawing using the original template.
`preamble.tex` declares the independent HTML build's drawing context.
Tables and the algorithm retain their LaTeX source. Appendix objects use continuous numbering across both outputs,
instead of the original document's local `A.` counter resets. The supplied
reference list is preserved as `bibliography.tex` and complete reference text in CSL
records; no unavailable bibliographic metadata is invented.
No prebuilt `figures/quarto/` assets are required.

Local PDF-source images are converted to Cairo SVG by `html-pdf.lua` for HTML;
the PDF output retains its original images. No embedded-reader CSS is needed.

## PDF layout adapters

PDF figures prefer the top of the page or column; grouped figures keep explicit
row/column layouts. TD-MPC uses a two-column grid for the four computational-budget
panels, an explicit six-frame layout for visualizations, and a running head set
outside the title's local group.

TD-MPC explicitly places `# References {.unnumbered}` and a `#refs` Div in
`sections/body.md`, inside a `.content-visible` block with `when-format="pdf"`.
This locates the PDF bibliography before the appendix; the explicit heading supplies
its title because this insertion path does not generate one automatically. HTML
excludes this block and places its bibliography at the end, after all appendices.
Other papers do not need an explicit Markdown `# References` heading: their PDF
bibliography titles come from the LaTeX bibliography commands in their templates
or supplied bibliography text. This is a difference in our paper adapters, not a
requirement specific to TD-MPC; its insertion could later be moved to the PDF
template to keep bibliography placement out of the shared manuscript.

IEEE caption and bibliography fonts are restored after Quarto/natbib configuration.
SkillOpt uses the report template example's 11pt document size. Ara explicitly
selects Unicode Latin, Chinese and monospaced fonts and keeps CTeX from replacing
the document's font size. These adjustments belong to the paper adapters; the
shared publisher style files are unchanged.

Highlighted code blocks use the listings backend with bounded widths and line
wrapping. Ara and Agentopia's plain-text schemas use wrapped fancyvrb/fvextra
output, retaining native `\texttt` for prose code and CJK boundary handling.
Inline listings inherit the surrounding font size instead of the smaller code-block
size. Font sizes and page counts can differ between English originals and Chinese
translations; the PDFs under `assets/` provide visual references, not page-count
targets.

HTML uses explicit routes: `{=latex}` selects lwarp; `.tex-render` with `render-method="native"` selects standalone LaTeX and Cairo SVG; source remains `{=latex}`.
Drawing dependencies use `html-tex.include-in-header`; existing dark themes and
PDF style mappings are unchanged. SuperMimic uses `preamble.tex`.
