# /// script
# requires-python = ">=3.11"
# dependencies = ["lxml==6.1.3", "python-docx==1.2.0"]
# ///
"""Finish DOCX layout preserving XML namespaces; never modify the reference.

Usage: python docx-finalize.py output.docx finalize.json
Only requested headers/footers, caption pagination and output styles change.
"""
from copy import deepcopy
import json
from pathlib import Path
import sys
import tempfile
from lxml import etree as ET
from docx.oxml import OxmlElement, parse_xml
import zipfile

W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
NS = {"w": W}
ET.register_namespace("w", W)
def tag(name):
    return f"{{{W}}}{name}"

def xml(root):
    return ET.tostring(root, encoding="utf-8", xml_declaration=True)

def normalize_properties(root):
    """Merge duplicate singleton OOXML property containers, later values win.

    Quarto's raw OpenXML can add a second pPr beside Pandoc's own pPr.
    python-docx's generated inserters retain the schema's property ordering.
    """
    properties = {tag(name) for name in ("pPr", "rPr", "tblPr", "trPr", "tcPr")}
    for parent in reversed(list(root.iter())):
        groups = {}
        for child in list(parent):
            if child.tag in properties:
                groups.setdefault(child.tag, []).append(child)
        for name, containers in groups.items():
            if len(containers) < 2:
                continue
            merged = OxmlElement("w:" + ET.QName(name).localname)
            values = {}
            for container in containers:
                merged.attrib.update(container.attrib)
                for value in container:
                    values[value.tag] = deepcopy(value)
            for value in values.values():
                insert = getattr(merged, "_insert_" + ET.QName(value).localname, None)
                if callable(insert):
                    insert(value)
                else:
                    merged.append(value)
            parent.insert(parent.index(containers[0]), merged)
            for container in containers:
                parent.remove(container)

def finalize(path, settings):
    with zipfile.ZipFile(path) as package:
        infos = package.infolist()
        parts = {info.filename: package.read(info) for info in infos}
    for name, data in list(parts.items()):
        if not name.endswith(".xml"):
            continue
        kind = "header" if name.startswith("word/header") else "footer" if name.startswith("word/footer") else None
        if kind is None or settings.get(kind) is None:
            continue
        root = ET.fromstring(data)
        paragraphs = root.findall(".//w:p", NS)
        if not paragraphs:
            paragraphs = [ET.SubElement(root, tag("p"))]
        # Keep PAGE fields and paragraph/run formatting; replace literal content.
        for paragraph in paragraphs:
            in_field = False
            for run in paragraph.findall(".//w:r", NS):
                field = run.find("w:fldChar", NS)
                if field is not None and field.get(tag("fldCharType")) == "begin":
                    in_field = True
                if not in_field:
                    for text in run.findall("w:t", NS):
                        text.text = ""
                if field is not None and field.get(tag("fldCharType")) == "end":
                    in_field = False
        value = settings[kind]
        if value == "title":
            value = settings["title"]
        if value:
            paragraph = paragraphs[0]
            run = ET.SubElement(paragraph, tag("r"))
            first = paragraph.find("w:r/w:rPr", NS)
            if first is not None:
                run.append(deepcopy(first))
            ET.SubElement(run, tag("t")).text = value
        parts[name] = xml(root)
    root = parse_xml(parts["word/document.xml"])
    normalize_properties(root)
    # Anchor-only paragraphs between a caption and a table must not break the
    # pagination chain. This applies to every caption, regardless of its text.
    for paragraph in root.findall(".//w:p", NS):
        style = paragraph.find("w:pPr/w:pStyle", NS)
        if style is None or not style.get(tag("val"), "").endswith("Caption"):
            continue
        following = paragraph
        while following is not None and following.tag == tag("p"):
            props = following.find("w:pPr", NS)
            if props is None:
                props = ET.SubElement(following, tag("pPr"))
            keep = props.find("w:keepNext", NS)
            if keep is None:
                keep = ET.SubElement(props, tag("keepNext"))
            keep.set(tag("val"), "1")
            following = following.getnext()
            if following is None or "".join(following.itertext()).strip() or following.find(".//w:drawing", NS) is not None:
                break
    parts["word/document.xml"] = xml(root)
    styles = ET.fromstring(parts["word/styles.xml"])
    hidden = styles.find("w:style[@w:styleId='DocxHidden']", NS)
    if hidden is None:
        hidden = ET.SubElement(styles, tag("style"), {tag("type"): "character", tag("styleId"): "DocxHidden"})
        ET.SubElement(hidden, tag("name"), {tag("val"): "Docx Hidden"})
    hidden_props = hidden.find("w:rPr", NS)
    if hidden_props is None:
        hidden_props = ET.SubElement(hidden, tag("rPr"))
    for name in ("vanish", "webHidden"):
        value = hidden_props.find(f"w:{name}", NS)
        if value is None:
            value = ET.SubElement(hidden_props, tag(name))
        value.set(tag("val"), "1")
    for style_id in ("Caption", "TableCaption"):
        style = styles.find(f"w:style[@w:styleId='{style_id}']", NS)
        if style is not None:
            props = style.find("w:pPr", NS)
            if props is None:
                props = ET.SubElement(style, tag("pPr"))
            keep = props.find("w:keepNext", NS)
            if keep is None:
                keep = ET.SubElement(props, tag("keepNext"))
            keep.set(tag("val"), "1")
    parts["word/styles.xml"] = xml(styles)
    with tempfile.NamedTemporaryFile(dir=path.parent, suffix=".docx", delete=False) as stream:
        temporary = Path(stream.name)
    try:
        with zipfile.ZipFile(temporary, "w", zipfile.ZIP_DEFLATED) as package:
            for info in infos:
                package.writestr(info, parts[info.filename])
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)

if __name__ == "__main__":
    finalize(Path(sys.argv[1]), json.loads(Path(sys.argv[2]).read_text(encoding="utf-8")))
