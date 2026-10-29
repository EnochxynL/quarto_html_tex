"""Preserve source packages; isolate original styles and add Pandoc-facing styles."""
from pathlib import Path
from copy import deepcopy
import hashlib
import json
import subprocess
import zipfile
from lxml import etree as ET
from build_word_references import ROOT, OUT, SOURCES

W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
NS = {'w': W}
VAL = '{'+W+'}val'
SID = '{'+W+'}styleId'
REFS = {'pStyle', 'rStyle', 'tblStyle', 'basedOn', 'next', 'link',
        'numStyleLink', 'styleLink'}

def digest(data):
    return hashlib.sha256(data).hexdigest()

def xml(data):
    return ET.fromstring(data)

def serialize(root):
    return ET.tostring(root, encoding='UTF-8', xml_declaration=True, standalone=True)

def remap(root, mapping):
    for node in root.iter():
        if not isinstance(node.tag, str):
            continue
        tag = ET.QName(node)
        if tag.namespace == W and tag.localname in REFS and node.get(VAL) in mapping:
            node.set(VAL, mapping[node.get(VAL)])

def build(key, source):
    target = OUT/key/'reference-xml.docx'
    original_hash = digest(source.read_bytes())
    with zipfile.ZipFile(source) as archive:
        parts = {n: archive.read(n) for n in archive.namelist()}
        infos = archive.infolist()
    with zipfile.ZipFile(OUT/key/'style-seed.docx') as archive:
        additions = xml(archive.read('word/styles.xml'))
    styles = xml(parts['word/styles.xml'])
    source_styles = styles.findall('w:style', NS)
    original_definitions = [deepcopy(s) for s in source_styles]
    occupied = {n.get(SID) for n in additions.findall('w:style', NS)}
    mapping = {}
    # Word resolves these built-ins implicitly (TOC links / table base style).
    # Keep their canonical identity rather than cloning an implicit default.
    preserved = {s.get(SID) for s in source_styles if s.get(SID) in {'Hyperlink','TableNormal'}}
    for style in source_styles:
        old = style.get(SID)
        if old in preserved:
            continue
        new = 'Original_' + old
        while new in occupied:
            new = 'Original_' + new
        mapping[old] = new
        occupied.add(new)
    changed = []
    compatibility_upgraded = False
    # Change only style references, never text, runs, geometry or relationships.
    for name, data in list(parts.items()):
        if not name.startswith('word/') or not name.endswith('.xml') or name == 'word/styles.xml':
            continue
        tree = xml(data)
        before = ET.tostring(tree, method='c14n')
        remap(tree, mapping)
        upgraded = False
        if name == 'word/settings.xml':
            for setting in tree.findall('w:compat/w:compatSetting', NS):
                if setting.get('{'+W+'}name') == 'compatibilityMode' and int(setting.get(VAL,'15')) < 14:
                    setting.set(VAL,'14')
                    upgraded = True
                    compatibility_upgraded = True
        if name == 'word/stylesWithEffects.xml':
            for node in tree.findall('w:style', NS):
                if node.get(SID) in mapping:
                    node.set(SID, mapping[node.get(SID)])
        if ET.tostring(tree, method='c14n') != before:
            check = deepcopy(tree)
            remap(check, {v:k for k,v in mapping.items()})
            if name == 'word/stylesWithEffects.xml':
                reverse = {v:k for k,v in mapping.items()}
                for node in check.findall('w:style', NS):
                    if node.get(SID) in reverse:
                        node.set(SID, reverse[node.get(SID)])
            if not upgraded:
                assert ET.tostring(check, method='c14n') == before, name
            parts[name] = serialize(tree)
            changed.append(name)
    remap(styles, mapping)
    for style in source_styles:
        if style.get(SID) in preserved:
            continue
        style.set(SID, mapping[style.get(SID)])
        name = style.find('w:name', NS)
        if name is not None:
            name.set(VAL, 'Original ' + name.get(VAL, ''))
        # Aliases must not make Pandoc select the source-only definitions.
        alias = style.find('w:aliases', NS)
        if alias is not None:
            alias.set(VAL, ','.join('Original '+s for s in alias.get(VAL,'').split(',')))
    for current, original in zip(source_styles, original_definitions):
        check = deepcopy(current)
        remap(check, {v:k for k,v in mapping.items()})
        check.set(SID, original.get(SID))
        for tag in ['name','aliases']:
            old = original.find('w:'+tag,NS)
            now = check.find('w:'+tag,NS)
            if old is not None and now is not None:
                now.set(VAL,old.get(VAL))
        assert ET.tostring(check,method='c14n') == ET.tostring(original,method='c14n')
    added_count = 0
    for style in additions.findall('w:style', NS):
        if style.get(SID) in preserved:
            continue
        node = deepcopy(style)
        node.attrib.pop('{'+W+'}default', None)
        # CT_TblStylePr requires pPr/rPr before tblPr/trPr/tcPr.
        for conditional in node.findall('w:tblStylePr', NS):
            order = {'pPr':0,'rPr':1,'tblPr':2,'trPr':3,'tcPr':4}
            conditional[:] = sorted(conditional, key=lambda n:order.get(ET.QName(n).localname,99))
        styles.append(node)
        added_count += 1
    parts['word/styles.xml'] = serialize(styles)
    with zipfile.ZipFile(target, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        for info in infos:
            archive.writestr(info, parts[info.filename])
    assert digest(source.read_bytes()) == original_hash
    original_doc = xml(zipfile.ZipFile(source).read('word/document.xml'))
    output_doc = xml(parts['word/document.xml'])
    assert original_doc.xpath('//w:t/text()',namespaces=NS) == output_doc.xpath('//w:t/text()',namespaces=NS)
    assert [ET.tostring(x) for x in original_doc.xpath('//w:sectPr',namespaces=NS)] == [ET.tostring(x) for x in output_doc.xpath('//w:sectPr',namespaces=NS)]
    work = ROOT/'build/word-xml-review'/key
    work.mkdir(parents=True, exist_ok=True)
    probe = work/'pandoc-probe.docx'
    subprocess.run(['quarto','pandoc',str(OUT/'specimen.md'),
        '--resource-path='+str(OUT), '--reference-doc='+str(target),
        '--output='+str(probe)],check=True)
    with zipfile.ZipFile(probe) as archive:
        probe_doc = xml(archive.read('word/document.xml'))
        probe_styles = xml(archive.read('word/styles.xml'))
    ids = {n.get(SID) for n in probe_styles.findall('w:style',NS)}
    used = probe_doc.xpath('//w:pStyle/@w:val | //w:rStyle/@w:val | //w:tblStyle/@w:val', namespaces=NS)
    assert set(used) <= ids
    return dict(name=key, source=str(source), source_sha256=original_hash,
        reference=str(target.relative_to(ROOT)), changed_parts=changed+['word/styles.xml'],
        reference_sha256=digest(target.read_bytes()),
        original_content_preserved=True, section_xml_preserved=True,
        original_style_properties_preserved=True, compatibility_upgraded_to_14=compatibility_upgraded,
        untouched_parts=len(parts)-len(changed)-1, package_parts=len(parts),
        original_styles_isolated=len(mapping), pandoc_styles_added=added_count,
        pandoc_probe_passed=True, pandoc_probe_styles=sorted(set(used)),
        visual_review='pending')

if __name__ == '__main__':
    records = [build(key,source) for key,source in SOURCES.items()]
    (OUT/'xml-validation.json').write_text(json.dumps(records,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(records,ensure_ascii=True,indent=2))
