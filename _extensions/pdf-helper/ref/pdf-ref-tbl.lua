-- Verify table references after the Markdown and HTML table converters run.
-- A tbl- prefix alone does not guarantee that a LaTeX label survived conversion.
if FORMAT ~= "pdf" and FORMAT ~= "latex" then
  return {}
end

local float_labels = {}
return {
  {
    FloatRefTarget = function(float)
      if float.type == "Table" and float.identifier ~= "" then
        float_labels[float.identifier] = true
      end
    end,
  },
  {
    Pandoc = function(doc)
      local labels, refs = {}, {}
      for label in pairs(float_labels) do labels[label] = true end
      local function inspect(raw)
        if raw.format ~= "tex" and raw.format ~= "latex" then return end
        for label in raw.text:gmatch("\\label%s*{([^}]+)}") do
          labels[label] = true
        end
        for ref in raw.text:gmatch("\\ref%s*{(tbl%-[^}]+)}") do
          refs[ref] = true
        end
      end
      doc:walk({
        RawInline = inspect,
        RawBlock = inspect,
        Table = function(tbl)
          if tbl.identifier ~= "" then labels[tbl.identifier] = true end
        end,
        Link = function(link)
          if link.attributes["reference-type"] == "ref" then
            local ref = link.attributes["reference"]
            if ref and ref:match("^tbl%-") then refs[ref] = true end
          end
        end,
      })
      local missing = {}
      for ref in pairs(refs) do
        if not labels[ref] then missing[#missing + 1] = ref end
      end
      table.sort(missing)
      for _, ref in ipairs(missing) do
        io.stderr:write("[pdf-ref-tbl] WARNING: missing table label: " .. ref .. "\n")
      end
      return doc
    end,
  },
}
