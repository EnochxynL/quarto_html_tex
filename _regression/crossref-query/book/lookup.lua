local query = dofile((PANDOC_SCRIPT_FILE:match("^(.*[/\\])") or "") .. "../../../_extensions/crossref-query/crossref-query.lua")
function Pandoc(doc)
  for _, id in ipairs({"sec-chapter", "sec-appendix", "tbl-chapter", "tbl-appendix"}) do
    local result = query.lookup(id)
    if result then
      assert(result.identifier == id)
      assert(result.number == nil, "Book numbering is not final during file-local filtering")
      assert(result.target == "#" .. id)
    end
  end
  return doc:walk({
    Span = function(span)
      if span.classes:includes("api-book-target") then
        local result = assert(query.lookup(span.attributes.target))
        assert(result.number == nil)
      end
    end
  })
end
