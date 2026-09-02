# PDF-Helper

Quarto 扩展：**pdf(含 html 内容) → 任意期刊 sty 的 PDF 适配器**。

姊妹扩展：[HTML-Helper](../html-helper/README.md)（能力 A：qmd(含 latex) → HTML 翻译器，pandoc 超集）。

## 架构：两个正交能力

| | HTML-Helper | PDF-Helper |
|---|---|---|
| 能力 | qmd(含 latex) → 单格式 HTML | pdf(含 html 内容) → 期刊 sty 的 PDF |
| 发展方向 | 语法扩展：应对层出不穷的 {=latex} block（tabular → algorithm → …） | 模板适配：适配更多期刊 sty（与具体语法无关，解析交给 LaTeX 编译器，再困难可用 {=latex} 兜底） |
| 测试样本 | 语法片段 qmd（tabular 变体、algorithmic 方言…） | 期刊模板编译验证 |
| 归属 | `_extensions/html-helper/` | `_extensions/pdf-helper/` |

使用方两者都挂：`filters: [html-helper, pdf-helper]`——一次编译，双端自动。

## 解决的问题

Markdown 内容（管道表、{=html} 表格）编译进期刊 LaTeX 模板时，pandoc 默认生成 longtable（双栏模板下报错），且无法控制浮动体位置/caption 位置。本扩展把内容翻译成期刊模板认可的 LaTeX 构造（table*/table/longtable + booktabs tabular），并让 tbl- 前缀的失败可见。

## 安装

```bash
# 把 _extensions/pdf-helper/ 复制到目标项目的 _extensions/ 下即可
# （与 html-helper 并排放置；workspace 级 _extensions/ 共享给所有子项目）
```

## 用法

```yaml
---
filters:
  - html-helper
  - pdf-helper          # 只要 PDF 端则只挂这个
format:
  pdf:
    html-helper:        # 配置命名空间暂沿用 html-helper（兼容），后续迁移 pdf-helper
      md-table-env: table*    # 管道表环境：table*（双栏通栏）| table（单栏）| longtable
      md-table-pos: htbp      # 管道表浮动位置参数
      html-table-env: table    # {=html} 直写表环境：table（默认）| table*
      html-table-pos: htbp     # {=html} 表浮动位置参数
      table-caption-pos: top   # caption 位置：top（表上方，ICML 惯例）| bottom（表下方，AAAI/Springer 惯例）
---
```

## 组件

| 文件 | 作用 |
|------|------|
| `pdf-md-tables.lua` | **管道表**（顶层 Table）→ `table*`/`table`/`longtable` booktabs tabular（双栏 longtable 报错故重写为浮动体；caption/label 走 LaTeX 原生）；配置经 `doc.meta` 读取（key: `html-helper`，兼容旧名 `paper-tables`）。只处理顶层 Table，Div 原样保留（{=html} 表交给 pdf-html-tables.lua） |
| `pdf-html-tables.lua` | **`{=html}` 直写表**：`Div(quarto-scaffold)` 包裹的原生 Table → 单栏 `table`（默认）booktabs tabular。独立配置 `html-table-env`/`html-table-pos`（默认 `table`/`htbp`），table-caption-pos 与 pdf-md-tables 共享 |
| `pdf-ref-tbl.lua` | **tbl- 引用提示器**（INFO 日志，不改文档）：正文 `\ref{tbl-X}` → 提示通道行为。实证 2026-08-30：管道表 `{#tbl-X}` 的 `\label{tbl-X}` 被 PDF writer 原样写回中间 tex——LaTeX 原生 \ref 编译命中，**不 ??**（旧版"tbl- 必 ??"判断对管道表不成立）；{=latex} 表 label 被 float 接管挪进 caption（实体保留）但复杂表仍须 tab- 让路（HTML 端 float 接管静默消失） |

## 行为

| 输入 | PDF |
|------|-----|
| Markdown 管道表 | 转成 `table*`/`table`/`longtable` + booktabs tabular（默认 Pandoc 生成的 longtable 在双栏下报错） |
| `{=html}` 直写表 | `pandoc.read()` 解析 `<table>` → booktabs tabular（quarto 会把它解析为 Div 包裹的原生 Table，本扩展整体替换，避免 writer 重组） |
| `{=latex}` 复杂表 | raw LaTeX 原样传递（pdflatex/xelatex 编译）——不归本扩展管 |

## 关键约定

1. **label 前缀必须用 `tab-`**（quarto crossref 只处理 `tbl-`，用 `tab-` 让它让路；否则它会拆碎 raw LaTeX 表格）
2. 正文引用写 `\ref{tab-example}`（PDF 原生解析）
3. 期刊模板适配只需改 `md-table-env`/`table-caption-pos`：

| 模板 | 配置 |
|------|------|
| ICML（双栏） | `md-table-env: table*`，`table-caption-pos: top` |
| IEEE（双栏） | `md-table-env: table`（配 `\hline` 风格需自行调） |
| Springer（单栏） | `md-table-env: table` 或 `longtable`，`table-caption-pos: bottom` |
| AAAI（单栏） | `md-table-env: table`，`table-caption-pos: bottom`（booktabs 三线表即 AAAI 推荐风格） |
| 博客/HTML | 无需配置，默认走 HTML 分支 |

## 踩坑（与 HTML-Helper README 共享历史档案）

PDF 相关条目见 `../html-helper/README.md` 踩坑记录：1、3、5、6、13、15、17、21、24（tbl- 前缀机制）、25。
