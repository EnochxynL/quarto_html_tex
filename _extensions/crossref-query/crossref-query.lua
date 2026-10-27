-- Load this module from the consuming filter using dofile().
-- A future public API can replace the private adapter without changing callers.
local directory = debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or ""
if quarto.doc and quarto.doc.crossref and
    type(quarto.doc.crossref.lookup) == "function" then
  return {lookup = quarto.doc.crossref.lookup}
end
local create_query = dofile(directory .. "query.lua")
local create_backend = dofile(directory .. "quarto-internal.lua")
return create_query(create_backend())
