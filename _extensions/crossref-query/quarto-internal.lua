-- Transitional adapter. This is the ONLY file that reads private Quarto globals.
-- Call from a post-quarto (or later) document callback: older Quarto versions
-- have no reliable public flag indicating that indexing has finished.
return function()
  local function internal(name)
    local value = rawget(_G, name)
    assert(value ~= nil, "crossref-query: incompatible Quarto internals: " .. name)
    return value
  end
  local param = internal("param")
  return {
    enabled = function() return param("enable-crossref", true) end,
    resolve_numbers = function() return param("crossref-resolve-refs", true) end,
    entry = function(identifier)
      local state = internal("crossref")
      assert(state.index and state.index.entries,
        "crossref-query requires a post-quarto or later filter")
      return state.index.entries[identifier]
    end,
    ref_type = internal("refType"),
    number = internal("refNumberOption"),
    subnumber = internal("subrefNumber"),
  }
end
