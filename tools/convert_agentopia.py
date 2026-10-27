"""Convert the supplied Agentopia sources without modifying the original TeX.

Run explicitly to regenerate this paper's Quarto entries and shared Markdown.
"""
from pathlib import Path
import json
import re

from convert_papers import argument, markdown, uncomment

root = Path(__file__).resolve().parents[1]
paper = root / 'arXiv-2606.07513v1'
source = uncomment((paper / 'main.tex').read_text(encoding='utf-8'))
preamble = source.split(r'\begin{document}')[0]


def expand_inputs(text):
    return re.sub(r'\\input\{([^}]+)\}',
                  lambda m: expand_inputs(uncomment((paper / (m[1] + '.tex')).read_text(encoding='utf-8'))), text)


def normalize_labels(text):
    def normalized(label):
        label = label.replace(':', '-').replace('_', '-')
        return 'sec-' + label[4:] if label.startswith('app-') else label
    return re.sub(r'\\(label|ref|eqref|[cC]ref)\{([^}]+)\}',
                  lambda m: '\\' + m[1] + '{' + ','.join(normalized(x.strip()) for x in m[2].split(',')) + '}', text)


macros = r'''
\newcommand{\method}{Agentopia\xspace}
\newcommand{\eg}{\textit{e.g.}}
\newcommand{\etc}{\textit{e.t.c.}}
\newcommand{\ie}{\textit{i.e.}}
\newcommand{\vs}{\textit{v.s.}}
\newcommand{\wo}{\textit{w/o}}
\newcommand{\dq}[1]{``#1''}
\newcommand{\sq}[1]{`#1'}
\newcommand{\apartment}{\textbf{The Apartment}\xspace}
\newcommand{\campus}{\textbf{The Campus}\xspace}
\newcommand{\academy}{\textbf{Arcane Academy}\xspace}
\newcommand{\cmark}{\ding{51}}
\newcommand{\xmark}{\ding{55}}
\definecolor{mygray}{RGB}{226,226,226}
\definecolor{myred}{RGB}{252,142,142}
\definecolor{mygreen}{RGB}{147,255,143}
\definecolor{myblue}{RGB}{144,155,255}
\definecolor{myyellow}{RGB}{253,253,143}
\definecolor{mypurple}{RGB}{255,142,250}
'''.strip()


def prose(tex):
    # Editorial shortcuts are expanded by Pandoc's LaTeX reader, not discarded.
    for name, value in [('method', 'Agentopia'), ('apartment', r'\textbf{The Apartment}'),
                        ('campus', r'\textbf{The Campus}'), ('academy', r'\textbf{Arcane Academy}')]:
        tex = re.sub(r'\\' + name + r'\b(?:\{\})?', lambda m: value, tex)
    return markdown(macros + '\n' + tex, paper)


counts = {'tables': 0, 'figures': 0, 'equations': 0}


