#!/usr/bin/env python3
"""tblref.py — HTML 表格引用占位符自动编号（quarto post-render 脚本）

背景（html-helper2 的 tbl- 通道）：
  管道表用 {#tbl-X} 时 quarto 原生接管（reader 消费 id 进 crossref 内部状态，
  用户 filter 拿不到 id 自数）——实证（2026-08-30）：
    1) PDF 端：\\label{tbl-X} 原样写回中间 tex（\\ref{tbl-X} 在 LaTeX 层命中，
       不 ??）；{=latex} 表格的 label 被挪进 \\caption 但保留（同样命中）。
    2) HTML 端：quarto 输出 <div id="tbl-X" class="quarto-float quarto-figure ...">
       包裹 div（锚点存在，编号 = FloatRefTarget 文档顺序）。
  html-ref-tbl.lua 对正文 \\ref{tbl-X}（Math/RawInline/Link）输出占位
  <a href="#tbl-X">[tbl-X]</a>（tab- 通道自数，tbl- 通道走后处理）。
  本脚本在 quarto 渲染完成后数 tbl- float div 的文档顺序得编号，替换占位符。
  编号与 quarto 原生 @tbl-X 引用同源（都数 FloatRefTarget 顺序），双引用语法
  编号一致；前缀（"Table " / "表 "）从正文 quarto-xref 引用学习（零配置）。

用法：由 quarto 自动调用（_quarto.yml project.post-render，与 figref.py 并列），
  或手动: python tblref.py <file.html> [file2.html ...]
环境变量：QUARTO_PROJECT_OUTPUT_FILES（quarto 传入，换行分隔的相对路径）
"""
import os
import re
import sys

# 管道表 float 包裹 div：<div id="tbl-X" class="quarto-float quarto-figure ...">
DIV_RE = re.compile(r'<div id="(tbl-[^"]+)" class="quarto-float quarto-figure')
# quarto 渲染的表格 xref：<a href="#tbl-X" class="quarto-xref">Table&nbsp;1</a>
XREF_RE = re.compile(
    r'<a href="#tbl-[^"]+" class="quarto-xref"[^>]*>\s*([^<&]+?)\s*&nbsp;?\s*\d+</a>')
# 管道表 caption 格式学习：<figcaption ... quarto-float-tbl ...>Table&nbsp;1: 标题
# 提取"数字前的词"（Table/表）与"数字后的分隔符"（: / ：）
CAP_WORD_RE = re.compile(
    r'<figcaption[^>]*quarto-float-tbl[^>]*>\s*([^<&\d]*?)&nbsp;?\s*\d+')
CAP_SEP_RE = re.compile(
    r'<figcaption[^>]*quarto-float-tbl[^>]*>\s*[^<&\d]*?&nbsp;?\s*\d+\s*([:：])')
# 复杂表 caption 占位：<div class="table-caption">[TAB-CAP:6]标题</div>
TAB_CAP_RE = re.compile(r'\[TAB-CAP:(\d+)\]')
# 占位（可能带前缀残留，pandoc 把 ~ 转 &nbsp;）：<a href="#tbl-X">[tbl-X]</a>
PLACEHOLDER_RE = re.compile(
    r'(?:Table|Tab\.?|表)(?:(?:&nbsp;)|[ \t~\r\n])*<a href="#(tbl-[^"]+)"[^>]*>\[(?:tbl-[^\]]+)\]</a>')
PLACEHOLDER_BARE_RE = re.compile(
    r'<a href="#(tbl-[^"]+)"[^>]*>\[(?:tbl-[^\]]+)\]</a>')
# 链接后句号被换行分隔（</a>\n.）→ 紧贴（PDF 端 "Table 4." 一致）
PERIOD_FIX_RE = re.compile(r'</a>\s*\r?\n\s*\.')


def process(path):
    try:
        with open(path, encoding="utf-8") as fh:
            html = fh.read()
    except OSError as e:
        print(f"tblref: 跳过 {path}: {e}")
        return

    # 1) 表格编号：数 tbl- float div 文档顺序（quarto 编号 = FloatRefTarget 顺序）
    tbl_nums = {}
    for i, m in enumerate(DIV_RE.finditer(html), 1):
        tbl_nums.setdefault(m.group(1), i)
    # 无 tbl- 表格不早退：复杂表 [TAB-CAP] 占位仍需处理（SkillOpt 全复杂表场景）

    # 2) 前缀学习：优先从正文 quarto-xref "Table&nbsp;1" / "表&nbsp;1" 提取
    prefix = "Table "
    for m in XREF_RE.finditer(html):
        word = m.group(1).strip()
        if word:
            prefix = word + " "
            break

    # 3) caption 格式学习：从管道表 figcaption 提取前缀词与分隔符
    #    （"Table&nbsp;1: 标题" → word="Table" sep=":"）——复杂表 [TAB-CAP:N]
    #    占位用同一格式填充，零配置且与管道表天然统一（跟随 quarto 语言设置）
    cap_word, cap_sep = None, ": "
    mw = CAP_WORD_RE.search(html)
    if mw:
        cap_word = mw.group(1).strip()
    ms = CAP_SEP_RE.search(html)
    if ms:
        cap_sep = ms.group(1) + (" " if ms.group(1) == ":" else "")
    cap_prefix = (cap_word + " ") if cap_word else prefix

    # 4) 替换占位（带前缀残留的先吃，裸占位兜底）
    def repl(m, ref):
        n = tbl_nums.get(ref)
        if n is None:
            return m.group(0)
        return f'<a href="#{ref}">{prefix}{n}</a>'

    new_html, c1 = PLACEHOLDER_RE.subn(
        lambda m: repl(m, m.group(1)), html)
    new_html, c2 = PLACEHOLDER_BARE_RE.subn(
        lambda m: repl(m, m.group(1)), new_html)
    count = c1 + c2

    # 5) 复杂表 caption 占位填充（[TAB-CAP:N] → "Table N: "）
    cap_count = 0
    if TAB_CAP_RE.search(new_html):
        new_html, cap_count = TAB_CAP_RE.subn(
            lambda m: f"{cap_prefix}{m.group(1)}{cap_sep}", new_html)

    if count or cap_count:
        new_html = PERIOD_FIX_RE.sub('</a>.', new_html)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(new_html)
        print(f"tblref: 替换 {count} 处表格引用占位 + {cap_count} 处 caption（前缀 "
              f"\"{prefix}\"，caption 格式 \"{cap_prefix}N{cap_sep}\"，{len(tbl_nums)} 个表）→ {path}")
    else:
        print(f"tblref: {path} 无表格引用占位（{len(tbl_nums)} 个表，跳过）")


def main():
    files = []
    env = os.environ.get("QUARTO_PROJECT_OUTPUT_FILES", "")
    if env:
        files = [f for f in env.splitlines() if f.strip().endswith((".html", ".htm"))]
    files.extend(a for a in sys.argv[1:] if a.endswith((".html", ".htm")))
    seen, uniq = set(), []
    for f in files:
        if f not in seen:
            seen.add(f)
            uniq.append(f)
    if not uniq:
        print("tblref: 无输出文件（QUARTO_PROJECT_OUTPUT_FILES 未设置且无参数）")
        return
    for f in uniq:
        if os.path.exists(f):
            process(f)
        else:
            print(f"tblref: 跳过（不存在）{f}")


if __name__ == "__main__":
    main()
