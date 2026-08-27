#!/usr/bin/env python3
"""figref.py — HTML 图引用占位符自动编号（quarto post-render 脚本）

背景：
  复杂表格走 RawBlock(html) 绕开 quarto Table 处理（html-latex-tables.lua），
  caption 内的 \\ref{fig-X} 在 RawBlock 字符串里，quarto crossref 是 AST 层
  遍历（只找 Cite 节点），永远不碰字符串内部 —— 引用语法换什么（\\ref / @fig-X）
  都没用。html-crossref.lua 只能输出占位 <a href="#fig-X">[fig-X]</a>。
  本脚本在 quarto 渲染完成后运行（project.post-render）：此时 quarto 已把
  @fig-X 渲染成 <div id="fig-X" class="quarto-float quarto-figure ..."> 包裹
  div（编号已定，figcaption 文本里就有 "Figure N:"）—— 数包裹 div 的文档
  顺序得 fig-X → N 映射，替换占位符。
  前缀（"Figure " / "图 "）从正文 quarto-xref 引用学习（零配置中英文通吃）。

用法：由 quarto 自动调用（_quarto.yml project.post-render），或手动:
  python figref.py <file.html> [file2.html ...]

环境变量：QUARTO_PROJECT_OUTPUT_FILES（quarto 传入，换行分隔的相对路径）
"""
import os
import re
import sys

# 图包裹 div：<div id="fig-X" class="quarto-float quarto-figure ...">
DIV_RE = re.compile(r'<div id="(fig-[^"]+)" class="quarto-float quarto-figure')
# quarto 渲染的 figure xref：<a href="#fig-X" class="quarto-xref">Figure&nbsp;1</a>
XREF_RE = re.compile(
    r'<a href="#fig-[^"]+" class="quarto-xref"[^>]*>\s*([^<&]+?)\s*&nbsp;?\s*\d+</a>')
# 占位（可能带 LaTeX 前缀残留 Figure~/Fig.~/图~，pandoc 把 ~ 转成 &nbsp;，
# caption 序列化时词间以换行分隔）：<a href="#fig-X">[fig-X]</a>
PLACEHOLDER_RE = re.compile(
    r'(?:Figure|Fig\.?|图)(?:(?:&nbsp;)|[ \t~\r\n])*<a href="#(fig-[^"]+)"[^>]*>\[(?:fig-[^\]]+)\]</a>')
PLACEHOLDER_BARE_RE = re.compile(
    r'<a href="#(fig-[^"]+)"[^>]*>\[(?:fig-[^\]]+)\]</a>')
# 链接后句号被换行分隔（</a>\n.）→ 紧贴（PDF 端 "Figure 4." 一致）
PERIOD_FIX_RE = re.compile(r'</a>\s*\r?\n\s*\.')


def process(path):
    try:
        with open(path, encoding="utf-8") as fh:
            html = fh.read()
    except OSError as e:
        print(f"figref: 跳过 {path}: {e}")
        return

    # 1) 图编号：数包裹 div 文档顺序（quarto 编号 = FloatRefTarget 文档顺序）
    fig_nums = {}
    for i, m in enumerate(DIV_RE.finditer(html), 1):
        fig_nums.setdefault(m.group(1), i)
    if not fig_nums:
        print(f"figref: {path} 无图（跳过）")
        return

    # 2) 前缀学习：优先从正文 quarto-xref "Figure&nbsp;1" / "图&nbsp;1" 提取
    prefix = "Figure "
    for m in XREF_RE.finditer(html):
        word = m.group(1).strip()
        if word:
            prefix = word + " "
            break

    # 3) 替换占位（带前缀残留的先吃，裸占位兜底）
    def repl(m, ref):
        n = fig_nums.get(ref)
        if n is None:
            return m.group(0)
        return f'<a href="#{ref}">{prefix}{n}</a>'

    new_html, c1 = PLACEHOLDER_RE.subn(
        lambda m: repl(m, m.group(1)), html)
    new_html, c2 = PLACEHOLDER_BARE_RE.subn(
        lambda m: repl(m, m.group(1)), new_html)
    count = c1 + c2
    if count:
        # 句号紧贴链接（</a>\n. → </a>.，PDF 端 "Figure 4." 一致）
        new_html = PERIOD_FIX_RE.sub('</a>.', new_html)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(new_html)
        print(f"figref: 替换 {count} 处图引用占位（前缀 \"{prefix}\"，{len(fig_nums)} 个图）→ {path}")
    else:
        print(f"figref: {path} 无图引用占位（{len(fig_nums)} 个图，跳过）")


def main():
    files = []
    env = os.environ.get("QUARTO_PROJECT_OUTPUT_FILES", "")
    if env:
        files = [f for f in env.splitlines() if f.strip().endswith((".html", ".htm"))]
    files.extend(a for a in sys.argv[1:] if a.endswith((".html", ".htm")))
    # 去重保序
    seen, uniq = set(), []
    for f in files:
        if f not in seen:
            seen.add(f)
            uniq.append(f)
    if not uniq:
        print("figref: 无输出文件（QUARTO_PROJECT_OUTPUT_FILES 未设置且无参数）")
        return
    for f in uniq:
        if os.path.exists(f):
            process(f)
        else:
            print(f"figref: 跳过（不存在）{f}")


if __name__ == "__main__":
    main()
