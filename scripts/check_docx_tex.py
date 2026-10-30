"""Inspect end-to-end Word artifacts and the block-only citation regression.

Run after scripts/render-word-experiments.ps1 and the word-test profile.
Uses only the Python standard library; results are written under build/.
"""
import argparse
from base64 import b64decode
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
NS = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main",
      "m": "http://schemas.openxmlformats.org/officeDocument/2006/math",
      "wp": "http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing",
      "asvg": "http://schemas.microsoft.com/office/drawing/2016/SVG/main",
      "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships"}

def inspect(path):
    with ZipFile(path) as package:
        assert package.testzip() is None, f"Corrupt ZIP: {path}"
        root = ET.fromstring(package.read("word/document.xml"))
        styles = ET.fromstring(package.read("word/styles.xml"))
        relationships = ET.fromstring(package.read("word/_rels/document.xml.rels"))
        targets = {rel.get("Id"): rel.get("Target") for rel in relationships}
        svg_blips = root.findall(".//asvg:svgBlip", NS)
        for blip in svg_blips:
            target = targets[blip.get(f"{{{NS['r']}}}embed")]
            svg = package.read("word/" + target)
            assert target.endswith(".svg") and ET.fromstring(svg).tag == "{http://www.w3.org/2000/svg}svg", f"Invalid embedded SVG: {path}"
        texts = "".join(node.text or "" for node in root.findall(".//w:t", NS))
        identity = ""
        for name in package.namelist():
            if name.endswith(".xml") and name.startswith(("word/header", "word/footer")):
                identity += "".join(ET.fromstring(package.read(name)).itertext())
        assert "谢怡诺" not in identity and "实验三与实验四" not in identity, f"Stale report identity: {path}"
        assert not re.search(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", texts), f"Control characters: {path}"
        assert "\\def \\LWR" not in texts and "\\boldsymbol{" not in texts, f"Unrendered internal TeX: {path}"
        assert "\ufffd" not in "".join(root.itertext()), f"Replacement characters indicate lost text: {path}"
        assert all(len(paragraph.findall("w:pPr", NS)) <= 1 for paragraph in root.findall(".//w:p", NS)), f"Duplicate paragraph properties: {path}"
        assert all(len(run.findall("w:rPr", NS)) <= 1 for run in root.findall(".//w:r", NS)), f"Duplicate run properties: {path}"
        hidden = styles.find("w:style[@w:styleId='DocxHidden']/w:rPr/w:vanish", NS)
        result = {
            "file": path.relative_to(ROOT).as_posix(),
            "omml": len(root.findall(".//m:oMath", NS)),
            "display_equations": len(root.findall(".//m:oMathPara", NS)),
            "tables_including_nested_and_layout": len(root.findall(".//w:tbl", NS)),
            "images": len(root.findall(".//w:drawing", NS)),
            "svg_drawings": len(svg_blips),
            "bibliography_entries": sum(
                p.find("w:pPr/w:pStyle", NS) is not None and p.find("w:pPr/w:pStyle", NS).get(f"{{{NS['w']}}}val") == "Bibliography"
                for p in root.findall(".//w:p", NS)),
            "hidden_style_defined": hidden is not None,
        }
        if path.name == "fixture.docx":
            assert result["bibliography_entries"] == 3, "Block-only reference was omitted"
            assert "Last parent citation [3]" in texts, "Citation first-use order changed"
            table_text = "".join(t.text or "" for tbl in root.findall(".//w:tbl", NS) for t in tbl.findall(".//w:t", NS))
            assert "[2]" in table_text, "Block citation disagrees with bibliography"
            assert "offline diffusion" in texts and "finite differences" in texts, "Unicode extraction failed"
            assert "\u51b3\u7b56" in texts, "Chinese texttt content was lost"
            assert result["omml"] >= 5, "Native equations were lost"
            assert not root.findall(".//w:numPr", NS), "CSS list-style:none became Word bullets"
            assert result["hidden_style_defined"], "Temporary citation slots have no hidden style"
            drawings = {drawing.find("wp:docPr", NS).get("descr"): drawing
                        for drawing in root.findall(".//wp:inline", NS)
                        if drawing.find("wp:docPr", NS) is not None}
            for description, size in (("small symbol", (6, 9)), ("sized symbol", (12, 18)), ("data symbol", (6, 9))):
                assert description in drawings, f"Missing SVG specimen: {description}"
                extent = drawings[description].find("wp:extent", NS)
                actual = (int(extent.get("cx")), int(extent.get("cy")))
                # A point is 12700 EMU; SVG keeps its physical dimensions.
                assert all(abs(value - points * 12700) < 100 for value, points in zip(actual, size)), f"SVG physical size changed: {description} {actual}"
            assert "Diagram" in drawings, "Native TikZ drawing was lost"
            assert len(svg_blips) == 4, "File, data URI, explicit-size and TikZ SVGs must remain vectors"
            for description in ("small symbol", "data symbol"):
                blip = drawings[description].find(".//asvg:svgBlip", NS)
                target = targets[blip.get(f"{{{NS['r']}}}embed")]
                if description == "data symbol":
                    source = (ROOT / "tests/docx-tex/fixture-content.md").read_text(encoding="utf-8")
                    expected = b64decode(re.search(r"data:image/svg\+xml;base64,([A-Za-z0-9+/=]+)", source).group(1))
                else:
                    expected = (ROOT / "tests/docx-tex/small.svg").read_bytes()
                assert package.read("word/" + target) == expected, "Original SVG bytes changed"
        if path.parent.name == "arXiv-2508.00362v1" and path.name in ("report.docx", "report-modern.docx", "report-classic.docx", "report-bachelor.docx"):
            assert result["omml"] == 67 and result["images"] == 7, "Whole-body paper lost math or figures"
            for value in ("0.0103", "0.0535", "0.0089", "0.0170", "0.1086", "0.0154", "0.0472", "0.1299", "0.0359", "11.34", "23.72", "0.5644"):
                assert value in texts, f"Table value missing: {value}"
        return result

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture-only", action="store_true", help="Check regression output without rebuilding the six papers")
    args = parser.parse_args()
    backend = ROOT / "_extensions/docx-tex/backend/latex"
    backend_files = list(backend.glob("*.lua"))
    assert len(backend_files) == 4, "Expected four self-contained backend files"
    for path in backend_files:
        original = ROOT / "_extensions/html-tex/latex" / path.name
        assert path.read_bytes() == original.read_bytes(), f"Backend copies differ: {path.name}"
    paths = []
    if not args.fixture_only:
        paths = sorted(ROOT.glob("build/arXiv-*/report.docx"))
        assert len(paths) == 6, "Expected six paper reports"
        paths += [ROOT / "build/arXiv-2508.00362v1" / (name + ".docx") for name in ("report-modern", "report-classic", "report-bachelor")]
    paths += [ROOT / "build/tests/docx-tex/fixture.docx"]
    assert all(path.exists() for path in paths), "Build the selected reports and regression specimens first"
    results = [inspect(path) for path in paths]
    report = ROOT / "build" / ("word-fixture-validation.json" if args.fixture_only else "word-validation.json")
    report.write_text(json.dumps({"backend_copies_identical": True, "artifacts": results}, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(results, ensure_ascii=True, indent=2))
    print(f"PASS: {len(results)} artifacts; {report}")

if __name__ == "__main__":
    main()
