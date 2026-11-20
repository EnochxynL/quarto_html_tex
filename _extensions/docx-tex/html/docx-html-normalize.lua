-- Normalize lwarp's HTML for the DOCX writer, using the TeX distribution's own
-- LuaXML (luaxml): HTML parsing and CSS selector matching come from there, so
-- the plugin needs nothing beyond what a TeX installation already provides.
--
-- Two layers are ours:
--   * a repair pass that balances tags, because lwarp emits markup that relies
--     on the browser's HTML5 error recovery;
--   * the CSS cascade (specificity, order, importance, inheritance) applied to
--     the five document rules.
local M = {}

local dom, void

local function load_dom()
  if dom then return dom end
  local located = pandoc.pipe('kpsewhich', {'luaxml-domobject.lua'}, '')
  located = located:gsub('%s+$', '')
  assert(located ~= '', 'docx-tex: luaxml-domobject.lua not found (install the luaxml TeX package)')
  local directory = located:match('^(.*)[/\\]')
  package.path = directory .. '/?.lua;' .. package.path
  kpse = {}                                  -- luaxml picks TeX-flavoured modules
  dom = require('luaxml-domobject')
  void = { area = true, base = true, br = true, col = true, hr = true, img = true,
           input = true, link = true, meta = true, param = true, source = true,
           track = true, wbr = true }
  return dom
end

-- A start tag that implicitly closes an open element of the same family: HTML5
-- closes the previous cell, row, or list item before opening the next one.
local implies_close = {
  td = { td = true, th = true },
  th = { td = true, th = true },
  tr = { td = true, th = true, tr = true },
  tbody = { td = true, th = true, tr = true },
  thead = { td = true, th = true, tr = true },
  tfoot = { td = true, th = true, tr = true },
  li = { li = true },
  dt = { dt = true, dd = true },
  dd = { dt = true, dd = true },
  option = { option = true },
}
local block_start = {
  div = true, p = true, table = true, ul = true, ol = true, dl = true, li = true,
  section = true, figure = true, blockquote = true, pre = true, form = true,
  h1 = true, h2 = true, h3 = true, h4 = true, h5 = true, h6 = true, hr = true,
}
local formatting = {
  em = true, b = true, i = true, strong = true, code = true, tt = true,
  u = true, s = true, sub = true, sup = true,
}

