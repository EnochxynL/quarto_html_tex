-- pdf-ref-tbl.lua — PDF 端 \ref{tbl-X} 引用提示器（INFO 日志，不改文档）
--
-- 职责：检测正文 \ref{tbl-X}（RawInline tex）→ stderr INFO 提示通道行为：
--   管道表 {#tbl-X}：quarto PDF writer 把 \label{tbl-X} 原样写回中间 tex
--     （实证 index.tex）——LaTeX 原生 \ref 编译命中，与 @tbl-X 同号，正常
--   {=latex} 表 \label{tbl-X}：quarto float 接管——label 被挪进 caption
--     （结构污染但实体保留），\ref 仍命中；复杂表（resizebox 等）HTML 端
--     会被 float 接管后静默消失（pandoc 解析失败），故仍须 tab- 让路
--
-- 何时需要关注（本提示只在引用真出问题时才有用）：\ref{tbl-X} 显示 ?? 或
-- caption 异常 → 查是否 {=latex} 表被 quarto float 接管。
--
-- 本模块不拦截不警告——tbl- 不是错误通道（实证 2026-08-30：旧版"tbl- 是
-- @ 地盘、\ref 必 ??"的判断对管道表不成立——label 原样写回可命中）。
if FORMAT ~= "pdf" and FORMAT ~= "latex" then
  return {}
end

local warned = {}

function Pandoc(doc)
  local function walk_inlines(inlines)
    for _, inl in ipairs(inlines) do
      if inl.t == "RawInline" and inl.format == "tex" then
        local ref = inl.text:match("^\\ref{tbl%-([^}]+)}")
        if ref and not warned[ref] then
          warned[ref] = true
          io.stderr:write("INFO pdf-ref-tbl: \\ref{tbl-" .. ref ..
            "} 走 tbl- 通道（管道表 label 原样写回可命中；{=latex} 表 label" ..
            " 被 quarto 挪进 caption 但实体保留）。若显示 ?? 或 caption" ..
            " 异常，检查是否 {=latex} 表格被 quarto float 接管。\n")
        end
      elseif inl.content and (inl.t == "Strong" or inl.t == "Emph" or inl.t == "Span"
        or inl.t == "Link" or inl.t == "Quoted" or inl.t == "Cite") then
        walk_inlines(inl.content)
      end
    end
  end

  local function walk_blocks(blocks)
    for _, b in ipairs(blocks) do
      if b.t == "Para" or b.t == "Plain" or b.t == "Header" then
        walk_inlines(b.content)
      elseif b.t == "Div" or b.t == "BlockQuote" then
        walk_blocks(b.content)
      elseif b.t == "Figure" then
        walk_blocks(b.content)
      elseif b.t == "BulletList" or b.t == "OrderedList" then
        for _, item in ipairs(b.content) do
          walk_blocks(item)
        end
      elseif b.t == "DefinitionList" then
        for _, item in ipairs(b.content) do
          walk_inlines(item[1])
          for _, def in ipairs(item[2]) do
            walk_blocks(def)
          end
        end
      elseif b.t == "Table" then
        local function walk_cells(rows)
          for _, row in ipairs(rows or {}) do
            for _, c in ipairs(row.cells) do
              walk_inlines(c.content)
            end
          end
        end
        if b.head then walk_cells(b.head.rows) end
        for _, bd in ipairs(b.bodies) do walk_cells(bd.body) end
        walk_cells(b.foot and b.foot.rows)
      end
    end
  end

  walk_blocks(doc.blocks)
  return doc
end
