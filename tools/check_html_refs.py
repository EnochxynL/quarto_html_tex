"""Audit the six rendered papers' reference links without re-counting objects.

Run after tools/render_papers.py --formats html. An optional --baseline folder
contains PAPER.html files for reporting changed link text during migration.
"""
import argparse
from collections import Counter, defaultdict
from html.parser import HTMLParser
import json
from pathlib import Path
import re


class References(HTMLParser):
    def __init__(self, html):
        super().__init__()
        self.ids = Counter()
        self.links = []
        self.active = None
        self.math = []
        self.current_math = None
        self.numbers = {}
        self.current_caption = None
        self.feed(html)

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if attrs.get("id"):
            self.ids[attrs["id"]] += 1
            if attrs.get("data-number"):
                self.numbers[attrs["id"]] = attrs["data-number"]
        if tag == "figcaption" and "-caption-" in attrs.get("id", ""):
            self.current_caption = dict(target=attrs["id"].split("-caption-", 1)[0], text="")
        if tag == "a" and attrs.get("href", "").startswith("#"):
            self.active = dict(target=attrs["href"][1:], text="",
                               native="quarto-xref" in attrs.get("class", "").split())
        if tag == "span" and "math" in attrs.get("class", "").split():
            self.current_math = ""

    def handle_data(self, data):
        if self.active is not None:
            self.active["text"] += data
        if self.current_math is not None:
            self.current_math += data
        if self.current_caption is not None:
            self.current_caption["text"] += data

    def handle_endtag(self, tag):
        if tag == "a" and self.active is not None:
            self.links.append(self.active)
            self.active = None
        if tag == "span" and self.current_math is not None:
            self.math.append(self.current_math)
            self.current_math = None
        if tag == "figcaption" and self.current_caption is not None:
            match = re.match(r"[^\d]*?(\d+(?:\.\d+)*)\s*:", self.current_caption["text"].strip())
            if match:
                self.numbers[self.current_caption["target"]] = match[1]
            self.current_caption = None


def trailing_number(text):
    text = text.strip()
    if re.fullmatch(r"\(\d+(?:\.\d+)*\)", text):
        text = text[1:-1]
    match = re.search(r"(\d+(?:\.\d+)*(?:\s*\([a-z]+\))?)$", text.strip())
    return re.sub(r"\s+", "", match[1]) if match else None


def audit(path, baseline=None):
    html = path.read_text(encoding="utf-8")
    doc = References(html)
    broken = sorted({a["target"] for a in doc.links if a["target"] and a["target"] not in doc.ids})
    assert not broken, (path.parent.name, "broken links", broken)
    assert 'class="lwarp-failed"' not in html, path
    assert "unresolved-ref" not in html, path
    assert "@@REF:" not in html and "[TAB-CAP:" not in html, path
    assert "@@HTMLREF-LITERAL:" not in html, path
    assert not re.search(r"\[(?:fig|tbl|tab|sec|eq|alg)-[^\]<]+\]", html), path
    assert not any(re.search(r"\\(?:eq)?ref\s*\{", text) for text in doc.math), path
    native = dict(doc.numbers)
    for a in doc.links:
        if a["native"] and trailing_number(a["text"]):
            native[a["target"]] = trailing_number(a["text"])
    compared = 0
    for a in doc.links:
        number = trailing_number(a["text"])
        if not a["native"] and a["target"] in native and number:
            assert number == native[a["target"]], (path, a, native[a["target"]])
            compared += 1
    result = dict(paper=path.parent.name, fragment_links=len(doc.links),
                  native_number_comparisons=compared, broken_links=broken)
    if baseline and baseline.exists():
        old = References(baseline.read_text(encoding="utf-8"))
        old_duplicates = {key: n for key, n in old.ids.items() if n > 1}
        assert all(n <= old_duplicates.get(key, 1) for key, n in doc.ids.items()), path
        def texts(document):
            values = defaultdict(set)
            for a in document.links:
                if a["target"]:
                    values[a["target"]].add(a["text"].strip())
            return values
        before, after = texts(old), texts(doc)
        result["changed_link_text"] = {
            key: dict(before=sorted(before[key]), after=sorted(after[key]))
            for key in before.keys() & after.keys() if before[key] != after[key]
        }
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--papers", nargs="+")
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    papers = args.papers or sorted(p.name for p in root.glob("arXiv-*") if (p / "index.qmd").exists())
    results = []
    for name in papers:
        baseline = args.baseline / (name + ".html") if args.baseline else None
        result = audit(root / name / "index.html", baseline)
        results.append(result)
        print(f"PASS {name}: {result['fragment_links']} fragment links, "
              f"{result['native_number_comparisons']} native number comparisons")
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
