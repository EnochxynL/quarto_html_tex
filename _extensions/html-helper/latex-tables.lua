-- latex-tables.lua (v4) — 通用版
-- 
-- 核心能力：把 raw LaTeX 表格渲染为双格式
--   HTML: raw LaTeX 表格 → pandoc.read → Table AST → pandoc.write(html) → RawBlock("html")
--         直接输出 HTML 字符串，绕过 main.lua 对 Table 的 crossref 处理（它会吃掉 id）
--   PDF:  保持原样（crossref.lua 对 tab- 前缀只警告不拦截）
-- 
-- 用法（filters 里按名称引用，如 html-helper）：
--   filters:
--     - html-helper
-- 
-- v4 变更：RawBlock 回调 → Pandoc(doc) 回调
--   1) 元素回调拿不到 pandoc.meta（nil/空表），只有 Pandoc(doc) 的 doc.meta 有完整
--      metadata——表格内 \citep{key} 需要在子文档上跑 pandoc.utils.citeproc 才能
--      渲染出 (Author Year)，而 bibliography 路径必须从 doc.meta 读
--   2) 表格子文档注入 bibliography 后调 citeproc：\citep{key} → (Starace et al. 2025)
--      （主文档 citeproc 不处理 RawBlock 字符串内部，只能在这里自己调）

-- 递归找 Table 节点
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

-- 子文档跑 citeproc（表格内 \citep 渲染成 (Author Year)）
local function run_citeproc(doc, bibstr)
  if not (bibstr and pandoc.utils.citeproc) then return doc end
  doc.meta["bibliography"] = pandoc.MetaString(bibstr)
  local ok, res = pcall(pandoc.utils.citeproc, doc)
  if ok then return res end
  return doc
end

-- 单个 latex 表格块 → RawBlock("html")
local function convert_table(el, bibstr)
  -- 预处理：剥离 \cmidrule 行（Pandoc 不认识，会变成垃圾文本）
  local cleaned = el.text:gsub("\\cmidrule[^\n]*\n?", "")
  -- 勾叉：\cmark/\xmark 是 pifont 自定义命令，pandoc 的 LaTeX reader 不认识会丢弃 → 替换为 Unicode
  cleaned = cleaned:gsub("\\cmark%{%}?", "✓"):gsub("\\cmark", "✓")
  cleaned = cleaned:gsub("\\xmark%{%}?", "✗"):gsub("\\xmark", "✗")

  local doc = pandoc.read(cleaned, "latex")

  -- 表格内 \citep/\citet 等：子文档跑 citeproc（主文档 citeproc 不碰 RawBlock 字符串）
  if cleaned:match("\\cite") then
    doc = run_citeproc(doc, bibstr)
  end

  local tbl = find_table(doc.blocks)
  if not tbl then
    return el
  end

  -- 补 caption（Pandoc 的 LaTeX reader 会丢失它们）；caption 内的 \citep 同样过 citeproc
  local cap_match = cleaned:match("\\caption%b{}")
  if cap_match then
    local caption = cap_match:sub(10, -2)  -- 去掉 "\caption{" 和 "}"
    local cap_ast = pandoc.read(caption, "latex")
    if caption:match("\\cite") then
      cap_ast = run_citeproc(cap_ast, bibstr)
    end
    if #cap_ast.blocks > 0 and cap_ast.blocks[1].content then
      tbl.caption = pandoc.Caption(pandoc.Inlines(cap_ast.blocks[1].content))
    end
  end

  -- 补 label
  local label = el.text:match("\\label{([^}]+)}")
  if label then
    tbl.attr = tbl.attr or pandoc.Attr()
    tbl.attr.identifier = label
  end

  -- 渲染成 HTML 字符串
  local html = pandoc.write(pandoc.Pandoc({tbl}), "html")
  -- 去掉包裹的 <p> 或多余结构，只保留表格部分
  html = html:gsub("^%s*<p>", ""):gsub("</p>%s*$", "")
  -- 加 paper-table class（styles.css 的表格样式选择器，否则复杂表无边框、靠左）
  html = html:gsub("<table", '<table class="paper-table"', 1)
  return pandoc.RawBlock("html", html)
end

function Pandoc(doc)
  -- PDF/LaTeX: 保持原样（crossref 让路因为 tab- 前缀）
  if FORMAT == "latex" or FORMAT == "pdf" then
    return nil
  end

  -- HTML: 处理所有 raw LaTeX 表格块
  if FORMAT == "html" or FORMAT == "html5" then
    local bib = doc.meta and doc.meta["bibliography"]
    local bibstr = bib and pandoc.utils.stringify(bib) or nil

    local function process_blocks(blocks)
      local out = {}
      for _, b in ipairs(blocks) do
        if b.t == "RawBlock" and b.format == "latex"
          and (b.text:match("\\begin{table%*?}") or b.text:match("\\begin{tabular}")) then
          out[#out + 1] = convert_table(b, bibstr)
        elseif b.t == "Div" then
          b.content = pandoc.List(process_blocks(b.content))
          out[#out + 1] = b
        else
          out[#out + 1] = b
        end
      end
      return out
    end

    doc.blocks = pandoc.List(process_blocks(doc.blocks))
    return doc
  end

  return nil
end
