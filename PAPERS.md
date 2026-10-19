# Paper previews

Each paper has an HTML entry (`index.qmd`) and a PDF entry sharing Markdown
content under `sections/`. The two newly converted papers use `paper.qmd` for
PDF so Quarto's intermediate `.tex` file cannot overwrite the original `main.tex`.

| Paper | HTML | PDF | PDF entry |
| --- | --- | --- | --- |
| TD-MPC (2203.04955v2) | [Preview](arXiv-2203.04955v2/index.html) | [PDF](arXiv-2203.04955v2/paper.pdf) | `paper.qmd` |
| Whole-body motion imitation (2508.00362v1) | [Preview](arXiv-2508.00362v1/index.html) | [PDF](arXiv-2508.00362v1/paper.pdf) | `paper.qmd` |
| Agent-native research artifacts (2604.24658v3) | [Preview](arXiv-2604.24658v3/index.html) | [PDF](arXiv-2604.24658v3/main.pdf) | `main.qmd` |
| SkillOpt (2605.23904v2) | [Preview](arXiv-2605.23904v2/index.html) | [PDF](arXiv-2605.23904v2/main.pdf) | `main.qmd` |

From the workspace root, run `python tools/render_papers.py` to render all eight
outputs sequentially. Quarto, MiKTeX, and Python must be available; the script
also finds their standard per-user Windows installation locations. Per-format
logs are saved in each paper directory; `render-report.json` records exit codes.

The newly converted PDF entries retain their original publication templates.
TD-MPC's algorithm syntax is migrated from `algorithmic` to `algpseudocode` in the
shared body, since lwarp does not support the old package. The original source
and local style files are preserved. The humanoid paper's supplied bibliography
is preserved as `bibliography.tex` for PDF and as CSL records in `references.json`
for HTML; no missing bibliographic metadata is invented.

The Ara Markdown-table labels are preserved by the PDF filters, and its inline
terms remain inline in HTML. Run `python tools/check_table_term_regression.py`
to check table ownership, labels, captions, and shortcode output in both formats.

`tools/convert_papers.py` regenerates the two new entries and bodies from their
original sources. It overwrites its generated QMD, Markdown, template, and CSS
files, so rerun it only when intentionally repeating the conversion.
