local query = dofile((PANDOC_SCRIPT_FILE:match("^(.*[/\\])") or "") .. "../../_extensions/crossref-query/crossref-query.lua")
-- Exercise the extension API against unmodified Quarto.
function Pandoc(doc)
  local lookup = query.lookup
  assert(lookup("fig-missing") == nil)
  assert(lookup("plain-anchor") == nil)
  assert(lookup("sec-hidden") == nil)
  assert(lookup("fig-raw-latex") == nil)
  assert(not pcall(lookup, {}))
  return doc:walk({
    Span = function(span)
      if not span.classes:includes("api-number") then
        return nil
      end
      local id = span.attributes.target
      local result = assert(lookup(id), "Missing target " .. id)
      assert(result.identifier == id)
      assert(result.ref_type == span.attributes.kind)
      assert(result.target == "#" .. id)
      assert(result.parent == span.attributes.parent)
      assert(pandoc.utils.type(result.number) == "Inlines")
      local expected = span.attributes.expected
      assert(pandoc.utils.stringify(result.number) == expected,
        id .. ": expected " .. expected .. ", got " .. pandoc.utils.stringify(result.number))
      -- Returned records and number nodes must not mutate the internal index.
      result.number[1] = pandoc.Str("changed")
      result.parent = "changed"
      result.target = "changed"
      local fresh = lookup(id)
      assert(pandoc.utils.stringify(fresh.number) == expected)
      assert(fresh.parent == span.attributes.parent)
      assert(fresh.target == "#" .. id)
      local capitalized = id:sub(1, 1):upper() .. id:sub(2)
      assert(pandoc.utils.stringify(lookup(capitalized).number) == expected)
      span.content = fresh.number
      return span
    end
  })
end
