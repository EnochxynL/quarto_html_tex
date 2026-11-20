-- Native DOCX structure, PDF figures, and the finalize manifest.
-- Runs after the post-quarto compilation and reference resolution.
if FORMAT ~= "docx" then return {} end
local directory = pandoc.path.directory(PANDOC_SCRIPT_FILE)
local ast = dofile(directory .. "/html/docx-html-ast.lua")
local images = dofile(directory .. "/figure/docx-pdf.lua")
function Pandoc(doc)
  pandoc.system.make_directory(".quarto/docx-tex", true)
  local snapshot = assert(io.open(".quarto/docx-tex/compiled.json", "wb"))
  snapshot:write(pandoc.write(doc, "json")); snapshot:close()
  doc = ast.convert(doc, directory)
  doc = images.convert(doc)
  local config = doc.meta["docx-tex"] or {}
  local manifest = assert(io.open(".quarto/docx-tex/finalize.json", "wb"))
  manifest:write(pandoc.json.encode({
    title = pandoc.utils.stringify(doc.meta.title or ""),
    header = config["page-header"] and pandoc.utils.stringify(config["page-header"]) or nil,
    footer = config["page-footer"] and pandoc.utils.stringify(config["page-footer"]) or nil,
  })); manifest:close()
  return doc
end
