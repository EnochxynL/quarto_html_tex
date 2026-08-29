-- pdf-tbl-warn.lua — PDF 端 tbl- 前缀检测提示
--
-- 背景（实证 2026-08-30，_tbltest 探针）：quarto 对 tbl- 表格的处理分两种：
--   1) 管道表 {#tbl-X}：quarto reader 消费 id 进 crossref 内部状态（用户 filter
--      AST 层看不到 id——这是 html-helper2 用 tblref.py 后处理编号的原因），
--      但 PDF writer 把 \label{tbl-X} 原样写回中间 tex（实证：index.tex 里
--      \caption{管道表一}\label{tbl-probe} 原样存在）——LaTeX 原生 \ref{tbl-X}
--      在编译时命中，**不会 ??**。HTML 端锚点 <div id="tbl-X"
--      class="quarto-float quarto-figure"> 也存在（quarto 需要它渲染 @tbl-X）。
--   2) {=latex} 表格 \label{tbl-X}：main.lua float 识别接管——label 被挪进
--      \caption{\label{tbl-X}...}（结构污染：caption 文本被插 label），表格体
--      \resizebox 等原样保留（tex 实证）。\ref{tbl-X} 仍命中（label 实体在），
--      但 caption 结构被 quarto 改动过。
--
-- 结论（修正 2026-08-29 版错误机制澄清）：tbl- 前缀在 PDF 端**不是必然 ??**——
-- 旧版说"tbl- 是 @ 引用的地盘，\ref 天然找不到"对管道表不成立（label 原样
-- 写回）。真正需要 tab- 的场景收窄为：{=latex} 复杂表格（resizebox 等）在
-- HTML 端被 quarto 接管后静默消失（pandoc 解析 resizebox 失败→空输出，
-- 实证 index3）——因此 {=latex} 复杂表仍须 tab- 让路给 html-latex-tables
-- 翻译；管道表用 tbl- 走 quarto 原生（html-helper2 的 tbl- 通道）。
--
-- 本 filter 保留为提示器：检测正文 \ref{tbl-X}（RawInline tex）→ 提示其
-- 走 tbl- 通道（管道表 ✓ / {=latex} 表注意 caption 结构），不再是"警告 ?? "。
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
          io.stderr:write("INFO pdf-tbl-warn: \\ref{tbl-" .. ref ..
            "} 走 tbl- 通道（管道表 PDF label 原样写回可命中；{=latex} 表 label" ..
            " 会被 quarto 挪进 caption 但实体保留）。若引用显示 ?? 或 caption" ..
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
