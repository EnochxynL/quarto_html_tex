from pathlib import Path
from docx import Document
import sys
sys.stdout.reconfigure(encoding='utf-8')
sources={
'python':Path('D:/MY_WORK/Works_Workshop/AfterStory/PythonDL/reports/实验三&实验四 自动化2303 谢怡诺 补充实验完整版.docx'),
'cad':Path('D:/MY_WORK/Works_Workshop/AfterStory/Cad/shou/New folder/第5组_正式提交/案例-5-谢怡诺胡小乐许晋郗杨浩睿.docx'),
'paper':Path('D:/MY_WORK/Works_Workshop/AfterStory/CadPpt/论文/7组自动化2303论文.docx'),
'senses':Path(__file__).resolve().parents[1]/'styles/word/electronic-senses/source-converted.docx'}
for label,path in sources.items():
 d=Document(path);print('\nSOURCE',label)
 for s in d.sections[:2]:print('PAGE',s.page_width.cm,s.page_height.cm,'MARGINS',s.top_margin.cm,s.bottom_margin.cm,s.left_margin.cm,s.right_margin.cm)
 for p in d.paragraphs[:26]:
  if p.text:print('PARA',p.style.name,repr(p.text[:120]),[(r.text[:18],r.font.name,r.font.size.pt if r.font.size else None,r.bold) for r in p.runs[:3]])
 for s in d.styles:
  if s.name in ['Normal','Body Text','Title','Subtitle','Heading 1','Heading 2','Heading 3','Caption','Image Caption','Table Caption','Table','Source Code'] or s.name.startswith(('Report','Equation','Code','Cover')):
   print('STYLE',s.name,s.style_id,s.font.name,s.font.size.pt if s.font.size else None)
