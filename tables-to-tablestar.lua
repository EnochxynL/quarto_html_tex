-- tables-to-tablestar.lua
-- PDF：把 markdown 管道表（Pandoc Table）转成 table* + tabular。
-- 原因：双栏（\twocolumn）下 Pandoc 默认生成的 longtable 会报 "longtable not in 1-column mode"。
-- HTML：交给 Pandoc 原生处理（管道表 → <table>）。
if FORMAT ~= "pdf" and FORMAT ~= "latex" then
  return {}
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

function Table(tbl)
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
    -- 提取 \{\#id\} 形式的残留 id（LaTeX 转义：# → \#）
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

  local result = "\\begin{table*}[htbp]\n\\centering\n"
    .. caption .. (caption ~= "" and "\n" or "")
    .. label .. (label ~= "" and "\n" or "")
    .. "\\begin{tabular}{" .. cstext .. "}\n"
    .. table.concat(lines, "\n") .. "\n"
    .. "\\end{tabular}\n\\end{table*}"

  return { pandoc.RawBlock("latex", result) }
end
