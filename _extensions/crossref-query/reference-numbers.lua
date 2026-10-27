-- Optional example consumer: []{.reference-number target="fig-example"}.
local directory = PANDOC_SCRIPT_FILE:match("^(.*[/\\])") or ""
local query = dofile(directory .. "crossref-query.lua")
function Pandoc(doc)
  return doc:walk({Span = function(span)
    if not span.classes:includes("reference-number") then return nil end
    local ref = query.lookup(span.attributes.target)
    if ref and ref.number then
      return pandoc.Link(ref.number, ref.target)
    end
    -- Keep unresolved content for the consuming extension to handle.
  end})
end
