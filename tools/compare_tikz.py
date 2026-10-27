"""Build an isolated visual comparison from SuperMimic's original TikZ sources.

Writes only to .quarto/tikz-compare; does not regenerate paper Markdown/assets.
Requires the existing TeX/Poppler tools and dvisvgm. Open the resulting index.html.
"""
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import argparse
import json
import os
import re
import shutil
import subprocess
import time
import xml.etree.ElementTree as ET

from convert_papers import argument, uncomment

root = Path(__file__).resolve().parents[1]
paper = root / "arXiv-2610.28480v1"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--figures", nargs="+", default=["fig-pipeline", "fig-compute", "fig-failed-motions"])
parser.add_argument("--screenshots", action="store_true", help="Capture comparison previews with installed Microsoft Edge")
parser.add_argument("--reuse", action="store_true", help="Reuse measured figures to regenerate the comparison page")
args = parser.parse_args()
output = root / ".quarto/tikz-compare"
output.mkdir(parents=True, exist_ok=True)
env = os.environ.copy()
env["PATH"] = str(Path.home() / "AppData/Local/Programs/MiKTeX/miktex/bin/x64") + os.pathsep + env["PATH"]
if not shutil.which("perl", path=env["PATH"]) and Path("C:/Program Files/Git/usr/bin/perl.exe").exists():
    env["PATH"] = "C:/Program Files/Git/usr/bin" + os.pathsep + env["PATH"]
env["TEXINPUTS"] = str(paper) + os.pathsep + env.get("TEXINPUTS", "")
env["SOURCE_DATE_EPOCH"] = "1793059200"


def run(command, directory, log):
    start = time.perf_counter()
    with (directory / log).open("w", encoding="utf-8") as stream:
        proc = subprocess.run(command, cwd=directory, env=env, stdout=stream, stderr=subprocess.STDOUT)
    if proc.returncode:
        raise RuntimeError(f"{command[0]} failed; see {directory / log}")
    return round(time.perf_counter() - start, 3)


original = uncomment((paper / "root.tex").read_text(encoding="utf-8"))
preamble = original.split(r"\title{", 1)[0].split(r"\setlength{\textfloatsep}", 1)[0]
# Retain drawing styles, colors and macros, without publication page/heading
# styling. All routes use the same drawing code and the same 5.5in text width.
preamble = preamble.replace(r"\usepackage[final]{corl_2026}", "")
preamble = preamble.replace(r"\usepackage[table]{xcolor}", r"\usepackage{xcolor}")
# The selected drawings do not use wmrfade. Its unused preamble declaration
# triggers lwarp's TikZ image hook before the document has started.
preamble = re.sub(r"\\tikzfading[^\n]*", "", preamble)
preamble += "\n" + r"\usepackage{times}\setlength{\textwidth}{5.5in}" + "\n"
aux = dict(re.findall(r"\\newlabel\{([^}]+)\}\{\{([^}]+)\}", (paper / "paper.aux").read_text(encoding="utf-8")))
source = original + "\n" + "\n".join(uncomment(p.read_text(encoding="utf-8")) for p in sorted((paper / "sections").glob("*.tex")))
labels = {}
for identifier in re.findall(r"\\label\{([^}]+)\}", source):
    normalized = identifier.replace(":", "-").replace("_", "-")
    if normalized.startswith("app-"):
        normalized = "sec-" + normalized[4:]
    if normalized in aux:
        labels[identifier] = aux[normalized]
references = "\n".join(r"\newlabel{" + key + "}{{" + value + "}{1}}" for key, value in sorted(labels.items()))

bodies = {}
for match in re.finditer(r"\\begin\{figure\}(?:\[[^]]*\])?[\s\S]*?\\end\{figure\}", source):
    figure = match[0]
    identifier = argument(figure, "label").replace(":", "-").replace("_", "-")
    caption = argument(figure, "caption")
    body = figure.replace(r"\caption{" + caption + "}", "")
    body = re.sub(r"\\label\{[^}]+\}", "", body)
    body = re.sub(r"^\\begin\{figure\}(?:\[[^]]*\])?", "", body)
    body = re.sub(r"\\end\{figure\}\s*$", "", body)
    bodies[identifier] = body


