-- html-tab-crossref.lua — HTML 表格引用体系（编号 + caption 前缀 + 引用链接）
--
-- 从 html-crossref.lua 拆出（tab 半边）。职责：
--   1) 统计所有含表格的 RawBlock（<table）按文档顺序编号
--      （组合表 resizebox+minipage 多子表的多 label 别名 → 同一编号）
--   2) <caption> 加 caption-prefix + 编号 + caption-sep（配置化，对齐 PDF 端 LaTeX 自动编号）
--   3) 表格引用 \ref{tab-X}（正文 RawInline + RawBlock 文本）→ <a href="#tab-X">N</a>
--      （"表"字由内容层手写"表 \ref{tab-X}"提供——filter 只出数字，避免"表 表 N"双表）
--
-- 只处理 tab- 前缀；其他引用（sec-/fig-/未知）未命中时原样重拼保留，
-- 由 html-sec-crossref / html-fig-crossref 处理（filter 链顺序：tab → sec → fig，
-- fig 最后做未知引用兜底）。
--
-- 配置（format 级别，html-helper 命名空间；format.html 或 format.pdf 下均可，
-- read_config 嵌套优先、平铺回退，见 README 踩坑 13）：
--   format:
--     html:
--       html-helper:
--         caption-prefix: "Table "   # caption 编号前缀：默认 "表 "（中文论文）；英文论文配 "Table "
--         caption-sep: ": "          # 编号与标题间分隔符：默认 "："（中文全角）；英文论文配 ": "（半角+空格）
-- 填写注意：配置值写"带尾随空格"的形式——YAML 提升会 trim 尾随空格
-- （"Table " → "Table"），read_config 对配置值统一补回一个空格；默认值（Lua 字面）
-- 不经 YAML，原样保留（"表 " 带空格、"：" 无空格）。
--
-- 注意：pandoc.walk_block / pandoc.walk_inline 在本 pandoc 版本均不可靠，全部手写递归。
if FORMAT ~= "html" and FORMAT ~= "html5" then
  return {}
end

local function read_config(meta)
  local pt = meta["html-helper"] or meta["paper-tables"] or {}
  local pdf = pt["pdf"] or {}
  local pv = pdf["caption-prefix"] or pt["caption-prefix"]
  local sv = pdf["caption-sep"] or pt["caption-sep"]
  local prefix = pv and (pandoc.utils.stringify(pv) .. " ") or "表 "
  local sep = sv and (pandoc.utils.stringify(sv) .. " ") or "："
  return prefix, sep
end

-- 表格引用 → <a href="#tab-X">N</a>；未命中 nil（原样保留给后续 filter）
local function ref_link(ref, tab_nums)
  if tab_nums[ref] then
    return '<a href="#' .. ref .. '">' .. tab_nums[ref] .. "</a>"
  end
  return nil
end

-- tbl- 引用 → 占位符 <a href="#tbl-X">[tbl-X]</a>（html-helper2 新通道）
-- 实证（2026-08-30）：quarto 对 tbl- 管道表 label 原样写回 tex（PDF \ref 命中）、
-- HTML 端输出 <div id="tbl-X" class="quarto-float quarto-figure">（锚点存在）。
-- 编号由 tblref.py（post-render）数 float div 文档顺序填充——与 quarto 原生
-- @tbl-X 编号同源（FloatRefTarget 顺序），双引用语法编号一致。
local function tbl_placeholder(ref)
  if ref:match("^tbl%-") then
    return '<a href="#' .. ref .. '">[' .. ref .. "]</a>"
  end
  return nil
end

