"""Regenerate SuperMimic's Quarto sources from the original TeX (overwrites MD)."""
from pathlib import Path
import argparse
import json
import os
import re
import subprocess

from convert_papers import argument, markdown, uncomment

root = Path(__file__).resolve().parents[1]
paper = root / 'arXiv-2610.28480v1'
parser = argparse.ArgumentParser()
parser.add_argument('--build-figures', action='store_true')
args = parser.parse_args()
original = uncomment((paper / 'root.tex').read_text(encoding='utf-8'))
preamble, document = original.split(r'\begin{document}', 1)
document = document.split(r'\end{document}')[0]
plot_preamble = preamble.split(r'\title{')[0]
figure_dir = paper / 'figures/quarto'
figure_dir.mkdir(exist_ok=True)
build = paper / '.quarto/figure-build'
build.mkdir(parents=True, exist_ok=True)
figures, table_count, equation_count = [], 0, 0


def normalize(text):
    def label(value):
        value = value.replace(':', '-').replace('_', '-')
        return 'sec-' + value[4:] if value.startswith('app-') else value
    text = re.sub(r'\\(label|ref\*?|eqref|[cC]ref)\{([^}]+)\}',
                  lambda m: '\\' + m[1].rstrip('*') + '{' + label(m[2]) + '}', text)
    # The source's nested hyperref/ref points to the same section; retain the
    # visible section reference without producing nested HTML links.
    for match in reversed(list(re.finditer(r'\\hyperref\[[^]]+\]\{', text))):
        content = argument(text[match.start():], 'hyperref')
        text = text[:match.start()] + content + text[match.end() + len(content) + 1:]
    return text


def prose(tex):
    tex = re.sub(r'\\qty\{\\sim\s+([^}]+)\}', lambda m: r'$\sim$ \qty{' + m[1] + '}', tex)
    # siunitx is not a MathJax package. Plain decimal numbers need no macro;
    # raw table blocks retain siunitx and are executed by TeX/lwarp instead.
    tex = re.sub(r'\\num\{([-+]?\d+(?:\.\d+)?)\}', r'\1', tex)
    return markdown(tex, paper)


def math_units(tex):
    """Use standard math notation for siunitx calls inside MathJax formulas."""
    units = {r'\metre': r'\mathrm{m}', r'\second': r'\mathrm{s}',
             r'\hour': r'\mathrm{h}', r'\radian': r'\mathrm{rad}'}
    def number(value):
        scientific = re.fullmatch(r'([-+]?\d+(?:\.\d+)?)[eE]([-+]?\d+)', value)
        return scientific[1] + r'\times10^{' + str(int(scientific[2])) + '}' if scientific else value
    def math(match):
        content = match[1]
        content = re.sub(r'\\num\{([^}]+)\}', lambda m: number(m[1]), content)
        def quantity(m):
            if m[2] not in units:
                raise ValueError('Unmapped math unit: ' + m[2])
            return number(m[1]) + r'\,' + units[m[2]]
        content = re.sub(r'\\qty\{([^}]+)\}\{([^}]+)\}', quantity, content)
        return '$' + content + '$'
    tex = re.sub(r'(?<!\\)\$(.*?)(?<!\\)\$', math, tex, flags=re.S)
    # Render scientific notation as math rather than extracting a font-specific
    # Unicode minus from lwarp's typeset siunitx text.
    tex = re.sub(r'\\num\{([-+]?\d+(?:\.\d+)?[eE][-+]?\d+)\}',
                 lambda m: '$' + number(m[1]) + '$', tex)
    return tex


