-- crossref-html.lua (v2) — HTML 表格统一编号 + 引用链接化
--
-- 背景：所有表格（复杂表 / 管道表 / {=html} 表）在 HTML 端都已是 RawBlock("html")
--（html-latex-tables.lua 与 html-md-tables.lua 转换），quarto 的 Table 处理被绕过，
-- 表格编号和 \ref 链接都需要本 filter 统一负责。
--
-- 职责：
--   1) 按文档顺序统计所有 <table id="..."> → 编号映射
--   2) 给 <caption> 加 "表 N：" 前缀（与 PDF 端 LaTeX 自动编号的文档顺序一致）
--   3) 正文 RawInline("tex") 的 \ref{X} / \S\ref{X}：
--        X 是表格 id → <a href="#X">表 N</a>（可点击）
--        其他（章节等）→ 保持 [§X] 占位符
--   4) RawBlock("html") 内部（caption 等）的 \S?\ref{X} 文本 → 同上
--
-- 注意：pandoc.walk_block / pandoc.walk_inline 在本 pandoc 版本均不可靠，
--       全部手写递归。
if FORMAT ~= "html" and FORMAT ~= "html5" then
  return {}
end

-- 引用替换：表格 → 表 N；章节 → §N（自数编号）；图 → [fig-X]（quarto 锚点存在但编号在 writer 阶段生成，filter 拿不到）；其他 → nil（调用方决定占位符）
local function ref_link(ref, tab_nums, sec_nums)
  if tab_nums[ref] then
    return '<a href="#' .. ref .. '">表 ' .. tab_nums[ref] .. "</a>"
  elseif sec_nums[ref] then
    return '<a href="#' .. ref .. '">§' .. sec_nums[ref] .. "</a>"
  elseif ref:match("^fig%-") then
    return '<a href="#' .. ref .. '">[' .. ref .. "]</a>"
  end
  return nil
end