function Pandoc(doc)
  local cap_prefix, cap_sep = read_config(doc.meta)
  -- 1) 表格编号统计：所有含表格的 RawBlock 按文档顺序编号（无 id 也占序号，
  --    保证与 PDF 端一致）；组合表多 label 别名全部收集映射到同一编号
  local tab_nums = {}
  local tab_counter = 0
  local raw_tables = {}  -- { {rb=RawBlock, num=...}, ... }
  local function collect(blocks)
    for _, b in ipairs(blocks) do
      if b.t == "RawBlock" and b.format == "html" and b.text:match("%<table") then
        tab_counter = tab_counter + 1
        for id in b.text:gmatch('id="([^"]+)"') do
          tab_nums[id] = tab_counter
        end
        raw_tables[#raw_tables + 1] = { rb = b, num = tab_counter }
      elseif b.t == "Div" then
        collect(b.content)
      end
    end
  end
  collect(doc.blocks)

  -- 2) + 3) RawBlock 文本内引用替换（表格 caption 等）
  -- 注意 Lua pattern：`\\S?\\ref` 需要两个反斜杠，`\ref`（单反斜杠）不匹配——
  -- 必须分两个 pattern，先长后短；§? 可选多字节匹配空分支失败，拆两个 pattern。
  -- 未命中（非 tab-）原样重拼保留（丢 data-* 属性但保留 href/label，后续 filter 可继续处理）
  local function replace_in_text(text)
    text = text:gsub("§<a%s+href=\"#([^\"]+)\"[^>]*>[^%[]*%[([^%]]+)%]</a>", function(ref, label)
      local link = ref_link(ref, tab_nums) or tbl_placeholder(ref)
      if link then return link:gsub("^§", "") end
      return "§<a href=\"#" .. ref .. "\">[" .. label .. "]</a>"
    end)
    text = text:gsub("<a%s+href=\"#([^\"]+)\"[^>]*>[^%[]*%[([^%]]+)%]</a>", function(ref, label)
      local link = ref_link(ref, tab_nums) or tbl_placeholder(ref)
      if link then return link end
      return "<a href=\"#" .. ref .. "\">[" .. label .. "]</a>"
    end)
    text = text:gsub("\\\\S\\\\ref{([^}]+)}", function(ref)
      local link = ref_link(ref, tab_nums) or tbl_placeholder(ref)
      if link then return link end
      return "\\S\\ref{" .. ref .. "}"
    end)
    text = text:gsub("\\\\ref{([^}]+)}", function(ref)
      local link = ref_link(ref, tab_nums) or tbl_placeholder(ref)
      if link then return link end
      return "\\ref{" .. ref .. "}"
    end)
    return text
  end

  for _, t in ipairs(raw_tables) do
    t.rb.text = replace_in_text(t.rb.text)
    t.rb.text = t.rb.text:gsub("(<caption>)([^<]*)", function(open, cap)
      if cap:match("^" .. cap_prefix .. "%d+") then return open .. cap end
      return open .. cap_prefix .. t.num .. cap_sep .. cap
    end, 1)
    -- 组合表 caption 已由 html-latex-tables 移出 table 为独立 div
    -- （<caption> 元素只能在 table 内，容器级用 div），前缀同样要加；
    -- 注意 pattern 里 class 名 table-caption 的连字符须转义 %-（否则被
    -- 当作非贪婪修饰符，pattern 永远不匹配）
    t.rb.text = t.rb.text:gsub('(<div class="table%-caption">)([^<]*)', function(open, cap)
      if cap:match("^" .. cap_prefix .. "%d+") then return open .. cap end
      return open .. cap_prefix .. t.num .. cap_sep .. cap
    end, 1)
  end

  -- 3) 正文 inline 替换（手写递归；未命中原样保留）
  local function walk_inlines(inlines)
    local out = pandoc.List({})
    for _, inl in ipairs(inlines) do
      if inl.t == "RawInline" and inl.format == "tex" then
        local ref = inl.text:match("^\\ref{([^}]+)}")
        if not ref then
          ref = inl.text:match("^\\S\\ref{([^}]+)}")
        end
        if ref then
          local link = ref_link(ref, tab_nums) or tbl_placeholder(ref)
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
        -- （实证：quarto render 输出 <span class="math inline">\(\ref{tab-x}\)</span>）
        -- 未命中（非 tab-）原样保留，留给后续 filter（sec/fig 同理各自处理）
        local ref = inl.text:match("^\\ref{([^}]+)}")
        if not ref then
          ref = inl.text:match("^\\S\\ref{([^}]+)}")
        end
        if ref then
          local link = ref_link(ref, tab_nums) or tbl_placeholder(ref)
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
        local link = ref_link(ref, tab_nums) or tbl_placeholder(ref)
        if link then
          out:insert(pandoc.RawInline("html", link))
        else
          -- 未命中：原样保留（tab/sec 不认领的引用留给后续 filter）
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
