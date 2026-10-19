"""Check that raw LaTeX table colors retain text and resolve to CSS colors."""
from pathlib import Path
import re
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
pandoc = shutil.which('pandoc') or str(
    Path.home() / 'AppData/Local/Programs/Quarto/bin/tools/pandoc.exe')
source = r'''---
html-helper:
  latex-macros: |
    \definecolor{BrickRed}{rgb}{0.8,0.25,0.33}
    \definecolor{CustomBlue}{HTML}{123ABC}
    \definecolor{CustomGray}{gray}{0.5}
    \definecolor{CustomCyan}{cmyk}{1,0,0,0}
---

```{=latex}
\begin{table*}[t]
\caption{Color regression}\label{tab-color-regression}
\begin{tabular}{ll}
Method & Value \\
Red & \color{BrickRed}{Ground-truth model} \\
Green & \color{OliveGreen}{\Checkmark} \\
Orange & \color{YellowOrange}{Moderate} \\
Cross & \color{BrickRed}{\XSolidBrush} \\
Blue & \textcolor{CustomBlue}{\textbf{Nested text}} \\
Gray & \color{CustomGray}{Gray text} \\
Cyan & \color{CustomCyan}{Cyan text} \\
\end{tabular}
\end{table*}
```
'''
result = subprocess.run(
    [pandoc, '-f', 'markdown', '-t', 'html',
     '--lua-filter=_extensions/html-helper/latex/html-latex-tables.lua'],
    input=source, text=True, encoding='utf-8', capture_output=True,
    cwd=root, check=True)
html = re.sub(r'\s+', ' ', result.stdout)
for color, content in [('rgb(204,64,84)', 'Ground-truth model'),
                       ('rgb(55,153,8)', '✓'),
                       ('rgb(255,148,0)', 'Moderate'),
                       ('rgb(204,64,84)', '✗'),
                       ('#123ABC', '<strong>Nested text</strong>'),
                       ('rgb(128,128,128)', 'Gray text'),
                       ('rgb(0,255,255)', 'Cyan text')]:
    assert f'<span style="color: {color}">{content}</span>' in html, html
assert 'id="tab-color-regression"' in html
print('PASS: colored text, nested formatting, check/cross symbols, and table label')
