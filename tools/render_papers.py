"""Render all four papers; retain per-format logs and a machine-readable report."""
from pathlib import Path
import os
import subprocess
import json
import time
import argparse
import re

parser = argparse.ArgumentParser()
parser.add_argument('--papers', nargs='+')
parser.add_argument('--formats', nargs='+', choices=['html', 'pdf'], default=['html', 'pdf'])
args = parser.parse_args()

root = Path(__file__).resolve().parents[1]
home = Path.home()
env = os.environ.copy()
env['PATH'] = ';'.join(str(home / p) for p in (
    'AppData/Local/Programs/Quarto/bin',
    'AppData/Local/Programs/MiKTeX/miktex/bin/x64', 'miniforge3')) + ';' + env['PATH']
quarto = home / 'AppData/Local/Programs/Quarto/bin/quarto.exe'
report_file = root / 'render-report.json'
report = json.loads(report_file.read_text(encoding='utf-8')) if report_file.exists() else []
for name in args.papers or ['arXiv-2203.04955v2', 'arXiv-2508.00362v1', 'arXiv-2604.24658v3', 'arXiv-2605.23904v2']:
    for fmt, entry in [('html', 'index.qmd'), ('pdf', 'paper.qmd' if '2203' in name or '2508' in name else 'main.qmd')]:
        if fmt not in args.formats:
            continue
        print('START', name, fmt, flush=True)
        start = time.time()
        with (root / name / ('render-' + fmt + '.log')).open('w', encoding='utf-8') as log:
            proc = subprocess.run([str(quarto), 'render', name + '/' + entry, '--to', fmt],
                                  cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT)
        record = dict(paper=name, format=fmt, exit_code=proc.returncode, seconds=round(time.time()-start, 1))
        if fmt == 'html' and proc.returncode == 0:
            html = (root / name / 'index.html').read_text(encoding='utf-8')
            record['latex_failures'] = html.count('class="lwarp-failed"')
            record['unresolved_placeholders'] = sorted(set(re.findall(r'\[(?:fig|tab|eq|alg|sec)-[^\]<]+\]', html)))
        elif fmt == 'pdf' and proc.returncode == 0:
            texlog = (root / name / Path(entry).with_suffix('.log')).read_text(encoding='utf-8', errors='replace')
            record['unresolved_references'] = sorted(set(re.findall(r"Reference `([^']+)'[^\n]*undefined", texlog)))
        report = [r for r in report if (r['paper'], r['format']) != (name, fmt)] + [record]
        report_file.write_text(json.dumps(report, indent=2), encoding='utf-8')
        print('DONE', record, flush=True)
