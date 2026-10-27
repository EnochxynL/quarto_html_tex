# html-tex

把 Quarto 中保留的原始 LaTeX 环境转换为 HTML。表格、算法等统一交给
lwarp 执行，不再通过 Lua 拆解表格或经 Pandoc Table 中转。PDF 渲染不受影响。

## 使用

~~~yaml
filters: [html-tex]
format:
  html:
    html-tex:
      latex-packages: [graphicx, xcolor, booktabs, colortbl, multirow]
      latex-macros: |
        \newcommand{\ourmethod}{\textsc{OurMethod}}
~~~

在 `{=latex}` 块中保留完整的 table / table*、tabular、标题及标签。
宏包和自定义命令必须显式声明；插件不根据表格内容猜测依赖。
Markdown 原生表格继续由 Quarto 处理。
本扩展不修复 PDF 双栏下的 Markdown 表格限制；六篇论文的共享表格使用原生 LaTeX。

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

```{=latex}
\begin{tikzpicture}
\node[draw] (a) at (0,0) {Input};
\node[draw] (b) at (3,0) {Output};
\draw[->] (a) -- (b);
\end{tikzpicture}
```

Example diagram.
:::
~~~~

HTML 端由 `figure/html-tikz.lua` 独立编译 PDF，再调用 `pdftocairo -svg`，
将 SVG 以 data URI 嵌入原生图形对象；不经 lwarp。PDF 端保留原始图体，
由文档自身的 LaTeX 引擎、模板编译。无编号的裸 TikZ 块也可使用。
不要将外层 `figure`、caption 和 label 一起放入绘图块。

复杂图形可显式声明构图依赖：

~~~yaml
format:
  html:
    html-tex:
      tikz:
        engine: pdflatex
        preamble-file: figures/tikz-preamble.tex
~~~

`preamble-file` 相对当前文档目录，内容为宏包、字体、样式、尺寸和宏定义，
不包含 `\documentclass` 或文档正文。默认使用 article 类及 tikz 包；可选引擎为
pdflatex、lualatex、xelatex。PDF 模板或 `include-in-header` 需自行提供相应依赖，
HTML 配置不会自动改写 PDF 模板。CSV、图片和 `\input` 的路径相对当前文档目录。

插件先登记绘图位置，再在 Quarto 索引完成后编译，从统一引用桥取得当前文档
的编号，支持前向引用及将 `\ref` 封装在宏中的用法；不读取历史 PDF 的 aux 文件。
图内编号在 SVG 生成前解析；它们成为图形内容，不会自动获得正文链接的悬停预览。
跨文件书籍的最终编号尚未确定时，依赖这些编号的绘图会报告未解析引用。

每次 HTML 渲染都会重新编译，以观察外部数据和图片的改动。中间 TeX、PDF、SVG
及诊断保存在 `.quarto/tikz/figure-N/`。缺失依赖、未解析引用、缺失字形和转换错误
会使渲染明确失败。独立图体内的文献引用不自动运行父文档的 bibliography 流程。

## 转换链

1. html-css.lua：默认样式；figure/html-pdf.lua 在 post-quarto 将本地 PDF 图片
   转成 Cairo SVG。无需 embed 专用 CSS，使用原生图片尺寸和响应式布局。
   figure/html-tikz.lua 在 pre-quarto 准备绘图对象，在引用桥之后的 post-quarto
   编译 TikZ → PDF → SVG；figure caption 和编号仍由 Quarto 管理。
2. latex/html-latex-counters.lua：为独立编译块准备全文计数上下文。
3. latex/html-latex-lwarp.lua：生成 TeX，运行 LuaLaTeX 打印版和 HTML 版，
   用 pdftotext 提取 HTML，并嵌入主页面。每块 CSS 和内部锚点单独隔离。
   遇到 lateximage（例如 pifont 符号）时，额外编译以确定图片页码，按 lwarp
   的转换顺序生成 SVG，并以 data URI 嵌入，不依赖临时目录中的图片路径。
4. latex/html-latex-ref.lua：在 post-quarto 阶段统一处理 LaTeX 引用和 lwarp 占位符。
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
表格结构仍完全由 lwarp 处理。当前引用桥支持无可选参数的 \cite、
\citep、\citet 等命令。文献链接指向主页面的参考文献。

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
  不支持的宏包、语法或缺失依赖会显示 lwarp-failed 警告及原始代码。
- 每次渲染重新编译，尚无结果缓存。每块源文件和编译日志保存在
  .quarto/lwarp/block-N/，可直接检查失败位置。
- 图片生成需要 pdfseparate、pdfcrop、pdftocairo；pdfcrop 还需要 Perl 和
  Ghostscript。转换错误会显示失败块，详细日志在各块的 image-tools.log。
  Windows 下插件会尝试向转换子进程提供 Git 自带的 Perl，不修改系统环境。

## 验证

~~~text
python tools/check_lwarp_tables.py
python tools/check_tikz.py
python tools/check_pdf_images.py
python tools/check_table_term_regression.py
python _regression/html-refs/run.py
python tools/render_papers.py
python tools/check_html_refs.py
~~~

_regression/lwarp-tables.qmd 覆盖跨列表头、嵌套单元格、颜色和符号、组合面板、
同块多标题、嵌套文档块及前后向引用。六篇论文提供真实内容回归。
