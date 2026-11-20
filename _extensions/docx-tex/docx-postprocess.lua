-- Writes the finalize manifest that docx-finalize.py reads after the render.
-- The HTML and figure stages run as their own filters before this one.
if FORMAT ~= "docx" then return {} end

function Pandoc(doc)
  pandoc.system.make_directory(".quarto/docx-tex", true)
  local config = doc.meta["docx-tex"] or {}
  local manifest = assert(io.open(".quarto/docx-tex/finalize.json", "wb"))
  manifest:write(pandoc.json.encode({
    title = pandoc.utils.stringify(doc.meta.title or ""),
    header = config["page-header"] and pandoc.utils.stringify(config["page-header"]) or nil,
    footer = config["page-footer"] and pandoc.utils.stringify(config["page-footer"]) or nil,
  })); manifest:close()
  return doc
end
