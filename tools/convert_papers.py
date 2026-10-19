"""Convert the two original arXiv sources into shared Quarto bodies.

Run with the workspace root as the current directory. Original TeX is preserved.
"""
from pathlib import Path
import re
import subprocess
import json

ROOT = Path.cwd()
PANDOC = Path.home() / 'AppData/Local/Programs/Quarto/bin/tools/pandoc.exe'


def uncomment(text):
    text = re.sub(r'(?m)^[ \t]*%[^\n]*\n', '', text)
    return re.sub(r'(?<!\\)%[^\n]*', '', text)


def argument(text, command):
    match = re.search(r'\\' + command + r'(?:\[[^\]]*\])?\s*\{', text)
    if not match:
        return ''
    start = pos = match.end()
    depth = 1
    while depth and pos < len(text):
        if text[pos] == '{' and text[pos-1] != '\\': depth += 1
        if text[pos] == '}' and text[pos-1] != '\\': depth -= 1
        pos += 1
    return text[start:pos-1]


def markdown(tex, directory, fmt='markdown+raw_tex'):
    proc = subprocess.run([str(PANDOC), '-f', 'latex', '-t', fmt, '--wrap=none'],
                          input=tex, text=True, encoding='utf-8', capture_output=True, cwd=directory)
    if proc.returncode:
        raise RuntimeError(proc.stderr)
    return proc.stdout.strip()


