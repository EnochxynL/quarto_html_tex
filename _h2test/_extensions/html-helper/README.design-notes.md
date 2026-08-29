## 设计备忘（路线图）：algorithm 块 → HTML filter

**动机**：algorithm/algorithmic 环境是 CS 论文标准结构（ICML/NeurIPS 模板默认），跨论文复用率高。当前门控双轨（PDF 轨 `{=latex}` algorithm + HTML 轨手写 `.algorithm-box`）的代价：内容写两遍（`\State`/`\If` 逐一手动翻译成列表）、编号写死（"Algorithm 1" 是源文本，加 Algorithm 2 不自动跟进）、改动需双端同步。

**判据**（与 fbox 对照）：语法标准化 + 语义可识别 → 值得 filter（algorithmic 命令集固定）；纯视觉原语（`\fbox{minipage}` 是万能框，filter 无法猜"引语框"语义）→ 保留门控双轨。

**实证（2026-08-27）**：pandoc 对 algorithmic 的解析**不可用**——`\begin{algorithmic}` 被当普通文本；`\State`/`\Require`/`\If` 命令被静默吞掉；`\Else`→`\ESClse`、`\EndIf`→`\ESCndIf`（命令名被 ESC 转义占位符破坏）；缩进/嵌套结构全丢。**结论：filter 不能走 html-latex-tables 的 `pandoc.read(latex)` 整体解析路线**（那条路可行是因为 tabular 是 pandoc 原生环境；algorithmic 不是）。须纯字符串翻译。

**设计 sketch**：
1. 检测：RawBlock（format tex/latex）含 `\begin{algorithm`
2. 提取：`\caption{...}`（标题）、`\label{alg-X}`（锚点）
3. 翻译（字符串级，数学 `$...$` 保留给 pandoc）：`\State X`→列表项；`\If{X}`/`\Else`/`\ElsIf{X}`/`\EndIf`→嵌套层级；`\For{X}`/`\While{X}`/`\Repeat`/`\Until{X}`→嵌套块；`\Require`/`\Ensure`→前置/后置条件段；`\Comment{X}`→注释；`\Call{f}{a}`→`f(a)`
4. 编号：统计 `\begin{algorithm` 文档顺序（复用 html-tab-crossref 的编号统计模式）→ "Algorithm N" 自动编号，**根治写死问题**
5. 输出：`<div class="algorithm-box">` + 标题 + Require/Ensure + 嵌套 ol/ul（复用现有 styles.css 的 .algorithm-box 样式）
6. 回退：未翻译命令保留原文可见（不静默吞）

**方言边界**：只支持 algorithmicx/algpseudocode 一派（`\State`/`\If`/`\For`/`\While`/`\Repeat`/`\Require`/`\Ensure`/`\Comment`/`\Call`）。algorithm2e（`\KwIn`/`\KwOut`/`\ForEach`/`\tcp{}`）是另一套语法，不支持——遇到则手写双轨（诚实边界，不是失败）。

**触发条件**：下一篇论文出现 algorithm 块时实现（YAGNI——SkillOpt 的 HTML 轨已工作，立即收益为零；本备忘已含全部设计决策，实现时无需重新趟坑）。
