# html-tex

把 Quarto 中保留的原始 LaTeX 环境转换为 HTML。表格、算法、TikZ 等统一交给
lwarp 执行，不再通过 Lua 拆解表格或经 Pandoc Table 中转。PDF 渲染不受影响。

## 使用

~~~yaml
filters: [html-tex]
format:
  html:
    html-tex:
      include-in-header:
        text: |
          \usepackage{graphicx,xcolor,booktabs,colortbl,multirow}
          \newcommand{\ourmethod}{\textsc{OurMethod}}
~~~

`html-tex.include-in-header` also accepts `file: preamble.tex`, a bare filename,
or an ordered list of file/text entries. Paths are relative to the input document.
The TeX header supplies lwarp, counter declarations and MathJax macro discovery.


在 `{=latex}` 块中保留完整的 table / table*、tabular、标题及标签。
宏包和自定义命令必须显式声明；插件不根据表格内容猜测依赖。
Markdown 原生表格继续由 Quarto 处理。
本扩展不修复 PDF 双栏下的 Markdown 表格限制；六篇论文的共享表格使用原生 LaTeX。

## Inline LaTeX

Write inline TeX explicitly so Pandoc preserves it in the document:

~~~markdown
We introduce `\ourmethod{}`{=latex}.
~~~

Declare `\newcommand{\ourmethod}{\textsc{OurMethod}}` in
`html-tex.include-in-header`. HTML output uses lwarp's text and scoped CSS;
PDF output passes the same inline TeX to LaTeX. No separate HTML term definition
or shortcode extension is needed. Arguments and nested text formatting are supported.

All inline occurrences are compiled in one batch, in document order, without
string deduplication. Diagnostics are retained in `.quarto/lwarp/block-inline/`.
An inline fragment must produce inline content; use a raw LaTeX block for a
paragraph, table, or other block environment. Inline compilation has its own TeX
context: it does not inherit temporary declarations or counter changes from
surrounding Markdown or independently compiled blocks. Keep document-wide
numbering in the existing reference/counter pipeline.

## PDF 源图

本地 PDF 图片在 HTML 端使用 `pdfinfo` 检查页数，再由 `pdftocairo -svg` 转为
SVG，以 data URI 写回原生 Image。宽高、alt、title、class、caption 和 Quarto
交叉引用仍由原生图片流程处理，不再使用 PDF 阅读器或 MediaBox 比例补丁。
PDF 输出保持原图，不调用转换器；未指定尺寸时采用 Quarto 的原生图片布局。

单页 PDF 无需额外配置。多页 PDF 必须明确选择页码，使用 Pandoc 已支持的
`page` 属性，使 HTML 和 PDF 输出选择同一页：