def convert(name, title, authors, icml=False):
    directory = ROOT / name
    source = uncomment((directory / 'main.tex').read_text(encoding='utf-8'))
    preamble, body = source.split(r'\begin{document}', 1)
    body = body.split(r'\end{document}')[0]
    start = body.index(r'\begin{abstract}')
    opening, body = body[:start], body[start:]
    # Expand local table includes before shielding raw environments.
    body = re.sub(r'\\input\{([^}]+)\}', lambda m: uncomment((directory / (m[1] + '.tex')).read_text(encoding='utf-8')), body)
    # Use the same label spelling in both outputs, compatible with Quarto.
    body = re.sub(r'(?<=[{,])((?:fig|sec|eq|alg|tab)):+', r'\1-', body)
    body = re.sub(r'(?<=[{,])table_([\w-]+)', lambda m: 'tab-' + m[1].replace('_', '-'), body)
    preamble = preamble.replace(r'\newcommand{\theHalgorithm}', r'\providecommand{\theHalgorithm}')
    if icml:
        preamble = preamble.replace(r'\usepackage[noend]{algorithmic}', r'\usepackage[noend]{algpseudocode}')
        # ICML requires the old package internally; mark it provided by its replacement.
        preamble = preamble.replace(r'\usepackage[accepted]{icml2022}', '\\makeatletter\n\\@namedef{ver@algorithmic.sty}{2026/10/19}\n\\makeatother\n\\usepackage[accepted]{icml2022}')
        for old, new in {'REQUIRE':'Require','ENSURE':'Ensure','STATE':'State','FOR':'For','ENDFOR':'EndFor',
                         'IF':'If','ELSE':'Else','ENDIF':'EndIf','WHILE':'While','ENDWHILE':'EndWhile','RETURN':'Return'}.items():
            body = re.sub(r'\\' + old + r'\b', lambda m: '\\' + new, body)
    protected = []
    def protect(value):
        token = 'QUARTOBLOCKTOKEN' + str(len(protected)) + 'ENDTOKEN'
        protected.append(value)
        return '\n\n' + token + '\n\n'
    def raw(m):
        value = m[0].strip()
        label = argument(value, 'label')
        caption = argument(value, 'caption')
        if label and caption and value.startswith('\\begin{table'):
            # threeparttable notes can reset caption's reference context.
            value = value.replace('\\label{' + label + '}', '')
            value = value.replace('\\caption{' + caption + '}', '\\caption{' + caption + '}\\label{' + label + '}', 1)
        return protect('```{=latex}\n' + value + '\n```')
    def algorithm(value):
        # algorithmicx keeps nesting state in TeX assignments. A surrounding
        # colour group spanning loops restores that state too early.
        pattern = r'\{\\color\{[^}]+\}'
        for match in reversed(list(re.finditer(pattern, value))):
            depth, end = 1, match.start() + 1
            while depth and end < len(value):
                if value[end] == '{' and value[end-1] != '\\': depth += 1
                if value[end] == '}' and value[end-1] != '\\': depth -= 1
                end += 1
            group = value[match.start()+1:end-1]
            if '\\For' in group or '\\While' in group:
                value = value[:match.start()] + group + '\\color{black}' + value[end:]
        return value
    body = re.sub(r'\\begin\{codesnippet\}([\s\S]*?)\\end\{codesnippet\}',
                  lambda m: protect('```python\n' + m[1].strip() + '\n```'), body)
    # Algorithms wrapped in figures must remain one environment, not a figure caption.
    def figure(m):
        value = m[0]
        if r'\begin{algorithm}' in value:
            alg = re.search(r'\\begin\{algorithm\}[\s\S]*?\\end\{algorithm\}', value)[0]
            return protect('```{=latex}\n' + algorithm(alg) + '\n```')
        caption = markdown(argument(value, 'caption'), directory)
        label = argument(value, 'label')
        images = re.findall(r'\\includegraphics(?:\[[^\]]*\])?\{([^}]+)\}', value)
        if not images:
            return raw(m)
        if len(images) == 1:
            span = ' fig-env="figure*"' if r'\begin{figure*}' in value else ''
            return protect('![' + caption + '](' + images[0] + '){#' + label + ' width="100%"' + span + '}')
        widths = [float(w) for w in re.findall(r'width=([0-9.]+)\\textwidth', value)]
        ncol = max(1, round(1 / max(widths))) if widths and max(widths) < .4 else 1
        span = ' fig-env="figure*"' if r'\begin{figure*}' in value else ''
        return protect('::: {#' + label + ' layout-ncol="' + str(ncol) + '"' + span + '}\n\n' + '\n\n'.join('![](' + path + '){width="100%"}' for path in images) + '\n\n' + caption + '\n\n:::')
    body = re.sub(r'\\begin\{figure\*?\}(?:\[[^\]]*\])?[\s\S]*?\\end\{figure\*?\}', figure, body)
    body = re.sub(r'\\begin\{(table\*?|algorithm)\}(?:\[[^\]]*\])?[\s\S]*?\\end\{\1\}', raw, body)
    # Number equations through Quarto, including align/gather environments.
    def equation(m):
        env, content = m[1], m[2]
        labels = re.findall(r'\\label\{([^}]+)\}', content)
        if len(labels) > 1:
            rows = re.split(r'\\\\\s*(?=\\label)', content.strip())
            if len(rows) == len(labels):
                values = []
                for row, label in zip(rows, labels):
                    row = re.sub(r'\\label\{[^}]+\}', '', row).strip()
                    row = re.sub(r'\n\s*\n', '\n', row)
                    values.append('$$\n\\begin{aligned}\n' + row + '\n\\end{aligned}\n$$ {#' + label + '}')
                return protect('\n\n'.join(values))
        content = re.sub(r'\\label\{[^}]+\}', '', content).strip()
        content = re.sub(r'\n\s*\n', '\n', content)
        if env.rstrip('*') in ('align', 'gather'):
            wrapper = 'aligned' if env.startswith('align') else 'gathered'
            content = '\\begin{' + wrapper + '}\n' + content + '\n\\end{' + wrapper + '}'
        attr = ' {#' + labels[0] + '}' if labels else ''
        return protect('$$\n' + content + '\n$$' + attr)
    body = re.sub(r'\\begin\{(equation\*?|align\*?|gather\*?)\}([\s\S]*?)\\end\{\1\}', equation, body)
    abstract = re.search(r'\\begin\{abstract\}([\s\S]*?)\\end\{abstract\}', body)
    abstract_md = markdown(abstract[1], directory)
    body = body.replace(abstract[0], '')
    bibliography = ''
    if icml:
        body = re.sub(r'\\bibliographystyle\{[^}]+\}\s*\\bibliography\{[^}]+\}', '', body)
        bibliography = 'main.bib'
    else:
        bibmatch = re.search(r'\\begin\{thebibliography\}[^\n]*([\s\S]*?)\\end\{thebibliography\}', body)
        entries = re.split(r'\\bibitem\{([^}]+)\}', bibmatch[1])
        records = []
        for i in range(1, len(entries), 2):
            # Keep complete supplied bibliography text without inventing metadata.
            text = re.sub(r'\\vspace\{[^}]+\}', '', entries[i+1]).strip()
            records.append({'id': entries[i], 'type': 'article', 'title': markdown(text, directory, 'plain')})
        (directory / 'references.json').write_text(json.dumps(records, ensure_ascii=False, indent=2), encoding='utf-8')
        bibliography = 'references.json'
        # Native LaTeX bibliography is retained for the template-based PDF.
        (directory / 'bibliography.tex').write_text(bibmatch[0] + '\n', encoding='utf-8')
        body = body.replace(bibmatch[0], '')
    body = re.sub(r'\\(?:newpage|clearpage|onecolumn|appendix)\b', '', body)
    body = re.sub(r'\\(?:vspace|hspace)\*?\{[^}]*\}', '', body)
    # Cref is a LaTeX-only macro; use native Quarto cross references in prose.
    body = re.sub(r'\\[cC]ref\{([^}]+)\}', lambda m: ', '.join('Table \\ref{' + k.strip() + '}' if k.strip().startswith('tab-') else '@' + k.strip() for k in m[1].split(',')), body)
    result = markdown(body, directory)
    for i, value in enumerate(protected):
        result = result.replace('QUARTOBLOCKTOKEN' + str(i) + 'ENDTOKEN', value)
    result = re.sub(r'\[(?:\\\[[^\n]*?\\\]|[0-9.]+)\]\(#[^)]+\)\{reference-type="ref" reference="([^"]+)"\}',
                    lambda m: '@' + m[1] if m[1].startswith('eq-') else '\\ref{' + m[1] + '}', result)
    result = result.replace('\\@', '@')
    result = re.sub(r'(?<![\w@-])@(eq-[\w-]+)', r'[-@\1]', result)
    # Equivalent source forms supported by lwarp; do not parse table structure
    # in the HTML filter. Multirow continuation markers are inert in PDF.
    if icml:
        result = re.sub(r'\\color(\{[^}]+\})(?=\{)', r'\\textcolor\1', result)
    else:
        result = result.replace('& & & \\multicolumn{1}{c}{\\textbf{COM',
                                '\\mrowcell & \\mrowcell & \\mrowcell & \\multicolumn{1}{c}{\\textbf{COM')
    (directory / 'sections').mkdir(exist_ok=True)
    (directory / 'sections/body.md').write_text(result + '\n', encoding='utf-8')
    (directory / 'sections/abstract.md').write_text(abstract_md + '\n', encoding='utf-8')
    # A dedicated template keeps original publication layout and title commands.
    # Use a different intermediate/output name so main.tex can never be overwritten.
    if icml:
        bibend = '\\bibliographystyle{icml2022}\n\\bibliography{main}'
    else:
        bibend = '\\input{bibliography.tex}'
    template = preamble + '\n\\providecommand{\\tightlist}{\\setlength{\\itemsep}{0pt}\\setlength{\\parskip}{0pt}}\n\\providecommand{\\passthrough}[1]{#1}\n$for(header-includes)$\n$header-includes$\n$endfor$\n\\begin{document}\n' + opening + '\n\\begin{abstract}\n' + abstract[1] + '\n\\end{abstract}\n$body$\n' + bibend + '\n\\end{document}\n'
    if not icml:
        template = template.replace('\\usepackage{hyperref}', '\\makeatletter\n\\let\\NAT@parse\\undefined\n\\makeatother\n\\usepackage[numbers]{natbib}\n\\usepackage{hyperref}')
    graphics = (Path.home() / 'AppData/Local/Programs/Quarto/share/formats/pdf/pandoc/graphics.tex').read_text(encoding='utf-8')
    graphics = '\n'.join(line for line in graphics.splitlines() if not line.startswith('$'))
    template = template.replace('\\begin{document}', graphics + '\n\\begin{document}')
    # Pandoc templates treat dollar signs as directives; escape source math dollars.
    template = template.replace('$', '$$').replace('$$for(header-includes)$$', '$for(header-includes)$').replace('$$header-includes$$', '$header-includes$').replace('$$endfor$$', '$endfor$').replace('$$body$$', '$body$')
    (directory / 'quarto-template.tex').write_text(template, encoding='utf-8')
    packages = ['amsmath', 'amssymb', 'bm', 'mathrsfs', 'graphicx', 'xcolor', 'booktabs', 'colortbl']
    if icml: packages += ['algorithm', 'algpseudocode', 'bbding']
    else: packages += ['multirow', 'threeparttable']
    macros = '\\definecolor{CadetBlue}{rgb}{0.37,0.62,0.63}\n\\definecolor{BrickRed}{rgb}{0.8,0.25,0.33}\n\\definecolor{MidnightBlue}{rgb}{0.1,0.1,0.44}\n\\definecolor{YellowGreen}{rgb}{0.6,0.8,0.2}\n\\newcommand{\\colorcell}{\\cellcolor{CadetBlue!8}}\n\\newcommand{\\hcolorcell}{\\cellcolor{YellowGreen!10}}' if icml else ''
    if icml:
        macros += '\n\\definecolor{OliveGreen}{cmyk}{0.64,0,0.95,0.40}\n\\definecolor{YellowOrange}{cmyk}{0,0.42,1,0}'
    html = '---\ntitle: ' + json.dumps(title) + '\nauthor: ' + json.dumps(authors) + '\nfilters: [html-helper]\nbibliography: ' + bibliography + '\nformat:\n  html:\n    theme: cosmo\n    toc: true\n    number-sections: true\n    css: styles.css\n    html-helper:\n      caption-prefix: "Table "\n      caption-sep: ": "\n      latex-packages:\n' + ''.join('        - ' + p + '\n' for p in packages)
    if macros: html += '      latex-macros: |\n' + ''.join('        ' + line + '\n' for line in macros.splitlines())
    if not icml:
        html += 'csl: source-numeric.csl\n'
    html += '---\n\n::: {.callout-note appearance="simple" icon="false"}\n## Abstract\n\n{{< include sections/abstract.md >}}\n\n:::\n\n{{< include sections/body.md >}}\n'
    (directory / 'index.qmd').write_text(html, encoding='utf-8')
    pdf = '---\nfilters: [pdf-helper]\nbibliography: ' + bibliography + '\nformat:\n  pdf:\n    output-file: quarto.pdf\n    pdf-engine: pdflatex\n    template: quarto-template.tex\n    keep-tex: true\n    latex-clean: false\n    number-sections: true\n    cite-method: natbib\n    citeproc: false\n    syntax-highlighting: none\n---\n\n{{< include sections/body.md >}}\n'
    if not icml:
        pdf = pdf.replace('    syntax-highlighting: none\n',
                          '    syntax-highlighting: none\n    include-in-header:\n      - text: |\n          \\providecommand{\\mrowcell}{}\n')
    (directory / 'paper.qmd').write_text(pdf.replace('output-file: quarto.pdf', 'output-file: paper.pdf'), encoding='utf-8')
    (directory / 'styles.css').write_text('main { max-width: 960px; }\nfigure embed { width: 100%; }\n.quarto-float { margin: 1.75rem 0; }\npre { overflow-x: auto; }\n', encoding='utf-8')
    print(name, len(result), 'characters', len(protected), 'preserved blocks')


if __name__ == '__main__':
    convert('arXiv-2203.04955v2', 'Temporal Difference Learning for Model Predictive Control',
            'Nicklas Hansen, Xiaolong Wang, Hao Su', icml=True)
    convert('arXiv-2508.00362v1', 'A Whole-Body Motion Imitation Framework from Human Data for Full-Size Humanoid Robot',
            'Zhenghan Chen, Haodong Zhang, Dongqi Wang, Jiyu Yu, Haocheng Xu, Yue Wang, Rong Xiong')
