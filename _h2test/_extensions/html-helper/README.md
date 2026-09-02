# HTML-Helper

Quarto 扩展：**qmd（含 latex 内容）→ 单格式 HTML 翻译器**。挂载即用，零配置起步；复杂 latex 块、{=latex} 表格、`\ref` 引用体系按职责分模块，filter 不持有任何"针对特定内容类型"的专门适配（通用性——用户 2026-09-02 验收：职责清晰）。

## 目录结构

```
_extensions/html-helper/
  _extension.yml            filter 链声明（顺序见下）
  html-css.lua              默认样式注入（同目录 html-css.css，:where() 零特异性——项目 styles.css 天然覆盖）
  html-css.css              插件默认样式（论文共性部分，2026-08-31 提取）
  html-pdf-embed.lua        .pdf 源图 → <embed> + aspect-ratio（读 MediaBox，保矢量免预处理）
  latex/                   latex 块领地（RawBlock(tex) 翻译）
    html-latex-tables.lua     {=latex} 复杂表格 → <table>（resizebox/minipage/multicolumn 预处理）
    html-latex-counters.lua   全文计数器注册与编号（latex 块 caption 排序——扫描 RawBlock 自动发现）
    html-latex-lwarp.lua      lwarp 子页面通道（任意复杂 latex 块 → 语义化 HTML 子页面）
  ref/                     引用领地（\ref 双轨）
    html-ref-tbl.lua          \ref{tbl-X} 自管编号（数 RawBlock <table> 顺序）+ [TAB-CAP] 占位
    html-ref-sec.lua          \ref{sec-X} / \S\ref{sec-X} → §N 链接（Header 层级自数）
    html-ref-fig.lua          \ref{fig-X} → 占位（图 id 被 quarto 消费，figref.py 后处理编号）
    figref.py / tblref.py     post-render 占位编号脚本（数 quarto float div 顺序）
```

**filter 链顺序**（_extension.yml）：`html-css.lua → html-pdf-embed.lua → latex/tables → latex/counters → latex/lwarp → ref/tbl → ref/sec → ref/fig`——counters 先跑写 meta、lwarp 后跑读 meta；ref/fig 最后兜底。

## 用法

```yaml
filters:
  - html-helper          # HTML 端
  - pdf-helper           # PDF 端（另一扩展——HTML filter 全部 FORMAT 守卫，PDF 零影响）
format:
  html:
    html-helper:
      caption-prefix: "Table "     # 表格 caption 前缀（英文论文；默认中文 "表 "）
      caption-sep: ": "            # caption 分隔符
      latex-packages:              # latex 块独立编译所需宏包——块编译脱离文档层，
        - algorithm                # 包不从内容猜（猜包注入已删——用户拍板 2026-09-02），
        - algpseudocode            # 此处显式声明（与 PDF 端 include-in-header 平行）
        - amsmath
      latex-macros: |              # 文档层宏定义（用户宏——\ourmethod 等）
        \newcommand{\ourmethod}{\textsc{SkillOpt}}
```

## 三领地职责

| 领地 | 模块 | 内容 | 机制 |
|---|---|---|---|
| latex 块 | counters → lwarp | 任意 `{=latex}` 环境块（algorithm 等） | counters 扫描全文 RawBlock + latex-macros 收 `\newfloat/\newtheorem/\newcounter` 注册 → meta 握手；lwarp 收非表格含 `\begin{ENV}` 的块 → lualatex 双编译（打印版 + HTML 版）→ pdftotext 提取子页面 → CSS 作用域化 → 嵌入 |
| 表格 | tables | {=latex} 复杂表（resizebox/multicolumn） | pandoc.read → Table AST → html；PDF 端原样走 LaTeX 原生 |
| 引用 | tbl/sec/fig | 正文 `\ref{...}` | 编号对齐=caption 排序：sec 自数、tbl 自数、fig 占位（quarto 消费图 id）→ post-render 数成品 |

## 核心机制实证（2026-08-30 ~ 09-02）

- **lwarp 子页面通道**（替代 tex4ht）：lwarp 在 TeX 宏层输出 HTML5 语义结构；数学走 MathJax。三步：lualatex 打印版（自动生成 `X_html.tex`）→ lualatex HTML 版（源码嵌 PDF 文本层）→ `pdftotext -layout` 提取。块内引用（label 同块）aux 跨遍原生解析。
- **引用协议**：数学外 `\ref`——块内 lwarp 原生；块外 `\newlabel` 假条目注入（href 真名 + 占位显示，fileref 固定 `block`）；数学内一律 `@@REF:{X}@@` 占位（lwarp detokenize，MathJax 不执行 `\ref`）→ 第二遍统一填编号。
- **MathJax 宏自动发现**（零配置）：扫描全文数学内容收集 `\CMD` → 定义查找链（用户 `\newcommand` → latex-packages 包源）→ 翻译（无参别名展开 + 内核字体映射 + `\ifthenelse` 剥离）→ body 开头同步 `<script>` 设 `window.MathJax tex.macros`。定义驱动过滤：MathJax 内建命令在定义源找不到 → 自动跳过——无需白名单。实证：**MathJax 4 移除文档级 `\newcommand`**；`\textsc` 不支持（smallcaps）→ `\text` 正体近似。
- **计数器开放集**：注册源 = 块内 + latex-macros（跨块共享由文档层声明）；块内注册不强求跨块；环境名≠计数器名靠 `\@ifundefined{c@ENV}` 保护兜底。
- **失败不可静默**：lwarp 编译失败 → 可见警告块 `div.lwarp-failed`（原 latex 源码 escape 显示）；PDF 控制片段（无 `\begin` 结构）不编译。

## 双轨表格引用

| 通道 | 表格形态 | 编号 | 适用 |
|---|---|---|---|
| **tbl-** | 管道表 `{#tbl-X}`（quarto 原生 float） | quarto `@tbl-X` / tblref.py | 新论文管道表 |
| **tab-** | {=latex} 复杂表 `\label{tab-X}` | html-ref-tbl 自管 | 复杂表必须 tab-（tbl- 触发 quarto float 接管 → 表格静默消失） |

## 已知限制

- **老式 algorithmic 包**（非 algorithmicx）：lwarp 拒绝（`Package algorithmic is not yet supported`）——输出警告块 + 原代码，项目层改写（零强行适配）。
- **lwarp 嵌套行号位置缺陷**（algpseudocode 嵌套 `\State` 行号输出在行尾）——lwarp-algorithmicx 引擎层问题，filter 不修（不背算法结构知识）。
- **每次渲染重新编译**（无缓存）。
- **数学内引用**只能纯文本编号（MathJax 不渲染 `<a>`）。

## 回归素材（repo 内）

- `_h2test/`：合成测试（引用前向/后向/未知、数学内引用、MathJax 宏、双端渲染）
- `arXiv-2605.23904v2/`（SkillOpt）：真实论文回归素材（A_appendix 真实算法块 + `\Comment` 自引用 + `\Call` 数学宏）——每次改动跑它验证
- `_mk4ht-test/`：lwarp/MathJax 机制探针（lwprobe/lwref/mjmc/mjinj 等）
- PDF 基线：SkillOpt 1,008,480 字节 0 error（pdflatex；filter 改动仅 HTML 端，FORMAT 守卫保证 PDF 零影响）
