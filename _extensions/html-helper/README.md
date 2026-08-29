# HTML-Helper

Quarto 扩展（能力 A）：**qmd(含 latex) → 单格式 HTML 翻译器**——用自定义 Lua 解析器做 pandoc 做不到的事（复杂表格/算法块/引用体系），本质是 pandoc 的超集。

姊妹扩展：[PDF-Helper](../pdf-helper/README.md)（能力 B：pdf(含 html 内容) → 期刊 sty 的 PDF 适配器）。

## 架构：两个正交能力

| | HTML-Helper | PDF-Helper |
|---|---|---|
| 能力 | qmd(含 latex) → 单格式 HTML | pdf(含 html 内容) → 期刊 sty 的 PDF |
| 发展方向 | 语法扩展：应对层出不穷的 {=latex} block（tabular → algorithm → …） | 模板适配：适配更多期刊 sty（解析交给 LaTeX 编译器，再困难可用 {=latex} 兜底） |
| 测试样本 | 语法片段 qmd | 期刊模板编译验证 |
| 归属 | `_extensions/html-helper/` | `_extensions/pdf-helper/` |

使用方两者都挂：`filters: [html-helper, pdf-helper]`——一次编译，双端自动。拆分为两个扩展是为了独立开发空间（演进方向/测试策略/失败模式不同），使用体验零损失。

## 解决的问题

论文写作中，复杂表格（`\multicolumn`、`\shortstack`、`\cmidrule`）、算法块（algorithmic）等 `{=latex}` 内容无法用 Markdown 表达，而 quarto 对 `{=latex}` 在 HTML 端**静默忽略**。本扩展在 Pandoc AST 层面翻译这些 LaTeX 内容块为 HTML：复杂表格（剥 resizebox/minipage/multicolumn → `<table>`）、算法（algorithmic/algpseudocode 双方言 → 嵌套列表）、引用体系（tab/sec/fig/alg 交叉引用）——**pandoc 解析不了的（实证：resizebox 弃表、algorithmic 命令吞毁、\ref 数学化）正是本扩展的功夫所在**。

## 安装

### 本地使用（当前项目）

```bash
# 把 _extensions/html-helper/ 复制到目标项目的 _extensions/ 下即可
```

### 从 GitHub 分发（未来）

```bash
quarto add <user>/html-helper
```

## 用法

```yaml
---
filters:
  - html-helper
  - pdf-helper          # 只要 HTML 端则只挂 html-helper
format:
  html:
    html-helper:
      caption-prefix: "Table "   # 表格 caption 编号前缀（英文论文 "Table "；默认中文 "表 "）
      caption-sep: ": "          # 编号与标题间分隔符（英文 ": "；默认中文 "："）
      algo-caption-prefix: "Algorithm "  # 算法 caption 前缀（默认 "Algorithm "）
      algo-caption-sep: ": "
      algo-macros:               # 算法块自定义宏（纯字符串替换，如 \ourmethod{} → SkillOpt）
        "\\ourmethod{}": "SkillOpt"
---
```

PDF 端配置（期刊模板适配）见 [PDF-Helper README](../pdf-helper/README.md)。

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
| `{=latex}` 复杂表 | raw LaTeX 原样传递（`xelatex` 编译） | `pandoc.read()` 解析为 Table AST → 补 caption/label → 渲染为 `<table>`（`paper-table` class） |
| Markdown 管道表 | 转成 `table*`/`table`/`longtable` + booktabs tabular（默认 Pandoc 生成的 longtable 在双栏下报错） | 转 RawBlock(`<table>`)——quarto 的 Table 处理会清空 id 并把 `{#id}` 残留进 caption，必须绕过 |
| `{=html}` 直写表 | `pandoc.read()` 解析 `<table>` → 同一套 booktabs tabular（quarto 会把它解析为 Div 包裹的原生 Table，本扩展整体替换，避免 writer 重组） | 转 RawBlock(`<table>`)（原样语义） |

### HTML 端编号与引用（html-crossref.lua v2）

quarto 只对 `tbl-` 前缀表格做编号/crossref，本扩展所有表格都用 `tab-` 前缀绕开它，因此 **HTML 端编号和引用由 html-crossref.lua 统一负责**：

