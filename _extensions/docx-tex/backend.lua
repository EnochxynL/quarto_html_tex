-- Byte-identical backend files run in an isolated HTML-fragment context.
-- Quarto and the parent DOCX writer retain their real format.
local M = {}
function M.run(doc, directory, name)
  local format = setmetatable({is_html_output=function() return true end}, {__index=quarto.format})
  local proxy = setmetatable({format=format}, {__index=quarto})
  local env = setmetatable({FORMAT="html", quarto=proxy}, {__index=_G})
  local result = assert(loadfile(directory .. "/backend/latex/" .. name, "t", env))()
  if env.Pandoc then return env.Pandoc(doc) end
  for _, filter in ipairs(result or {}) do doc = doc:walk(filter) end
  return doc
end
return M
