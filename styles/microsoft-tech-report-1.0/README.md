# Microsoft Tech Report LaTeX Template

A compact LaTeX template for technical reports and arXiv-style preprints.

Repository: <https://github.com/lhmd/microsoft-tech-report>

Author and maintainer: [Weijie Wang](http://lhmd.top)

This is an unofficial template. It is not affiliated with, endorsed by, or
sponsored by Microsoft.

## Quick Start

You can download this repository and upload it to Overleaf!

Copy this repository into a new Overleaf project or clone it locally, then set
`main.tex` as the main file.

```sh
tectonic --outfmt pdf main.tex
```

The example output is included as `microsoft-tech-report.pdf`.

## Common Edits

- Replace the report metadata near the top of `main.tex`.
- The default date uses `\techreportmonthyear`, which renders as `Month, Year`.
- Leave optional metadata fields empty (`{}`) to hide them.
- The title page uses `figures/microsoft.pdf` by default.
- Corresponding authors are marked with `\ddagger`; see `main.tex` for the
  `Correspondence` metadata and footnote example.
- Replace the placeholder teaser box in `main.tex` with `\includegraphics` when
  you have a real figure.
- Edit the section files under `sections/`.
- Add references to `reference.bib`.

The title-page logo row accepts multiple logos if you want to adapt the source:

```tex
\techreportlogos{%
  \techreportlogo{figures/microsoft.pdf}
  \techreportlogo{figures/partner-logo.pdf}
}
```

Use PDF logos when possible for clean rendering in Overleaf.

## Trademark Note

`figures/microsoft.pdf` contains the Microsoft logo. The template source is
licensed under LPPL, but Microsoft names and logos are trademarks of Microsoft.
Use the logo only if your use is authorized or otherwise consistent with
Microsoft's trademark and brand guidelines.

## Files

- `main.tex`: example report using the template.
- `microsoft-tech-report.sty`: reusable LaTeX style package.
- `sections/`: short placeholder section files.
- `reference.bib`: placeholder bibliography.
- `microsoft-tech-report.pdf`: compiled example output.

## License

This work is distributed under the LaTeX Project Public License, version 1.3c
or later. See `LICENSE` for the full license text and `NOTICE` for attribution
details.
