#!/usr/bin/env python3
"""Pre-render hook: gate LaTeX tables with format-specific divs.

Reads sections/*.md (clean LaTeX tables), writes _build/sections/*.md (with gating).
Copies all auxiliary files (.lua, .css, .bib, figures/, styles/) to _build/.
"""
import os
import re
import shutil
from pathlib import Path

SRC_DIR = Path("sections")
BUILD_DIR = Path("_build")
BUILD_SECTIONS = BUILD_DIR / "sections"


def find_latex_table_blocks(text: str) -> list[tuple[str, int, int]]:
    """Find all ```{=latex} blocks containing table environments."""
    pattern = r'```\{=latex\}\n(.*?)\n```'
    matches = []
    for m in re.finditer(pattern, text, re.DOTALL):
        content = m.group(1)
        if r'\begin{table' in content or r'\begin{tabular' in content:
            matches.append((content, m.start(), m.end()))
    return matches


def tabular_to_html(latex_block: str, table_id: str = None) -> str:
    """Convert LaTeX table environment to raw HTML."""
    # Extract caption
    caption_m = re.search(r'\\caption\{(.+?)\}\s*\\label', latex_block, re.DOTALL)
    if not caption_m:
        caption_m = re.search(r'\\caption\{(.+?)\}\s*$', latex_block, re.DOTALL | re.MULTILINE)
    caption = caption_m.group(1).strip() if caption_m else ""
    caption_html = convert_inlines(caption)
    
    # Extract label for ID
    label_m = re.search(r'\\label\{([^}]+)\}', latex_block)
    label = label_m.group(1) if label_m else ""
    id_attr = f' id="{label}"' if label else ''
    
    # Extract tabular environment
    tabular_m = re.search(r'\\begin\{tabular\}[^{]*(\{[^}]+\})(.*?)\\end\{tabular\}', latex_block, re.DOTALL)
    if not tabular_m:
        return f"<div>{latex_block}</div>"
    
    col_spec = tabular_m.group(1)
    body = tabular_m.group(2).strip()
    
    # Parse rows
    rows = []
    for line in body.split('\n'):
        line = line.strip()
        if not line or line.startswith('%'):
            continue
        if line.startswith('\\toprule') or line.startswith('\\midrule') or line.startswith('\\bottomrule') or line.startswith('\\cmidrule'):
            continue
        if line.endswith('\\\\'):
            line = line[:-2].strip()
        if line:
            rows.append(line)
    
    # Convert rows to HTML
    html_rows = []
    for row_idx, row in enumerate(rows):
        # Handle \shortstack
        def convert_shortstack(m):
            parts = m.group(1).split('\\\\')
            return '<br>'.join(p.strip() for p in parts)
        
        row = re.sub(r'\\shortstack\[l\]\{([^}]+)\}', convert_shortstack, row)
        row = re.sub(r'\\scriptsize', '', row)
        row = re.sub(r'\\addlinespace', '', row)
        
        # Split cells
        cells = [c.strip() for c in row.split('&')]
        
        # Check for multicolumn
        cell_html = []
        for cell in cells:
            if cell.startswith('\\multicolumn'):
                mc_m = re.match(r'\\multicolumn\{(\d+)\}\{([^}]+)\}\{(.+)\}$', cell, re.DOTALL)
                if mc_m:
                    n = int(mc_m.group(1))
                    content = mc_m.group(3).strip()
                    cell_html.append(f'<th colspan="{n}">{convert_inlines(content)}</th>')
                else:
                    cell_html.append(f'<td>{convert_inlines(cell)}</td>')
            else:
                cell_html.append(f'<td>{convert_inlines(cell)}</td>')
        
        # Use th for header row (first row)
        if row_idx == 0:
            cell_html = [c.replace('<td>', '<th>').replace('</td>', '</th>') for c in cell_html]
        
        html_rows.append(f'<tr>{"".join(cell_html)}</tr>')
    
    return f"""<table class="paper-table"{id_attr}>
<tbody>
{"".join(html_rows)}
</tbody>
</table>

<p class="table-caption">{caption_html}</p>"""


