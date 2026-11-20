-- The byte-identical backend files read docx-tex settings under html-tex.
if FORMAT ~= "docx" then return {} end
function Pandoc(doc)
  doc.meta["html-tex"] = doc.meta["docx-tex"] or pandoc.MetaMap({})
  return doc
end