function Pandoc(doc)
  -- 1) 统计编号：
  -- 表格编号：所有含表格的 RawBlock 按文档顺序编号（无 id 也占序号，保证与 PDF 端一致）
  local tab_nums = {}
  local tab_counter = 0
  local raw_tables = {}  -- { {rb=RawBlock, id=..., num=...}, ... }

  local function collect(blocks)
    for _, b in ipairs(blocks) do
      if b.t == "RawBlock" and b.format == "html" and b.text:match("%<table") then
        tab_counter = tab_counter + 1
        local id = b.text:match('id="([^"]+)"')
        raw_tables[#raw_tables + 1] = { rb = b, id = id, num = tab_counter }
        if id then tab_nums[id] = tab_counter end
      elseif b.t == "Div" then
        collect(b.content)
      end
    end
  end
  collect(doc.blocks)

  -- 章节编号：遍历 Header（含 Div 嵌套），按层级自数（1.1.1 格式，与 PDF 端 Pandoc number-sections 一致）
  local sec_nums = {}
  local sec_counters = { 0, 0, 0, 0, 0, 0 }
  local function scan_headers(blocks)
    for _, b in ipairs(blocks) do
      if b.t == "Header" then
        local lvl = b.level or 1
        sec_counters[lvl] = sec_counters[lvl] + 1
        for i = lvl + 1, 6 do sec_counters[i] = 0 end
        local parts = {}
        for i = 1, lvl do parts[i] = sec_counters[i] end
        local id = b.attr and b.attr.identifier or ""
        if id ~= "" then
          sec_nums[id] = table.concat(parts, ".")
        end
      elseif b.t == "Div" then
        scan_headers(b.content)
      end
    end
  end
  scan_headers(doc.blocks)

  -- 2) + 4) 表格 RawBlock：替换内部引用 + caption 加编号前缀
  -- 注意 Lua pattern：`\\S?\\ref` 需要两个反斜杠，`\ref`（单反斜杠）不匹配——必须分两个 pattern，先长后短
  local function replace_in_text(text)
    -- 先处理 pandoc LaTeX reader 生成的 Link 形态：\ref{X} 在 latex reader 里是
    -- Link(attrs: reference-type=ref, reference=X, 文本 "[X]")，latex-tables.lua
    -- write 成 html 后形如 <a href="#X" data-reference-type="ref" ...>[X]</a>。
    -- \S\ref{X} 的 \S 已被 reader 转成 § 字符（Str）留在文本里，此时去掉 ref_link
    -- 返回的 § 前缀避免重复。
    -- 注意：不能写成 (§?)<a ... —— Lua pattern 里 §? 的多字节可选匹配空分支会失败。
    text = text:gsub("§<a%s+href=\"#([^\"]+)\"[^>]*>%[([^%]]+)%]</a>", function(ref, label)
      local link = ref_link(ref, tab_nums, sec_nums)
      if link then return link:gsub("^§", "") end
      return "§[" .. label .. "]"
    end)
    text = text:gsub("<a%s+href=\"#([^\"]+)\"[^>]*>%[([^%]]+)%]</a>", function(ref, label)
      local link = ref_link(ref, tab_nums, sec_nums)
      if link then return link end
      return "[" .. label .. "]"
    end)
    text = text:gsub("\\S\\ref{([^}]+)}", function(ref)
      local link = ref_link(ref, tab_nums, sec_nums)
      if link then return link end
      return "[§" .. ref .. "]"
    end)
    text = text:gsub("\\ref{([^}]+)}", function(ref)
      local link = ref_link(ref, tab_nums, sec_nums)
      if link then return link end
      return "[§" .. ref .. "]"
    end)
    return text
  end

  for _, t in ipairs(raw_tables) do
    t.rb.text = replace_in_text(t.rb.text)
    t.rb.text = t.rb.text:gsub("(<caption>)([^<]*)", function(open, cap)
      if cap:match("^表 %d+[:：]") then return open .. cap end
      return open .. "表 " .. t.num .. "：" .. cap
    end, 1)
  end

  -- 3) 正文 inline 替换（手写递归）
  local function walk_inlines(inlines)
    local out = pandoc.List({})
    for _, inl in ipairs(inlines) do
      if inl.t == "RawInline" and inl.format == "tex" then
        -- 注意：`\S\ref{X}` 会被解析成两个 RawInline（\S 和 \ref{X}），且 `\\S?\\ref` pattern 需要两个反斜杠
        local ref = inl.text:match("^\\ref{([^}]+)}$")
        if not ref then
          ref = inl.text:match("^\\S\\ref{([^}]+)}$")
        end
        if ref then
          local link = ref_link(ref, tab_nums, sec_nums)
          if link then
            out:insert(pandoc.RawInline("html", link))
          else
            out:insert(pandoc.Str("[§" .. ref .. "]"))
          end
        else
          out:insert(inl)
        end
      else
        -- 递归进入 inline 容器（Strong/Emph/Span/Link/Quoted/Cite 等）
        if inl.content and (inl.t == "Strong" or inl.t == "Emph" or inl.t == "Span"
          or inl.t == "Link" or inl.t == "Quoted" or inl.t == "Cite") then
          inl.content = walk_inlines(inl.content)
        end
        out:insert(inl)
      end
    end
    return out
  end

  local function walk_blocks(blocks)
    local out = {}
    for _, b in ipairs(blocks) do
      if b.t == "Para" or b.t == "Plain" or b.t == "Header" then
        b.content = walk_inlines(b.content)
      elseif b.t == "Div" or b.t == "BlockQuote" then
        b.content = walk_blocks(b.content)
      elseif b.t == "Figure" then
        b.content = walk_blocks(b.content)
      elseif b.t == "BulletList" or b.t == "OrderedList" then
        for i, item in ipairs(b.content) do
          b.content[i] = walk_blocks(item)
        end
      elseif b.t == "DefinitionList" then
        for _, item in ipairs(b.content) do
          -- item = {term (Inlines), defs (List of Blocks)}
          item[1] = walk_inlines(item[1])
          for j, def in ipairs(item[2]) do
            item[2][j] = walk_blocks(def)
          end
        end
      elseif b.t == "Table" then
        -- 防御：HTML 端理论上没有原生 Table（tables-to-tablestar.lua 已转 RawBlock）
        local function walk_cells(rows)
          for _, row in ipairs(rows or {}) do
            for _, c in ipairs(row.cells) do
              c.content = walk_inlines(c.content)
            end
          end
        end
        if b.head then walk_cells(b.head.rows) end
        for _, bd in ipairs(b.bodies) do walk_cells(bd.body) end
        walk_cells(b.foot and b.foot.rows)
      end
      out[#out + 1] = b
    end
    return out
  end

  doc.blocks = pandoc.List(walk_blocks(doc.blocks))
  return doc
end
