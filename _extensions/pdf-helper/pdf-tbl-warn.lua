-- pdf-tbl-warn.lua — PDF 端 tbl- 前缀检测警告
--
-- 背景：quarto main.lua（18268-18360，无配置开关）在用户 filter 之前/之中对
-- RawBlock(latex) 表格做 float 识别：\label{tbl-X} 被剥离、表格被接管重组
-- （{=latex} 保真破坏）；管道表生成的 \label{tbl-X 同样被吃掉。实证：
-- 用户 filter 阶段 {=latex} 表格的 RawBlock 已只剩 caption（label/表格体被
-- quarto 拿走），归一化 filter 对该路径无效。
--
-- 机制澄清（为什么配对正确的 tbl- 也会 ??）：tbl- 前缀是 quarto 原生
-- @tbl-x 交叉引用的地盘——quarto crossref 体系在 reader 阶段把 tbl- 的
-- id/label 消费进自己的内部状态（管道表 attr.identifier 清空、{=latex}
-- 表格 \label 被剥离接管）。LaTeX 原生 \ref{tbl-x} 走不到 quarto 的
-- crossref（quarto 只认 @tbl-x 语法），LaTeX 层又找不到已被消费的
-- \label{tbl-x} → 悬空渲染 ??。因此这不是"标签引用错配"（人错配是
-- \ref{tbl-b} 对 \label{tbl-a} 那种），而是 tbl- 资源被分配给 @ 体系后
-- \ref 天然找不到它——即使 label/ref 配对正确也一样。
--
-- 结论：tbl- 前缀仅在 HTML 端受支持（RawBlock(html) quarto 不碰，id 原样保留，
-- html-crossref.lua 不限前缀收集，\ref{tbl-X} 命中编号链接）；PDF 端内容层
-- 表格前缀必须用 tab-（quarto 唯一放行的前缀）。本 filter 负责让 tbl- 输入
-- 的失败可见：检测正文 \ref{tbl-X}（RawInline tex）→ 警告，防止 PDF 端静默
-- 渲染 "??"。
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
          io.stderr:write("WARN pdf-tbl-warn: \\ref{tbl-" .. ref ..
            "} — tbl- 前缀在 PDF 端被 quarto 接管（表格拆碎），请改用 tab-" ..
            ref .. " 融入 html-helper 引用框架。\n")
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
