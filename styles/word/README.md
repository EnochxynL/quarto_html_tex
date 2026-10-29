# Word样式与版面样张（第二版）

**人工对照请打开各目录的`reference-reviewed.docx`或同名PDF。**第一版只提取部分样式，遗漏了分节、单双栏和标题区装配，不能认为与原稿格式相同。第二版已逐份对照原稿、用Microsoft Word导出PDF并目检修改。

| 目录 | 来源 | 第二版检查与恢复的主要规则 | 样张页数 |
| --- | --- | --- | ---: |
| `python-experiment` | PythonDL补充实验完整版 | 蓝色标题、独立封面、10.5磅正文、按章分页、彩色表格、图注和页码 | 6 |
| `cad-report` | Cad第5组正式Smith案例报告 | 分层标题、封面成员表、目录、正文、浅底代码、表格和图注 | 5 |
| `course-paper` | CadPpt第7组论文 | 黑白论文、封面、目录、摘要独页、12磅正文、三线表、横向图页及正文页码起算 | 7 |
| `electronic-senses` | `D:/MY_WORK/template/DOCX/电子感官.doc` | 紧凑双语标题摘要；单栏→双栏正文→单栏参考区域；原稿行距、缩进及图注 | 2 |

四份原稿均未修改。样张使用同一份`specimen.md`正文与`specimen-metadata.json`示例元数据；内容、人员和数值都是样例，因此不会与原稿逐页对应。原稿未使用的代码、表格等角色补充了基本规则，公式统一保留原生OMML，没有复制课程论文原稿的图片公式策略。

## 样式与版面必须区分

- `style-seed.docx`：干净的样式载体，提取原稿有效样式和必要的直接格式，不携带原稿正文及旧图片。
- `layout.json`：分节、单双栏、横向区域、封面类型、表格及页眉页脚规则。
- `reference-reviewed.docx`：应用两层规则后的完整验收样张，也可提供参考样式。
- `reference-reviewed.pdf`：本轮Microsoft Word实际渲染的目检版本。
- `reference.docx`：尝试同步为修订版；Word正占用的旧文件无法覆盖，详见`manifest.json`的`original_reference_updated`。不要依靠已打开的旧窗口判断修订结果。

**仅配置`reference-doc`不会自动重建正文中的分节和封面。**它只提供Pandoc支持的样式及文档属性；完整的双栏与横向输出还需要确定性的版面适配器。本轮未改动现有论文的Quarto渲染入口，不宣称已经接入整个项目。

## 确定性构建

使用已具备`python-docx`、Pillow和PyMuPDF的Python环境，Quarto提供Pandoc。此次沿用现有环境，没有安装新环境。先运行样式提取和装配，再渲染、回填目录并复核：

```powershell
python scripts/build_word_references.py
& scripts/preview_word_references.ps1
python scripts/update_word_reference_tocs.py
& scripts/preview_word_references.ps1 -Variants @('cad-report','course-paper')
python scripts/review_word_reference_pdfs.py
python scripts/validate_word_references.py
```

目录缓存由实际PDF中的标题位置生成，并保留为Word TOC字段的缓存结果；最终校验再次核对页码。若内容变化导致目录超过一页，需增加分页收敛处理，当前验收样例的目录均为一页。

`build_word_references.py`在提取阶段读取四份本机源文档。原`.doc`的转换副本为`electronic-senses/source-converted.docx`。`manifest.json`记录源路径和SHA256，`validation.json`记录正文保留、原稿哈希、分节、公式和页面边界检查结果。

## 后续接入边界

版面适配器为`scripts/apply_word_layout.py`。其输入为Pandoc生成的中间DOCX、`layout.json`和独立元数据。`scripts/word-layout-markers.lua`传递正文起点、`.layout-landscape`和`.layout-references`语义区域，避免按某篇论文的标题文字或固定图片序号定位。

这一步仍是四个方案的样张与适配验证。全项目Quarto格式扩展、任意复杂LaTeX块转换、Linux/LibreOffice一致性、任意长度目录收敛不在此次完成范围内。Windows和Linux字体与分页需要分别验收，不能相互代替。

## 目检与验证

`build/word-reference-review/`保留四份修订PDF、逐页图片、联系图及原稿对照。此次修正了第一版遗漏的单双栏、空目录、表格跨页、代码两端对齐、额外页眉横线、段落孤页等问题。保留各方案的不同章节分页习惯，未为填满页面改写示例正文。

`validation.json`中的视觉检查结论来自本次人工式页面检查，不由脚本自动判定。结构与边界检查只能证明指定检查通过，不能证明与原稿逐像素相同。
