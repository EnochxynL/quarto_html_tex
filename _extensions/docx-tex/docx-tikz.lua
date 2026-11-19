-- Adapter: run the html-tex tikz copy inside an isolated HTML context.
if FORMAT ~= "docx" then return {} end
local directory = pandoc.path.directory(PANDOC_SCRIPT_FILE)
local runner = dofile(directory .. "/latex/html-latex.lua")
function Pandoc(doc)
  return runner.run(doc, directory .. "/latex/html-latex-tikz.lua")
end
