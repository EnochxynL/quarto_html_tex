"""Render raw LaTeX tables through the real lwarp pipeline and check semantics."""
from pathlib import Path
import atexit
import base64
import html as html_lib
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
fixture = root / '_regression/lwarp-tables.qmd'
stem.with_suffix('.qmd').write_text(fixture.read_text(encoding='utf-8'), encoding='utf-8')
atexit.register(lambda: stem.with_suffix('.qmd').unlink(missing_ok=True))
logs = root / '.quarto'
logs.mkdir(exist_ok=True)
with (logs / 'lwarp-tables.log').open('w', encoding='utf-8') as log:
    subprocess.run([str(quarto), 'render', stem.name + '.qmd', '--to', 'html'],
                   cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
html = stem.with_suffix('.html').read_text(encoding='utf-8')
assert '[html-latex-lwarp]' not in (logs / 'lwarp-tables.log').read_text(encoding='utf-8')
assert 'class="lwarp-failed"' not in html
assert '"bm": ["\\\\boldsymbol{#1}", 1]' in html, 'native Math nodes did not register bm'
assert re.search(r'colspan="2"[^>]*>\s*Grouped methods', html)
for text in ['Colored text', 'First line', 'Second line', 'Macro value', 'Panel A', 'Panel B', 'Final panel']:
    assert text in html, text
assert re.search(r'color:\s*#B91C1C', html, re.I)
decoded = html_lib.unescape(html)
assert '\u2713' in decoded and '\u2717' in decoded
for number in (1, 2, 3):
    assert re.search(r'Table\s*' + str(number) + ':', decoded)
ids = re.findall(r'(?<![\w-])id="([^"]+)"', html)
assert len(ids) == len(set(ids)), 'duplicate anchors between compiled blocks'
for number, name in enumerate(['grouped', 'panels', 'third'], 1):
    target = 'tab-regression-' + name
    assert html.count('id="' + target + '"') == 1, target
    assert f'<a href="#{target}">{number}</a>' in html, target
assert '[TAB-CAP:' not in html
assert '@@REF:' not in html
assert 'caption-top table' not in html  # no Bootstrap classes on nested tables
images = re.findall(r'src="data:image/svg\+xml;base64,([^"]+)"', html)
assert len(images) >= 2, 'pifont image resources were not embedded'
for data in images:
    svg = base64.b64decode(data).decode('utf-8')
    assert '<svg' in svg and '<path' in svg, 'empty generated symbol'
    dimensions = re.search(r'<svg[^>]*width="([\d.]+)"[^>]*height="([\d.]+)"', svg)
    assert dimensions and all(0 < float(n) < 100 for n in dimensions.groups()), 'uncropped symbol page'
assert not re.search(r'src="block-images[/\\]', html), 'temporary image URL leaked'
print('PASS: spanning columns, nested cells, colors, captions, references, embedded SVG symbols')