def convert(tex):
    global table_count, equation_count
    tex = normalize(uncomment(tex))
    saved = []

    def protect(value):
        token = f'SUPERMIMICBLOCK{len(saved)}END'
        saved.append(value)
        return '\n\n' + token + '\n\n'

    def figure(match):
        value = match[0]
        label = argument(value, 'label') or 'fig-teaser'
        caption = argument(value, 'caption')
        body = value.replace('\\caption{' + caption + '}', '')
        body = re.sub(r'\\label\{[^}]+\}', '', body)
        body = re.sub(r'^\\begin\{figure\}(?:\[[^]]*\])?', '', body.strip())
        body = re.sub(r'\\end\{figure\}\s*$', '', body)
        figures.append((label, body))
        # Native figures keep Quarto's caption, numbering and reference support;
        # TikZ/PGFPlots supplies the vector artwork independently of HTML.
        return protect(f'![{prose(caption)}](figures/quarto/{label}.pdf){{#{label} width="100%" fig-pos="H"}}')

    tex = re.sub(r'\\begin\{figure\}(?:\[[^]]*\])?[\s\S]*?\\end\{figure\}', figure, tex)
    tex = math_units(tex)

    def table(match):
        global table_count
        value = match[0]
        # The source places two independently captioned tables in one float.
        # Give each caption its own block so the shared counter bridge sees it.
        if value.count('\\caption{') == 2:
            split = value.index('\\vspace', value.index('\\label{'))
            first = value[:split] + '\n\\end{table}'
            second = '\\begin{table}[p]\n' + value[split:]
            table_count += 2
            return protect('```{=latex}\n' + first + '\n```') + protect('```{=latex}\n' + second + '\n```')
        table_count += 1
        return protect('```{=latex}\n' + value + '\n```')

    tex = re.sub(r'\\begin\{table\}(?:\[[^]]*\])?[\s\S]*?\\end\{table\}', table, tex)
    tex = re.sub(r'\\begin\{algorithm\}(?:\[[^]]*\])?[\s\S]*?\\end\{algorithm\}',
                 lambda m: protect('```{=latex}\n' + m[0] + '\n```'), tex)

    def equation(match):
        global equation_count
        equation_count += 1
        content = match[1].strip()
        label = argument(content, 'label') or f'eq-supermimic-{equation_count}'
        content = re.sub(r'\\label\{[^}]+\}', '', content).strip()
        return protect('$$\n' + content + '\n$$ {#' + label + '}')

    tex = re.sub(r'\\begin\{equation\}([\s\S]*?)\\end\{equation\}', equation, tex)
    tex = tex.replace(r'\phantomsection\label{par-accounting}', protect('[]{#par-accounting}'))
    result = prose(tex)
    for i, value in enumerate(saved):
        result = result.replace(f'SUPERMIMICBLOCK{i}END', value)
    result = re.sub(r'\[(?:\\\[[^\n]*?\\\]|[^\]\n]*)\]\(#[^)]*\)\{reference-type="(?:ref|eqref)" reference="([^"]+)"\}',
                    lambda m: '\\ref{' + m[1] + '}', result)
    assert 'SUPERMIMICBLOCK' not in result
    return result + '\n'


# Preserve the supplied printed bibliography. CSL records deliberately contain
# the complete reference text rather than invented structured metadata.
bbl = (paper / 'root.bbl').read_text(encoding='utf-8')
(paper / 'bibliography.tex').write_text(bbl, encoding='utf-8')
entries = re.split(r'\\bibitem(?:\[[\s\S]*?\])?\{([^}]+)\}', bbl)[1:]
records = []
for key, entry in zip(entries[::2], entries[1::2]):
    entry = entry.split(r'\end{thebibliography}')[0]
    entry = entry.replace(r'\newblock', ' ')
    entry = re.sub(r'\\doi\{([^}]+)\}', lambda m: ' https://doi.org/' + m[1], entry)
    records.append({'id': key, 'type': 'article', 'title': markdown(entry, paper, 'plain')})
assert len(records) == 28
(paper / 'references.json').write_text(json.dumps(records, ensure_ascii=False, indent=2), encoding='utf-8')
(paper / 'source-numeric.csl').write_text((root / 'arXiv-2508.00362v1/source-numeric.csl').read_text(encoding='utf-8'), encoding='utf-8')

opening = document.split(r'\begin{abstract}')[0].replace(r'\maketitle', '')
opening = re.sub(r'^\{\\makeatletter[\s\S]*?\}\s*(?=\\begin\{figure\})', '', opening.strip())
(paper / 'sections/teaser.md').write_text(convert(opening), encoding='utf-8')
abstract = re.search(r'\\begin\{abstract\}([\s\S]*?)\\end\{abstract\}', document)[1]
(paper / 'sections/abstract.md').write_text(prose(abstract) + '\n', encoding='utf-8')
parts = ['introduction', 'related-work', 'method', 'results', 'conclusion', 'appendix']
for part in parts:
    text = convert((paper / f'sections/{part}.tex').read_text(encoding='utf-8'))
    text = re.sub(r'\[\^(\d+)\]', lambda m: '[^' + part + '-' + m[1] + ']', text)
    (paper / f'sections/{part}.md').write_text(text, encoding='utf-8')
ack = argument(document, 'acknowledgments')
(paper / 'sections/acknowledgments.md').write_text('# Acknowledgments {.unnumbered}\n\n' + prose(ack) + '\n', encoding='utf-8')