def convert(text):
    text = normalize_labels(expand_inputs(text))
    protected = []

    def protect(value):
        token = f'AGENTOPIABLOCK{len(protected)}END'
        protected.append(value)
        return '\n\n' + token + '\n\n'

    def figure(m):
        value = m[0]
        caption, label = prose(argument(value, 'caption')), argument(value, 'label')
        images = re.findall(r'\\includegraphics(?:\[[^\]]*\])?\{([^}]+)\}', value)
        counts['figures'] += 1
        if images:
            for image in images:
                assert (paper / image).is_file(), image
            if len(images) == 1:
                width = re.search(r'width=([\d.]+)\\textwidth', value)
                percent = float(width[1]) * 100 if width else 100
                placement = ' fig-pos="H"' if counts['figures'] == 1 else ''
                return protect(f'![{caption}]({images[0]}){{#{label} width="{percent:g}%"{placement}}}')
            content = '\n\n'.join(f'![]({image}){{width="100%"}}' for image in images)
        else:
            verbatim = re.search(r'\\begin\{verbatim\}([\s\S]*?)\\end\{verbatim\}', value)
            if not verbatim:
                raise ValueError('Unsupported figure: ' + value[:120])
            content = '```text\n' + verbatim[1].strip('\n') + '\n```'
        return protect(f'::: {{#{label} layout-ncol="1"}}\n\n{content}\n\n{caption}\n\n:::')

    text = re.sub(r'\\begin\{figure\*?\}(?:\[[^\]]*\])?[\s\S]*?\\end\{figure\*?\}', figure, text)

    def table(m):
        counts['tables'] += 1
        value = m[0].strip()
        # lwarp's multirow line-break handler recurses inside shortstack. Use
        # the column's explicit paragraph width and ordinary line breaks.
        width = re.search(r'\\begin\{tabular\}\{p\{([^}]+)\}', value)
        for match in reversed(list(re.finditer(r'\\multirow\{(\d+)\}\{\*\}\{\\shortstack(?:\[[^]]*\])?\{', value))):
            start, pos, depth = match.end(), match.end(), 1
            while depth:
                escaped = (pos - len(value[:pos].rstrip('\\'))) % 2 == 1
                if value[pos] == '{' and not escaped: depth += 1
                if value[pos] == '}' and not escaped: depth -= 1
                pos += 1
            assert width and value[pos] == '}'
            content = value[start:pos - 1].replace('\\\\', '\\newline ')
            value = value[:match.start()] + '\\multirow{' + match[1] + '}{' + width[1] + '}{' + content + '}' + value[pos + 1:]
        # These source tables use first-column multirows. lwarp requires inert
        # continuation markers in the covered cells; retain the actual layout.
        def mark_rows(group):
            count = int(group[1])
            seen = 0
            def cell(cell_match):
                nonlocal seen
                seen += 1
                return cell_match[0] if seen == 1 else cell_match[1] + r'\mrowcell &'
            content = re.sub(r'(?m)^([ \t]*)&', cell, group[0])
            assert seen == count, (count, seen, group[0][:100])
            return content
        value = re.sub(r'\\multirow\{(\d+)\}[\s\S]*?(?=\\midrule|\\bottomrule)', mark_rows, value)
        return protect('```{=latex}\n' + value + '\n```')

    text = re.sub(r'\\begin\{(table\*?)\}(?:\[[^\]]*\])?[\s\S]*?\\end\{\1\}', table, text)

    def equation(m):
        counts['equations'] += 1
        env, body = m[1], m[2].strip()
        label = argument(body, 'label')
        body = re.sub(r'\\label\{[^}]+\}', '', body)
        if env.startswith('align'):
            body = '\\begin{aligned}\n' + body + '\n\\end{aligned}'
        if not env.endswith('*'):
            label = label or f'eq-agentopia-{counts["equations"]}'
        return protect('$$\n' + body + '\n$$' + (' {#' + label + '}' if label else ''))

    text = re.sub(r'\\begin\{(equation\*?|align\*?)\}([\s\S]*?)\\end\{\1\}', equation, text)
    # Inline enumerations have no direct Markdown equivalent; preserve all items
    # as a normal ordered list instead of losing the original custom environment.
    text = re.sub(r'\\begin\{inparaenum\}(?:\[[^\]]*\])?', r'\\begin{enumerate}', text)
    text = text.replace(r'\end{inparaenum}', r'\end{enumerate}')
    text = re.sub(r'\\(?:clearpage|newpage)\b', '', text)
    text = re.sub(r'\\[cC]ref\{([^}]+)\}', lambda m: ', '.join('\\ref{' + x.strip() + '}' for x in m[1].split(',')), text)
    result = prose(text)
    for i, value in enumerate(protected):
        result = result.replace(f'AGENTOPIABLOCK{i}END', value)
    result = re.sub(r'\[(?:\\\[[^\n]*?\\\]|[^\]\n]*)\]\(#[^)]*\)\{reference-type="(?:ref|eqref)" reference="([^"]+)"\}',
                    lambda m: '\\ref{' + m[1] + '}', result)
    assert 'AGENTOPIABLOCK' not in result
    return result + '\n'


parts = ['1_intro', '2_related', '3_framework', '4_method', '5_experiments', '6_conclusion', 'appendix']
converted = []
for part in parts:
    original = uncomment((paper / f'Sections/{part}.tex').read_text(encoding='utf-8'))
    content = convert(original)
    # Pandoc restarts footnote IDs for each input; namespace them before the
    # sections are included together so footnotes cannot overwrite each other.
    content = re.sub(r'\[\^(\d+)\]', lambda m: '[^' + part + '-' + m[1] + ']', content)
    converted.append(content)
    (paper / f'Sections/{part}.md').write_text(content, encoding='utf-8')
