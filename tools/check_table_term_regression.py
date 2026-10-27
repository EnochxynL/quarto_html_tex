"""Check raw LaTeX tables and inline terms without a PDF conversion filter."""
from pathlib import Path
import atexit
import os
import re
import subprocess

root = Path(__file__).resolve().parents[1]
home = Path.home()
env = os.environ.copy()
env['PATH'] = ';'.join(str(home / p) for p in (
    'AppData/Local/Programs/Quarto/bin',
    'AppData/Local/Programs/MiKTeX/miktex/bin/x64', 'miniforge3')) + ';' + env['PATH']
quarto = home / 'AppData/Local/Programs/Quarto/bin/quarto.exe'
stem = root / '_table-term-regression'
fixture = (root / '_regression/table-term.qmd').read_text(encoding='utf-8')
atexit.register(lambda: stem.with_suffix('.qmd').unlink(missing_ok=True))
logs = root / '.quarto'
logs.mkdir(exist_ok=True)

for caption_pos in ('top', 'bottom'):
    source = fixture
    if caption_pos == 'top':
        source = re.sub(
            r'(\\begin\{table\*?\}\[htbp\]\n\\centering\n)(.*?)'
            r'(\\caption(?:\[[^\n]*\])?\{[^\n]*\}\n\\label\{[^\n]*\}\n)(\\end\{table\*?\})',
            lambda m: m[1] + m[3] + m[2] + m[4], source, flags=re.S)
    stem.with_suffix('.qmd').write_text(source, encoding='utf-8')
    with (logs / f'table-term-{caption_pos}.log').open('w', encoding='utf-8') as log:
        subprocess.run([str(quarto), 'render', stem.name + '.qmd', '--to', 'pdf'],
                       cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
    tex = stem.with_suffix('.tex').read_text(encoding='utf-8')
    latex_log = stem.with_suffix('.log').read_text(encoding='utf-8', errors='replace')
    assert 'There were undefined references' not in latex_log
    assert 'longtable not in 1-column mode' not in latex_log
    tables = re.findall(r'\\begin\{(table\*?)\}.*?\\end\{\1\}', tex, re.S)
    assert tables.count('table*') == 2, tables
    assert tables.count('table') == 1, tables
    for label, expected_env in [('tbl-regression-native', 'table*'),
                                ('tbl-regression-nested', 'table*'),
                                ('tbl-regression-html', 'table')]:
        label_tex = '\\label{' + label + '}'
        assert tex.count(label_tex) == 1, label
        table = next(m[0] for m in re.finditer(r'\\begin\{(table\*?)\}.*?\\end\{\1\}', tex, re.S)
                     if label_tex in m[0])
        assert table.startswith('\\begin{' + expected_env + '}'), table
        before = table.index('\\caption[') < table.index('\\begin{tabular}')
        assert before == (caption_pos == 'top'), table
    assert '\\caption[Wide table]{Wide table with \\ara{}.}' in tex
    assert tex.count('\\ara{} &') == 2
    assert 'Text before the nested table must survive.' in tex
    assert 'Text after the nested table must survive.' in tex

stem.with_suffix('.qmd').write_text(fixture, encoding='utf-8')
with (logs / 'table-term-html.log').open('w', encoding='utf-8') as log:
    subprocess.run([str(quarto), 'render', stem.name + '.qmd', '--to', 'html'],
                   cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
html = stem.with_suffix('.html').read_text(encoding='utf-8')
assert '<p>Before <strong>bold (<span class="ara">Ara</span>)</strong> after.</p>' in html
assert '<p><span class="ara">Ara</span> starts this paragraph.</p>' in html
assert '<strong>bold (<p>' not in html

assert 'class="lwarp-failed"' not in html
for label in ('tbl-regression-native', 'tbl-regression-html'):
    assert f'href="#{label}"' in html
assert '@@REF:' not in html
print('PASS: raw table environments, top/bottom captions, labels, nested content and inline terms')