macros = r'''
\sisetup{group-separator={,},group-minimum-digits=5,range-phrase={--},range-units=single,per-mode=symbol,separate-uncertainty=true,separate-uncertainty-units=single}
\definecolor{AnaFill}{RGB}{217,240,211}
\newcommand{\cmarkg}{\textcolor{green!55!black}{\checkmark}}
\newcommand{\xmarkr}{\textcolor{red!75!black}{\ding{55}}}
'''.strip()
title = 'SuperMimic: Scaling Humanoid Whole-Body Control with One Differentiable World Model'
html = '---\ntitle: ' + json.dumps(title) + '''
author: "Qiayuan Liao, Yiyang Shao, Junfeng Long, Kevin Zakka, Roberto Horowitz, Pieter Abbeel, Koushil Sreenath"
filters: [html-tex]
bibliography: references.json
csl: source-numeric.csl
number-depth: 3
format:
  html:
    theme: cosmo
    toc: true
    number-sections: true
    css: styles.css
    html-tex:
      caption-prefix: "Table "
      caption-sep: ": "
      latex-packages: [amsmath, amssymb, bm, graphicx, xcolor, colortbl, booktabs, array, siunitx, pifont, algorithm, algpseudocode]
      latex-macros: |
''' + ''.join('        ' + line + '\n' for line in macros.splitlines()) + '---\n\n'
html += '{{< include sections/teaser.md >}}\n\n::: {.callout-note appearance="simple" icon="false"}\n## Abstract\n\n{{< include sections/abstract.md >}}\n\n:::\n\n'
html += '\n\n'.join('{{< include sections/' + part + '.md >}}' for part in parts[:-1] + ['acknowledgments', 'appendix']) + '\n'
(paper / 'index.qmd').write_text(html, encoding='utf-8')

template = preamble + r'''
\usepackage{float}
\DeclareUnicodeCharacter{2212}{\ensuremath{-}}
\DeclareUnicodeCharacter{2006}{\,}
\providecommand{\tightlist}{\setlength{\itemsep}{0pt}\setlength{\parskip}{0pt}}
\providecommand{\passthrough}[1]{#1}
\providecommand{\pandocbounded}[1]{#1}
$for(header-includes)$
$header-includes$
$endfor$
\begin{document}
\maketitle
{\makeatletter\let\@footnotetext\H@@footnotetext\makeatother\renewcommand{\thefootnote}{*}\footnotetext{Equal contribution. \quad $^{\dagger}$Equal advising.}}
$body$
\end{document}
'''
template = template.replace('$', '$$')
for directive in ('for(header-includes)', 'header-includes', 'endfor', 'body'):
    template = template.replace('$$' + directive + '$$', '$' + directive + '$')
(paper / 'quarto-template.tex').write_text('\n'.join(line.rstrip() for line in template.splitlines()) + '\n', encoding='utf-8')
pdf = r'''---
filters: [pdf-helper]
bibliography: references.json
number-depth: 3
format:
  pdf:
    output-file: paper.pdf
    pdf-engine: pdflatex
    template: quarto-template.tex
    keep-tex: true
    latex-clean: false
    number-sections: true
    cite-method: natbib
    citeproc: false
    syntax-highlighting: none
---

{{< include sections/teaser.md >}}

```{=latex}
\begin{abstract}
```

{{< include sections/abstract.md >}}

```{=latex}
\end{abstract}
\keywords{Humanoid Robot, Whole-Body Control, Model-Based Reinforcement Learning}
```

'''
pdf += '\n\n'.join('{{< include sections/' + part + '.md >}}' for part in parts[:-1] + ['acknowledgments'])
pdf += '\n\n```{=latex}\n\\clearpage\n\\input{bibliography.tex}\n\\clearpage\n\\appendix\n```\n\n{{< include sections/appendix.md >}}\n'
# Keep globally unique sequential numbers in both outputs. Source-local appendix
# counter resets are intentionally not copied into the mixed Quarto document.
(paper / 'paper.qmd').write_text(pdf, encoding='utf-8')
(paper / 'styles.css').write_text('main { max-width: 1040px; }\nfigure embed { width: 100%; }\n.quarto-float { margin: 1.75rem 0; }\npre { overflow-x: auto; }\n', encoding='utf-8')

for label, body in figures:
    tex = plot_preamble + '\n\\usepackage[active,tightpage]{preview}\n\\setlength{\\PreviewBorder}{2pt}\n\\begin{document}\n\\begin{preview}\n\\begin{minipage}{\\textwidth}\n' + body + '\n\\end{minipage}\n\\end{preview}\n\\input{bibliography.tex}\n\\end{document}\n'
    (build / (label + '.tex')).write_text(tex, encoding='utf-8')
    if args.build_figures:
        env = os.environ.copy()
        env['PATH'] = str(Path.home() / 'AppData/Local/Programs/MiKTeX/miktex/bin/x64') + ';' + env['PATH']
        for run in range(2):
            with (build / (label + f'-{run}.log')).open('w', encoding='utf-8') as log:
                subprocess.run(['pdflatex', '-interaction=nonstopmode', '-halt-on-error',
                                '-jobname=' + label, '-output-directory=' + str(build), str(build / (label + '.tex'))],
                               cwd=paper, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
        (figure_dir / (label + '.pdf')).write_bytes((build / (label + '.pdf')).read_bytes())
        print('Built', label, flush=True)
print('SuperMimic:', len(figures), 'figures,', table_count, 'tables,', equation_count, 'equations,', len(records), 'references')