- 所有 `<table>` 按文档顺序编号（与 PDF 端 LaTeX 自动编号一致），caption 加"表 N："前缀
- 正文 ``\ref{tab-X}`` / ``\S\ref{tab-X}`` → ``<a href="#tab-X">表 N</a>``（可点击跳转）
- 章节 ``\S\ref{sec-X}`` → ``<a href="#sec-X">§N</a>``（N 为按 Header 层级自数的编号，与 PDF 端一致）
- 图 ``\ref{fig-X}`` → ``<a href="#fig-X">[fig-X]</a>``（quarto 锚点存在；图编号由 quarto writer 阶段生成，filter 拿不到）
- 悬空引用（目标 id 不存在，如 ``\ref{sec-related}``）→ ``[§X]`` 占位符

### 关键约定

1. **label 前缀必须用 `tab-`**（Quarto crossref.lua 只处理 `tbl-`，用 `tab-` 让它让路；否则它会拆碎 raw LaTeX 表格）
2. 正文引用写 ``\ref{tab-example}``（PDF 原生解析；HTML 由 `html-crossref.lua` 转为可点击链接）
3. ``\cmidrule`` 会在 HTML 侧自动剥离（Pandoc 不认识它）

## 组件

| 文件 | 作用 |
|------|------|
| `html-latex-tables.lua` | 核心：raw LaTeX 表格 → HTML `<table>`（返回 RawBlock 绕开 main.lua 的 id 清理）；表格内 `\citep{key}` → 子文档跑 `pandoc.utils.citeproc` 渲染 `(Author Year)`。仅 HTML 生效，PDF 原样 |
| `html-md-tables.lua` | 管道表/`{=html}` 表 → RawBlock(`<table>`)（绕过 quarto 的 Table 处理：清 id + caption 残留 `{#id}`） |
| `html-tab-crossref.lua` | 表格引用体系：`<table>` 文档顺序编号 + caption 前缀（`caption-prefix`/`caption-sep` 配置化）+ 正文 `\ref{tab-X}`（RawInline/Math/Link 三分支）→ `<a href="#tab-X">N</a>`；组合表 div 版 caption 前缀 |
| `html-sec-crossref.lua` | 章节引用：`\S\ref{sec-X}` / `\ref{sec-X}` → `<a href="#sec-X">§N</a>`（按 Header 层级自数编号） |
| `html-fig-crossref.lua` | 图引用 + 未知引用兜底：`\ref{fig-X}` → 占位链接（figref.py 后处理编号）；未命中引用 → `[§X]` 占位 |
| `html-algorithm.lua` | 算法块翻译：algorithmic/algpseudocode 双方言 → 嵌套列表（`algorithm-box` div）；`\Call`/`\Return`/`\If`/跨行颜色/行尾注释；编号 `algo-caption-prefix`/`algo-caption-sep` + `algo-macros` 宏表 |
| `html-pdf-embed.lua` | HTML 端 `.pdf` 源图 → `<embed style="width:100%; aspect-ratio:W/H">`（Lua 读 PDF 文件头 `/MediaBox` 明文算比例，浏览器自动算高度，保留矢量；多页取第一页；读不到则降级原样输出） |
| `figref.py` | **post-render 脚本**：表格 caption 内图引用占位符 `<a href="#fig-X">[fig-X]</a>` → `<a href="#fig-X">Figure N</a>`（quarto 渲染完成后数 `<div id="fig-X" class="quarto-float quarto-figure">` 文档顺序，前缀从正文 quarto-xref 学习） |

PDF 端组件（pdf-md-tables / pdf-html-tables / pdf-tbl-warn）见 [PDF-Helper README](../pdf-helper/README.md)。

### 踩坑记录（实现注意）

历史档案（含 PDF-Helper 相关条目：1/3/5/6/13/15/17/21/24，索引见 PDF-Helper README）。

