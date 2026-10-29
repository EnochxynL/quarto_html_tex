# 原稿XML副本式Word参考文档

这次不重建正文。四个目录内新增的`reference-xml.docx`直接来自原稿包，保留全文、封面、目录、媒体、页眉页脚及全部分节。`reference-xml.pdf`是同一副本用Microsoft Word导出的目检版本；之前的`reference-reviewed.docx`仍保留，不混用两个版本。

| 目录 | 原稿与XML副本页数 | 同分辨率逐页像素对比 |
| --- | ---: | --- |
| python-experiment | 16 / 16 | 全部一致 |
| cad-report | 22 / 22 | 全部一致 |
| course-paper | 20 / 20 | 全部一致 |
| electronic-senses | 3 / 3 | 全部一致 |

比较基准为本轮在同一台电脑、同一Microsoft Word中只读导出的原稿PDF，不使用其他环境以前导出的PDF。共61页，以90 DPI光栅化后逐像素比较，并查看并排联系图。原稿已有的空白页、目录域错误也忠实保留，本任务没有修改原文或修订其内容。电子感官以原`.doc`先前转存的`source-converted.docx`为XML源。

## 修改范围

1. 对原稿样式加`Original_`样式ID前缀，并同步修改正文、编号、页眉页脚等部件的样式引用。原样式的格式属性不变；隐式默认样式仍保留默认身份。超链接与表格基准内置样式保留规范身份，避免Word隐式解析改变外观。
2. 在`word/styles.xml`追加供Pandoc使用的样式，来自已有`style-seed.docx`。这仍复用了上一轮提取出的格式定义，但没有复用上一轮的正文和布局重建程序，也不把正文换成示例内容。
3. 电子感官副本将`compatibilityMode`从11升到14，保留其他旧版排版选项。实测旧模式与Pandoc表格的`tblCaption`同时存在时，Word拒绝打开生成的文件；升级后测试通过，原文全部3页仍像素一致。
4. 媒体、关系文件、主题、原文文字、直接格式、分节XML等没有重建。验证记录列出具体变动部件、原稿和副本SHA256。

这不是Pandoc规定的唯一DOCX结构，而是让原稿格式与Pandoc输出样式并存的一种保守实现。代价是样式数量增加；以后可以在确认无引用后精简，本轮不清理中间文件。

## 使用与验证

```yaml
format:
  docx:
    reference-doc: styles/word/electronic-senses/reference-xml.docx
```

`reference-doc`仍只让Pandoc利用样式及其支持的文档属性，**不会把参考文件全文、封面、完整的多节单双栏流程插入新输出**。保留原稿结构的副本已完成；未来若需要对新QMD重现相同结构，仍需在副本指定区域装填正文。本次没有接入或修改`_extensions`。

四份参考文档都已实际交给Pandoc渲染同一`specimen.md`，涵盖标题、正文、表格、图片、列表、公式、代码和链接，再用Word成功打开、导出PDF并查看测试样张。测试文档位于`build/word-xml-review/<目录>/pandoc-probe.docx`，用于验证可用性，不作为原稿版式复刻的证明。

```powershell
python scripts/build_word_xml_references.py
& scripts/preview_word_xml_references.ps1
python scripts/compare_word_xml_references.py
```

Python环境需具备上一轮使用的python-docx、lxml、Pillow、PyMuPDF；Quarto提供Pandoc。查看`build/word-xml-review/`中的并排对照图后，才可用`--visual-review-confirmed`记录人工检查。`xml-validation.json`保存本轮结构检查和61页渲染对比结果；重新构建会重置视觉检查状态。
