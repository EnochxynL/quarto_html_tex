-- HTML semantics -> native Pandoc nodes -> DOCX. No LaTeX table parser.
local M = {}
function M.convert(doc, directory)
  local definitions = {}
  doc:walk({RawBlock=function(node)
    if node.format ~= 'html' then return end
    local json = node.text:match('window.MathJax = {tex: {macros: ({.-})}};')
    if json then
      local config = pandoc.json.decode(json)
      for name, value in pairs(assert(config, 'Invalid lwarp MathJax macros')) do
        definitions[#definitions+1] = '\\newcommand{\\' .. name .. '}[' .. string.format('%d',value[2]) .. ']{' .. value[1] .. '}'
      end
    end
  end})
  local prefix = table.concat(definitions,'\n')
  local debug = io.open('.quarto/docx-tex/macros.tex','w')
  if debug then debug:write(prefix); debug:close() end
  local fragments={}
  doc:walk({RawBlock=function(node)
    if node.format=='html' then fragments[#fragments+1]=node.text end
  end,RawInline=function(node)
    if node.format=='html' then fragments[#fragments+1]=node.text end
  end})
  local normalized={}
  if #fragments>0 then
    local result=pandoc.pipe('uv',{'run','--locked','--script',directory..'/latex/normalize-html.py'},
      pandoc.json.encode(fragments))
    local values=assert(pandoc.json.decode(result),'HTML normalization did not return JSON')
    for i,html in ipairs(fragments) do normalized[html]=values[i] end
  end
  local function read(html)
    return pandoc.read(assert(normalized[html]),'html+tex_math_single_backslash').blocks
  end
  doc = doc:walk({
    RawBlock=function(node)
      if node.format == 'html' then return read(node.text) end
    end,
    RawInline=function(node)
      if node.format ~= 'html' then return end
      local result = pandoc.Inlines({})
      for _, block in ipairs(read(node.text)) do
        if block.content then result:extend(block.content) end
      end
      return result
    end,
  })
  doc = doc:walk({
    Span=function(span)
      -- Keep citation slots until Pandoc's final citeproc pass. Removing them
      -- early would renumber parent citations and omit block-only references.
      if span.attributes['aria-hidden']=='true' or span.attributes.style=='display:none' then
        span.attributes['custom-style']='Docx Hidden'
        return span
      end
    end,
    Math=function(math)
      if #prefix > 0 then
        local parsed = pandoc.read(prefix .. '\n\n\\[' .. math.text .. '\\]', 'latex')
        parsed:walk({Math=function(expanded) math.text=expanded.text end})
      end
      return math
    end,
    Table=function(tbl)
      for i, col in ipairs(tbl.colspecs) do tbl.colspecs[i] = {col[1],1/#tbl.colspecs} end
      return tbl
    end,
  })
  return doc
end
return M
