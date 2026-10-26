"""Check the rendered SuperMimic paper against its original labels and assets."""
from html.parser import HTMLParser
from pathlib import Path
import json
import re

paper = Path(__file__).resolve().parents[1] / 'arXiv-2610.28480v1'
original = (paper / 'root.tex').read_text(encoding='utf-8') + '\n' + '\n'.join(
    f.read_text(encoding='utf-8') for f in (paper / 'sections').glob('*.tex'))
labels = {s.replace(':', '-').replace('_', '-')
          for s in re.findall(r'\\label\{([^}]+)\}', original)}
labels = {'sec-' + s[4:] if s.startswith('app-') else s for s in labels}


class Document(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids, self.links = set(), set()

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if attrs.get('id'):
            self.ids.add(attrs['id'])
        if attrs.get('href', '').startswith('#') and attrs['href'] != '#':
            self.links.add(attrs['href'][1:])


html = (paper / 'index.html').read_text(encoding='utf-8')
doc = Document()
doc.feed(html)
assert labels <= doc.ids, sorted(labels - doc.ids)
assert doc.links <= doc.ids, sorted(doc.links - doc.ids)
assert 'class="lwarp-failed"' not in html
assert '\ufffd' not in html, 'Replacement character in extracted HTML'
assert not re.search(r'\[(?:fig|tab|eq|alg|sec)-[^\]<]+\]', html)
# Ignore lwarp's hidden macro declarations, and inspect actual displayed math.
body = re.sub(r'<div[^>]*data-nosnippet[^>]*>.*?</div>', '', html, flags=re.S)
assert not re.search(r'\\(?:num|qty)\b', body), 'siunitx command escaped into MathJax'
assert len(list((paper / 'figures/quarto').glob('*.pdf'))) == 8
assert len(json.loads((paper / 'references.json').read_text(encoding='utf-8'))) == 28
log = (paper / 'paper.log').read_text(encoding='utf-8', errors='replace')
assert not re.search(r'(?:Reference|Citation) `[^\n]*undefined', log)
assert 'Float too large' not in log
assert 'Overfull' not in log
assert 'Missing character:' not in log
aux = (paper / 'paper.aux').read_text(encoding='utf-8')
assert labels <= set(re.findall(r'\\newlabel\{([^}]+)\}', aux))
print(f'PASS: {len(labels)} original labels in HTML/PDF, all fragment links resolve, 8 vector figures, 28 references')
print(re.findall(r'Output written on[^\n]*', log)[-1])
