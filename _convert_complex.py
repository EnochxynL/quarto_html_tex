"""Pre-render hook: 检测 sections/*.tex，按需转换为 sections/*.md。

作为 Quarto pre-render hook 运行：
  - 扫描 sections/ 目录下的 .tex 文件
  - 如果对应的 .md 不存在或比 .tex 旧，则重新转换
  - 转换规则：
    * 简单表 -> 管道表
    * 复杂表 -> 门控 raw LaTeX(PDF) + raw HTML table(HTML)
    * description -> markdown
    * lstlisting -> 代码块
    * 数学 $...$ 保留（Pandoc/KaTeX 处理，实测 raw HTML 内也渲染）
    * 图 caption：swap ![短](path "长") -> ![长](path)，\ara{} -> 纯文本（短代码在 alt 不生效）

Usage:
  自动（Quarto pre-render）: 在 index.qmd 中配置
  手动: python _convert_complex.py [file1.tex file2.tex ...]
"""
import re, os, sys
from pathlib import Path

# 获取脚本所在目录作为基准
SCRIPT_DIR = Path(__file__).parent
SECTIONS_DIR = SCRIPT_DIR / "sections"

# legacy alias：旧 label 指向的 canonical section
ALIASES = {
    "app:eval-corpus": "app:eval-details",
    "app:extension-trajectories": "app:extension-cases",
}

def map_key(key):
    key = ALIASES.get(key, key)
    prefix, sep, rest = key.partition(":")
    if not sep:
        return key
    m = {"fig": "fig", "sec": "sec", "app": "sec-app", "tab": "tab", "eq": "eq"}
    return m.get(prefix, prefix) + "-" + rest

def map_raw_latex(text):
    text = re.sub(r"\\label\{([^}]+)\}", lambda m: "\\label{" + map_key(m.group(1)) + "}", text)
    text = re.sub(r"\\S\\ref\{([^}]+)\}", lambda m: "\\S\\ref{" + map_key(m.group(1)) + "}", text)
    text = re.sub(r"\\ref\{([^}]+)\}", lambda m: "\\ref{" + map_key(m.group(1)) + "}", text)
    return text

def match_braces(s, open_pos):
    """s[open_pos] 必须是 '{'。返回匹配的 '}' 下标，否则 -1。跳过转义与嵌套。"""
    depth = 0
    i = open_pos
    while i < len(s):
        ch = s[i]
        if ch == "\\" and i + 1 < len(s):
            i += 2
            continue
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1

def sub_cmd(s, cmd, repl):
    """把 s 中所有 \\cmd{...}（内容可含嵌套/转义花括号）替换为 repl(内容)。"""
    pat = "\\" + cmd + "{"
    L = len(pat)
    out = []
    i = 0
    while True:
        j = s.find(pat, i)
        if j == -1:
            out.append(s[i:])
            break
        end = match_braces(s, j + L - 1)
        if end == -1:
            out.append(s[i:])
            break
        out.append(s[i:j])
        out.append(repl(s[j + L:end]))
        i = end + 1
    return "".join(out)

def _tt(x):
    """\\texttt 内容：代码行内，反斜杠转义还原。"""
    for a, b in [("\\_", "_"), ("\\{", "{"), ("\\}", "}"), ("\\#", "#"), ("\\$", "$"), ("\\%", "%")]:
        x = x.replace(a, b)
    return "`" + x + "`"

def convert_inlines(text, ara_plain=False):
    text = re.sub(r"\\S\\ref\{([^}]+)\}", lambda m: "\\S\\ref{" + map_key(m.group(1)) + "}", text)
    text = re.sub(r"\\ref\{([^}]+)\}", lambda m: "\\ref{" + map_key(m.group(1)) + "}", text)
    text = re.sub(r"\\citep\{([^}]+)\}", lambda m: "[" + "; ".join("@" + k.strip() for k in m.group(1).split(",")) + "]", text)
    text = re.sub(r"\\citet\{([^}]+)\}", lambda m: "@" + m.group(1).strip(), text)
    text = re.sub(r"\\cite\{([^}]+)\}", lambda m: "[" + "; ".join("@" + k.strip() for k in m.group(1).split(",")) + "]", text)
    text = text.replace("\\ara{}", "Ara" if ara_plain else "{{< ara >}}")
    if ara_plain:
        text = text.replace("{{< ara >}}", "Ara")
    text = sub_cmd(text, "texttt", _tt)
    text = sub_cmd(text, "textbf", lambda x: "**" + x + "**")
    text = sub_cmd(text, "emph", lambda x: "*" + x + "*")
    text = sub_cmd(text, "textit", lambda x: "*" + x + "*")
    text = re.sub(r"\\url\{([^}]+)\}", lambda m: "<" + m.group(1) + ">", text)
    text = text.replace("\\&", "&")
    text = text.replace("{=latex}", "")
    text = re.sub(r"\\textdollar\{\}", r"\\$", text)
    text = text.replace("\\textdollar", "\\$")
    text = text.replace("~", " ")
    text = text.replace("{,}", ",")
    text = text.replace("\\,", " ")
    text = text.replace("\\:", " ")
    text = text.replace("\\!", "")
    text = re.sub(r"\\noindent\s*", "", text)
    text = re.sub(r"\{#([^}]+)\}", lambda m: "{#" + map_key(m.group(1)) + "}", text)
    return text

