"""Inspect end-to-end Word artifacts and the block-only citation regression.

Run after scripts/render-word-experiments.ps1 and the word-test profile.
Uses only the Python standard library; results are written under build/.
"""
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
NS = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main",
      "m": "http://schemas.openxmlformats.org/officeDocument/2006/math",
      "wp": "http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"}

def inspect(path):
    with ZipFile(path) as package:
        assert package.testzip() is None, f"Corrupt ZIP: {path}"
        root = ET.fromstring(package.read("word/document.xml"))
        styles = ET.fromstring(package.read("word/styles.xml"))
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
            symbols = [drawing for drawing in root.findall(".//wp:inline", NS)
                       if drawing.find("wp:docPr", NS) is not None
                       and drawing.find("wp:docPr", NS).get("descr") == "small symbol"]
            assert len(symbols) == 1, "The inline SVG specimen is missing"
            extent = symbols[0].find("wp:extent", NS)
            assert int(extent.get("cx")) < 200000 and int(extent.get("cy")) < 200000, "Inline SVG grew during rasterization"
        if path.parent.name == "arXiv-2508.00362v1" and path.name in ("report.docx", "report-modern.docx", "report-classic.docx", "report-bachelor.docx"):
            assert result["omml"] == 67 and result["images"] == 7, "Whole-body paper lost math or figures"
            for value in ("0.0103", "0.0535", "0.0089", "0.0170", "0.1086", "0.0154", "0.0472", "0.1299", "0.0359", "11.34", "23.72", "0.5644"):
                assert value in texts, f"Table value missing: {value}"
        return result

def main():
    backend = ROOT / "_extensions/docx-tex/backend/latex"
    backend_files = list(backend.glob("*.lua"))
    assert len(backend_files) == 4, "Expected four self-contained backend files"
    for path in backend_files:
        original = ROOT / "_extensions/html-tex/latex" / path.name
        assert path.read_bytes() == original.read_bytes(), f"Backend copies differ: {path.name}"
    paths = sorted(ROOT.glob("build/arXiv-*/report.docx"))
    assert len(paths) == 6, "Expected six paper reports"
    paths += [ROOT / "build/arXiv-2508.00362v1" / (name + ".docx") for name in ("report-modern", "report-classic", "report-bachelor")]
    paths += [ROOT / "build/tests/docx-tex/fixture.docx"]
    assert all(path.exists() for path in paths), "Build all six papers, four templates and the regression specimen first"
    results = [inspect(path) for path in paths]
    report = ROOT / "build/word-validation.json"
    report.write_text(json.dumps({"backend_copies_identical": True, "artifacts": results}, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(results, ensure_ascii=True, indent=2))
    print(f"PASS: {len(results)} artifacts; {report}")

if __name__ == "__main__":
    main()
