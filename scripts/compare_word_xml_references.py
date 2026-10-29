"""Compare Word PDF renders page by page, retaining visual review artifacts."""
import json
import argparse
import hashlib
from pathlib import Path
import pymupdf as fitz
from PIL import Image, ImageChops, ImageDraw
from build_word_references import ROOT, OUT

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--visual-review-confirmed',action='store_true')
    args = parser.parse_args()
    records = json.loads((OUT/'xml-validation.json').read_text(encoding='utf-8'))
    for record in records:
        assert hashlib.sha256(Path(record['source']).read_bytes()).hexdigest() == record['source_sha256']
        assert hashlib.sha256((ROOT/record['reference']).read_bytes()).hexdigest() == record['reference_sha256']
        folder = ROOT/'build/word-xml-review'/record['name']
        source = fitz.open(folder/'original.pdf')
        target = fitz.open(folder/'reference.pdf')
        assert len(source) == len(target), record['name']
        comparisons = []
        thumbs = []
        for index, (before, after) in enumerate(zip(source,target)):
            assert before.rect == after.rect
            a = before.get_pixmap(matrix=fitz.Matrix(1.25,1.25),alpha=False)
            b = after.get_pixmap(matrix=fitz.Matrix(1.25,1.25),alpha=False)
            im1 = Image.frombytes('RGB',(a.width,a.height),a.samples)
            im2 = Image.frombytes('RGB',(b.width,b.height),b.samples)
            diff = ImageChops.difference(im1,im2)
            bbox = diff.getbbox()
            comparisons.append(dict(page=index+1,pixel_identical=bbox is None,difference_bbox=bbox))
            if bbox:
                diff.save(folder/f'difference-{index+1:02}.png')
            pair = Image.new('RGB',(520,395),'#dddddd')
            draw = ImageDraw.Draw(pair)
            draw.text((5,3),f'Page {index+1}: original | XML reference',fill='black')
            for column,im in enumerate((im1,im2)):
                im.thumbnail((250,370))
                pair.paste(im,(column*260+5,20))
            thumbs.append(pair)
        for start in range(0,len(thumbs),8):
            batch = thumbs[start:start+8]
            sheet = Image.new('RGB',(1040,395*((len(batch)+1)//2)),'white')
            for i,im in enumerate(batch):
                sheet.paste(im,((i%2)*520,(i//2)*395))
            sheet.save(folder/f'comparison-{start//8+1}.png')
        probe = fitz.open(folder/'pandoc-probe.pdf')
        sheet = Image.new('RGB',(300*len(probe),440),'#dddddd')
        for i,page in enumerate(probe):
            pix = page.get_pixmap(alpha=False)
            im = Image.frombytes('RGB',(pix.width,pix.height),pix.samples)
            im.thumbnail((290,420))
            sheet.paste(im,(300*i+5,10))
        sheet.save(folder/'pandoc-probe-contact.png')
        record.update(pdf_pages=len(source),render_comparison=comparisons,
            all_pages_pixel_identical=all(p['pixel_identical'] for p in comparisons),
            pandoc_probe_pages=len(probe),
            visual_review='confirmed_after_page_review' if args.visual_review_confirmed else 'pending')
        print(record['name'],len(source),'pages; identical:',record['all_pages_pixel_identical'])
        # Put the exact PDF paired with this reference beside the DOCX for review.
        (OUT/record['name']/'reference-xml.pdf').write_bytes((folder/'reference.pdf').read_bytes())
    (OUT/'xml-validation.json').write_text(json.dumps(records,ensure_ascii=False,indent=2),encoding='utf-8')

if __name__ == '__main__':
    main()
