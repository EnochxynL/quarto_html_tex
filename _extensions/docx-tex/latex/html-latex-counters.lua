-- Adapter: run the byte-identical html-tex backend file in an HTML context.
if FORMAT ~= "docx" then return {} end
local directory = pandoc.path.directory(PANDOC_SCRIPT_FILE)
local backend = dofile(directory .. "/../backend.lua")
function Pandoc(doc)
  return backend.run(doc, directory .. "/../backend/latex/html-latex-counters.lua")
end
