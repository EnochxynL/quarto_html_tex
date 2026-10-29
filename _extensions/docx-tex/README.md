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

- `backend/latex/`：`html-tex/latex/`四个文件的原样副本。保持逐字节一致，更新时同步，不依赖安装`html-tex`。
- `backend.lua`：在隔离的HTML片段上下文中调用副本；主文档仍为DOCX。
- `docx-prepare.lua`：在Quarto编号前登记块和计数器。
- `docx-render.lua`：编号后编译、解析引用、装配原生内容。
- `latex/docx-native.lua`：HTML结构与数学转Pandoc结构。引用槽保留到最终citeproc处理，输出为隐藏的Word字符样式，避免丢失块内独有的文献或改变编号。
- `latex/normalize-html.py`：HTML5lib解析HTML，tinycss2/cssselect2处理CSS选择器与层叠；统一处理隐藏内容、无圆点列表、顺序浮动容器和空白布局。不解释LaTeX环境，不识别论文名称或表格内容。
- `figure/docx-images.lua`：PDF图片选页、转换PNG。图片转换不涉及公式。
- `docx-finalize.py`：构建后合并重复的OOXML属性容器，使用python-docx插入器保持属性顺序；整理表题分页和隐藏样式，并按明确配置替换已有页眉页脚文字。保留页码域，不改参考文档。

依赖包括Quarto/Pandoc、LuaLaTeX、lwarp及显式声明的宏包、Poppler和uv。Python辅助程序使用PEP 723脚本依赖和各自的`.lock`文件，`uv run --locked --script`自动准备隔离环境。HTML处理采用HTML5lib、lxml、tinycss2、cssselect2；SVG通过PyMuPDF栅格化，避免依赖系统安装的rsvg-convert。PDF/SVG图片最长边2400像素；公式不栅格化。

本项目的`scripts/collect-build.js`会在Quarto构建后调用整理程序。独立分发时，将下面命令加入自己的post-render流程（路径随文档位置调整）：

```powershell
uv run --locked --script _extensions/docx-tex/docx-finalize.py build/paper/report.docx paper/.quarto/docx-tex/finalize.json
```

`page-header: title`将已有页眉文字替换为当前题名；任意字符串为固定文字。`page-footer: ''`清空旧模板文字并保留页码域。未配置时保留原页眉页脚；当前不创建模板中不存在的页眉页脚区域。

## 实验边界

这是内容转换扩展，CSS布局不会自动成为Word样式。学校封面装填、声明页、单双栏分节仍需另外实现。原生Word表格保留HTML能表达的结构；复杂嵌套表、宽表、算法行号需要实际渲染检查，生成DOCX成功不代表视觉通过。

HTML规范化只处理进入Word时需要明确的结构语义，不是浏览器排版引擎；任意CSS颜色、边框、定位和尺寸不保证逐项映射。Word参考文档负责主要样式，源内容中的错误公式应修正源文件，不在转换器中加论文特判。

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