def build(identifier):
    directory = output / identifier
    directory.mkdir(exist_ok=True)
    body = bodies[identifier]
    (directory / "drawing.tex").write_text(body, encoding="utf-8")
    reference = preamble + "\n" + references + "\n" + r"\usepackage[active,tightpage]{preview}\setlength{\PreviewBorder}{2pt}"
    reference += "\n" + r"\begin{document}\begin{preview}\begin{minipage}{\textwidth}" + body
    reference += r"\end{minipage}\end{preview}\end{document}"
    (directory / "reference.tex").write_text(reference, encoding="utf-8")
    timing = {}
    timing["pdf"] = sum(run(["pdflatex", "-interaction=nonstopmode", "-halt-on-error", "reference.tex"], directory, f"pdf-{i}.log") for i in range(2))
    timing["cairo"] = run(["pdftocairo", "-svg", "-noshrink", "reference.pdf", "cairo.svg"], directory, "cairo.log")
    timing["dvisvgm"] = run(["dvisvgm", "--pdf", "--no-fonts", "--page=1", "--output=dvisvgm.svg", "reference.pdf"], directory, "dvisvgm.log")
    run(["pdftoppm", "-png", "-singlefile", "-scale-to", "1800", "reference.pdf", "reference"], directory, "png.log")
    warp = directory / "lwarp"
    warp.mkdir(exist_ok=True)
    for name in ("block.aux", "block_html.aux"):
        (warp / name).unlink(missing_ok=True)
    # The HTML image pipeline mirrors the plugin: LuaLaTeX, stabilize lateximage
    # page records, extract the PDF page, crop, convert with pdftocairo.
    # This is a direct lwarp test, not a Quarto filter integration test.
    warp_pre = preamble.replace(r"\documentclass{article}", r"\documentclass{article}" + "\n" + r"\usepackage[mathjax]{lwarp}")
    warp_source = warp_pre + "\n" + references + "\n" + r"\begin{document}\begin{minipage}{\textwidth}" + body
    warp_source += r"\end{minipage}\end{document}"
    (warp / "block.tex").write_text(warp_source, encoding="utf-8")
    start = time.perf_counter()
    run(["lualatex", "-interaction=nonstopmode", "-halt-on-error", "block.tex"], warp, "print.log")
    images = []
    for i in range(3):
        run(["lualatex", "-interaction=nonstopmode", "-halt-on-error", "block_html.tex"], warp, f"html-{i}.log")
        images = [line.split("|") for line in (warp / "block-images.txt").read_text().splitlines()
                  if re.match(r"^\|\d+\|", line)]
        if images and all(int(row[1]) > 0 for row in images):
            break
    assert len(images) == 1 and int(images[0][1]) > 0, (identifier, images)
    page = images[0][1]
    run(["pdfseparate", "-f", page, "-l", page, "block_html.pdf", "page-%d.pdf"], warp, "separate.log")
    run(["pdfcrop", "--hires", "--margins", "0 1 0 0", f"page-{page}.pdf", "cropped.pdf"], warp, "crop.log")
    run(["pdftocairo", "-svg", "-noshrink", "cropped.pdf", "../lwarp.svg"], warp, "svg.log")
    timing["lwarp"] = round(time.perf_counter() - start, 3)
    log = (warp / f"html-{i}.log").read_text(encoding="utf-8", errors="replace")
    assert "There were undefined references" not in log, identifier
    sizes = {name: (directory / file).stat().st_size for name, file in
             [("pdf", "reference.pdf"), ("cairo", "cairo.svg"), ("dvisvgm", "dvisvgm.svg"), ("lwarp", "lwarp.svg")]}
    for file in ("cairo.svg", "dvisvgm.svg", "lwarp.svg"):
        assert "<svg" in (directory / file).read_text(encoding="utf-8"), file
    record = dict(figure=identifier, seconds=timing, bytes=sizes)
    print(json.dumps(record), flush=True)
    return record


