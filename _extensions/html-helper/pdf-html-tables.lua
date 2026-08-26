-- pdf-html-tables.lua — PDF 方案：{=html} 直写表 → table（单栏）booktabs tabular
--
-- 从 pdf-md-tables.lua 拆出的 {=html} 半边：管道表（顶层 Table）由 pdf-md-tables.lua
-- 处理（md-table-env 配置，当前 table* 双栏通栏）；{=html} 直写表走本 filter，
-- 默认单栏 table（HTML 直写表多为内容简短的验证/示例表，双栏通栏过宽）。
--
-- quarto 把 {=html} 的 <table> 解析为 Div(__quarto_custom_scaffold) 包裹的原生
-- Table（HTML 半边见 html-md-tables.lua 注释），<caption> 文本被拆到独立的
-- Plain 块、Table.caption 为空——需提取 Table + caption 并整体替换整个 Div
-- （只替换内部 Table 会被 quarto writer 重组：丢位置参数、注入重复 label）。
-- CLI pandoc（非 quarto）环境下 {=html} 保持 RawBlock，走 pandoc.read("html") 兜底。
--
-- 配置（format 级别，如 pdf 下）：
--   format:
--     pdf:
--       html-helper:
--         html-table-env: table        # {=html} 表环境：table（单栏，默认）| table* | longtable
--         html-pos: htbp         # 浮动位置参数
--         table-caption-pos: bottom    # caption 位置（与 pdf-md-tables 共享）
--
-- 注意（踩坑记录）：见 pdf-md-tables.lua 头部（meta 读取、平铺提升、stringify）。
if FORMAT ~= "pdf" and FORMAT ~= "latex" then
  return {}
end

local function get_str(v, default)
  if v == nil then return default end
  if type(v) == "string" then return v end
  local s = pandoc.utils.stringify(v)
  if s == "" then return default end
  return s
end

-- 从 doc.meta 读取配置（嵌套优先、平铺回退，见 README 踩坑 13）
local function read_config(meta)
  local pt = meta["html-helper"] or meta["paper-tables"] or {}
  local pdf = pt["pdf"] or {}
  return {
    env = get_str(pdf["html-table-env"], get_str(pt["html-table-env"], "table")),
    pos = get_str(pdf["html-pos"], get_str(pt["html-pos"], "htbp")),
    cap_pos = get_str(pdf["table-caption-pos"], get_str(pt["table-caption-pos"], "top")),
  }
end

local ALIGN = { AlignLeft = "l", AlignRight = "r", AlignCenter = "c", AlignDefault = "l" }

local function render_cell(cell)
  local parts = {}
  for _, b in ipairs(cell.contents) do
    local s = pandoc.write(pandoc.Pandoc({ b }), "latex")
    s = s:gsub("%s*\n%s*", " ")
    parts[#parts + 1] = s
  end
  return table.concat(parts, " ")
end

local function render_row(row)
  local cells = {}
  for _, c in ipairs(row.cells) do
    cells[#cells + 1] = render_cell(c)
  end
  return table.concat(cells, " & ")
end

-- Table AST → LaTeX 字符串（table* / table / longtable + booktabs tabular）
local function table_to_latex(tbl, cfg)
  local TABLE_ENV, TABLE_POS, CAPTION_POS = cfg.env, cfg.pos, cfg.cap_pos
  local colspec = {}
  for _, cs in ipairs(tbl.colspecs) do
    local a = cs[1]
    colspec[#colspec + 1] = ALIGN[a] or "l"
  end
  local cstext = table.concat(colspec)

  local lines = { "\\toprule" }
  if tbl.head and tbl.head.rows then
    for _, r in ipairs(tbl.head.rows) do
      lines[#lines + 1] = render_row(r) .. " \\\\"
    end
    if #tbl.head.rows > 0 then
      lines[#lines + 1] = "\\midrule"
    end
  end
  for _, bd in ipairs(tbl.bodies) do
    for _, r in ipairs(bd.body) do
      lines[#lines + 1] = render_row(r) .. " \\\\"
    end
  end
  lines[#lines + 1] = "\\bottomrule"

  local id = (tbl.attr and tbl.attr.identifier) or tbl.identifier or ""
  local caption = ""
  if tbl.caption and tbl.caption.long and #tbl.caption.long > 0 then
    local s = pandoc.write(pandoc.Pandoc(tbl.caption.long), "latex")
    s = s:gsub("%s*\n%s*", " ")
    local cap_id = s:match("\\{\\#([^}]+)\\}")
    if cap_id then
      if id == "" then
        id = cap_id
      end
      s = s:gsub("\\{\\#[^}]+\\}", "")
    end
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    if s ~= "" then
      caption = "\\caption{" .. s .. "}"
    end
  end
  local label = ""
  if id ~= "" then
    label = "\\label{" .. id .. "}"
  end

  local head = "\\begin{" .. TABLE_ENV .. "}[" .. TABLE_POS .. "]\n\\centering\n"
  local body = "\\begin{tabular}{" .. cstext .. "}\n" .. table.concat(lines, "\n") .. "\n\\end{tabular}"
  local close = "\\end{" .. TABLE_ENV .. "}"

  if CAPTION_POS == "bottom" then
    local tail = body
    if caption ~= "" then tail = tail .. "\n" .. caption end
    if label ~= "" then tail = tail .. "\n" .. label end
    return head .. tail .. "\n" .. close
  else
    return head .. caption .. (caption ~= "" and "\n" or "")
      .. label .. (label ~= "" and "\n" or "")
      .. body .. "\n" .. close
  end
end

-- {=html} 直写表格 → Table AST（找不到返回 nil）
local function html_raw_to_table(text)
  local doc = pandoc.read(text, "html")
  local function find_table(blocks)
    for _, b in ipairs(blocks) do
      if b.t == "Table" then
        return b
      elseif b.t == "Div" then
        local t = find_table(b.content)
        if t then return t end
      end
    end
    return nil
  end
  return find_table(doc.blocks)
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

-- 手写递归遍历
local function process_blocks(blocks, cfg)
  local out = {}
  for _, b in ipairs(blocks) do
    if b.t == "Div" then
      -- quarto 把 {=html} 表格包在 Div(quarto-scaffold) 里：整体替换，避免 quarto writer 输出浮动体时重组
      local found = extract_table_and_caption(b.content)
      if found and found.table then
        local tbl = found.table
        local has_cap = tbl.caption and tbl.caption.long and #tbl.caption.long > 0
        if not has_cap and found.caption then
          tbl.caption = pandoc.Caption(pandoc.Inlines(found.caption))
        end
        out[#out + 1] = pandoc.RawBlock("latex", table_to_latex(tbl, cfg))
      else
        b.content = pandoc.List(process_blocks(b.content, cfg))
        out[#out + 1] = b
      end
    elseif b.t == "RawBlock" and b.format == "html" and b.text:match("%<table") then
      -- CLI pandoc（非 quarto）环境下 {=html} 保持 RawBlock；PDF 端走 pandoc.read 兜底
      local tbl = html_raw_to_table(b.text)
      if tbl then
        out[#out + 1] = pandoc.RawBlock("latex", table_to_latex(tbl, cfg))
      else
        out[#out + 1] = b
      end
    elseif b.t == "BlockQuote" then
      b.content = pandoc.List(process_blocks(b.content, cfg))
      out[#out + 1] = b
    else
      out[#out + 1] = b
    end
  end
  return out
end

function Pandoc(doc)
  local cfg = read_config(doc.meta)
  doc.blocks = pandoc.List(process_blocks(doc.blocks, cfg))
  return doc
end