abstract = expand_inputs(re.search(r'\\begin\{abstract\}([\s\S]*?)\\end\{abstract\}', preamble)[1])
abstract = abstract.replace(r'\textbf{Abstract:}', '').strip()
(paper / 'Sections/0_abstract.md').write_text(prose(abstract) + '\n', encoding='utf-8')

authors = re.findall(r'\\author\[\d+\]\{([^}]+)\}', preamble)
title = 'Agentopia: Long-Term Life Simulation and Learning in Agent Societies'
html = '---\ntitle: ' + json.dumps(title) + '\nauthor: ' + json.dumps(', '.join(authors)) + '''
filters: [html-tex]
bibliography: main.bib
format:
  html:
    theme: cosmo
    toc: true
    number-sections: true
    css: styles.css
    html-tex:
      caption-prefix: "Table "
      caption-sep: ": "
      latex-packages: [amsmath, amssymb, graphicx, xcolor, booktabs, colortbl, pifont, multirow, makecell, tabularx, arydshln, xspace]
      latex-macros: |
''' + ''.join('        ' + line + '\n' for line in macros.splitlines()) + '---\n\n'
includes = '\n\n'.join('{{< include Sections/' + part + '.md >}}' for part in parts)
html += '::: {.callout-note appearance="simple" icon="false"}\n## Abstract\n\n{{< include Sections/0_abstract.md >}}\n\n:::\n\n' + includes + '\n'
(paper / 'index.qmd').write_text(html, encoding='utf-8')

# The original class captures abstract and author metadata before maketitle.
# Keep that preamble and title machinery, with shared Markdown as the body.
template = preamble.replace(r'\usepackage{color-edits}', '')
template = '\\PassOptionsToPackage{inline,shortlabels}{enumitem}\n' + template
template += r'''
\providecommand{\tightlist}{\setlength{\itemsep}{0pt}\setlength{\parskip}{0pt}}
\providecommand{\passthrough}[1]{#1}
\providecommand{\pandocbounded}[1]{#1}
\providecommand{\mrowcell}{}
\providecommand{\mcolrowcell}{}
\usepackage{float}
$for(header-includes)$
$header-includes$
$endfor$
\begin{document}
\maketitle
$body$
\end{document}
'''
template = template.replace('$', '$$').replace('$$for(header-includes)$$', '$for(header-includes)$').replace('$$header-includes$$', '$header-includes$').replace('$$endfor$$', '$endfor$').replace('$$body$$', '$body$')
(paper / 'quarto-template.tex').write_text(template, encoding='utf-8')
pdf = '''---
filters: [pdf-helper, pdf-layout.lua]
bibliography: main.bib
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

'''
pdf += '\n\n'.join('{{< include Sections/' + part + '.md >}}' for part in parts[:-1])
pdf += '\n\n```{=latex}\n\\bibliography{main}\n\\clearpage\n\\appendix\n```\n\n{{< include Sections/appendix.md >}}\n'
(paper / 'paper.qmd').write_text(pdf, encoding='utf-8')
(paper / 'styles.css').write_text('main { max-width: 1040px; }\nfigure embed { width: 100%; }\n.quarto-float { margin: 1.75rem 0; }\npre { overflow-x: auto; }\n', encoding='utf-8')
full_source = normalize_labels(expand_inputs(source))
original_labels = set(re.findall(r'\\label\{([^}]+)\}', full_source))
generated = '\n'.join(converted)
generated_labels = {a or b for a, b in re.findall(r'\\label\{([^}]+)\}|\{#([^ }]+)', generated)}
assert original_labels <= generated_labels, sorted(original_labels - generated_labels)
assert set(re.findall(r'\\ref\{([^}]+)\}', generated)) <= generated_labels
footnotes = re.findall(r'(?m)^\[\^([^]]+)\]:', generated)
assert len(footnotes) == len(set(footnotes)), 'Duplicate footnote IDs'
print('Agentopia:', counts)