def convert_inlines(text: str) -> str:
    """Convert inline LaTeX to HTML."""
    text = re.sub(r'\\textbf\{([^}]+)\}', r'<strong>\1</strong>', text)
    text = re.sub(r'\\(?:textit|emph)\{([^}]+)\}', r'<em>\1</em>', text)
    text = re.sub(r'\\texttt\{([^}]+)\}', r'<code>\1</code>', text)
    text = text.replace('\\cmark', '<span class="cmark">✓</span>')
    text = text.replace('\\xmark', '<span class="xmark">✗</span>')
    text = text.replace('\\ara{}', '<span class="ara">Ara</span>')
    text = text.replace('\\ara', '<span class="ara">Ara</span>')
    text = re.sub(r'\$(.+?)\$', r'$\1$', text)
    text = re.sub(r'\\S\\ref\{([^}]+)\}', r'[§\1]', text)
    text = re.sub(r'\\ref\{([^}]+)\}', r'[\1]', text)
    text = re.sub(r'\\citep\{([^}]+)\}', r'[@\1]', text)
    text = text.replace(' & ', ' &amp; ')
    return text


def gate_latex_table(latex_block: str) -> str:
    """Wrap LaTeX table in format-specific gating divs.
    
    在 PDF 部分把 tbl- 前缀改成 tab-，避免 Quarto crossref.lua 主动拆碎表格。
    HTML 部分的 id 保持原始 label。
    """
    # 提取原始 label（HTML 侧用）
    label_m = re.search(r'\\label\{([^}]+)\}', latex_block)
    original_label = label_m.group(1) if label_m else ""
    
    # PDF 侧：把 tbl- 改成 tab-（crossref.lua 只拦截 tbl-）
    pdf_block = latex_block.replace('tbl-', 'tab-')
    
    html_version = tabular_to_html(latex_block)
    
    return f"""::: {{.content-visible when-format="pdf"}}
```{{=latex}}
{pdf_block}
```
:::

::: {{.content-visible when-format="html"}}

{html_version}

:::
"""


def process_markdown_file(src_path: Path, dst_path: Path):
    """Read .md, find LaTeX tables, add gating, write to _build/."""
    text = src_path.read_text(encoding="utf-8")
    
    # 全文替换 tbl- → tab-（PDF 侧 label 和正文 \ref{} 都统一用 tab- 前缀）
    text = text.replace('tbl-', 'tab-')
    
    blocks = find_latex_table_blocks(text)
    
    if not blocks:
        dst_path.parent.mkdir(parents=True, exist_ok=True)
        dst_path.write_text(text, encoding="utf-8")
        return
    
    for content, start, end in reversed(blocks):
        gated = gate_latex_table(content)
        text = text[:start] + gated + text[end:]
    
    dst_path.parent.mkdir(parents=True, exist_ok=True)
    dst_path.write_text(text, encoding="utf-8")
    print(f"  {src_path.name} -> {dst_path.name} (gated {len(blocks)} tables)")


def main():
    """Main entry point."""
    print("=== Pre-render: gating LaTeX tables ===")
    
    if BUILD_DIR.exists():
        shutil.rmtree(BUILD_DIR)
    BUILD_SECTIONS.mkdir(parents=True, exist_ok=True)
    
    # Copy index.qmd with tbl- → tab- replacement
    index_src = Path("index.qmd")
    index_dst = BUILD_DIR / "index.qmd"
    if index_src.exists():
        text = index_src.read_text(encoding="utf-8")
        text = text.replace('tbl-', 'tab-')
        index_dst.write_text(text, encoding="utf-8")
        print(f"  index.qmd -> _build/index.qmd (tbl- → tab-)")
    
    # Copy auxiliary files
    for pattern in ["*.lua", "*.css", "*.bib"]:
        for f in Path(".").glob(pattern):
            dst = BUILD_DIR / f.name
            shutil.copy(f, dst)
            print(f"  {f.name} -> _build/{f.name}")
    
    # Copy directories
    for dirname in ["styles", "figures"]:
        src_dir = Path(dirname)
        if src_dir.exists():
            dst_dir = BUILD_DIR / dirname
            if dst_dir.exists():
                shutil.rmtree(dst_dir)
            shutil.copytree(src_dir, dst_dir)
            print(f"  {dirname}/ -> _build/{dirname}/")
    
    # Process all .md files in sections/
    for md_file in sorted(SRC_DIR.glob("*.md")):
        dst = BUILD_SECTIONS / md_file.name
        process_markdown_file(md_file, dst)
    
    print("=== Pre-render complete ===")


if __name__ == "__main__":
    main()
