-- latex-tables.lua (v3) — 通用版
-- 
-- 核心能力：把 raw LaTeX 表格渲染为双格式
--   HTML: raw LaTeX 表格 → pandoc.read → Table AST → pandoc.write(html) → RawBlock("html")
--         直接输出 HTML 字符串，绕过 main.lua 对 Table 的 crossref 处理（它会吃掉 id）
--   PDF:  保持原样（crossref.lua 对 tab- 前缀只警告不拦截）
-- 
-- 用法（filters 里按名称引用，如 paper-tables）：
--   filters:
--     - paper-tables
--   format:
--     pdf:
--       paper-tables:
--         label-prefix: tab-      # 表格 label 前缀（默认 tab-，crossref 只处理 tbl-）
-- 
-- 注意：源文件里的表格 label 必须用 tab- 前缀（crossref.lua 只处理 tbl-）

-- 从 metadata 读取配置
local function get_config()
  local meta = pandoc.meta or {}
  local cfg = (meta["paper-tables"] and meta["paper-tables"]["pdf"]) or {}
  return {
    label_prefix = cfg["label-prefix"] or "tab-",
  }
end

function RawBlock(el)
  if el.format ~= "latex" then
    return nil
  end
  
  -- 只处理表格
  if not (el.text:match("\\begin{table%*?}") or el.text:match("\\begin{tabular}")) then
    return nil
  end
  
  -- PDF/LaTeX: 保持原样（crossref 让路因为 tab- 前缀）
  if FORMAT == "latex" or FORMAT == "pdf" then
    return nil
  end
  
  -- HTML: 解析成 Table AST，再渲染成 HTML 字符串
  if FORMAT == "html" or FORMAT == "html5" then
    -- 预处理：剥离 \cmidrule 行（Pandoc 不认识，会变成垃圾文本）
    local cleaned = el.text:gsub("\\cmidrule[^\n]*\n?", "")
    -- 勾叉：\cmark/\xmark 是 pifont 自定义命令，pandoc 的 LaTeX reader 不认识会丢弃 → 替换为 Unicode
    cleaned = cleaned:gsub("\\cmark%{%}?", "✓"):gsub("\\cmark", "✓")
    cleaned = cleaned:gsub("\\xmark%{%}?", "✗"):gsub("\\xmark", "✗")

    local doc = pandoc.read(cleaned, "latex")

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

    local tbl = find_table(doc.blocks)
    if tbl then
      -- 补 caption（Pandoc 的 LaTeX reader 会丢失它们）
      local cap_match = cleaned:match("\\caption%b{}")
      if cap_match then
        local caption = cap_match:sub(10, -2)  -- 去掉 "\caption{" 和 "}"
        local cap_ast = pandoc.read(caption, "latex")
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
  end
  
  return nil
end