1. **`pandoc.meta` 在 filter 模块顶层和元素回调（Table/RawBlock）内都是 nil 或空表**——只有 `Pandoc(doc)` 回调的 `doc.meta` 才有完整 metadata。因此 `html-md-tables.lua`/`pdf-md-tables.lua`/`html-crossref.lua` 都用 `Pandoc()` 回调 + 手写递归遍历（`pandoc.walk_block` 在本 pandoc 版本不可靠：函数 filter 报错、表 filter 静默不调用；`pandoc.walk_inline` 也报错）。
2. **metadata 值是 MetaInlines（`[Str "x"]`）**，需 `pandoc.utils.stringify` 才能与字符串比较（否则 `== "bottom"` 恒为 false）。
3. **quarto 把 `{=html}` 的 `<table>` 解析为 `Div(quarto-scaffold)` 包裹的原生 Table**，`<caption>` 文本被拆到独立的 `Plain` 块、Table.caption 为空。处理时需提取 Table + Plain，并**整体替换整个 Div**（只替换内部 Table 会被 quarto writer 重组：丢失位置参数、注入重复 label）。
4. 提取 Table/caption 时**不能以"找到 Table"作为返回条件**——含 caption 的子树可能没有 Table。
5. **quarto reader 不消费管道表 caption 的 `{#id}`**（pandoc 原生消费，quarto 不消费）——残留文本留在 caption，attr.identifier 为空。HTML 转换时需在字符串层面提取 `{#id}` → `<table id>` 并移除残留。
6. **quarto 的 Table 处理（main.lua）会清空非 `tbl-` 前缀的 attr.identifier** 并把 id 写回 caption 文本——这是管道表必须转 RawBlock 的原因。
7. **Lua pattern 陷阱**：`\\S?\\ref` 在 Lua 里是"两个反斜杠 + 可选 S + ref"，匹配不了单反斜杠的 `\ref`——必须分两个 pattern 先匹配 `\S\ref` 再匹配 `\ref`（`\S\ref{X}` 还会被 pandoc 拆成两个独立 RawInline：`\S` 和 `\ref{X}`）。
8. **pandoc 的 LaTeX reader 把 `\ref{X}` 解析成 Link 节点**（`reference-type=ref` 属性、链接文本 `[X]`）而非 RawInline——html-latex-tables.lua write 成 html 后是 `<a href="#X" data-reference-type="ref">[X]</a>`，`\ref{...}` 文本 gsub 匹配不到。html-crossref.lua 需额外处理该形态（`§` 前缀版去掉 ref_link 返回的 `§` 避免重复）。正文 markdown 路径不受影响（`\ref` 是 RawInline tex）。
9. **pandoc.write 对长属性行换行**（`<a\nhref=...`），HTML 文本 pattern 匹配 `<a href` 会失败——用 `%s+` 吸收空白。注意 quarto render 的 writer options 与 `quarto run` 直调 pandoc.write 不同（后者 wrap=auto 必换行），调试时以实际渲染产物为准。
10. **Lua pattern 里 `§?`（可选多字节 UTF-8 字符）匹配空分支失败**——`(§?)<a` 匹配不到无 `§` 前缀的 `<a`。拆成两个独立 gsub（带 `§` / 不带）。
11. **quarto 交叉引用 `@fig-X` 后直接跟汉字会被吞进 citationId**（`@fig-X按难度` → id=`fig-X按难度`，quarto 找不到 → 渲染 `?@fig-X` + Strong 包住被吞文本）。pandoc 的 citation id 边界：汉字/ASCII 字母数字连续吞，全角标点（`，（）。、`）是边界。修复：内容层把后跟汉字的 `@fig-X` 改成 `[@fig-X]`（方括号是边界，quarto 渲染视觉等价）。
12. **RawBlock 字符串内部不经过主文档 citeproc**——`{=latex}` 表格内的 `\citep{key}` 经 pandoc.read 解析为 Cite，内部 write 无 citeproc → HTML writer 输出**空 span**（静默消失，无文本无报错）。修复：html-latex-tables.lua 改 Pandoc(doc) 回调（元素回调拿不到 doc.meta 的 bibliography），表格子文档注入 `bibliography` 后调 `pandoc.utils.citeproc`（pcall 保护），`\citep{key}` → `(Starace et al. 2025)`。仅当文本含 `\cite` 时调用（省开销）。
13. **quarto 把 `format.pdf` 下的扩展配置提升为顶层 meta（平铺）**——`format: pdf: html-helper: {md-table-env, md-table-pos, table-caption-pos}` 经 quarto 合并后 `doc.meta["html-helper"]` 是 `{md-table-env=..., table-caption-pos=..., md-table-pos=...}`（**无 `pdf` 嵌套层**，实证 keys）。若 read_config 读 `meta["html-helper"]["pdf"]` 恒为 nil → 全默认值：`md-table-env`/`md-table-pos` 默认恰等于示例值（table*/htbp）掩盖 bug，`table-caption-pos` 默认 top 导致管道表 caption 一直在表格上方。修复：read_config 嵌套优先（`html-helper.pdf.x`）、平铺回退（`html-helper.x`）。
14. **quarto 无原生 PDF 图位置控制，但 `fig-pos` 可传 LaTeX 位置参数**——markdown 图生成的 `\begin{figure}` 默认无位置参数（LaTeX 默认 tbp：top 空间不足时沉底/穿插文中）。实测：`figure-placement: top`（metadata/format 级）不生效；`fig-pos: top` 把 `top` 字面塞进 `\begin{figure}[top]` → LaTeX 报错（fig-pos 文档上是 HTML 选项，但值会被**原样**写入 PDF 的 figure 位置参数）。**正解：`fig-pos: "!t"`**（format.pdf 下，值须用 LaTeX 位置参数语法并加引号——`!` 开头会被 YAML 当 tag）。备选：LaTeX 层 `\usepackage{float}` + `\floatplacement{figure}{!t}`（include-in-header）。**filter 方案不可行**：PDF 端图是带 `__quarto_custom_type="FloatRefTarget"` 标记的 Div，caption 纯文本无 `{#fig-X}`（id 被 quarto 消费进内部状态），整体转 RawBlock 绕开 main.lua → `\label{fig-X}` 丢失、交叉引用全断。
15. **`number-sections: true` 默认编号到最深层级**——`####`（→ LaTeX `\paragraph`，pandoc 默认映射）和 `#####` 也会被编号：PDF 端 quarto 写 `\setcounter{secnumdepth}{5}`，HTML 端 h4/h5 也带 data-number。若要编号止于 subsubsection（原始论文的 \paragraph 无自动编号、secnumdepth 默认 3），用 **`number-depth: 3`**（顶层，一个配置同时控制 PDF 的 secnumdepth 与 HTML 的编号深度；`toc-depth` 只影响目录显示不影响编号）。
16. **quarto 对 `.pdf` 源图在 HTML 端输出 `<embed>`（不可控）**——浏览器 PDF viewer 嵌入：`img-fluid` 的 `max-width:100%` 只设上限不强制撑满（PDF 页面固有宽度小 → 显示小一圈）；CSS 强制 `width:100%` 后高度又不按原图比例（viewer 行为，CSS 治不了）。**正解：读 MediaBox 算比例 + CSS aspect-ratio**——PDF 文件头的 `/MediaBox [0 0 W H]` 是明文（页面对象通常未压缩），Lua `io.open` 读取匹配即可得宽高比；输出 `<embed style="width:100%; aspect-ratio:W/H">`，现代浏览器按比例自动算高度（Chrome 88+/Firefox 89+/Safari 15+）。**不用转 PNG**（保矢量、免预处理）。附带实证：pandoc 的 Image attr 会透传 `width`/`height` 到 embed（`{width=800px}` → `width="800"`），但 **`style` 键被丢弃**——所以只能 RawInline 输出。备选（已弃）：转同名 PNG（`pdftoppm -f 1 -l 1 -png -r 300`），损失矢量。
17. **quarto 1.9+ 的 `listings: true` 已失效，代码块走 listings 要用 `syntax-highlighting: idiomatic`**——quarto 默认把 markdown 代码块渲染成 fancyvrb `Shaded`/`Highlighting` 环境（自带高亮宏，`\lstset` 不生效）；`listings: true`（旧选项，等价 `--listings`）在 1.10 实测不切换。`syntax-highlighting: idiomatic`（format.pdf 下）→ 代码块输出 `\begin{lstlisting}`，`\lstset` 样式生效（与原始论文一致）。字号注意：原始论文每块 `[basicstyle=\ttfamily\scriptsize]` 覆盖全局 small——迁移时直接改 lstset 的 basicstyle。
18. **`\checkmark`（amssymb 数学符号）在双端失效**——HTML 端 pandoc 的 texmath 不认识 `\checkmark` → 静默丢弃（单元格变空 `<td>`）；PDF 端 xelatex 的 math font 下 amssymb 的 MSAM legacy 字形缺失（pdflatex 正常，原始论文即 pdflatex）。**修复：改用 pifont 的 `\cmark`**（`\newcommand{\cmark}{\textcolor{green!60!black}{\ding{51}}}`，html-latex-tables.lua 已预处理 `\cmark` → Unicode ✓）——两端都可靠。
19. **自定义宏（`\ara{}` 等）在 HTML 表格子文档被 pandoc 丢弃——通用修复是 metadata 注入 `latex-macros`**——pandoc 的 LaTeX reader 支持 `latex_macros` extension（`\newcommand` + 使用同文即展开，quarto 环境实测有效），把宏定义拼在表格文本前即可。三个坑：① 配置必须放 **`format.html.html-helper.latex-macros`**（html-latex-tables.lua 是 HTML filter，放 format.pdf 下 HTML 渲染时 doc.meta 里根本没有 html-helper）；② YAML `|` 块标量在 pandoc 3 解析为 **Blocks 类型**（无 `t` 字段，`pandoc.utils.type` 返回 "Blocks"），`ipairs(v)` 直接遍历出 `RawBlock("tex")`——`stringify` 对 RawBlock 返回空，需手动提取 `b.text`；③ RawBlock 格式名是 `"tex"` 不是 `"latex"`。此为通用方案（任何文章的宏都可声明），不硬编码具体宏。
20. **pandoc 对三类 LaTeX 表格构造的解析陷阱（SkillOpt 实测）**——① `\resizebox{..}{!}{...}`：pandoc 直接放弃解析整个表格（输出空 `<div class="table*">`），须预处理剥离外壳（`\resizebox%b{}%b{}%b{}` 平衡匹配取第三组内容，minipage 结构保留）；② `\multicolumn{N}{align}{内容}`：pandoc 不认跨列，**整个单元格内容被丢弃**（行变空）——预处理展开为内容文本（列数错位由 pandoc 自动补空，内容保留在首列）；③ **行首 `%` 注释**：LaTeX 语义下注释吃掉换行、把后续命令与上一行合并 → pandoc 解析错位（实测 transfer 表首段头整行丢失）——预处理剥离行首注释（`^[ \t]*%`，不动数据里的 `20\%`）。配合 latex-macros 的"简化宏定义"（`\harnessrow` 去掉 `\rowcolor/\multicolumn`、`\methodcell` 去掉 `\cellcolor`、`\dvalp` 去掉 `\hphantom`），任意论文的复杂表格都可走 pandoc.read 管线。
21. **quarto 的 xelatex 模板加载 `unicode-math`，与 `\textsubscript`/`\textbf` 等字体切换命令冲突**——实测：unicode-math 下只要发生字体切换（`\textsubscript` 的 mbox `\selectfont`、`\textbf` 的 `\bfseries`），**之后所有数学符号（−/→/τ/∑/∈/∅ 等）全部丢失**（LaTeX 报 167 个 `Missing character`，符号被静默删除）；无 unicode-math 的 pdflatex 零缺失。**修复：`pdf-engine: pdflatex`**（原版 arXiv 论文本就是 pdflatex，还顺带对齐了 `\checkmark` 等 MSAM 字形）。注意 ARL 论文用 xelatex 是因为 ctex 中文——纯英文论文一律 pdflatex。
22. **html-crossref 的 caption 前缀/图引用配置化（英文论文适配）**——① `caption-prefix`/`caption-sep` 默认中文（"表 "/"："），英文论文配置 `"Table "`/`": "`；**YAML 提升会 trim 配置值的尾随空格**（`"Table "` → `"Table"`），filter 对配置值统一补一个空格、默认值（Lua 字面）不动；② 表格 caption 内的图引用 `\ref{fig-X}` 无法自数（quarto 消费图 id，filter 拿不到编号）——**方案：postprocess 自动编号**（见踩坑 23，`fig-nums` 配置逻辑已移除，图编号零配置全自动），正文图引用仍用 `@fig-X` 原生语法；③ 组合表（resizebox+minipage）的**多 label 别名**（`\label{tab-a}\label{tab-b}`）须全部收集进编号映射（同一 RawBlock 的多个 `id="..."` 都映射到同一编号），否则别名引用变 `[§x]` 占位。

