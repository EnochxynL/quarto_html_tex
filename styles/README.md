# Shared LaTeX styles

The downloaded template directories are kept unchanged. Paper-specific metadata,
macros, and Quarto compatibility adjustments belong in each paper's QMD or
`example.tex`, not in these upstream files.

| Paper | Shared style | Source |
| --- | --- | --- |
| TD-MPC | `icml2022/icml2022.sty` and `.bst` | [ICML 2022](https://icml.cc/Conferences/2022/StyleAuthorInstructions) |
| Whole-body motion imitation | `ieeeconf/ieeeconf.cls` | [PaperCept](https://controls.papercept.net/conferences/support/tex.php) |
| Ara | `icml2026/icml2026.sty` and `.bst` | [ICML 2026](https://icml.cc/Conferences/2026/AuthorInstructions) |
| SkillOpt | `microsoft-tech-report-1.0/microsoft-tech-report.sty` | [Unofficial Microsoft report template](https://github.com/lhmd/microsoft-tech-report) |
| Agentopia | `berkeley/berkeley.cls` | Extracted from the Agentopia source distribution; see [provenance](berkeley/README.md) |
| SuperMimic | `corl_2026_template_cameraready/corl_2026.sty` | [CoRL 2026](https://2026.corl.org/contributions/instruction-for-authors) |

The paper adapters load these files through paths relative to each paper
directory. SuperMimic's standalone TikZ preamble uses the same CoRL style.
Generic packages such as `algorithm` and `fancyhdr` are provided by the installed
TeX distribution, rather than duplicated in paper directories.

SkillOpt uses the report template's newer `microsoft...` interfaces. Its QMD
sets the report identity and logo, supplies the run-in paragraph adaptation,
and disables Quarto's duplicate bibliography configuration so the style can load
natbib with its own options. The upstream style remains unmodified.

Agentopia uses the paper-supplied class under `berkeley/`, alongside its original
TeX manuscript and resources retained as an example. This is an extraction,
not a verified official template download; its original class header and declared
CC BY-SA 4.0 license are preserved. The shared template example manuscripts are
references, not entries in the root Quarto render list. Keep licenses and notices.
