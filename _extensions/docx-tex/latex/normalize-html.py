# /// script
# requires-python = ">=3.11"
# dependencies = ["lxml==6.1.3", "html5lib==1.1", "tinycss2==1.5.1", "cssselect2==0.10.1"]
# ///
"""Normalize browser layout semantics before Pandoc's HTML reader.

HTML5 parsing and CSS selector/cascade parsing use established libraries. No
LaTeX commands, paper names, table contents or algorithm syntax appear here.
"""
import json
import re
import sys
import html5lib
from lxml import etree
import cssselect2
import tinycss2

sys.stdin.reconfigure(encoding="utf-8")
sys.stdout.reconfigure(encoding="utf-8")

def declarations(text):
    return {item.lower_name: (tinycss2.serialize(item.value).strip(), item.important)
            for item in tinycss2.parse_declaration_list(text, skip_comments=True, skip_whitespace=True)
            if item.type == "declaration"}

def normalize(source):
    document = html5lib.parse(source, treebuilder="lxml", namespaceHTMLElements=False)
    root = document.getroot()
    matcher = cssselect2.Matcher()
    for style in root.iter("style"):
        for rule in tinycss2.parse_stylesheet(style.text or "", skip_comments=True, skip_whitespace=True):
            if rule.type != "qualified-rule":
                continue
            try:
                selectors = cssselect2.compile_selector_list(rule.prelude)
            except cssselect2.SelectorError:
                continue
            values = declarations(tinycss2.serialize(rule.content))
            for selector in selectors:
                matcher.add_selector(selector, values)
    computed = {}
    for wrapper in cssselect2.ElementWrapper.from_html_root(root).iter_subtree():
        element = wrapper.etree_element
        values = {}
        if element.getparent() is not None:
            parent = computed.get(element.getparent(), {})
            for key in ("list-style-type", "visibility"):
                if key in parent:
                    values[key] = parent[key]
        # Matcher orders by specificity and rule order. Importance sorts last.
        candidates = []
        for specificity, order, pseudo, rules in matcher.match(wrapper):
            if pseudo is None:
                for key, (value, important) in rules.items():
                    candidates.append((important, specificity, order, key, value))
        for key, (value, important) in declarations(element.get("style", "")).items():
            candidates.append((important, (1000000, 0, 0), 0, key, value))
        for _, _, _, key, value in sorted(candidates):
            values[key] = value
        computed[element] = values
    for element in list(root.iter()):
        if element.getparent() is None or not isinstance(element.tag, str):
            continue
        values = computed.get(element, {})
        hidden = ("hidden" in element.attrib or element.get("aria-hidden") == "true"
                  or values.get("display") == "none" or values.get("visibility") == "hidden")
        if hidden or element.tag in ("script", "style"):
            parent = element.getparent()
            if element.tail:
                previous = element.getprevious()
                if previous is None:
                    parent.text = (parent.text or "") + element.tail
                else:
                    previous.tail = (previous.tail or "") + element.tail
            parent.remove(element)
            continue
        if element.tag == "figure":
            # Sequential float content must not become a Word image gallery.
            element.tag = "div"
        if element.tag == "figcaption" or "figurecaption" in element.get("class", "").split():
            element.tag = "div"
            element.set("custom-style", "Caption")
        if element.tag in ("ul", "ol") and values.get("list-style-type") == "none":
            element.tag = "div"
            for child in element:
                if child.tag == "li":
                    child.tag = "div"
        if element.tag == "span" and values.get("display") == "inline-block":
            width = re.fullmatch(r"([0-9.]+)(pt|px|em)", values.get("width", ""))
            if width and not "".join(element.itertext()).strip():
                size, unit = float(width[1]), width[2]
                points = size * {"pt": 1, "px": .75, "em": 12}[unit]
                element.text = "\u2002" * round(points / 6)
    body = root.find("body")
    return etree.tostring(body, method="html", encoding="unicode")

json.dump([normalize(item) for item in json.load(sys.stdin)], sys.stdout, ensure_ascii=False)