def fix_figure_swap(text):
    """![短](path "长标题"){#id} -> ![长标题](path){#id}（Pandoc 用 alt 当 caption，title 在括号内）。"""
    def repl(m):
        alt, path, title, attr = m.group(1), m.group(2), m.group(3), m.group(4) or ""
        return "![" + convert_inlines(title, ara_plain=True) + "](" + path + ")" + attr
    return re.sub(r'!\[([^\]]*)\]\(([^"\n]*)\s+"([^"]+)"\)(\{[^}]*\})?', repl, text)

def is_complex_table(tab, env_body=""):
    markers = ["multicolumn", "\\color", "cmark", "xmark", "multirow",
               "shortstack", "cmidrule", "p{", "$", "setlength"]
    return any(k in tab for k in markers) or "setlength" in env_body

def extract_caption_label(env):
    cap = ""
    cm = re.search(r"\\caption\{", env)
    if cm:
        end = match_braces(env, cm.end() - 1)
        if end != -1:
            cap = env[cm.end():end]
    lab = ""
    lm = re.search(r"\\label\{([^}]+)\}", env)
    if lm:
        lab = lm.group(1)
    return cap, lab

def split_rows(tab):
    """在花括号深度 0 处按 \\\\ 分割行（\\shortstack 内部的 \\\\ 不分割）。"""
    rows, depth, cur, i = [], 0, [], 0
    while i < len(tab):
        ch = tab[i]
        if ch == "\\" and i + 1 < len(tab):
            if tab[i + 1] == "\\" and depth == 0:
                rows.append("".join(cur)); cur = []; i += 2; continue
            cur.append(ch); cur.append(tab[i + 1]); i += 2; continue
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
        cur.append(ch); i += 1
    if cur:
        rows.append("".join(cur))
    return rows

