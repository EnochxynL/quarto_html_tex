-- html-fig-crossref.lua — HTML 图引用占位 + 未知引用兜底
--
-- 从 html-crossref.lua 拆出（fig 半边 + 兜底职责）。职责：
--   1) 图引用 \ref{fig-X}（正文 RawInline + RawBlock 文本）→ 占位
--      <a href="#fig-X">[fig-X]</a>：quarto reader 把图 id 消费进内部状态
--      （main.lua crossref index），filter 阶段图节点无 id 信息无法自数——
--      占位由项目级 post-render 脚本 figref.py 在渲染完成后自动编号
--      （数 <div id="fig-X" class="quarto-float quarto-figure"> 文档顺序，
--      见 README 踩坑 23）
--   2) 兜底：所有剩余未解析的 \ref{X}（tab-/sec- 未命中的、未知引用）→ [§X] 占位
--      ——本 filter 是引用链最后一个（tab → sec → fig），必须让失败可见
--
-- 无配置。内容层 @fig-X（quarto 原生语法）走 quarto crossref，不经过本 filter。
--
-- 注意：pandoc.walk_block / pandoc.walk_inline 在本 pandoc 版本均不可靠，全部手写递归。
if FORMAT ~= "html" and FORMAT ~= "html5" then
  return {}
end

-- 图引用 → 占位 <a href="#fig-X">[fig-X]</a>；其他前缀 → nil（由调用方决定兜底）
local function ref_link(ref)
  if ref:match("^fig%-") then
    return '<a href="#' .. ref .. '">[' .. ref .. "]</a>"
  end
  return nil
end

function Pandoc(doc)
  -- RawBlock 文本内图引用替换（表格 caption 内 \ref{fig-X} 的场景）
  -- 未命中（非 fig- 前缀，即 tab-/sec- 未命中或未知）→ 兜底占位 [label] / [§ref]
  local function replace_in_text(text)
    text = text:gsub("§<a%s+href=\"#([^\"]+)\"[^>]*>%[([^%]]+)%]</a>", function(ref, label)
      local link = ref_link(ref)
      if link then return link:gsub("^§", "") end
      return "§[" .. label .. "]"
    end)
    text = text:gsub("<a%s+href=\"#([^\"]+)\"[^>]*>%[([^%]]+)%]</a>", function(ref, label)
      local link = ref_link(ref)
      if link then return link end
      return "[" .. label .. "]"
    end)
    text = text:gsub("\\\\S\\\\ref{([^}]+)}", function(ref)
      local link = ref_link(ref)
      if link then return link end
      return "[§" .. ref .. "]"
    end)
    text = text:gsub("\\\\ref{([^}]+)}", function(ref)
      local link = ref_link(ref)
      if link then return link end
      return "[§" .. ref .. "]"
    end)
    return text
  end

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

  -- 正文 inline 替换：fig- → 占位链接；其他（tab-/sec- 未命中、未知）→ [§ref] 兜底
  local function walk_inlines(inlines)
    local out = pandoc.List({})
    for _, inl in ipairs(inlines) do
      if inl.t == "RawInline" and inl.format == "tex" then
        local ref = inl.text:match("^\\ref{([^}]+)}")
        if not ref then
          ref = inl.text:match("^\\S\\ref{([^}]+)}")
        end
        if ref then
          local link = ref_link(ref)
          if link then
            out:insert(pandoc.RawInline("html", link))
          else
            out:insert(pandoc.Str("[§" .. ref .. "]"))
          end
        else
          out:insert(inl)
        end
      elseif inl.t == "Math" then
        -- quarto markdown 扩展集无 raw_tex：正文裸 \ref{X} 被数学化成 Math 节点
        -- （实证：quarto render 输出 <span class="math inline">\(\ref{fig-x}\)</span>）
        local ref = inl.text:match("^\\ref{([^}]+)}")
        if not ref then
          ref = inl.text:match("^\\S\\ref{([^}]+)}")
        end
        if ref then
          local link = ref_link(ref)
          if link then
            out:insert(pandoc.RawInline("html", link))
          elseif not ref:match('^fig%-') then
            out:insert(pandoc.Str("[§" .. ref .. "]"))
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
        local link = ref_link(ref)
        if link then
          out:insert(pandoc.RawInline("html", link))
        elseif not ref:match('^fig%-') then
          -- 未命中：fig 兜底占位（Str），tab/sec 原样保留给后续 filter
          out:insert(pandoc.Str("[§" .. ref .. "]"))
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
