-- Query logic shared by the extension and a possible upstream implementation.
-- The backend supplies access to the index and Quarto's own number formatters.
return function(backend)
  return {
    lookup = function(identifier)
      assert(type(identifier) == "string", "crossref lookup expects an identifier string")
      if not backend.enabled() then return nil end
      identifier = pandoc.text.lower(identifier:sub(1, 1)) .. identifier:sub(2)
      local entry = backend.entry(identifier)
      if entry == nil then return nil end
      local result = {
        identifier = identifier,
        ref_type = backend.ref_type(identifier),
        parent = entry.parent,
        target = "#" .. identifier,
      }
      if backend.resolve_numbers() then
        local number
        if entry.parent then
          local parent = backend.entry(entry.parent)
          if parent == nil then return result end
          number = pandoc.Inlines(backend.number(backend.ref_type(entry.parent), parent)):clone()
          number:extend({pandoc.Space(), pandoc.Str("(")})
          number:extend(backend.subnumber(entry.order))
          number:insert(pandoc.Str(")"))
        else
          number = pandoc.Inlines(backend.number(result.ref_type, entry)):clone()
        end
        result.number = number
      end
      return result
    end,
  }
end
