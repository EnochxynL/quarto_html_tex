-- html-md-tables.lua — HTML 方案：管道表 / {=html} 表 → RawBlock("html")
--
-- 从 tables-to-tablestar.lua 拆出的 HTML 半边（PDF 半边见 pdf-md-tables.lua）。
--
-- 方案（为什么管道表在 HTML 端要转 RawBlock）：
--   quarto 的 Table 处理（main.lua）会：
--     1) 清空非 tbl- 前缀的 attr.identifier（我们架构用 tab-，会被清）
--     2) 把 caption 的 {#id} 写回 caption 文本（残留字面）
--   管道表 → RawBlock("html") 后完全绕过 quarto 的 Table 处理，
--   表格编号/引用链接由 crossref-html.lua 统一负责（文档顺序自数）。
--   {=html} 直写表会被 quarto 解析为 Div(quarto-scaffold){Div{Table}+Div{Plain(caption)}}，
--   这里提取 Table + caption 独立收集、整体替换整个 Div（只替换内部 Table
--   会被 quarto writer 重组：丢 [htbp]、注入重复 label）。
--
-- 注意（踩坑记录）：
--   pandoc.meta 在 filter 模块顶层和元素回调内都是 nil/空表；只有 Pandoc(doc)
--   回调的 doc.meta 才含完整 metadata。pandoc.walk_block 在本 pandoc 版本不可靠
--   （函数 filter 报错、表 filter 静默不调用），故手写递归。
if FORMAT ~= "html" and FORMAT ~= "html5" then
  return {}
end

-- 从 blocks 树中提取 {table, caption_inlines}；Table 和 caption 独立收集。
-- quarto 把 {=html} 的 <table> 解析为 Div(quarto-scaffold) { Div{Table} + Div{Plain(caption)} }，
-- Table.caption 为空、<caption> 文本被拆到独立的 Plain 块里。
-- 注意：不能以"找到 Table"作为返回条件——含 caption 的子树可能没有 Table，会被丢弃。
local function extract_table_and_caption(blocks)
  local tbl, cap = nil, nil
  for _, b in ipairs(blocks) do
    if b.t == "Table" and not tbl then
      tbl = b
    elseif b.t == "Div" then
      local r = extract_table_and_caption(b.content)
      if r then
        if not tbl and r.table then tbl = r.table end
        if not cap and r.caption then cap = r.caption end
      end
    elseif b.t == "Plain" and not cap then
      cap = b.content
    end
  end
  if tbl or cap then return { table = tbl, caption = cap } end
  return nil
end

-- 手写递归遍历（pandoc.walk_block 在本 pandoc 版本行为不可靠）
local function process_blocks(blocks, f)
  local out = {}
  for _, b in ipairs(blocks) do
    local r = f(b)
    if r ~= nil then
      out[#out + 1] = r
    elseif b.t == "Div" or b.t == "BlockQuote" or b.t == "Figure" then
      b.content = process_blocks(b.content, f)
      out[#out + 1] = b
    else
      out[#out + 1] = b
    end
  end
  return out
end

function Pandoc(doc)
  local function transform(b)
    if b.t == "Table" then
      -- HTML：转 RawBlock("html")，绕过 quarto 的 Table 处理（清空 id + caption 残留 {#id}）
      local html = pandoc.write(pandoc.Pandoc({ b }), "html")
      html = html:gsub("^%s*<p>", ""):gsub("</p>%s*$", "")
      -- quarto reader 不消费 caption 的 {#id}（残留文本）：提取为 <table id> 并移除残留
      local cap_id = html:match("<caption>.-{#([^}]+)}")
      if cap_id and not html:match('<table[^>]*id="') then
        html = html:gsub("%s*{#([^}]+)}", "", 1)
        html = html:gsub("<table", '<table id="' .. cap_id .. '"', 1)
      end
      html = html:gsub("<table", '<table class="paper-table"', 1)
      return pandoc.RawBlock("html", html)
    elseif b.t == "Div" then
      -- quarto 把 {=html} 表格包在 Div(quarto-scaffold) 里：整体替换，避免 quarto writer 输出浮动体时重组
      local found = extract_table_and_caption(b.content)
      if found and found.table then
        local tbl = found.table
        local has_cap = tbl.caption and tbl.caption.long and #tbl.caption.long > 0
        if not has_cap and found.caption then
          tbl.caption = pandoc.Caption(pandoc.Inlines(found.caption))
        end
        local html = pandoc.write(pandoc.Pandoc({ tbl }), "html")
        html = html:gsub("^%s*<p>", ""):gsub("</p>%s*$", "")
        html = html:gsub("<table", '<table class="paper-table"', 1)
        return pandoc.RawBlock("html", html)
      end
    elseif b.t == "RawBlock" and b.format == "html" and b.text:match("%<table") then
      -- HTML 端：{=html} 原样输出（保持 RawBlock）
      return nil
    end
    return nil
  end

  doc.blocks = pandoc.List(process_blocks(doc.blocks, transform))
  return doc
end