~~~markdown
![Results](figures/results.pdf){#fig-results page=2 width=80%}
~~~

HTML 也兼容 PDF 图片 URL 中的 `#page=2`，显式 `page` 属性优先；双格式文档
推荐使用属性写法。未选页的多页文件、越界页码、缺失或无法转换的文件会明确报错。
同一文档内重复引用同一文件和页码只转换一次，每次渲染重新读取原文件。
中间 SVG 和日志保存在 `.quarto/pdf-images/`。

处理范围是本地图片节点：普通 PDF 下载链接保持原样，远程 PDF 图片不自动下载。
完整文档的阅读器可自行写成原始 HTML，不属于这个图片转换步骤。

## TikZ / PGFPlots

图体直接写在原始 LaTeX 块中；外层使用 Quarto 原生 figure Div，标题保持 Markdown：

~~~~markdown
::: {#fig-example}

```{=tikz}
\begin{tikzpicture}
\node[draw] (a) at (0,0) {Input};
\node[draw] (b) at (3,0) {Output};
\draw[->] (a) -- (b);
\end{tikzpicture}
```

Example diagram.
:::
~~~~

HTML 端统一由 `latex/html-latex-lwarp.lua` 编译。正文和表格输出 HTML 元素，
TikZ / PGFPlots 使用 lwarp 的 lateximage 机制生成 SVG，以 data URI 嵌入 HTML。
同一个块可以包含文字、表格和绘图，不会被整个压成一张图片。
PDF 端保留原始代码，由文档自身的 LaTeX 引擎、模板编译。
若需要 Quarto 管理图题和编号，使用上例的原生 figure Div；原始 LaTeX figure
也可以交给 lwarp，其标题和标签由 lwarp 管理。

复杂图形可显式声明构图依赖：

~~~yaml
format:
  html:
    html-tex:
      include-in-header:
        file: figures/tikz-preamble.tex
~~~

`include-in-header.file` 相对当前文档目录，内容为宏包、字体、样式、尺寸和宏定义，
不包含 `\documentclass`、文档正文或出版页面样式。所有块使用 article 和 LuaLaTeX；
TikZ、PGFPlots 等依赖需在导言文件或 `include-in-header.text` 中声明。
同一宏不要在文件和 `include-in-header.text` 中重复定义。
PDF 模板或 `include-in-header` 需自行提供相应依赖，
HTML 配置不会自动改写 PDF 模板。CSV、图片和 `\input` 的路径相对当前文档目录。

插件先登记 LaTeX 块，再在 Quarto 索引完成后编译，从统一引用桥取得当前文档
的编号，支持前向引用及将 `\ref` 封装在宏中的用法；不读取历史 PDF 的 aux 文件。
图内编号在 SVG 生成前解析；它们成为图形内容，不会自动获得正文链接的悬停预览。
跨文件书籍的最终编号尚未确定时，依赖这些编号的绘图会报告未解析引用。

每次 HTML 渲染都会重新编译，以观察外部数据和图片的改动。中间 TeX、PDF、SVG
及诊断保存在 `.quarto/lwarp/block-N/`。缺失依赖、未解析引用和转换错误
会使渲染明确失败。图体中的 `\cite`、`\citep`、`\citet` 等 Pandoc 可识别的引用
参与父文档的 citeproc 流程，使用相同的 bibliography、CSL 样式及引用顺序；
图内首次出现的文献也会进入正文参考文献表。插件在原位置保留隐藏的引用节点，
从完整文档的 citeproc 结果取得图内文字，不单独编号，也不读取历史 PDF 的文献数据。
仅处理块中显式出现的命令，不执行任意 TeX 宏展开以发现引用；导言区引用不在此范围内。

当前包含两处局部 lwarp 兼容处理：构造 TikZ fading 遮罩时抑制错误的图片分页，
以及在 lateximage 内恢复 siunitx 的原生 quantity 格式化，避免数值和单位消失。
它们不改写绘图源码，也不影响普通 HTML 中的 siunitx 输出；回归测试检查实际图像页面。

## 转换链

1. html-css.lua：默认样式；figure/html-pdf.lua 在 post-quarto 将本地 PDF 图片
   转成 Cairo SVG。无需 embed 专用 CSS，使用原生图片尺寸和响应式布局。
2. latex/html-latex-counters.lua：在 pre-quarto 为独立编译块准备全文计数上下文。
3. latex/html-latex-lwarp.lua：在 pre-quarto 登记块、原生图片占位和文献引用。
   引用桥在 post-quarto 提供编号后，统一生成 TeX，运行 LuaLaTeX 打印版和 HTML 版，
   用 pdftotext 提取 HTML，并嵌入主页面。每块 CSS 和内部锚点单独隔离。
   遇到 lateximage（例如 pifont 符号）时，额外编译以确定图片页码，按 lwarp
   的转换顺序生成 SVG，并以 data URI 嵌入，不依赖临时目录中的图片路径。
4. latex/html-latex-ref.lua：在渲染前导出编号，在渲染后解析新生成 HTML 中的引用。
   内置查询辅助函数读取 Quarto 已登记目标，不按 sec/fig/tbl 前缀分派，
   也不重新计数或抓取最终 HTML。未登记目标再查 lwarp 计数桥提供的编号。
   lwarp 表格的标题和编号仍由 lwarp 输出。

html-tex 可独立安装，不依赖其他引用扩展。查询辅助函数暂时访问 Quarto 内部状态，
将来可按上游实际 API 替换；当前不预设正式 API 的名称。
`\ref` 输出编号，`\eqref` 输出带括号的编号；Figure、Table、§ 等前缀由正文提供，
显式的 `\S` 保留为 §。原生 `@...` 引用仍由 Quarto 处理。
未找到的目标保留可见占位并输出 `[html-ref] unresolved targets` 诊断。
已登记但编号延迟到项目阶段的目标不会回退到 lwarp，也不会自行推算编号；
本插件暂不为这些目标生成最终跨文件链接。

正文和标题里的 LaTeX 文献引用由父文档的 citeproc 数据解析，再交给 TeX；
表格结构仍完全由 lwarp 处理。支持 Pandoc 可识别的 \cite、\citep、\citet
及其可选参数。图内引用成为 SVG 内容，HTML 文献链接指向主页面的参考文献。

MathJax 宏发现同时扫描原始 LaTeX 块及 QMD 原生的行内、独立公式，包含嵌套内容。
显式声明 bm 宏包时，为网页端提供 bm → boldsymbol 的兼容映射；用户宏定义优先。
这用于常见粗体数学符号，不保证完整复现 bm 宏包的全部 TeX 字体行为。

## 表格约定与边界

- \multicolumn、嵌套 tabular、\cmidrule、颜色和背景由 lwarp 处理。
  不剥离 resizebox、跨列命令或表格外层结构，也不给内层表格添加 Bootstrap 样式。
- 宏定义和块正文启用 lwarp 的 \StartDefiningTabulars，使盒子或宏参数中的
  表格分隔符能被正确读取。
- \multirow 跨过的空单元格需要显式写 \mrowcell。共享源码用于 PDF 时，
  在 PDF 导言区添加 \providecommand{\mrowcell}{}。
- 当前 lwarp 对声明式 \color 的 HTML 输出不总能保留文字颜色。
  彩色正文使用 \textcolor{颜色}{内容}；颜色定义和混色交给 xcolor。
- 当前 lwarp 的 resizebox 参数不接受段落。组合表格在其参数内分隔源码时，
  使用仅含百分号的注释行代替空行，避免产生段落标记。
- 块内多个表格按 caption 数量推进计数，多个面板共享一个 caption 时只占一个编号。
  支持 `\caption[短标题]{完整标题}`；可选短标题不额外占用编号。
  这不是完整的 TeX 计数器解释器：任意计数器重置、不编号 caption，
  以及同一块混用不同计数器尚不保证正确。与原生表格混排仍存在两套编号来源，
  需要后续统一引用架构。
- 当前 Quarto 会尝试拆取带 `tbl-*` 标签的原始 LaTeX 表格，且其简单的 caption
  匹配可能截断含宏的标题。Ara 的五张迁移表使用标准的
  `\caption[短标题]{完整标题}`，保持原始标签名和完整可见标题，直接交由 LaTeX
  编译，不依靠改标签前缀规避这一问题。
- 保留的是网页中的内容与结构，不保证复现 PDF 的精确尺寸或分页。
  不支持的宏包、语法或缺失依赖会使渲染失败，并保留日志。
- 每次渲染重新编译，尚无结果缓存。每块源文件和编译日志保存在
  .quarto/lwarp/block-N/，可直接检查失败位置。
- 图片生成需要 pdfseparate、pdfcrop、pdftocairo；pdfcrop 还需要 Perl 和
  Ghostscript。转换错误会使渲染失败，详细日志在各块的 image-tools.log。
  Windows 下插件会尝试向转换子进程提供 Git 自带的 Perl，不修改系统环境。

## 论文示例

仓库中的六篇论文包含 HTML 和 PDF 入口，详见根目录的 `PAPERS.md`。
在仓库根目录运行 `quarto render` 即可编译全部示例，无需 Python 辅助脚本。


### Explicit rendering routes

Use `{=latex}` for lwarp HTML rendering. Use `{=tikz}` for standalone LaTeX to PDF to Cairo SVG, including tables, algorithms, or mixed content. The marker selects the backend. Both formats become raw LaTeX for PDF output. Standalone blocks share the preamble and document citation/reference numbers; SVG text is outlined.
