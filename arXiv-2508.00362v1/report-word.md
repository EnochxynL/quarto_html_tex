# Word实验入口

```powershell
quarto render arXiv-2508.00362v1/report.qmd --to docx
```

`report.qmd`采用东北大学学报参考文档。`report-modern.qmd`、`report-classic.qmd`、`report-bachelor.qmd`提供同文异模板对照；四者共用`report-content.qmd`和`report-metadata.yml`，后者保存真实题名、作者、文献与编译声明。正文继续引用原论文的`sections/abstract.md`、`sections/body.md`。

LaTeX环境统一由独立扩展`docx-tex`中的lwarp后端编译，经HTML5/CSS规范化、Pandoc HTML reader、DOCX writer进入Word。公式使用原生OMML；PDF/SVG插图转换为PNG，保留SVG的物理尺寸。后端四个源文件与`html-tex`对应文件逐字节一致。原来的论文专用转换脚本已作为开发基线留在`build/`，不再参与构建。

本项目post-render调用确定性的XML整理程序：规范化重复属性容器，更新明确指定的页眉页脚文字，保留页码域，并维持表题附近的分页关系。参考文档原件不因此改写。正文采用单栏；完整学报单双栏分节、毕业论文封面和声明装填尚未实现。

依赖与用法见[`docx-tex说明`](../_extensions/docx-tex/README.md)。最新前10页预览为`build/arXiv-2508.00362v1/report-sample-preview.pdf`，其余模板使用相应文件名前缀；四模板首页比较图为同目录的`four-templates-review.jpg`。

整体实验记录见[`word-experiment.md`](../docs/word-experiment.md)。
