# HTML规范化规则对照实验

日期：2026-10-30。环境：Quarto 1.10.19、Pandoc 3.10、本机Microsoft Word。基线为提交`221e786`中的`normalize-html.py`。

## 样本与方法

从已保存的`.quarto/docx-tex/compiled.json`提取原始HTML，不重新编译论文，不修改正文。六篇论文及回归样本共有874次HTML片段出现，按源字符串去重后为351个片段。

| 来源 | 片段出现次数 |
| --- | ---: |
| arXiv-2203.04955v2 | 71 |
| arXiv-2508.00362v1 | 6 |
| arXiv-2604.24658v3 | 403 |
| arXiv-2605.23904v2 | 86 |
| arXiv-2606.07513v1 | 217 |
| arXiv-2610.28480v1 | 87 |
| tests/docx-tex | 4 |

依次关闭隐藏内容、图容器、题注、列表、空白占位五类规则，并额外测试同时关闭图容器与题注、仅保留HTML5解析，以及完全绕过预处理，共九组。使用同一Pandoc HTML reader读取所有变体，比较完整AST哈希、纯文本哈希和节点数量。纯文本输出只用于对比，不用于最终Word转换。

再选取真实回归样本中的嵌套表格和算法片段，生成六份Word对照，用相同reference和整理程序处理，由Word只读打开并导出PDF进行目检。

## 结果

| 停用的规则 | AST变化片段数 | 纯文本变化片段数 | 已确认的影响 |
| --- | ---: | ---: | --- |
| 隐藏内容处理 | 91 | 91 | 内部初始化定义进入正文，新增9674个Math节点 |
| figure转顺序容器 | 90 | 0 | Word把题注与内容排成左右两列；对照页的表格数从2变4，新增布局表 |
| 题注标记Caption样式 | 90 | 0 | 对照页两个题注的Caption样式全部丢失 |
| 无项目符号列表处理 | 5 | 5 | 算法多出项目符号；对照页新增5个编号段落 |
| 定宽空白占位转空格 | 5 | 5 | 算法循环体缩进消失；回归样本第3行不再缩进 |

同时取消图容器和题注处理也不能恢复原效果，Word仍产生左右并排布局。完全绕过预处理不仅混入内部定义，原生表格总数还少1；该差异来自Ara论文的一个片段，HTML5解析与Pandoc直接解析的结果不同。

因此，五类规则在本语料中均有实际作用，没有整条删除。其中空白占位规则只保留层次关系，不保证Word中的空格宽度精确等于CSS长度；其近似性质没有因本次验证而消失。

## 可以交给Pandoc的部分

单独取消对`script`和`style`元素的手动删除后，351个片段的完整AST与纯文本均与基线一致。Pandoc HTML reader已经忽略这些元素，因此删除了Python中的这一重复条件，仍保留按`hidden`属性、`aria-hidden`和计算后的CSS判定隐藏内容的处理。MathJax宏提取在Lua中先于HTML规范化执行，不受此精简影响。

额外关闭片段内样式表计算，在本语料中同样没有改变结果。这不等于Pandoc支持CSS选择器或层叠；本次没有将这一未覆盖的样式表功能认定为由Pandoc接管，也没有取消它。

## 产物与回归

实验产物保存在`build/html-normalization-audit/`：

- `corpus.json`、`cases.json`：原始片段、来源及九组输入。
- `results.json`、`summary.json`：Pandoc结构与文字对比。
- `granular-results.json`：脚本/样式元素删除及样式表计算的细分对照。
- `comparison.jpg`：六组Word预览对照，分别为baseline、without_spacing、without_lists、without_figure、without_caption、without_figure_caption。
- 各变体`.docx`和`-preview.pdf`：可人工并列查看的结果。

现有`check_docx_tex.py`增加了三项实际退化检查：算法循环体缩进、两个题注的Caption样式、回归样本恰有三个表格（含原生提示块与嵌套表，防止额外布局表）。这些检查与已有的内部TeX泄漏、额外圆点检查共同保护本轮确认的行为。