-- Balance the markup: an end tag closes everything opened inside it, unmatched
-- end tags are dropped, open elements are closed at the end.
local function repair(html)
  local out, stack = {}, {}
  local position, length = 1, #html
  local function name_of(tag) return (tag:match('^</?%s*([%w:_-]+)') or ''):lower() end
  while position <= length do
    local start = html:find('<', position, true)
    if not start then out[#out + 1] = html:sub(position); break end
    if start > position then out[#out + 1] = html:sub(position, start - 1) end
    local stop = html:find('>', start, true)
    if not stop then out[#out + 1] = html:sub(start); break end
    local tag = html:sub(start, stop)
    position = stop + 1
    local name = name_of(tag)
    if name == '' then
      out[#out + 1] = tag
    elseif tag:sub(2, 2) == '/' then
      local found
      for index = #stack, 1, -1 do
        if stack[index] == name then found = index break end
      end
      if found then
        -- HTML5's adoption agency: formatting elements interrupted by an
        -- ancestor's end tag are closed there and reopened after it.
        local reopened = {}
        while #stack > found do
          local top = table.remove(stack)
          out[#out + 1] = '</' .. top .. '>'
          if formatting[top] then reopened[#reopened + 1] = top end
        end
        out[#out + 1] = tag
        table.remove(stack)
        for index = #reopened, 1, -1 do
          out[#out + 1] = '<' .. reopened[index] .. '>'
          stack[#stack + 1] = reopened[index]
        end
      end
    elseif void[name] or tag:find('/%s*>$') then
      out[#out + 1] = tag
    else
      local closes = implies_close[name]
      if closes then
        while #stack > 0 and closes[stack[#stack]] do
          out[#out + 1] = '</' .. table.remove(stack) .. '>'
        end
      elseif block_start[name] and stack[#stack] == 'p' then
        out[#out + 1] = '</p>'
        table.remove(stack)
      end
      -- HTML5 reconstructs formatting elements inside a new block: close them
      -- before the block, then reopen them as its first children.
      local reopen = {}
      if block_start[name] then
        while #stack > 0 and formatting[stack[#stack]] do
          local top = table.remove(stack)
          out[#out + 1] = '</' .. top .. '>'
          reopen[#reopen + 1] = top
        end
      end
      out[#out + 1] = tag
      stack[#stack + 1] = name
      for index = #reopen, 1, -1 do
        out[#out + 1] = '<' .. reopen[index] .. '>'
        stack[#stack + 1] = reopen[index]
      end
    end
  end
  while #stack > 0 do out[#out + 1] = '</' .. table.remove(stack) .. '>' end
  return table.concat(out)
end

local function parse_declarations(text)
  local declarations = {}
  for chunk in ((text or '') .. ';'):gmatch('([^;]*);') do
    local key, value = chunk:match('^%s*([%w%-]+)%s*:%s*(.-)%s*$')
    if key then
      local important = false
      local stripped = value:gsub('%s*!%s*important%s*$', '')
      if stripped ~= value then important = true end
      declarations[key:lower()] = { value = stripped, important = important }
    end
  end
  return declarations
end

-- Top-level qualified rules only; at-rules are skipped whole, as the previous
-- Python pass did.
local function parse_rules(css)
  local rules = {}
  local index, length = 1, #css
  local function skip_block(open)
    local depth, position = 0, open
    while position <= length do
      local char = css:sub(position, position)
      if char == '{' then depth = depth + 1
      elseif char == '}' then depth = depth - 1; if depth == 0 then return position end end
      position = position + 1
    end
    return length
  end
  while index <= length do
    local start = css:find('[^%s]', index)
    if not start then break end
    if css:sub(start, start + 1) == '/*' then
      local stop = css:find('*/', start + 2, true)
      index = stop and stop + 2 or length + 1
    elseif css:sub(start, start) == '@' then
      local brace = css:find('{', start, true)
      local semicolon = css:find(';', start, true)
      if not brace or (semicolon and semicolon < brace) then
        index = (semicolon or length) + 1
      else
        index = skip_block(brace) + 1
      end
    else
      local brace = css:find('{', start, true)
      if not brace then break end
      local selector = css:sub(start, brace - 1)
      local close = skip_block(brace)
      local declarations = parse_declarations(css:sub(brace + 1, close - 1))
      for one in selector:gmatch('[^,]+') do
        one = one:gsub('^%s+', ''):gsub('%s+$', '')
        if one ~= '' then rules[#rules + 1] = { selector = one, declarations = declarations } end
      end
      index = close + 1
    end
  end
  return rules
end

local function specificity(selector)
  local ids, classes, types = 0, 0, 0
  local index, length = 1, #selector
  local function skip(position)
    while position <= length and selector:sub(position, position):match('[%w%-_]') do position = position + 1 end
    return position
  end
  while index <= length do
    local char = selector:sub(index, index)
    if char == '#' then ids = ids + 1; index = skip(index + 1)
    elseif char == '.' then classes = classes + 1; index = skip(index + 1)
    elseif char == '[' then
      classes = classes + 1
      local close = selector:find(']', index, true)
      index = (close or length) + 1
    elseif char == ':' then
      if selector:sub(index + 1, index + 1) == ':' then
        types = types + 1
        index = skip(index + 2)
      else
        classes = classes + 1
        index = skip(index + 1)
      end
    elseif char:match('%a') then
      local previous = selector:sub(index - 1, index - 1)
      if previous == '' or previous:match('[%s>+~]') then types = types + 1 end
      index = skip(index)
    else
      index = index + 1
    end
  end
  return ids * 1000000 + classes * 1000 + types
end

local function has_class(node, name)
  local classes = node:get_attribute('class')
  if not classes then return false end
  for token in classes:gmatch('%S+') do if token == name then return true end end
  return false
end

local function remove_node(node)
  local parent = node:get_parent()
  if not parent or not parent._children then return false end
  for index, child in ipairs(parent._children) do
    if child == node then table.remove(parent._children, index); return true end
  end
  return false
end

local function insert_before(reference, node)
  local parent = reference:get_parent()
  if not parent or not parent._children then return false end
  for index, child in ipairs(parent._children) do
    if child == reference then
      table.insert(parent._children, index, node)
      node._parent = parent
      return true
    end
  end
  return false
end

local function computed_values(document, rules)
  local matched = {}
  for order, rule in ipairs(rules) do
    local ok, nodes = pcall(function() return document:query_selector(rule.selector) end)
    if ok and nodes then
      local weight = specificity(rule.selector)
      for _, node in ipairs(nodes) do
        local list = matched[node]
        if not list then list = {}; matched[node] = list end
        for key, declaration in pairs(rule.declarations) do
          list[#list + 1] = { important = declaration.important and 1 or 0,
                              weight = weight, order = order, key = key, value = declaration.value }
        end
      end
    end
  end
  local computed = {}
  document:traverse_elements(function(node)
    local values = {}
    local parent = node:get_parent()
    local inherited = parent and computed[parent]
    if inherited then
      values['list-style-type'] = inherited['list-style-type']
      values.visibility = inherited.visibility
    end
    local candidates = {}
    for _, candidate in ipairs(matched[node] or {}) do candidates[#candidates + 1] = candidate end
    for key, declaration in pairs(parse_declarations(node:get_attribute('style'))) do
      candidates[#candidates + 1] = { important = declaration.important and 1 or 0,
                                      weight = 1000000000000, order = 0, key = key, value = declaration.value }
    end
    table.sort(candidates, function(a, b)
      if a.important ~= b.important then return a.important < b.important end
      if a.weight ~= b.weight then return a.weight < b.weight end
      if a.order ~= b.order then return a.order < b.order end
      return a.key < b.key
    end)
    for _, candidate in ipairs(candidates) do values[candidate.key] = candidate.value end
    computed[node] = values
  end)
  return computed
end

local table_names = { table = true, tbody = true, thead = true, tfoot = true,
                      tr = true, td = true, th = true, caption = true, colgroup = true, col = true }

-- Move content that may not live inside a table in front of that table: this is
-- the HTML5 foster-parenting rule, without which Pandoc drops the whole table.
local function foster_parent(document)
  for _, table_node in ipairs(document:query_selector('table') or {}) do
    local parent = table_node:get_parent()
    if parent and parent._children then
      local table_index
      for index, child in ipairs(parent._children) do
        if child == table_node then table_index = index break end
      end
      if table_index then
        local pending = {}
        local function collect(node)
          for _, child in ipairs(node._children or {}) do
            local element = type(child.is_element) == 'function' and child:is_element()
            local text = type(child.is_text) == 'function' and child:is_text()
            if text and (child._text or ''):match('%S') then
              pending[#pending + 1] = child
            elseif element then
              local name = child:get_element_name()
              -- Content inside a cell or caption is legal; only table structure
              -- containers are inspected further.
              if name == 'table' or name == 'tbody' or name == 'thead'
                or name == 'tfoot' or name == 'tr' then
                collect(child)
              elseif not table_names[name] then
                pending[#pending + 1] = child
              end
            end
          end
        end
        collect(table_node)
        for _, node in ipairs(pending) do
          remove_node(node)
          local fresh
          for index, child in ipairs(parent._children) do
            if child == table_node then fresh = index break end
          end
          if fresh then table.insert(parent._children, fresh, node); node._parent = parent end
        end
      end
    end
  end
end

local function normalize_one(html)
  local document = load_dom().parse(repair(html))

  local rules = {}
  for _, style in ipairs(document:query_selector('style') or {}) do
    for _, rule in ipairs(parse_rules(style:get_text() or '')) do rules[#rules + 1] = rule end
  end
  local computed = computed_values(document, rules)

  foster_parent(document)

  local removals = {}
  document:traverse_elements(function(node)
    local values = computed[node] or {}
    local name = node:get_element_name()
    if node:get_attribute('hidden') ~= nil or node:get_attribute('aria-hidden') == 'true'
      or values.display == 'none' or values.visibility == 'hidden' then
      removals[#removals + 1] = node
    elseif name == 'figure' then
      node._name = 'div'
    elseif name == 'figcaption' or has_class(node, 'figurecaption') then
      node._name = 'div'
      node:set_attribute('custom-style', 'Caption')
    elseif (name == 'ul' or name == 'ol') and values['list-style-type'] == 'none' then
      node._name = 'div'
      for _, child in ipairs(node:get_children() or {}) do
        if type(child.is_element) == 'function' and child:is_element()
          and child:get_element_name() == 'li' then
          child._name = 'div'
        end
      end
    elseif name == 'span' and values.display == 'inline-block' then
      local size, unit = (values.width or ''):match('^([0-9%.]+)(%a+)$')
      if size and (unit == 'pt' or unit == 'px' or unit == 'em') then
        local text = node:get_text() or ''
        if text:match('%S') == nil then
          local points = tonumber(size) * ({ pt = 1, px = 0.75, em = 12 })[unit]
          for _, child in ipairs(node:get_children() or {}) do remove_node(child) end
          local filler = document:create_text_node(string.rep('\226\128\130', math.floor(points / 6 + 0.5)))
          node:add_child_node(filler)
        end
      end
    end
  end)
  for _, node in ipairs(removals) do remove_node(node) end

  local body = (document:query_selector('body') or {})[1]
  return (body or document):serialize()
end

function M.run(fragments)
  local results = {}
  for index, html in ipairs(fragments) do
    local ok, normalized = pcall(normalize_one, html)
    if not ok then error('docx-html-normalize: fragment ' .. index .. ': ' .. tostring(normalized)) end
    results[index] = normalized
  end
  return results
end

return M
