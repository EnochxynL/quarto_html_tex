-- Semantic region boundaries survive Pandoc without hard-coded heading text.
function Div(el)
  if el.classes:includes('layout-landscape') then
    local blocks = pandoc.List({pandoc.RawBlock('openxml', '<w:p><w:pPr><w:pStyle w:val="LayoutLandscapeStart"/></w:pPr></w:p>')})
    blocks:extend(el.content)
    blocks:insert(pandoc.RawBlock('openxml', '<w:p><w:pPr><w:pStyle w:val="LayoutLandscapeEnd"/></w:pPr></w:p>'))
    return blocks
  end
  if el.classes:includes('layout-references') then
    local blocks = pandoc.List({pandoc.RawBlock('openxml', '<w:p><w:pPr><w:pStyle w:val="LayoutReferencesStart"/></w:pPr></w:p>')})
    blocks:extend(el.content)
    return blocks
  end
end
function Pandoc(doc)
  doc.blocks:insert(1, pandoc.RawBlock('openxml','<w:p><w:pPr><w:pStyle w:val="LayoutBodyStart"/></w:pPr></w:p>'))
  return doc
end
