-- Resolve LaTeX references in HTML after Quarto has indexed native targets.
-- Query every identifier, regardless of its category/prefix. Unindexed lwarp
-- targets use the counter bridge's existing label map; this filter never counts.
if not quarto.format.is_html_output() then return {} end

local directory = PANDOC_SCRIPT_FILE:match("^(.*[/\\])") or ""
local query = dofile(directory .. "../../crossref-query/crossref-query.lua")

function Pandoc(doc)
  local counters = doc.meta["html-helper-lwarp-counters"] or {}
  local lwarp_refs = counters.refs or {}
  local missing = {}

  local function resolve(identifier)
    local ref = query.lookup(identifier)
    -- A known but deferred target must not fall through to another counter.
    if ref then return ref end
    if lwarp_refs[identifier] then
      return {
        target = "#" .. identifier:gsub(":", "-"),
        number = pandoc.Inlines({pandoc.Str(pandoc.utils.stringify(lwarp_refs[identifier]))}),
      }
    end
    missing[identifier] = true
  end

  local function number_inlines(ref, command)
    local number = ref.number:clone()
    if command == "eqref" then
      number:insert(1, pandoc.Str("("))
      number:insert(pandoc.Str(")"))
    end
    return number
  end

  local function link(identifier, command)
    local ref = resolve(identifier)
    if ref and not ref.number then return nil end
    if ref then
      return pandoc.Link(number_inlines(ref, command), ref.target)
    end
    return pandoc.Span({pandoc.Str("[" .. identifier .. "]")},
      pandoc.Attr("", {"unresolved-ref"}))
  end

  local function inline_reference(text)
    local prefix = ""
    local rest = text:match("^\\S%s*(.*)$")
    if rest then prefix, text = "§", rest end
    local command, identifier = text:match("^\\([%a]+)%s*{([^}]+)}%s*$")
    if command ~= "ref" and command ~= "eqref" then return nil end
    local result = link(identifier, command)
    if result == nil then return nil end
    if prefix ~= "" then return {pandoc.Str(prefix), result} end
    return result
  end

  local function latex_number(identifier, command)
    local ref = resolve(identifier)
    if not ref or not ref.number then return nil end
    return pandoc.write(pandoc.Pandoc({pandoc.Plain(number_inlines(ref, command))}),
      "latex"):gsub("%s+$", "")
  end

  local function replace_tex(text)
    return text:gsub("\\([%a]+)%s*{([^}]+)}", function(command, identifier)
      if command ~= "ref" and command ~= "eqref" then return nil end
      return latex_number(identifier, command)
    end)
  end

  local function html_inlines(inlines)
    return pandoc.write(pandoc.Pandoc({pandoc.Plain(inlines)}), "html")
      :gsub("%s+$", "")
  end

  local function replace_html(text)
    local literals = {}
    text = text:gsub("<!%-%-.-%-%->", function(comment)
      literals[#literals + 1] = comment
      return "@@HTMLREF-LITERAL:" .. #literals .. "@@"
    end)
    for _, tag in ipairs({"script", "style", "pre", "code", "textarea"}) do
      local pattern = tag:gsub("%a", function(letter)
        return "[" .. letter:lower() .. letter:upper() .. "]"
      end)
      text = text:gsub("<" .. pattern .. "%f[%s>][^>]*>.-</" .. pattern .. "%s*>", function(literal)
        literals[#literals + 1] = literal
        return "@@HTMLREF-LITERAL:" .. #literals .. "@@"
      end)
    end
    -- lwarp has already emitted the surrounding link/math markup. Replace only
    -- the placeholder's number, rather than introducing nested anchors.
    local function placeholder(identifier)
      identifier = identifier:gsub("%s+", "") -- pdftotext can wrap at hyphens.
      local ref = resolve(identifier)
      if ref and ref.number then return html_inlines(ref.number) end
      if ref then return nil end
      return "[" .. identifier .. "]"
    end
    text = text:gsub("@@REF:{([^@]+)}@@", placeholder)
    text = text:gsub("@@REF:([^@]+)@@", placeholder)
    -- MathJax consumes TeX inside these delimiters. Insert TeX numbers there,
    -- not HTML anchors, then protect the math from the HTML replacement pass.
    for _, delimiters in ipairs({{"(", ")"}, {"[", "]"}}) do
      text = text:gsub("\\%" .. delimiters[1] .. "(.-)\\%" .. delimiters[2], function(math)
        literals[#literals + 1] = "\\" .. delimiters[1] .. replace_tex(math) .. "\\" .. delimiters[2]
        return "@@HTMLREF-LITERAL:" .. #literals .. "@@"
      end)
    end
    -- Pandoc's LaTeX reader can serialize reference Links inside raw HTML.
    text = text:gsub('(<a%s+[^>]-href="#([^"]+)"[^>]*>)(%[[^%]]+%])(</a>)',
      function(open, identifier, original, close)
        local ref = resolve(identifier)
        if ref and ref.number then return open .. html_inlines(ref.number) .. close end
        return open .. original .. close
      end)
    text = text:gsub("\\S%s*\\ref%s*{([^}]+)}", function(identifier)
      local result = link(identifier, "ref")
      if result then return "§" .. html_inlines({result}) end
    end)
    text = text:gsub("\\([%a]+)%s*{([^}]+)}", function(command, identifier)
      if command ~= "ref" and command ~= "eqref" then return nil end
      local result = link(identifier, command)
      if result then return html_inlines({result}) end
    end)
    local function restore(index)
      local literal = literals[tonumber(index)]
      if literal then return literal:gsub("@@HTMLREF%-LITERAL:(%d+)@@", restore) end
    end
    return text:gsub("@@HTMLREF%-LITERAL:(%d+)@@", restore)
  end

  -- Native walking also visits captions, table cells, notes, lists and quotes.
  -- Native @references are already resolved; do not reinterpret ordinary Links.
  doc = doc:walk({
    Link = function(node)
      local command = node.attributes["reference-type"]
      local identifier = node.attributes.reference
      if identifier and (command == "ref" or command == "eqref") then
        return link(identifier, command)
      end
    end,
    Math = function(node)
      local result = inline_reference(node.text)
      if result then return result end
      node.text = replace_tex(node.text)
      return node
    end,
    RawInline = function(node)
      if node.format == "tex" or node.format == "latex" then
        if node.text == "\\S" then return pandoc.Str("§") end
        return inline_reference(node.text)
      elseif node.format == "html" then
        node.text = replace_html(node.text)
        return node
      end
    end,
    RawBlock = function(node)
      if node.format == "html" then
        node.text = replace_html(node.text)
        return node
      end
    end,
  })
  local identifiers = {}
  for identifier in pairs(missing) do identifiers[#identifiers + 1] = identifier end
  table.sort(identifiers)
  if #identifiers > 0 then
    io.stderr:write("[html-ref] unresolved targets: " .. table.concat(identifiers, ", ") .. "\n")
  end
  return doc
end