## 模板适配

期刊模板配置（`md-table-env`/`table-caption-pos` 等）属于 PDF-Helper 的能力 B 范畴，见 [PDF-Helper README 的模板适配表](../pdf-helper/README.md)。本扩展（HTML 端）不受期刊模板约束。

23. **表格 caption 内图引用的 postprocess 自动编号（figref.py）**——`\ref{fig-X}` 在 RawBlock 字符串里，quarto crossref 是 AST 层遍历（只找 Cite 节点），**引用语法换什么都不生效**（实测：caption 里写 quarto 原生 `[@fig-X]` 渲染后字面残留）；filter 数不出编号（图 id 被 quarto 消费进内部状态）。**绕开时序的唯一构建时方案：quarto 渲染完成后再数成品**——`project.post-render`（`_quarto.yml`）挂 figref.py：① 数 `<div id="fig-X" class="quarto-float quarto-figure">` 包裹 div 的文档顺序 = 图编号（quarto 编号 = FloatRefTarget 顺序；`<figure>` 本体无 id，干净 id 在包裹 div 上，figcaption 的 id 带 `-caption-uuid` 后缀）；② 前缀（"Figure "/"图 "）从正文 `<a class="quarto-xref">Figure&nbsp;1</a>` 学习（零配置中英文通吃，学不到默认 "Figure "）；③ 替换 `<a href="#fig-X">[fig-X]</a>` 占位。三个实测坑：pandoc 把 LaTeX 的 `~`（`Figure~\ref`）转成 `&nbsp;` 且 caption 序列化词间换行分隔——前缀正则须吃 `&nbsp;` 和 `\r\n`；替换后 `</a>\n.`（句号被换行隔开）须修回 `</a>.` 与 PDF 端 "Figure 4." 一致；脚本对无占位文件不写回（ARL 零副作用回归）。fig-nums 配置逻辑已随方案定型移除（html-crossref.lua 一律输出占位符）——图编号零配置，全由脚本处理。
24. **主文档 {=latex} 块的 RawBlock format 是 "tex"（include 文件是 "latex"）**——html-latex-tables 的转换条件若只认 "latex"，主文档（index.qmd）里直接写的 {=latex} 表格会静默转成空 `<div class="{=latex}">`（SkillOpt 表格全在 sections/ include 文件所以未暴露）。修复：条件兼容 `format == "latex" or format == "tex"`。顺带实证：**tbl- 前缀被 quarto 在 reader 阶段全面消费**——管道表 `{#tbl-X}` 进内部状态（caption 无残留、attr.identifier 清空，用户 filter 拿不到）；{=latex} 表格 PDF 端 `\label{tbl-X}` 被 main.lua float 识别剥离接管（表格拆碎）。因此**表格前缀必须用 tab-**（quarto 官方"非 float 让路"信号，knitr 兼容设计）；tbl- 仅在 {=latex} 表格的 HTML 端意外兼容（RawBlock 内容 quarto 不碰，id/引用/编号全通）。pdf-tbl-warn.lua 让 PDF 端 tbl- 引用的失败可见（警告而非静默 ??）。

