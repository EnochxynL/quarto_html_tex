-- html-ref-sec.lua — HTML 章节引用体系（Header 层级自数 + §N 链接）
-- 
-- 处理 \ref{sec-X} / \S\ref{sec-X} 形式的章节引用。
-- 内容层 @sec-X（quarto 原生语法）走 quarto crossref，不经过本 filter。
-- 
-- 职责：
--   1) 按 Header 层级自数章节编号（1.1.1 格式，与 PDF 端 Pandoc number-sections 一致——
--      quarto 的章节编号在 writer 阶段才生成，filter 拿不到）
--   2) 章节引用 \ref{sec-X} / \S\ref{sec-X}（正文 RawInline + RawBlock 文本）
--      → <a href="#sec-X">§N</a>（\S 是 LaTeX 命令被 HTML writer 丢弃，filter 补 §）
--
-- 无配置。
--
-- 注意：pandoc.walk_block / pandoc.walk_inline 在本 pandoc 版本均不可靠，全部手写递归。
if FORMAT ~= "html" and FORMAT ~= "html5" then
  return {}
end

-- 章节引用 → <a href="#sec-X">§N</a>；未命中 nil（原样保留给后续 filter）
local function ref_link(ref, sec_nums)
  if sec_nums[ref] then
    return '<a href="#' .. ref .. '">§' .. sec_nums[ref] .. "</a>"
  end
  return nil
end

function Pandoc(doc)
  -- 1) 章节编号：遍历 Header（含 Div 嵌套），按层级自数（1.1.1）
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

  -- 2) RawBlock 文本内章节引用替换（表格 caption 等；未命中原样重拼保留）
  local function replace_in_text(text)
    text = text:gsub("§<a%s+href=\"#([^\"]+)\"[^>]*>%[([^%]]+)%]</a>", function(ref, label)
      local link = ref_link(ref, sec_nums)
      if link then return link:gsub("^§", "") end
      return "§<a href=\"#" .. ref .. "\">[" .. label .. "]</a>"
    end)
    text = text:gsub("<a%s+href=\"#([^\"]+)\"[^>]*>%[([^%]]+)%]</a>", function(ref, label)
      local link = ref_link(ref, sec_nums)
      if link then return link end
      return "<a href=\"#" .. ref .. "\">[" .. label .. "]</a>"
    end)
    text = text:gsub("\\\\S\\\\ref{([^}]+)}", function(ref)
      local link = ref_link(ref, sec_nums)
      if link then return link end
      return "\\S\\ref{" .. ref .. "}"
    end)
    text = text:gsub("\\\\ref{([^}]+)}", function(ref)
      local link = ref_link(ref, sec_nums)
      if link then return link end
      return "\\ref{" .. ref .. "}"
    end)
    return text
  end

  -- RawBlock("html") 全部过一遍（表格 caption / {=html} 文本内的章节引用）
  local function walk_blocks_text(blocks)
    for _, b in ipairs(blocks) do
      if b.t == "RawBlock" and b.format == "html" then
        b.text = replace_in_text(b.text)
      elseif b.t == "Div" then
        walk_blocks_text(b.content)
      end
    end
  end
  walk_blocks_text(doc.blocks)

  -- 2) 正文 inline 替换（手写递归；未命中原样保留）
  local function walk_inlines(inlines)
    local out = pandoc.List({})
    for _, inl in ipairs(inlines) do
      if inl.t == "RawInline" and inl.format == "tex" then
        local ref = inl.text:match("^\\ref{([^}]+)}")
        if not ref then
          ref = inl.text:match("^\\S\\ref{([^}]+)}")
        end
        if ref then
          local link = ref_link(ref, sec_nums)
          if link then
            out:insert(pandoc.RawInline("html", link))
          else
            out:insert(inl)
          end
        else
          out:insert(inl)
        end
      elseif inl.t == "Math" then
        -- quarto markdown 扩展集无 raw_tex：正文裸 \ref{X} 被数学化成 Math 节点
        -- （实证：quarto render 输出 <span class="math inline">\(\ref{sec-x}\)</span>）
        -- 未命中（非 sec-）原样保留给后续 filter（fig 兜底）
        local ref = inl.text:match("^\\ref{([^}]+)}")
        if not ref then
          ref = inl.text:match("^\\S\\ref{([^}]+)}")
        end
        if ref then
          local link = ref_link(ref, sec_nums)
          if link then
            out:insert(pandoc.RawInline("html", link))
          else
            out:insert(inl)
          end
        else
          out:insert(inl)
        end
      elseif inl.t == "Link" and inl.attr and inl.attr.attributes
        and inl.attr.attributes["reference-type"] == "ref" then
        -- quarto reader 把正文 \ref{X} 解析成 Link（reference-type=ref，文本 [X]），
        -- 不是 RawInline——按引用处理（HTML writer 对 Link 输出 data-reference-type）
        local ref = inl.attr.attributes["reference"]
        local link = ref_link(ref, sec_nums)
        if link then
          out:insert(pandoc.RawInline("html", link))
        elseif true then
          -- 未命中：fig 兜底占位（Str），tab/sec 原样保留给后续 filter
          out:insert(inl)
        else
          out:insert(inl)
        end
      else
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
          item[1] = walk_inlines(item[1])
          for j, def in ipairs(item[2]) do
            item[2][j] = walk_blocks(def)
          end
        end
      elseif b.t == "Table" then
        local function walk_cells(rows)
          for _, row in ipairs(rows or {}) do
            for _, c in ipairs(row.cells) do
              c.content = walk_inlines(c.content)
            end
          end
        end
        -- caption.long 是 [Block]（Para/Plain），里面的引用也要替换
                if b.caption and b.caption.long then
                  for _, cblk in ipairs(b.caption.long) do
                    if (cblk.t == "Para" or cblk.t == "Plain") and cblk.content then
                      cblk.content = walk_inlines(cblk.content)
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
