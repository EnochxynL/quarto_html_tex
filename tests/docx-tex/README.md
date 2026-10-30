# DOCX conversion regression

```powershell
quarto render tests/docx-tex/fixture.qmd --to docx --profile word-test
quarto render tests/docx-tex/fixture-html.qmd --to html --profile word-test
uv run --no-project python scripts/check_docx_tex.py --fixture-only
```

此入口不加入默认整项目构建。样本检查嵌套表、算法、原生公式，以及“正文首次引用→块内独有引用→正文后续引用”的顺序；期望编号为1、2、3，三条文献全部保留。

两个入口共用`fixture-content.md`、`fixture-metadata.yml`和`fixture-preamble.tex`，用于验证HTML与Word对相同内容的处理，不维护多份测试正文。请顺序构建，它们共用编译缓存目录。

头文件在条件分支中声明旧字体编码，以验证lwarp的Unicode文本输出不受包预加载影响。输出应保留offline diffusion、finite differences与中文代码单元格“决策”，不能出现控制字符、替代字符或字符替换表。

SVG覆盖文件路径、Data URI、显式尺寸和原生TikZ后端生成的图。Word输出应有四个`svgBlip`引用，文件与Data URI的源字节不变；small.svg隐式尺寸为6pt×9pt，显式尺寸为12pt×18pt。原生Quarto提示块验证重复段落属性容器已被规范化。

Pandoc 3.10未找到`rsvg-convert`时会报告PNG兼容预览生成失败，但仍保留原生SVG。结构检查需要配合Word导出PDF目检，不能仅凭嵌入的SVG存在就判定显示正确。
