# docx-tex

独立分发的Quarto实验扩展。QMD中的LaTeX块经lwarp生成HTML片段，再由Pandoc的HTML reader转为原生结构，交给DOCX writer。正文数学保持Math节点，由Pandoc生成OMML；没有Word专用LaTeX表格解释器。

```yaml
filters: [docx-tex]
format:
  docx:
    reference-doc: ../styles/word/neu-journal/reference-xml.docx
docx-tex:
  page-header: title
  page-footer: ''
  include-in-header:
    file: preamble.tex
```

`include-in-header`支持文件、`text`及有序列表，与`html-tex`相同。Word版式由外部reference提供，不随插件绑定学校或论文模板。

## 文件职责

- `latex/html-latex-*.lua`：`html-tex/latex/`四个文件的派生副本。与原件只差输出格式判断多出的`docx`（外加一行说明注释），更新时同步；独立安装不需要另一个插件。
- `html-latex-config.lua`：把`docx-tex`配置放到副本读取的`html-tex`键下。
- `docx-postprocess.lua`：写出`docx-finalize.py`读取的整理清单（题名、页眉页脚配置），不参与内容转换。
- `html/docx-html-ast.lua`：HTML结构与数学转Pandoc结构。引用槽保留到最终citeproc处理，输出为隐藏的Word字符样式，避免丢失块内独有的文献或改变编号。
- `html/docx-html-normalize.lua`：用TeX发行版自带的LuaXML（`luaxml`，`kpsewhich`定位）解析HTML并做CSS选择器匹配，自己实现层叠（specificity、顺序、`!important`、继承）与五条规则：隐藏内容、`figure`容器、题注样式、无圆点列表、定宽空白。另含一层修复：lwarp产出的标记依赖浏览器的HTML5错误恢复（未闭合标签、表格内的裸内容、被祖先结束标签打断的格式元素），这里按同样规则补平，否则非浏览器消费方读不了。不解释LaTeX环境，不识别论文名称或表格内容。
- `figure/docx-pdf.lua`：PDF图片选页后通过`pdftocairo -svg`转为SVG，已有SVG原样交给Pandoc嵌入。图片转换不涉及公式。
- `docx-finalize.py`：构建后合并重复的OOXML属性容器，使用python-docx插入器保持属性顺序；整理表题分页和隐藏样式，并按明确配置替换已有页眉页脚文字。保留页码域，不改参考文档。

## 执行顺序

`_extension.yml`沿用`html-tex`的形式，逐项登记过滤器；文件顺序即执行顺序，不必追踪脚本之间的调用。

| 阶段 | 过滤器 | 该次调用的作用 |
| --- | --- | --- |
| pre-quarto | `html-latex-config.lua` | 把`docx-tex`配置交给副本 |
| pre-quarto | `html-latex-tikz.lua` | 按`render-method`路由，登记TikZ块 |
| pre-quarto | `html-latex-counters.lua` | 记录图、表、公式的计数器起点 |
| pre-quarto | `html-latex-lwarp.lua` | 登记LaTeX块，原位换占位图与引用槽 |
| post-quarto | `html-latex-ref.lua` | 把编号注入TeX源 |
| post-quarto | `html-latex-tikz.lua` | 批编译TikZ并回填 |
| post-quarto | `html-latex-lwarp.lua` | 批编译LaTeX块并回填生成的HTML |
| post-quarto | `html-latex-ref.lua` | 解析生成HTML里新出现的引用 |
| post-quarto | `html/docx-html-ast.lua` | 快照AST，HTML转Pandoc节点，展开数学宏，归一表宽 |
| post-quarto | `figure/docx-pdf.lua` | PDF选页转SVG并嵌入 |
| post-quarto | `docx-postprocess.lua` | 写出`docx-finalize.py`读取的整理清单 |

同一个文件出现两次，不是重复渲染：它按文档元数据里的状态键分两段执行，第一次登记、第二次编译，编译完清除状态键。中间隔着Quarto自己的编号与citeproc，所以两段不能合并——pre-quarto阶段就编译会拿到尚未分配的编号和尚未处理的文献。真正的TeX编译只有`tikz`和`lwarp`在post-quarto各一次批处理。

依赖包括Quarto/Pandoc、LuaLaTeX、lwarp及显式声明的宏包、Poppler、TeX发行版自带的`luaxml`，以及构建后处理用的`uv`。过滤器路径本身不再需要Python：HTML解析与CSS选择器来自`luaxml`，层叠与规则在Lua里实现。`docx-finalize.py`仍在post-render阶段用`uv run --locked --script`运行，Python依赖只服务这一步。PDF转换沿用HTML/TikZ后端的选页检查和`-noshrink`参数，保留矢量内容与物理尺寸；多页PDF必须指定`{page=N}`。转换产物及日志保存在`.quarto/docx-tex/pdf-images/`。

SVG文件或Data URI及其尺寸属性保持原样，由Pandoc DOCX writer生成Office的`svgBlip`引用，Word使用嵌入的矢量图。

Pandoc自身会尝试调用`rsvg-convert`在SVG旁附带PNG兼容预览；未安装时会警告，SVG本身仍会嵌入。此行为属于Pandoc writer，不是插件的回退逻辑，插件不隐藏该警告。

本项目的`scripts/collect-build.js`会在Quarto构建后调用整理程序。独立分发时，将下面命令加入自己的post-render流程（路径随文档位置调整）：

```powershell
uv run --locked --script _extensions/docx-tex/docx-finalize.py build/paper/report.docx paper/.quarto/docx-tex/finalize.json
```

`page-header: title`将已有页眉文字替换为当前题名；任意字符串为固定文字。`page-footer: ''`清空旧模板文字并保留页码域。未配置时保留原页眉页脚；当前不创建模板中不存在的页眉页脚区域。

## 实验边界

这是内容转换扩展，CSS布局不会自动成为Word样式。学校封面装填、声明页、单双栏分节仍需另外实现。原生Word表格保留HTML能表达的结构；复杂嵌套表、宽表、算法行号需要实际渲染检查，生成DOCX成功不代表视觉通过。

HTML规范化只处理进入Word时需要明确的结构语义，不是浏览器排版引擎；任意CSS颜色、边框、定位和尺寸不保证逐项映射。Word参考文档负责主要样式，源内容中的错误公式应修正源文件，不在转换器中加论文特判。

附录编号沿用正文的阿拉伯数字：`\appendix` 是LaTeX专属语义，只对经过LaTeX的PDF生效；`html-tex` 的HTML产物同样如此，属于两个派生后端的共同缺口，详见[实验记录](../../docs/word-experiment.md)。

编译诊断保存在文档目录`.quarto/lwarp/`和`.quarto/tikz/`，中间文档结构保存在`.quarto/docx-tex/compiled.json`。当前不复用旧块缓存，编译失败立即停止。请勿同时构建同一论文的HTML和DOCX：两个独立后端使用相同块缓存位置。

项目内六篇`report.qmd`为实际内容实验入口。`scripts/render-word-experiments.ps1`构建六篇Word及同文四模板样本。

```powershell
quarto render tests/docx-tex/fixture.qmd --to docx --profile word-test
uv run --no-project python scripts/check_docx_tex.py
powershell -NoProfile -File scripts/export-word-previews.ps1
# 快速抽样，避免在大型文档上等待完整分页：
powershell -NoProfile -File scripts/export-word-previews.ps1 -SamplePages 10
```

回归样本检查块内独有引用的编号、嵌套表格、无圆点算法、原生数学及Unicode文本；校验结果保存在`build/word-validation.json`。视觉检查PDF由本机Word只读打开输出文档后导出，不回写DOCX。
