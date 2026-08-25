# Paper-Tables

Quarto 扩展：让同一份表格源码同时渲染为 PDF（原生 LaTeX）和 HTML（`<table>`）。

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
      caption-pos: top     # caption 位置：top（表上方，ICML 惯例）| bottom（表下方，AAAI/Springer 惯例）
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

也可以直写 HTML 表格（PDF 端自动转成 booktabs 三线表）：

````markdown
```{=html}
<table id="tab-example2">
<caption>HTML 直写的表格。</caption>
<thead>
<tr><th>a</th><th>b</th></tr>
</thead>
<tbody>
<tr><td>1</td><td>2</td></tr>
</tbody>
</table>
```
````

## 行为

| 输入 | PDF | HTML |
|------|-----|------|
| `{=latex}` 复杂表 | raw LaTeX 原样传递（`xelatex` 编译） | `pandoc.read()` 解析为 Table AST → 补 caption/label → 渲染为 `<table>` |
| Markdown 管道表 | 转成 `table*`/`table`/`longtable` + booktabs tabular（默认 Pandoc 生成的 longtable 在双栏下报错） | Pandoc 原生 `<table>` |
| `{=html}` 直写表 | `pandoc.read()` 解析 `<table>` → 同一套 booktabs tabular（quarto 会把它解析为 Div 包裹的原生 Table，本扩展整体替换，避免 writer 重组） | 原样输出 |

### 关键约定

1. **label 前缀必须用 `tab-`**（Quarto crossref.lua 只处理 `tbl-`，用 `tab-` 让它让路；否则它会拆碎 raw LaTeX 表格）
2. 正文引用写 `\ref{tab-example}`（PDF 原生解析；HTML 由 `crossref-html.lua` 转为 `[§tab-example]` 占位符）
3. `\cmidrule` 会在 HTML 侧自动剥离（Pandoc 不认识它）

## 组件

| 文件 | 作用 |
|------|------|
| `latex-tables.lua` | 核心：raw LaTeX 表格 → HTML `<table>`（返回 RawBlock 绕开 main.lua 的 id 清理） |
| `tables-to-tablestar.lua` | PDF：管道表/`{=html}` 表 → `table*`/`table`/`longtable` booktabs tabular（`Pandoc()` 回调 + 手写递归，配置经 `doc.meta` 读取） |
| `crossref-html.lua` | HTML：`\ref{X}` → `[§X]` 占位符 |

### 踩坑记录（实现注意）

1. **`pandoc.meta` 在 filter 模块顶层和元素回调（Table/RawBlock）内都是 nil 或空表**——只有 `Pandoc(doc)` 回调的 `doc.meta` 才有完整 metadata。因此 `tables-to-tablestar.lua` 用 `Pandoc()` 回调 + 手写递归遍历（`pandoc.walk_block` 在本 pandoc 版本不可靠：函数 filter 报错、表 filter 静默不调用）。
2. **metadata 值是 MetaInlines（`[Str "x"]`）**，需 `pandoc.utils.stringify` 才能与字符串比较（否则 `== "bottom"` 恒为 false）。
3. **quarto 把 `{=html}` 的 `<table>` 解析为 `Div(quarto-scaffold)` 包裹的原生 Table**，`<caption>` 文本被拆到独立的 `Plain` 块、Table.caption 为空。处理时需提取 Table + Plain，并**整体替换整个 Div**（只替换内部 Table 会被 quarto writer 重组：丢失位置参数、注入重复 label）。
4. 提取 Table/caption 时**不能以"找到 Table"作为返回条件**——含 caption 的子树可能没有 Table。

## 模板适配

不同期刊模板只需改 `table-env` / `caption-pos`：

| 模板 | 配置 |
|------|------|
| ICML（双栏） | `table-env: table*`，`caption-pos: top` |
| IEEE（双栏） | `table-env: table`（配 `\hline` 风格需自行调） |
| Springer（单栏） | `table-env: table` 或 `longtable`，`caption-pos: bottom` |
| AAAI（单栏） | `table-env: table`，`caption-pos: bottom`（booktabs 三线表即 AAAI 推荐风格） |
| 博客/HTML | 无需配置，默认走 HTML 分支 |