25. **html-crossref 拆分三 filter 的三个深层坑（回归修复实录）**——① **Lua pattern 参数只做字符串级转义**：要匹配字面引号，源码写 `"`（1 反斜杠）运行时就是 `"`；写 `\\\"`（3 反斜杠的"双重转义"）运行时变成 `"`（反斜杠+引号），**实测 pandoc Lua pattern 的 `\"` 不匹配字面引号**（gsub/find 全 nil，`<a href="#X">[X]</a>` 链接永不替换、静默残留 data-ref）。同理 match 匹配字面 `\ref` 用源码 2 字节 `\\ref{`（非 4 字节）。**调试手法：从 filter 文件提取 pattern 原样字节，在独立 `--lua-filter` 探针里对真实文本跑 match 实测**（Lua 字符串/pattern 双重转义脑内推演必错）；另外单字节 `\S`（`\S` 源码）在 Lua 5.4 编译期直接报 `invalid escape sequence`——S 式必须成对 `\\S`。② **quarto markdown 扩展集无 raw_tex：正文裸 `\ref{X}` 被数学化成 Math 节点**（HTML 输出 `<span class="math inline">\(\ref{X}\)</span>`），与 pandoc 独立解析（RawInline(tex)）不同——最小复现与真实管线结果可能相反（`Table \ref{tab-x}` 在 reftest 是 Math）；且**同一文档内两种形态并存**（英文段落上下文 → RawInline，中文括号 `（\ref{X}）` → Math）——walk_inlines 必须同时处理 RawInline + Math + Link(reference-type="ref") 三分支，缺一漏一片（本次 ARL 只转出 7 个 § 而非基线 113 个，正是 sec filter 缺 Math 分支 + pattern 字节错误叠加）。③ **Lua 标准库没有 string.rfind**（调试代码误用 → 直接崩 filter "attempt to call a nil value (method 'rfind')"，连累整个渲染静默中断）；④ **Table 节点 caption.long 是 [Block]**（Para/Plain 列表），caption 内的 Link 引用须遍历 `caption.long[*].content` 的 inlines（只遍历单元格会漏 caption 里的 `<a data-reference-type>` 残留）。回归基线：ARL §=113 / sec 链接=189 / tab 引用=17，SkillOpt tab 引用=24，双端占位清零。


