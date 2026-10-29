# Word转换实验记录

验证日期：2026-10-29。环境：Windows、Quarto 1.10.19、本机Microsoft Word。

## 实现与样稿

六篇论文增加`report.qmd`入口，正文继续引用原有Markdown内容。Whole-body论文另提供三份入口，与默认NEU journal入口合成四模板对照；四者共用`report-content.qmd`和`report-metadata.yml`。没有为Word重写论文正文，也没有填入虚构的学生、导师或机构信息。

| 内容 | OMML对象 | 图片 | 参考文献条目 |
| --- | ---: | ---: | ---: |
| TD-MPC | 466 | 61 | 58 |
| Whole-body motion imitation | 67 | 7 | 33 |
| Agent-native research artifacts | 243 | 139 | 71 |
| SkillOpt | 258 | 3 | 41 |
| Agentopia | 336 | 54 | 39 |
| SuperMimic | 321 | 13 | 28 |

表中的图片数包含插图及原本属于绘图的符号，不包含正文公式截图。表格计数包含嵌套表和Word布局表，不能直接当作论文的数据表数量。结构检查的完整结果见`build/word-validation.json`。

`report.qmd`引用NEU journal样式；`report-modern.qmd`、`report-classic.qmd`、`report-bachelor.qmd`分别使用其余三份Word参考文档。相同内容会因字体、行距、页边距与标题样式不同而产生不同分页。

## 转换边界

LaTeX交给lwarp，HTML5和CSS交给HTML5lib、tinycss2、cssselect2，Word结构与公式交给Pandoc。`docx-tex/backend/latex/`四份文件与`html-tex/latex/`对应文件逐字节一致；独立安装不需要另一个插件。

Word端只适配这些工具之间的结构差异：隐藏的浏览器初始化内容、无项目符号列表、顺序排列的浮动内容、原生数学宏展开、图片尺寸和引用上下文。未添加按论文名称、表格数值或LaTeX环境逐项拆解的规则。

源文件中不合法的公式标签和数学区域内的Markdown代码标记，在源文件中修正。Agentopia的Word入口使用元数据中的原生摘要，移除了正文中重复插入的摘要；实验样稿XML也同步清除该重复内容。没有因此增加转换器特判。

## 验证中发现的通用问题

1. lwarp文本提取：旧字体编码会把连字输出为控制字符，Latin-only等宽字体还会丢失中文代码字符。在两份相同的编译后端中统一恢复Unicode编码，并为主字体、无衬线和等宽字体提供Unicode覆盖；SuperMimic完整HTML回归和同源中英文代码样本均通过。
2. 引用：LaTeX块内的引用槽不能在最终citeproc前删除。Word字符隐藏样式保留其引用语义，避免漏掉块内独有文献及改变编号。
3. SVG尺寸：栅格化提高像素数时必须保留物理尺寸。SVG渲染按物理页面设置PNG分辨率，修复了表格小符号撑满整页的问题。
4. 分页：不强制所有表格行保持在一页，交给Word处理长行和跨页；只维持表题附近的合理分页关系。
5. 预览导出：本机Word默认全篇导出模式曾长时间等待。明确计算页数并按完整页码范围导出，可完成同一文档的预览。
6. XML属性：Quarto的原始OpenXML与Pandoc输出叠加时可能产生重复的段落属性块。统一合并单一属性容器，用python-docx的插入器保持属性顺序，并在结构检查中拒绝重复`pPr`和`rPr`。

独立回归样本验证“正文首次引用→表格独有引用→正文后续引用”的1、2、3顺序，三条文献完整保留；还检查嵌套表、算法无额外圆点、原生OMML及小SVG的物理尺寸。运行命令见`tests/docx-tex/README.md`。

## 视觉检查范围

预览PDF由Word只读打开DOCX后导出，不回写DOCX。四模板首页、论文中的算法、嵌套表、比较表、绘图及中英文内容均有抽样检查。联系图与PDF留在相应`build/arXiv-*/`目录；结构检查不能替代这些视觉检查，也不等同于逐页人工验收。

当前版本的前10页抽样文件命名为`report-sample-preview.pdf`，模板对照依次为`report-modern-sample-preview.pdf`等。SVG尺寸修正也按保留的源SVG与旧PNG字节匹配，批量同步到此前生成的中文长文样稿，未增加按论文内容识别的转换规则。早期整篇预览只作为开发过程留档，不能替代最新抽样文件。

当前是可复现的内容转换原型。任意CSS边框、颜色、定位不保证等价映射到Word；复杂跨页表格和算法的间距还可以改进。完整期刊单双栏、毕业论文封面/声明装填，以及原文手工编号与自动交叉引用的全面统一，属于后续工作。插件继承现有HTML后端的构建工具和平台约束，尚未做跨平台矩阵验证。