records = []
if args.reuse:
    records = [r for r in json.loads((output / "report.json").read_text(encoding="utf-8")) if r["figure"] in args.figures]
else:
    with ThreadPoolExecutor(max_workers=3) as pool:
        for future in as_completed([pool.submit(build, identifier) for identifier in args.figures]):
            records.append(future.result())
records.sort(key=lambda r: args.figures.index(r["figure"]))
for record in records:
    svg = ET.parse(output / record["figure"] / "dvisvgm.svg")
    shapes = [node for node in svg.iter() if node.tag.rsplit("}", 1)[-1] in ("path", "rect", "circle", "ellipse", "polygon", "polyline", "line")]
    def visible_paint(node):
        a = node.attrib
        return ((a.get("fill", "black") != "none" and float(a.get("fill-opacity", "1")) > 0) or
                (a.get("stroke", "none") != "none" and float(a.get("stroke-opacity", "1")) > 0))
    record["dvisvgm_all_shapes_transparent"] = bool(shapes) and not any(visible_paint(node) for node in shapes)
    if record["dvisvgm_all_shapes_transparent"]:
        record["observed_issue"] = "Browser shows blank SVG; every drawing shape has transparent paint (local dvisvgm 3.4.3)."
(output / "report.json").write_text(json.dumps(records, indent=2), encoding="utf-8")

titles = {"fig-pipeline": "方法流程图：公式、箭头、图片图标", "fig-compute": "性能图：坐标轴、刻度、折线与图例", "fig-failed-motions": "附录曲线：长图例、参考线与刻度"}
routes = [("pdf", "A · PDF", "reference.pdf"), ("cairo", "B · PDF → SVG / Cairo", "cairo.svg"),
          ("dvisvgm", "C · PDF → SVG / dvisvgm", "dvisvgm.svg"), ("lwarp", "D · TikZ → lwarp → SVG", "lwarp.svg")]
sections = []
for record in records:
    identifier = record["figure"]
    cards = []
    for key, title, file in routes:
        url = identifier + "/" + file
        image = identifier + "/reference.png" if key == "pdf" else url
        note = "默认展示 PDF 的高分辨率截图；可切换原生 PDF 阅读器。" if key == "pdf" else "浏览器直接显示 SVG，可放大目检。"
        if key == "dvisvgm" and record["dvisvgm_all_shapes_transparent"]:
            note = "本机 dvisvgm 3.4.3 转换结果为空白：所有绘图路径透明。命令成功不代表视觉正确。"
        extra = f'<embed class="pdf-view" src="{url}#toolbar=0&navpanes=0&view=FitH" type="application/pdf">' if key == "pdf" else ""
        cards.append(f'<article><h3>{title}</h3><p class="metric">{record["bytes"][key]/1024:.1f} KiB · {record["seconds"][key]:.3f} s</p><div class="viewport"><img src="{image}" alt="{title}">{extra}</div><p>{note}</p><a href="{url}" target="_blank">打开原文件</a></article>')
    sections.append(f'<section id="{identifier}"><h2>{titles.get(identifier, identifier)}</h2><p><code>{identifier}</code> · <a href="{identifier}/drawing.tex">查看原始图体</a></p><div class="grid">'+"".join(cards)+"</div></section>")
page = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>TikZ 渲染方式对比</title>
<style>
*{box-sizing:border-box}body{font:15px/1.6 system-ui,"Microsoft YaHei",sans-serif;color:#14213d;background:#f4f6fa;margin:0;padding:28px}header,section{max-width:1800px;margin:0 auto 30px}h1{margin:0 0 12px}h2{font-size:21px}h3{font-size:16px;margin:0}.intro{max-width:1150px}.controls{position:sticky;top:0;z-index:3;background:#fff;padding:14px;border:1px solid #ccd5e0;border-radius:8px;display:flex;gap:22px;align-items:center;flex-wrap:wrap}.grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:16px}article{background:white;border:1px solid #dce2eb;border-radius:10px;padding:14px;min-width:0}.metric{color:#506078;font-size:13px;margin:5px 0 10px}.viewport{height:330px;overflow:auto;border:1px solid #e1e5ec;background:white}.viewport img{display:block;width:var(--zoom,100%);max-width:none;height:auto}.viewport embed{display:none;width:var(--zoom,100%);height:100%}body.pdf-native .pdf-view{display:block}body.pdf-native .viewport:has(.pdf-view) img{display:none}a{color:#1259b2}article>p{font-size:12px;color:#536279}code{font-size:13px}.caveat{border-left:4px solid #c68619;padding-left:14px}@media(max-width:1000px){.grid{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:600px){.grid{grid-template-columns:1fr}}
</style><header><h1>TikZ：四条路线，同一份图体</h1>
<div class="intro"><p>使用 SuperMimic 的三张真实图；图体、CSV 数据、颜色及 5.5in 文本宽度相同。A–C 共用同一个 PDF，D 重新用 LuaLaTeX/lwarp 编译。A 的默认图片是 PDF 的高分辨率截图，不能用其像素化判断 PDF 本身的矢量质量；可打开 PDF 或切换阅读器。</p>
<p class="caveat">独立测试适配：移除出版页面样式、去掉未使用的 wmrfade 声明和 xcolor 的 table 选项；统一 Times 字体，并从论文 aux 注入公式编号。图体不改。D 验证 lwarp 本身及与插件相同的图像转换步骤，并非当前插件的端到端测试。耗时是本机一次测量；B/C 仅为转换耗时，不含 A 的编译。</p></div>
<div class="controls"><label>图像宽度 <input id="zoom" type="range" min="100" max="400" step="25" value="100"> <output id="value">100%</output></label><label><input id="pdf" type="checkbox"> A 使用原生 PDF 阅读器</label><a href="report.json">完整测量数据</a></div></header>
''' + "".join(sections) + '''<script>document.querySelector('#zoom').oninput=e=>{document.documentElement.style.setProperty('--zoom',e.target.value+'%');document.querySelector('#value').textContent=e.target.value+'%'};document.querySelector('#pdf').onchange=e=>document.body.classList.toggle('pdf-native',e.target.checked);
const params=new URLSearchParams(location.search);if(params.has('figure'))document.querySelectorAll('section').forEach(s=>s.hidden=s.id!==params.get('figure'));
if(params.has('capture')){const style=document.createElement('style');style.textContent='.intro,.controls{display:none}.grid{grid-template-columns:repeat(2,minmax(0,1fr))}.viewport{height:auto;min-height:80px}header{margin-bottom:8px}';document.head.append(style)}
</script></html>'''
(output / "index.html").write_text(page, encoding="utf-8")
print("Open", output / "index.html", flush=True)
if args.screenshots:
    edge = Path("C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe")
    assert edge.exists(), "Microsoft Edge is required for --screenshots"
    for identifier in args.figures:
        url = (output / "index.html").as_uri() + "?figure=" + identifier + "&capture=1"
        run([str(edge), "--headless", "--disable-gpu", "--hide-scrollbars", "--no-first-run",
             "--user-data-dir=" + str(output / "edge-profile"), "--window-size=1900,1400",
             "--virtual-time-budget=1500", "--screenshot=" + str(output / (identifier + ".png")), url],
            output, identifier + "-browser.log")
        assert (output / (identifier + ".png")).exists()
    print("Saved browser comparison screenshots", flush=True)
