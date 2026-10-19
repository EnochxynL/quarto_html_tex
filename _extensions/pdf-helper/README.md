# PDF-Helper

Quarto 扩展：**pdf(含 html/markdown 表格内容) → 任意期刊模板的 PDF 适配器**。目标：任何 latex 模板（cls/sty）结合自己写的 qmd 就能马上编译。

姊妹扩展：[HTML-Helper](../html-helper/README.md)（qmd(含 latex) → HTML 翻译器）。两者都挂：`filters: [html-helper, pdf-helper]`——一次编译，双端自动（HTML filter 有 FORMAT 守卫，PDF filter 只在 pdf/latex 格式运行，互不干扰）。

## 目录结构

```
_extensions/pdf-helper/
  _extension.yml            filter 链声明
  md/                       Markdown 内容领地
    pdf-md-tables.lua         管道表（Table / FloatRefTarget）→ table*/table/longtable + booktabs tabular
  html/                     {=html} 内容领地
    pdf-html-tables.lua       {=html} 直写表 → 单栏 table + booktabs tabular
  ref/                      引用领地
    pdf-ref-tbl.lua           tbl- 引用校验器（缺失目标标签时警告，不改文档）
```

**filter 链**：`md/pdf-md-tables.lua → html/pdf-html-tables.lua → ref/pdf-ref-tbl.lua`。三者均在 `post-quarto` 阶段运行：先展开 shortcode、注册交叉引用，再转换表格并校验目标标签。

## 解决的问题

Markdown 内容（管道表、{=html} 表格）编译进期刊 LaTeX 模板时：pandoc 默认生成 longtable（双栏模板报错）、浮动体位置/caption 位置不可控。本扩展把内容翻译成期刊模板认可的 LaTeX 构造。

**表格三通道**：Markdown 管道表（md/）· {=html} 直写表（html/）· {=latex} 原样传递（LaTeX 编译器处理——本扩展不碰）。

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
      table-caption-pos: top   # caption 位置：top（表上方，ICML 惯例）| bottom（AAAI/Springer 惯例）
---
```

## 组件

| 文件 | 作用 |
|------|------|
| `md/pdf-md-tables.lua` | **管道表** → `table*`/`table`/`longtable` booktabs tabular。具名表从 Quarto 的 `FloatRefTarget` 取回 ID 和 caption，整体替换浮动体；普通顶层 `Table` 作为兜底。跳过带 `quarto-postprocess` 标记的 HTML 导入表。配置经 `doc.meta` 读取（key: `html-helper`，兼容旧名 `paper-tables`）。 |
| `html/pdf-html-tables.lua` | **{=html} 直写表**：`Div(quarto-scaffold)` 包裹的原生 Table → 单栏 `table`（默认）booktabs tabular。独立配置 `html-table-env`/`html-table-pos`（默认 `table`/`htbp`），table-caption-pos 与 pdf-md-tables 共享 |
| `ref/pdf-ref-tbl.lua` | **tbl- 引用校验器**：收集转换后的 LaTeX 标签、剩余表格 ID 和 `\ref{tbl-X}`，仅在目标缺失时警告。不改正文，也不因标签前缀就假定引用能成功。 |

## 行为

| 输入 | PDF |
|------|-----|
| Markdown 管道表 | 转成 `table*`/`table`/`longtable` + booktabs tabular（默认 Pandoc 生成的 longtable 在双栏下报错） |
| `{=html}` 直写表 | `pandoc.read()` 解析 `<table>` → booktabs tabular（quarto 把它解析为 Div 包裹的原生 Table，本扩展整体替换，避免 writer 重组） |
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

## 历史踩坑

PDF 相关的历史踩坑记录（tex4ht/make4ht/html-crossref 时代，1-27 条）已随 html-helper README 重写删除——完整历史在 git 里（`git log` + `git show <commit>:README.md` 可回溯）。
