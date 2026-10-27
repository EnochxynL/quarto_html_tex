# HTML-Helper

把 Quarto 中保留的原始 LaTeX 环境转换为 HTML。表格、算法等统一交给
lwarp 执行，不再通过 Lua 拆解表格或经 Pandoc Table 中转。PDF 渲染不受影响。

## 使用

~~~yaml
filters: [html-helper]
format:
  html:
    html-helper:
      latex-packages: [graphicx, xcolor, booktabs, colortbl, multirow]
      latex-macros: |
        \newcommand{\ourmethod}{\textsc{OurMethod}}
~~~

在 `{=latex}` 块中保留完整的 table / table*、tabular、标题及标签。
宏包和自定义命令必须显式声明；插件不根据表格内容猜测依赖。
Markdown 原生表格继续由 Quarto 处理。

## 转换链

1. html-css.lua、html-pdf-embed.lua：默认样式和 PDF 源图嵌入。
2. latex/html-latex-counters.lua：为独立编译块准备全文计数上下文。
3. latex/html-latex-lwarp.lua：生成 TeX，运行 LuaLaTeX 打印版和 HTML 版，
   用 pdftotext 提取 HTML，并嵌入主页面。每块 CSS 和内部锚点单独隔离。
   遇到 lateximage（例如 pifont 符号）时，额外编译以确定图片页码，按 lwarp
   的转换顺序生成 SVG，并以 data URI 嵌入，不依赖临时目录中的图片路径。
4. ref/html-latex-ref.lua：在 post-quarto 阶段统一处理 LaTeX 引用和 lwarp 占位符。
   通过同级 crossref-query 扩展查询 Quarto 已登记目标，不按 sec/fig/tbl 前缀分派，
   也不重新计数或抓取最终 HTML。未登记目标再查 lwarp 计数桥提供的编号。
   lwarp 表格的标题和编号仍由 lwarp 输出。

html-helper 需要同时安装同一工作区内的 `_extensions/crossref-query`。
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
  这不是完整的 TeX 计数器解释器：任意计数器重置、可选或不编号 caption，
  以及同一块混用不同计数器尚不保证正确。与原生表格混排仍存在两套编号来源，
  需要后续统一引用架构。
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
python tools/check_table_term_regression.py
python _regression/crossref-query/run.py
python tools/render_papers.py
python tools/check_html_refs.py
~~~

_regression/lwarp-tables.qmd 覆盖跨列表头、嵌套单元格、颜色和符号、组合面板、
同块多标题、嵌套文档块及前后向引用。六篇论文提供真实内容回归。
