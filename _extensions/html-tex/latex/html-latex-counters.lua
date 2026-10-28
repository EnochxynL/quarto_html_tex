-- Supply document counter context to independently compiled lwarp blocks.
-- Raw LaTeX tables and other environments share this pass. Table* uses the
-- table counter; captions advance it, and native tables occupy a number.
-- Nested Divs, block quotes, figures and list items are visited in source order.
--
-- This is a context bridge, not a complete TeX interpreter: arbitrary counter
-- resets, optional/unnumbered captions and mixed counter families inside one
-- block are not modeled. Blocks must declare shared custom counters in metadata.
-- Output: html-tex-lwarp-counters.blocks (counter/start) and .refs (label/number).
if FORMAT ~= "html" and FORMAT ~= "html5" then
  return {}
end

-- Count captions in table blocks, rather than nested tabular panels.
local function is_table_block(text)
  return text:find("\\begin{tabular", 1, true) ~= nil
      or text:find("\\begin{table", 1, true) ~= nil
end

-- 提取块内全部 label
local function extract_labels(text)
  local labels = {}
  for lab in text:gmatch("\\label{([^}]+)}") do
    labels[#labels + 1] = lab
  end
  return labels
end

-- Read ordered file/text entries; bare strings are filenames.
local function header_text(v)
  local typ = pandoc.utils.type(v)
  if typ == "Blocks" or typ == "MetaBlocks" then
    local parts = {}
    for _, b in ipairs(v) do
      parts[#parts + 1] = b.t == "RawBlock" and b.text or pandoc.utils.stringify(b)
    end
    return table.concat(parts, "\n")
  end
  return pandoc.utils.stringify(v)
end
local function read_header(meta)
  local config, parts = meta["html-tex"] or {}, {}
  local function append(v)
    local typ = pandoc.utils.type(v)
    if typ == "List" or typ == "MetaList" then
      for _, item in ipairs(v) do append(item) end
    elseif type(v) == "table" and (v.file ~= nil or v.text ~= nil) then
      if v.file ~= nil and v.text == nil then append(v.file)
      elseif v.text ~= nil and v.file == nil then parts[#parts + 1] = header_text(v.text)
      else assert(false, "html-tex.include-in-header: specify exactly one of file or text") end
    else
      local file, message = io.open(header_text(v), "rb")
      assert(file, "html-tex.include-in-header: " .. tostring(message))
      parts[#parts + 1] = file:read("*a")
      file:close()
    end
  end
  if config["include-in-header"] ~= nil then append(config["include-in-header"]) end
  return table.concat(parts, "\n")
end


-- 与 X 同名，惯例即可覆盖；regs 仅作语义记录）
local function collect_registrations(src, shared_of)
  for name, shared in src:gmatch("\\newtheorem{([^}]+)}%[([^%]]+)%]") do
    shared_of[name] = shared
  end
  -- \newtheorem{NAME} 的普通 gmatch 会匹配到共享形式的前半（NAME）——
  -- shared_of 已记录则跳过
  for name in src:gmatch("\\newtheorem{([^}]+)}") do
    if not shared_of[name] then shared_of[name] = name end
  end
  for name in src:gmatch("\\newfloat{([^}]+)}") do
    shared_of[name] = name
  end
  for name in src:gmatch("\\newcounter{([^}]+)}") do
    shared_of[name] = name
  end
end

return {
  {
    Pandoc = function(doc)
      local macros = read_header(doc.meta)
      local shared_of = {}
      collect_registrations(macros, shared_of)

      -- 第一遍收集所有 tex 非表格块（块内注册也进 shared_of——本块自洽）
      local tex_blocks = {}
      local function collect(blocks)
        for _, blk in ipairs(blocks) do
          if blk.t == "RawBlock" and (blk.format == "tex" or blk.format == "latex") then
            tex_blocks[#tex_blocks + 1] = blk.text
            collect_registrations(blk.text, shared_of)
          elseif blk.t == "Table" then
            tex_blocks[#tex_blocks + 1] = false -- native table occupies a number
          elseif blk.t == "Div" or blk.t == "BlockQuote" or blk.t == "Figure" then
            collect(blk.content)
          elseif blk.t == "BulletList" or blk.t == "OrderedList" then
            for _, item in ipairs(blk.content) do collect(item) end
          end
        end
      end
      collect(doc.blocks)

      -- 第二遍：每块主环境 → 计数器 → 分组计数
      -- 只对有 \begin{ENV} 的块发条目（无环境=PDF 控制片段——与 lwarp
      -- 的 is_compile_candidate 分派一致，保证 blocks 索引对齐）
      local counts = {}  -- 计数器名 → 已出现次数（下一个块的 start）
      local blocks = {}
      local refs = {}
      for _, text in ipairs(tex_blocks) do
        if text == false then
          counts.table = (counts.table or 0) + 1
        else
          local env = text:match("\\begin{([^}]+)}")
          if env then
            -- 共享注册优先（\newtheorem{X}[Y]——惯例猜不到）；否则环境名
            --（float 惯例 / 同名注册）
            local counter = shared_of[env] or env:gsub("%*$", "")
            local info = { counter = counter, start = counts[counter] or 0 }
            counts[counter] = (counts[counter] or 0) + 1
            -- 块内 label → 全文编号（start+1——注入后块内步进捕获）
            for _, lab in ipairs(extract_labels(text)) do
              refs[lab] = tostring(info.start + 1)
            end
            if is_table_block(text) then
              -- A source block may contain several table captions, or several
              -- tabular panels sharing one caption. Count captions, not panels.
              local captions = 0
              -- A short caption changes only the list-of-tables entry, not the
              -- counter advance. Normalize its optional argument in this scan;
              -- leave the actual LaTeX source for lwarp unchanged.
              local numbered_text = text:gsub("\\caption%s*%b[]%s*(%b{})", "\\caption%1")
              for command, arg in numbered_text:gmatch("\\([%a]+)%s*(%b{})") do
                if command == "caption" then
                  captions = captions + 1
                elseif command == "label" then
                  refs[arg:sub(2, -2)] = tostring(info.start + math.max(1, captions))
                end
              end
              counts[counter] = info.start + captions
            end
            blocks[#blocks + 1] = pandoc.MetaMap({
              counter = pandoc.MetaString(info.counter),
              start = pandoc.MetaInlines({ pandoc.Str(tostring(info.start)) }),
            })
          end
        end
      end

      -- 写输出（独立顶层 key——不碰 html-tex 现有配置结构）
      local refs_map = pandoc.MetaMap({})
      for lab, num in pairs(refs) do
        refs_map[lab] = pandoc.MetaString(num)
      end
      doc.meta["html-tex-lwarp-counters"] = pandoc.MetaMap({
        blocks = pandoc.MetaList(blocks),
        refs = refs_map,
      })
      return doc
    end,
  },
}
