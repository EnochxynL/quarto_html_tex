# DOCX conversion regression

```powershell
quarto render tests/docx-tex/fixture.qmd --to docx --profile word-test
quarto render tests/docx-tex/fixture-html.qmd --to html --profile word-test
```

此入口不加入默认整项目构建。样本检查嵌套表、算法、原生公式，以及“正文首次引用→块内独有引用→正文后续引用”的顺序；期望编号为1、2、3，三条文献全部保留。

两个入口共用`fixture-content.md`、`fixture-metadata.yml`和`fixture-preamble.tex`，用于验证独立后端对相同内容的处理，而不是维护两份测试正文。

头文件在条件分支中声明旧字体编码，以验证lwarp的Unicode文本输出不受包预加载影响。输出应保留offline diffusion、finite differences与中文代码单元格“决策”，不能出现控制字符、替代字符或字符替换表。

内嵌small.svg验证栅格化后仍保持6pt×9pt的物理尺寸；原生Quarto提示块验证重复段落属性容器已被规范化。
