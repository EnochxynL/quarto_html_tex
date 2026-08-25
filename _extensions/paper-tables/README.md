# Paper-Tables

Quarto 扩展：让同一份 LaTeX 表格源码同时渲染为 PDF（原生 LaTeX）和 HTML（`<table>`）。

## 解决的问题

论文写作中，复杂表格（`\multicolumn`、`\shortstack`、`\cmidrule`）无法用 Markdown 管道表表达。
传统做法是维护两份表格（LaTeX + HTML），或用 Python 脚本预生成门控内容。
本扩展在 Pandoc AST 层面用 `pandoc.read()` 解析 LaTeX 表格，零 Python 依赖。

## 安装

### 本地使用（当前项目）

```bash
# 把 _extensions/paper-tables/ 复制到目标项目的 _extensions/ 下即可
```

### 从 GitHub 分发（未来）

```bash
quarto add <user>/paper-tables
```

## 用法

```yaml
---
filters:
  - paper-tables
format:
  pdf:
    paper-tables:
      table-env: table*    # table*（双栏通栏）| table（单栏）| longtable
      table-pos: htbp      # 浮动位置参数
---
```

在正文中写 LaTeX 表格：

````markdown
```{=latex}
\begin{table*}[h]
\centering
\begin{tabular}{lcc}
\toprule
\textbf{列A} & \textbf{列B} & \textbf{列C} \\
\midrule
1 & 2 & 3 \\
\bottomrule
\end{tabular}
\caption{表格标题。}
\label{tab-example}
\end{table*}
```
````

## 行为

| 输出 | 处理方式 |
|------|---------|
| **PDF** | raw LaTeX 原样传递，`xelatex` 编译（crossref.lua 对 `tab-` 前缀让路） |
| **HTML** | `pandoc.read()` 解析为 Table AST → 补 caption/label → 渲染为 `<table>` |

### 关键约定

1. **label 前缀必须用 `tab-`**（Quarto crossref.lua 只处理 `tbl-`，用 `tab-` 让它让路；否则它会拆碎 raw LaTeX 表格）
2. 正文引用写 `\ref{tab-example}`（PDF 原生解析；HTML 由 `crossref-html.lua` 转为 `[§tab-example]` 占位符）
3. `\cmidrule` 会在 HTML 侧自动剥离（Pandoc 不认识它）

## 组件

| 文件 | 作用 |
|------|------|
| `latex-tables.lua` | 核心：raw LaTeX 表格 → HTML `<table>`（返回 RawBlock 绕开 main.lua 的 id 清理） |
| `tables-to-tablestar.lua` | PDF：Markdown 管道表 → `table*`/`table`/`longtable`（默认 Pandoc 生成的 longtable 在双栏下报错） |
| `crossref-html.lua` | HTML：`\ref{X}` → `[§X]` 占位符 |

## 模板适配

不同期刊模板只需改 `table-env`：

| 模板 | 配置 |
|------|------|
| ICML（双栏） | `table-env: table*` |
| IEEE（双栏） | `table-env: table`（配 `\hline` 风格需自行调） |
| Springer（单栏） | `table-env: table` 或 `longtable` |
| 博客/HTML | 无需配置，默认走 HTML 分支 |
