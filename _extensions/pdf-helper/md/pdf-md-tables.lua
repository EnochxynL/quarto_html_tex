-- pdf-md-tables.lua — PDF 方案：管道表 → table* / table / longtable + booktabs tabular
--
-- 领地划分（2026-09-02）：md/（管道表）· html/（{=html} 直写表）· ref/
-- （tbl- 引用提示器）——表格三通道：Markdown 管道表 / {=html} 直写表 /
-- {=latex} 原样传递（LaTeX 编译器处理）。
-- {=html} 直写表的转换已拆出到 pdf-html-tables.lua（单栏 table，独立配置）。
--
-- 方案（为什么管道表要转成 LaTeX 浮动体）：
--   双栏（\twocolumn）下 Pandoc 默认生成的 longtable 会报 "longtable not in 1-column mode"，
--   且默认输出用 \LTcaptype{none} 关掉表格计数器。这里重写为 booktabs 三线普通浮动表，
--   caption/label 由 LaTeX 原生处理（\caption + \label），编号走 LaTeX 编译时交叉引用。
--
-- 配置（format 级别，如 pdf 下）：
--   format:
--     pdf:
--       html-helper:
--         md-table-env: table*      # 管道表环境：table*（双栏通栏）| table（单栏）| longtable
--         md-table-pos: htbp        # 浮动位置参数
--         table-caption-pos: bottom # caption 位置：top | bottom（与 pdf-html-tables 共享）
--
-- 注意（踩坑记录）：
--   pandoc.meta 在 filter 模块顶层和元素回调（Table/RawBlock）内都是 nil 或空表；
--   只有 Pandoc(doc) 回调的 doc.meta 才含完整 metadata。metadata 值是 MetaInlines，
--   需 pandoc.utils.stringify 才能比较。quarto 把 format.pdf 下的 html-helper 提升为
--   顶层 meta（平铺，无 pdf 嵌套层）——read_config 嵌套优先、平铺回退（README 踩坑 13）。
--   本 filter 只处理顶层 Table 节点（管道表）：{=html} 表的 Table 在
--   Div(__quarto_custom_scaffold) 内部，递归进去会抢先把内部 Table 转成
--   md-table-env 环境——Div 一律原样保留，交给 pdf-html-tables.lua。
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
-- 键名：md-table-env/md-table-pos（管道表）、table-caption-pos（caption 位置，
-- 与 pdf-html-tables 共享）
local function read_config(meta)
  local pt = meta["html-helper"] or meta["paper-tables"] or {}
  local pdf = pt["pdf"] or {}
  return {
    env = get_str(pdf["md-table-env"], get_str(pt["md-table-env"], "table*")),
    pos = get_str(pdf["md-table-pos"], get_str(pt["md-table-pos"], "htbp")),
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

-- 手写递归：只处理顶层 Table；Div/BlockQuote 原样保留不递归
-- （{=html} 表的 Table 在 Div(__quarto_custom_scaffold) 内，递归会误转换）
local function process_blocks(blocks, cfg)
  local out = {}
  for _, b in ipairs(blocks) do
    if b.t == "Table" then
      out[#out + 1] = pandoc.RawBlock("latex", table_to_latex(b, cfg))
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
