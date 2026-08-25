-- tables-pdf.lua — PDF 方案：管道表 / {=html} 表 → table* / table / longtable + booktabs tabular
--
-- 从 tables-to-tablestar.lua 拆出的 PDF 半边（HTML 半边见 tables-html.lua）。
--
-- 方案（为什么管道表要转成 LaTeX 浮动体）：
--   双栏（\twocolumn）下 Pandoc 默认生成的 longtable 会报 "longtable not in 1-column mode"，
--   且默认输出用 \LTcaptype{none} 关掉表格计数器。这里重写为 booktabs 三线普通浮动表，
--   caption/label 由 LaTeX 原生处理（\caption + \label），编号走 LaTeX 编译时交叉引用。
--   {=html} 直写的 <table> 在 PDF 端用 pandoc.read(text,"html") 解析成 Table AST 后
--   走同一套转换（HTML raw → LaTeX 兜底）。
--
-- 配置（format 级别，如 pdf 下）：
--   format:
--     pdf:
--       html-helper:
--         table-env: table*      # 表格环境：table*（双栏通栏）| table（单栏）| longtable
--         table-pos: htbp        # 浮动位置参数
--         caption-pos: top       # caption 位置：top（表上方，ICML 惯例）| bottom（表下方，AAAI/Springer 惯例）
--
-- 注意（踩坑记录）：
--   pandoc.meta 在 filter 模块顶层和元素回调（Table/RawBlock）内都是 nil 或空表；
--   只有 Pandoc(doc) 回调的 doc.meta 才含完整 metadata。
--   因此本 filter 用 Pandoc() 回调 + 手写递归，而非 Table()/RawBlock() 自动分发。
--   metadata 值是 MetaInlines（[Str "x"]），需 pandoc.utils.stringify 才能比较。
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

-- 从 doc.meta 读取配置（Pandoc() 回调里才能拿到）；兼容旧名 paper-tables
local function read_config(meta)
  local pt = meta["html-helper"] or meta["paper-tables"] or {}
  local pdf = pt["pdf"] or {}
  return {
    env = get_str(pdf["table-env"], "table*"),
    pos = get_str(pdf["table-pos"], "htbp"),
    cap_pos = get_str(pdf["caption-pos"], "top"),
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
  -- 列规格（Pandoc 3.x：colspecs[i] 是 {alignment, width}）
  local colspec = {}
  for _, cs in ipairs(tbl.colspecs) do
    local a = cs[1]  -- alignment 字符串
    colspec[#colspec + 1] = ALIGN[a] or "l"
  end
  local cstext = table.concat(colspec)

  -- 表体
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

  -- caption + label（{#...} 若没被 Pandoc 识别为表 id，会作为字面量留在 caption 里，这里提取并移除）
  local id = (tbl.attr and tbl.attr.identifier) or tbl.identifier or ""
  local caption = ""
  if tbl.caption and tbl.caption.long and #tbl.caption.long > 0 then
    local s = pandoc.write(pandoc.Pandoc(tbl.caption.long), "latex")
    s = s:gsub("%s*\n%s*", " ")
    -- 提取 \{#id\} 形式的残留 id（LaTeX 转义：# → \#）
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
    -- caption/label 在表格之后（表下方，AAAI/Springer 惯例）
    local tail = body
    if caption ~= "" then tail = tail .. "\n" .. caption end
    if label ~= "" then tail = tail .. "\n" .. label end
    return head .. tail .. "\n" .. close
  else
    -- caption/label 在表格之前（表上方，ICML 惯例，默认）
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
  local cfg = read_config(doc.meta)

  local function transform(b)
    if b.t == "Table" then
      return pandoc.RawBlock("latex", table_to_latex(b, cfg))
    elseif b.t == "Div" then
      -- quarto 把 {=html} 表格包在 Div(quarto-scaffold) 里：整体替换，避免 quarto writer 输出浮动体时重组
      local found = extract_table_and_caption(b.content)
      if found and found.table then
        local tbl = found.table
        local has_cap = tbl.caption and tbl.caption.long and #tbl.caption.long > 0
        if not has_cap and found.caption then
          tbl.caption = pandoc.Caption(pandoc.Inlines(found.caption))
        end
        return pandoc.RawBlock("latex", table_to_latex(tbl, cfg))
      end
    elseif b.t == "RawBlock" and b.format == "html" and b.text:match("%<table") then
      -- CLI pandoc（非 quarto）环境下 {=html} 保持 RawBlock；PDF 端走 pandoc.read 兜底
      local tbl = html_raw_to_table(b.text)
      if tbl then
        return pandoc.RawBlock("latex", table_to_latex(tbl, cfg))
      end
    end
    return nil
  end

  doc.blocks = pandoc.List(process_blocks(doc.blocks, transform))
  return doc
end