def cell_to_html(cell, header=False):
    tag = "th" if header else "td"
    c = cell.strip()
    if c.startswith("\\multicolumn"):
        m = re.match(r"\\multicolumn\{(\d+)\}\{[^{}]*\}\{", c)
        if m:
            end = match_braces(c, m.end() - 1)
            if end == len(c) - 1:
                inner = cell_to_html(c[m.end():end], header)
                return '<%s colspan="%d">%s</%s>' % (tag, int(m.group(1)), inner, tag)
    c = sub_cmd(c, "shortstack[l]",
                lambda x: "<br>".join(cell_to_html(p, header) for p in re.split(r"\\\\", x)))
    c = sub_cmd(c, "textbf", lambda x: "<strong>" + cell_to_html(x, header) + "</strong>")
    c = sub_cmd(c, "texttt", lambda x: "<code>" + x.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;") + "</code>")
    c = sub_cmd(c, "emph", lambda x: "<em>" + x + "</em>")
    c = sub_cmd(c, "textit", lambda x: "<em>" + x + "</em>")
    c = sub_cmd(c, "scriptsize", lambda x: "<small>" + x + "</small>")
    c = re.sub(r"\\scriptsize\(([^)]*)\)", lambda m: "<small>(" + m.group(1) + ")</small>", c)
    c = re.sub(r"\\scriptsize", "", c)
    # 彩色勾叉（\color{...}\checkmark / $\sim$ / $\times$）
    c = re.sub(r"\{?\\color\{green[^}]*\}\s*\\checkmark\}?", '<span class="ok">✓</span>', c)
    c = re.sub(r"\{?\\color\{orange\}\s*\$\\sim\$\}?", '<span class="part">∼</span>', c)
    c = re.sub(r"\{?\\color\{red[^}]*\}\s*\$\\times\$\}?", '<span class="bad">✗</span>', c)
    c = re.sub(r"\\cmark\{\}", '<span class="ok">✓</span>', c)
    c = re.sub(r"\\xmark\{\}", '<span class="bad">✗</span>', c)
    c = re.sub(r"\\cmark", '<span class="ok">✓</span>', c)
    c = re.sub(r"\\xmark", '<span class="bad">✗</span>', c)
    c = re.sub(r"\\checkmark", "✓", c)
    c = c.replace("\\ara{}", '<span class="ara">Ara</span>')
    c = sub_cmd(c, "textsuperscript", lambda x: "<sup>" + x + "</sup>")
    c = c.replace("\\quad", " ")
    c = re.sub(r"\\citep\{([^}]+)\}", lambda m: "[" + "; ".join("@" + k.strip() for k in m.group(1).split(",")) + "]", c)
    c = re.sub(r"\\S\\ref\{([^}]+)\}", lambda m: "[§" + map_key(m.group(1)) + "]", c)
    c = re.sub(r"\\ref\{([^}]+)\}", lambda m: "[§" + map_key(m.group(1)) + "]", c)
    c = c.replace("~", " ")
    c = c.replace("\\,", " ")
    c = c.replace("\\:", " ")
    c = c.replace("\\!", "")
    c = c.replace("\\ ", " ")
    c = c.replace("\\&", "&amp;")
    c = c.replace("\\textdollar{}", "&#36;")
    c = c.replace("\\textdollar", "&#36;")
    c = c.replace("{,}", ",")
    c = c.replace("\\{", "{")
    c = c.replace("\\}", "}")
    c = re.sub(r"\\%", "%", c)
    c = re.sub(r"\\_", "_", c)
    c = c.replace("---", "—")
    c = c.replace("--", "–")
    return c.strip()

def split_cells(row):
    """在花括号深度 0 处按裸 & 分割单元格（跳过 \\& 转义与花括号内 &）。"""
    cells, depth, cur, i = [], 0, [], 0
    while i < len(row):
        ch = row[i]
        if ch == "\\" and i + 1 < len(row):
            cur.append(ch); cur.append(row[i + 1]); i += 2; continue
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
        elif ch == "&" and depth == 0:
            cells.append("".join(cur)); cur = []; i += 1; continue
        cur.append(ch); i += 1
    cells.append("".join(cur))
    return cells

def tabular_to_html(tab, lab=""):
    tab = re.sub(r"^\s*\{.*?\}(?=\s*\\)", "", tab, flags=re.S)
    rule = re.compile(r"\\(?:toprule|midrule|bottomrule|addlinespace|cline\{[^}]*\}|cmidrule(?:\([^)]*\))?\{[^}]*\})")
    header_rows, body_rows = [], []
    in_header = True
    for line in split_rows(tab):
        if re.search(r"\\midrule|\\bottomrule", line):
            in_header = False
        line = rule.sub("", line).strip()
        if not line:
            continue
        cells = [cell_to_html(c, header=in_header) for c in split_cells(line)]
        (header_rows if in_header else body_rows).append(cells)
    tid = (' id="%s"' % map_key(lab)) if lab else ""
    html = ['<table class="paper-table"%s>' % tid]
    if header_rows:
        html.append("<thead>")
        for r in header_rows:
            html.append("<tr>" + "".join(c if (c.startswith("<th") or c.startswith("<td")) else "<th>" + c + "</th>" for c in r) + "</tr>")
        html.append("</thead>")
    if body_rows:
        html.append("<tbody>")
        for r in body_rows:
            html.append("<tr>" + "".join(c if (c.startswith("<th") or c.startswith("<td")) else "<td>" + c + "</td>" for c in r) + "</tr>")
        html.append("</tbody>")
    html.append("</table>")
    return "\n".join(html)

def clean_residue(text):
    lines = []
    for ln in text.split("\n"):
        s = ln.strip()
        if not s or s.startswith("%"):
            continue
        if re.match(r"^(?:\\label\{[^}]*\}\s*)+$", s):
            continue
        lines.append(ln)
    return "\n".join(lines)

def process_residue(raw):
    out = []
    pos = 0
    for m in re.finditer(r"\\begin\{(table\*?|description|figure\*?|lstlisting)\}(.*?)\\end\{\1\}", raw, re.S):
        out.append(clean_residue(raw[pos:m.start()]))
        pos = m.end()
        envtype, body = m.group(1), m.group(2)
        if envtype in ("table", "table*"):
            tmatch = re.search(r"\\begin\{tabular\}(.*?)\\end\{tabular\}", body, re.S)
            if tmatch:
                tab = tmatch.group(1)
                cap, lab = extract_caption_label(body)
                if is_complex_table(tab, body):
                    rawhdr = '::: {.content-visible when-format="pdf"}\n```{=latex}\n' + map_raw_latex(m.group(0)) + "\n```\n:::\n"
                    htmltab = tabular_to_html(tab, lab)
                    htmlcap = cell_to_html(cap) if cap else ""
                    htmlhdr = '::: {.content-visible when-format="html"}\n\n' + htmltab + "\n\n" + ("<p class=\"table-caption\">" + htmlcap + "</p>" if htmlcap else "") + "\n\n:::\n"
                    out.append("\n" + rawhdr + "\n" + htmlhdr + "\n")
                else:
                    tab2 = re.sub(r"^\s*\{.*?\}(?=\s*\\)", "", tab, flags=re.S)
                    tab2 = re.sub(r"\\(?:toprule|midrule|bottomrule|addlinespace|cline\{[^}]*\})", "", tab2)
                    rows = []
                    for line in re.split(r"\\\\", tab2):
                        line = line.strip()
                        if line:
                            rows.append([c.strip() for c in line.split("&")])
                    if rows:
                        ncols = max(len(r) for r in rows)
                        norm = [[convert_inlines(c) for c in r] + [""] * (ncols - len(r)) for r in rows]
                        header = "| " + " | ".join(norm[0]) + " |"
                        sep = "|" + "---|" * ncols
                        body_rows = "\n".join("| " + " | ".join(r) + " |" for r in norm[1:])
                        out.append("\n" + header + "\n" + sep + "\n" + body_rows + "\n")
                        cap_md = convert_inlines(cap) if cap else ""
                        if cap_md:
                            out.append("\n: " + cap_md + " {#" + map_key(lab) + "}\n")
                        elif lab:
                            out.append("\n{#" + map_key(lab) + "}\n")
        elif envtype == "description":
            for it in re.split(r"\\item", body)[1:]:
                lm = re.match(r"\[([^\]]*)\](.*)", it, re.S)
                if lm:
                    out.append("\n**" + convert_inlines(lm.group(1)) + "**\n\n" + "\n".join(l.strip() for l in convert_inlines(lm.group(2)).split("\n")).strip() + "\n")
        elif envtype in ("figure", "figure*"):
            cap, lab = extract_caption_label(body)
            img = re.search(r"\\includegraphics(?:\[[^\]]*\])?\{([^}]+)\}", body)
            if img:
                out.append("\n![" + convert_inlines(cap, ara_plain=True) + "](" + img.group(1) + "){#" + map_key(lab) + "}\n")
        elif envtype == "lstlisting":
            lang = re.search(r"\\begin\{lstlisting\}\[language=([^\]]+)\]", m.group(0))
            out.append("\n```" + (lang.group(1) if lang else "") + "\n" + body.strip() + "\n```\n")
    out.append(clean_residue(raw[pos:]))
    return "".join(out)

def convert_file(tex_path):
    """Convert a single .tex file to .md, preserving relative structure."""
    tex_path = Path(tex_path)
    if not tex_path.exists():
        print(f"Warning: {tex_path} not found, skipping")
        return
    
    md_path = tex_path.with_suffix('.md')
    
    # Skip if .md exists and is newer than .tex
    if md_path.exists():
        tex_mtime = tex_path.stat().st_mtime
        md_mtime = md_path.stat().st_mtime
        if md_mtime > tex_mtime:
            print(f"Skipping {tex_path.name} (already up to date)")
            return
    
    src = tex_path.read_text(encoding="utf-8")
    parts = re.split(r"\\begin\{markdown\}|\\end\{markdown\}", src)
    out = [process_residue(parts[0])]
    i = 1
    while i < len(parts):
        if i % 2 == 1:
            out.append(fix_figure_swap(convert_inlines(parts[i])))
        else:
            out.append(process_residue(parts[i]))
        i += 1
    result = "".join(out)
    
    md_path.write_text(result, encoding="utf-8")
    print(f"Converted {tex_path.name} -> {md_path.name} ({len(result)} chars)")


def main():
    """Main entry point: auto-detect .tex files or process specified files."""
    if len(sys.argv) > 1:
        # Explicit files specified
        for arg in sys.argv[1:]:
            tex_path = Path(arg)
            if not tex_path.is_absolute():
                tex_path = SECTIONS_DIR / tex_path
            convert_file(tex_path)
    else:
        # Auto-detect: find all .tex files in sections/
        tex_files = list(SECTIONS_DIR.glob("*.tex"))
        if not tex_files:
            print("No .tex files found in sections/")
            return
        
        for tex_path in tex_files:
            convert_file(tex_path)
    
    print("Pre-render conversion complete")


if __name__ == "__main__":
    main()
