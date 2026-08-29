# HTML-Helper2

Quarto 扩展（能力 A 重构版）：**qmd(含 latex) → 单格式 HTML 翻译器**。三模块架构（format / parse / ref），目录结构替代单文件平铺——quarto 扩展支持子目录 filter（实证 2026-08-30）。

## 架构

```
_extensions/html-helper2/
  format/              格式微调，不利用文章语法结构
    html-pdf-embed.lua     .pdf 源图 → <embed aspect-ratio>
  parse/               语法解析
    html-latex-tables.lua  复杂 {=latex} 表格（resizebox/minipage/multicolumn）→ <table>
    html-latex.lua         algorithmic 算法块（双方言）→ algorithm-box 嵌套列表
  ref/                 引用处理（双轨：tab- 自管 / tbl- 后处理）
    html-ref-tbl.lua       \ref{tab-X} 自管编号；\ref{tbl-X} → 占位符（tblref.py 编号）
    html-ref-sec.lua       \S\ref{sec-X} / \ref{sec-X} → §N 链接
    html-ref-fig.lua       \ref{fig-X} → 占位链接（figref.py 编号）
    figref.py              图占位后处理编号（数 quarto float div 顺序）
    tblref.py              表格占位后处理编号（数 tbl- float div 顺序）
```

## 用法

```yaml
filters:
  - html-helper2
  - pdf-helper2
format:
  html:
    html-helper:
      caption-prefix: "Table "
      caption-sep: ": "
      algo-macros:
        "\\ourmethod{}": "SkillOpt"
project:
  post-render:
    - _extensions/html-helper2/ref/figref.py
    - _extensions/html-helper2/ref/tblref.py
```

## 双轨引用通道（实证定案 2026-08-30）

| 通道 | 表格形态 | 编号机制 | 适用 |
|---|---|---|---|
| **tbl-** | 管道表 `{#tbl-X}`（quarto 原生 float） | tblref.py 数 `<div id="tbl-X" class="quarto-float quarto-figure">` 文档顺序——与 quarto `@tbl-X` 编号同源（FloatRefTarget 顺序），双引用语法编号一致 | 新论文管道表 |
| **tab-** | `{=latex}` 复杂表 `\label{tab-X}`（quarto 让路） | html-ref-tbl 自管（AST 统计 RawBlock 顺序） | 复杂表（resizebox 等）必须 tab- |

**为什么复杂表必须 tab-**：实证——{=latex} resizebox 表格 + tbl- 被 quarto float 接管后，HTML 端 pandoc 解析失败 → **整个表格静默消失**（_tbltest/index3 实证）。tab- 让路后 RawBlock 保留，filter 翻译。

**PDF 端 tbl- 不 ??**：quarto 对管道表 tbl- 的 `\label{tbl-X}` **原样写回中间 tex**（实证 index.tex）——LaTeX 原生 `\ref{tbl-X}` 命中。旧 pdf-tbl-warn 的"tbl- 是 @ 地盘、\ref 找不到"机制澄清**对管道表不成立**（已修正，pdf-helper2 里改为提示器）。

## 迁移须知（旧论文 tab- → tbl-）

html-helper2 **移除了 html-md-tables**（管道表 tbl- 走 quarto 原生，不需要它）。旧论文的 **tab- 管道表**会掉进裂缝（既不被 quarto 接管、又无 filter 翻译 → 不是 paper-table、引用占位）。迁移：

1. 管道表 id：`{#tab-X}` → `{#tbl-X}`（caption 行）
2. 指向管道表的引用：`\ref{tab-X}` → `\ref{tbl-X}`
3. `{=latex}` 表格的 `\label{tab-X}` 和引用**保持 tab-**（不能改 tbl-，会触发 float 接管）

判断依据：SkillOpt（全 {=latex} 表，无管道表）切换 html-helper2 无缝（11 表/占位 0 与基线一致）；ARL（52 行 tab- 管道表）切换后 paper-table 9/15、占位 5——需先迁移。

## 算法 label 双形态

html-latex.lua 正文引用支持 `alg:inference`（冒号，TD-MPC 风格）与 `alg-inference`（连字符，SkillOpt 风格）两种 label。

## 实证样本（repo 内）

- `_tbltest/`：路线 C 探针（管道表 tbl- label 原样写回、HTML float div 锚点、{=latex} 复杂表静默消失）
- `_mk4ht-test/`：make4ht 探针（algorithmic 输出结构可用；tabular 在 MiKTeX 挂起——tex4ht 转换器死锁，分步 latex+tex4ht 可绕但输出纯文本）
- `_h2test/`：html-helper2 全链路测试（双端渲染）
