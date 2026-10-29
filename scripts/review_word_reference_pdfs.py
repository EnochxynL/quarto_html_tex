"""Render PDF contact sheets and inspect page bounds (does not replace eye review)."""
from pathlib import Path
import json
import pymupdf as fitz
from PIL import Image,ImageOps,ImageDraw
from build_word_references import SOURCES
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'build/word-reference-review'

def review(path,key):
 d=fitz.open(path);folder=OUT/key;folder.mkdir(exist_ok=True);tiles=[];pages=[]
 for i,page in enumerate(d):
  pix=page.get_pixmap(matrix=fitz.Matrix(1.2,1.2));im=Image.frombytes('RGB',(pix.width,pix.height),pix.samples);im.save(folder/f'page-{i+1:02}.png')
  tile=Image.new('RGB',(320,475),'#d5dde6');small=ImageOps.contain(im,(310,440));tile.paste(small,((320-small.width)//2,4));ImageDraw.Draw(tile).text((8,452),f'{key} / {i+1}',fill='black');tiles.append(tile)
  outside=[b[:4] for b in page.get_text('blocks') if b[0]<-1 or b[1]<-1 or b[2]>page.rect.width+1 or b[3]>page.rect.height+1]
  pages.append({'page':i+1,'characters':len(page.get_text()),'width':page.rect.width,'height':page.rect.height,'outside':outside})
 sheet=Image.new('RGB',(320*min(4,len(tiles)),475*((len(tiles)+3)//4)),'#b9c5d1')
 for i,tile in enumerate(tiles):sheet.paste(tile,((i%4)*320,(i//4)*475))
 sheet.save(folder/'contact.png')
 return {'pages':pages,'page_count':len(d),'visual_review':'pending'}

if __name__=='__main__':
 results={}
 for key,source in SOURCES.items():
  p=OUT/(key+'.pdf')
  if p.exists():results[key]=review(p,key)
  original=source.with_suffix('.pdf') if key!='electronic-senses' else OUT/'electronic-original.pdf'
  if original.exists():results[key+'-original']=review(original,key+'-original')
 (OUT/'page-checks.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf8')
 print(json.dumps({k:v['page_count'] for k,v in results.items()}))
