# Paper previews

Each paper has an HTML entry (`index.qmd`) and a PDF entry sharing Markdown
content under `sections/` (or Agentopia's `Sections/`). All six papers load their
publisher or report styles from the root `styles/` directory; see
[the style mapping](styles/README.md). Their unused original TeX manuscripts,
submission metadata, and duplicate style files have been removed. Generated
`paper.tex` are build artifacts, not editable source documents.

| Paper | HTML | PDF | PDF entry |
| --- | --- | --- | --- |
| TD-MPC (2203.04955v2) | [Preview](build/arXiv-2203.04955v2/index.html) | [PDF](build/arXiv-2203.04955v2/paper.pdf) | `paper.qmd` |
| Whole-body motion imitation (2508.00362v1) | [Preview](build/arXiv-2508.00362v1/index.html) | [PDF](build/arXiv-2508.00362v1/paper.pdf) | `paper.qmd` |
| Agent-native research artifacts (2604.24658v3) | [Preview](build/arXiv-2604.24658v3/index.html) | [PDF](build/arXiv-2604.24658v3/paper.pdf) | `paper.qmd` |
| SkillOpt (2605.23904v2) | [Preview](build/arXiv-2605.23904v2/index.html) | [PDF](build/arXiv-2605.23904v2/paper.pdf) | `paper.qmd` |
| Agentopia (2606.07513v1) | [Preview](build/arXiv-2606.07513v1/index.html) | [PDF](build/arXiv-2606.07513v1/paper.pdf) | `paper.qmd` |
| SuperMimic (2610.28480v1) | [Preview](build/arXiv-2610.28480v1/index.html) | [PDF](build/arXiv-2610.28480v1/paper.pdf) | `paper.qmd` |

From the workspace root, run `quarto render` to render all twelve outputs.
Quarto, a TeX distribution, and the external tools documented in
`_extensions/html-tex/README.md` must be available. Python is not required.
To render one entry, use `quarto render arXiv-2610.28480v1/index.qmd --to html`
or `quarto render arXiv-2610.28480v1/paper.qmd --to pdf`.
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
IDs and captions. `html-tex/figure/html-tikz.lua` builds PDF then Cairo SVG during
HTML rendering; PDF compiles the raw drawing using the original template.
`figures/tikz-preamble.tex` declares the independent HTML build's drawing context.
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

HTML uses explicit routes: `{=latex}` selects lwarp; `{=tikz}` selects standalone LaTeX and Cairo SVG.
Drawing dependencies use `html-tex.include-in-header`; existing dark themes and
PDF style mappings are unchanged. SuperMimic uses `figures/tikz-preamble.tex`.
