if FORMAT ~= "docx" then return {} end
local directory = pandoc.path.directory(PANDOC_SCRIPT_FILE)
local backend = dofile(directory .. "/backend.lua")
function Pandoc(doc)
  doc.meta["html-tex"] = doc.meta["docx-tex"] or pandoc.MetaMap({})
  doc = backend.run(doc, directory, "html-latex-tikz.lua")
  doc = backend.run(doc, directory, "html-latex-counters.lua")
  return backend.run(doc, directory, "html-latex-lwarp.lua")
end