26. **html-algorithm.lua（algorithmic → HTML）实现实录（TD-MPC 论文触发）**——① **pandoc 解析 algorithmic 不可用已实证**（`\State`/`\Require` 静默吞、`\Else`→`\ESClse` 名毁）：filter 纯字符串翻译，数学 `$...$` 保护为占位后 token 栈扫描（{\color → span、\emph/\textbf → em/strong、} 弹栈），再自转 `<span class="math inline">\(...\)</span>`（**RawBlock html 里 `$...$` 不二次解析**，MathJax 渲染 \(...\) 形态）。② **改 RawBlock 必须连带 format**：只改 text（format 仍是 latex）→ HTML writer 丢弃；且**不能替换包装表字段**（doc.blocks 持原对象引用，替换对文档无效果）——直接改对象 `t.rb.format="html"; t.rb.text=html`。③ **Lua pattern 的 \color 不匹配字面 \color**（\c 被当转义，探针实证 copen nil）——整行 {\color{X} 识别改用纯字符串 sub 检查；同理 
ef 的 
、\v 都是坑。④ **裸 { 必须压栈对称**：scan_tokens 只压命令栈时，
ef{eq:...} 的 } 弹空栈被当跨行颜色闭合 → } 丢失——裸 { 压 brace 标记，} 弹 brace 输出字面。⑤ **sub(#cmd) off-by-one**：跳过命令名用 sub(#cmd+1)（探针铁证 sub(4) 残留 R）。⑥ **注释分割消费数学**：\STATE 行尾注释 \vartriangleleft 分割 pattern 会把数学本身吃掉——先整体 translate_inline 再 plain find marker 切分包 algo-comment。⑦ **跨行颜色块**（{\color{BrickRed} 独立行包住 FOR 块）：span 包不了跨 li 颜色 → 颜色上 li（style 属性）；孤立 } 输出 \x04 标记弹跨行颜色栈。⑧ **REQUIRE 多行**（\ 结尾 + ~~~ 缩进续行）：block_kind 状态机；\begin{algorithmic}[1] 的 [1] 行号剥除；~ 对齐序列转单空格。⑨ **filter 链顺序**：algorithm 必须在 html-fig-crossref 前（fig 的未知引用兜底把 alg: 引用转 [§ref] 占位）。⑩ 正文 
ef{alg:X} 提取须含 alg: 前缀（label key 完整）。回归：SkillOpt 11 表/ARL 15 表零破坏、占位清零；两个真实算法块（figure 包裹 + 4 层嵌套 + 三色 + 行尾注释）HTMLParser 全文件 0 结构问题。
27. **html-algorithm 数学内 \Call 展开（MathJax 红色字面坑）**——algpseudocode 的 \Call{f}{a} 在数学 $...$ 内时：MathJax 不认识 \Call → 红色字面显示不渲染。filter 在 protect_math 阶段展开 \Call{f}{a} → \mathrm{f}(a)（标准数学命令）。三个实测坑：① **Lua gsub 无捕获组时替换函数收到完整匹配**（含 $ 边界）——expand_call 收到的 x 带 $ 是正常的，替换后仍带 $ 也无妨（占位还原原样输出）；② **pos 指向 \Call 的 \，{ 在 pos+5**——balanced_brace 要求以 { 开头，sub(pos+6) 会从内容首字符开始导致 fn 错位（实测 fn=valuate}{M,h,...）——必须 sub(pos+5)；③ expand_call 的 find 用 plain（pattern 的 \C/{ 是坑）。
## 设计备忘（路线图）

- **algorithm 块 → HTML filter**：**已于 2026-08-29 实现（html-algorithm.lua，arXiv-2203.04955v2 触发）**——实测通过（两个真实算法块、回归零破坏），详见踩坑 26。设计备忘全文见 `README.design-notes.md`（含已兑现的实证结论）。
