# Berkeley report style

This directory contains the class and example manuscript extracted from the source distribution of
Agentopia (arXiv:2606.07513v1). It is not a verified official Berkeley template.
The class file is preserved byte-for-byte from the paper distribution.

Its header attributes the style to UC Berkeley RAIL contributors and describes
it as a modification of the Google DeepMind technical report template. The same
header declares Creative Commons Attribution-ShareAlike 4.0 International
(CC BY-SA 4.0); retain these attribution and license statements when reusing it.

From a paper directory alongside `styles/`, load the class with:

```tex
\documentclass[11pt,letterpaper]{../styles/berkeley/berkeley}
```

Generic package and font dependencies come from the TeX distribution. The optional
`logo` option references `assets/berkeley_logo`, which was not included in the
supplied paper files and is not enabled by Agentopia. No logo is fabricated here.

## Example manuscript

`main.tex`, `Sections/*.tex`, `Tables/*.tex`, `Figures/`, `main.bib` and
`00README.json` retain the original Agentopia example manuscript and its local
resources. Compile it with this directory as the working directory. Its class
name is again simply `berkeley`, and its original input/resource paths are kept.
This is a paper-derived example, not an official publisher's blank manuscript.

Figures and bibliography were copied because the Quarto paper still uses them;
subsequent edits to the paper do not automatically update this archived example.
The archive retains the original source's dependencies and optional commands;
it does not supply the missing optional logo assets mentioned above.

The active Quarto paper remains in `arXiv-2606.07513v1/`. Its `example.tex` is the
PDF adapter and loads the shared class here. Translated Markdown, `abstract.yml`,
Chinese-font settings and table-body fitting belong to that active paper, rather
than this example manuscript.
