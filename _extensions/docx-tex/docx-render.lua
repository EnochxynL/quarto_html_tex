if FORMAT ~= "docx" then return {} end
local directory = pandoc.path.directory(PANDOC_SCRIPT_FILE)
local backend = dofile(directory .. "/backend.lua")
local native = dofile(directory .. "/latex/docx-native.lua")
local images = dofile(directory .. "/figure/docx-images.lua")
function Pandoc(doc)
  doc = backend.run(doc, directory, "html-latex-ref.lua")
  doc = backend.run(doc, directory, "html-latex-tikz.lua")
  doc = backend.run(doc, directory, "html-latex-lwarp.lua")
  doc = backend.run(doc, directory, "html-latex-ref.lua")
  pandoc.system.make_directory(".quarto/docx-tex", true)
  local snapshot = assert(io.open(".quarto/docx-tex/compiled.json", "wb"))
  snapshot:write(pandoc.write(doc, "json")); snapshot:close()
  doc = native.convert(doc, directory)
  doc = images.convert(doc, directory)
  local config=doc.meta['docx-tex'] or {}
  local manifest=assert(io.open('.quarto/docx-tex/finalize.json','wb'))
  manifest:write(pandoc.json.encode({
    title=pandoc.utils.stringify(doc.meta.title or ''),
    header=config['page-header'] and pandoc.utils.stringify(config['page-header']) or nil,
    footer=config['page-footer'] and pandoc.utils.stringify(config['page-footer']) or nil,
  })); manifest:close()
  return doc
end
