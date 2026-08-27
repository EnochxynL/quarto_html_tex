-- html-latex-tables.lua — HTML 方案：raw LaTeX 表格 → RawBlock("html")
--
-- 核心能力：把 {=latex} 复杂表格（\multicolumn、\shortstack、\cmidrule）渲染为双格式
--   HTML: raw LaTeX 表格 → pandoc.read → Table AST → pandoc.write(html) → RawBlock("html")
--         直接输出 HTML 字符串，绕过 main.lua 对 Table 的 crossref 处理（它会吃掉 id）
--   PDF:  保持原样（crossref.lua 对 tab- 前缀只警告不拦截），编号走 LaTeX 原生
--
-- 方案要点：
--   1) 元素回调拿不到 pandoc.meta（nil/空表），只有 Pandoc(doc) 的 doc.meta 有完整
--      metadata——因此用 Pandoc() 回调（与 html-md-tables.lua 等统一排版）
--   2) 表格内 \citep{key} 经 pandoc.read 解析为 Cite，内部 write 无 citeproc →
--      HTML writer 输出空 span（静默消失）。修复：表格子文档注入 bibliography 后调
--      pandoc.utils.citeproc（pcall 保护），\citep{key} → (Starace et al. 2025)
--   3) \cmidrule 行剥离（Pandoc 不认识，会变成垃圾文本）
--   4) 自定义宏（如 \ara{}）pandoc 不认识会丢弃——通过 metadata 配置注入：
--      html-helper:
--        latex-macros: |
--          \newcommand{\ara}{\textsc{Ara}}
--      pandoc.read 前拼在表格文本开头（latex_macros extension 展开，通用方案，
--      不硬编码任何具体宏；\cmark/\xmark 有内置预处理，不必声明，声明也无害）
--
-- 用法（filters 里按名称引用，如 html-helper）：
--   filters:
--     - html-helper
if FORMAT ~= "html" and FORMAT ~= "html5" then
  return {}
end

-- 从 doc.meta 读取配置（嵌套优先、平铺回退，见 README 踩坑 13）
-- latex-macros 的 YAML 块标量（|）在 pandoc 3 解析为 Blocks 类型（MetaBlocks，
-- 无 t 字段，ipairs 直接遍历出 RawBlock("tex")）；stringify 对 RawBlock 返回空
-- ——需手动提取 RawBlock 文本
local function read_config(meta)
  local pt = meta["html-helper"] or meta["paper-tables"] or {}
  local pdf = pt["pdf"] or {}
  local v = pdf["latex-macros"] or pt["latex-macros"]
  if v == nil then return "" end
  local typ = pandoc.utils.type(v)
  if typ == "Blocks" or typ == "MetaBlocks" then
    local parts = {}
    for _, b in ipairs(v) do
      if b.t == "RawBlock" and (b.format == "latex" or b.format == "tex") then
        parts[#parts + 1] = b.text
      elseif b.t == "Para" or b.t == "Plain" then
        parts[#parts + 1] = pandoc.utils.stringify(b)
      end
    end
    return table.concat(parts, "\n")
  end
  local s = pandoc.utils.stringify(v)
  return s:gsub("^%s+", ""):gsub("%s+$", "")
end

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

-- 剥离行首 % 注释（LaTeX 的 % 注释会吃掉换行，把后续命令和上一行合并，
-- 导致 pandoc 解析错位——实测 transfer_all 的 (a) 段头整行丢失）。
-- 只删行首注释，不动数据里的转义 \%（如 20\% train）
local function strip_line_comments(s)
  local out = {}
  for line in s:gmatch("([^\n]*)\n?") do
    if not line:match("^[ \t]*%%") then
      out[#out + 1] = line
    end
  end
  return table.concat(out, "\n")
end

-- 单个 latex 表格块 → RawBlock("html")
local function convert_table(el, bibstr, macros)
  -- 预处理：剥离 \cmidrule 行（Pandoc 不认识，会变成垃圾文本）
  local cleaned = el.text:gsub("\\cmidrule[^\n]*\n?", "")

  -- 预处理：剥离 \resizebox{..}{..}{内容} 外壳（Pandoc 对 resizebox 直接放弃
  -- 解析整个表格 → 空 div；内容保留，minipage 结构由 Pandoc 解析为 div 嵌套）
  cleaned = cleaned:gsub("\\resizebox%b{}%b{}%b{}", function(m)
    local inner = m:match("^\\resizebox%b{}%b{}(%b{})$")
    if not inner then return m end
    return inner:sub(2, -2)
  end)

  -- 剥离行首 % 注释（在 resizebox 剥离之后，覆盖其内容里的注释行）
  cleaned = strip_line_comments(cleaned)

  -- 预处理：\multicolumn{N}{align}{内容} 展开为内容文本（Pandoc 不认跨列，
  -- 会丢弃整个单元格内容；展开后内容保留在首列，其余列由 Pandoc 补空）
  cleaned = cleaned:gsub("\\multicolumn%b{}%b{}%b{}", function(m)
    local inner = m:match("^\\multicolumn%b{}%b{}(%b{})$")
    if not inner then return m end
    return inner:sub(2, -2)
  end)

  -- 自定义宏注入（latex_macros extension 展开；\ara/\cmark/\xmark 等由
  -- format.html.html-helper.latex-macros 配置声明，不硬编码；无配置时 prefix 为空）
  local prefix = (macros ~= "") and (macros .. "\n") or ""
  local doc = pandoc.read(prefix .. cleaned, "latex")

  -- 表格内 \citep/\citet 等：子文档跑 citeproc（主文档 citeproc 不碰 RawBlock 字符串）
  if cleaned:match("\\cite") then
    doc = run_citeproc(doc, bibstr)
  end

  -- 补 caption（Pandoc 的 LaTeX reader 在某些结构下会丢失它们——组合表/嵌套
  -- minipage 时尤其；丢失则从原文重新解析，已有则覆盖为同一内容）；caption 内
  -- 的 \citep 同样过 citeproc
  local cap_match = cleaned:match("\\caption%b{}")
  if cap_match then
    local caption = cap_match:sub(10, -2)  -- 去掉 "\caption{" 和 "}"
    local cap_ast = pandoc.read(prefix .. caption, "latex")  -- 宏定义同样注入
    if caption:match("\\cite") then
      cap_ast = run_citeproc(cap_ast, bibstr)
    end
    if #cap_ast.blocks > 0 and cap_ast.blocks[1].content then
      local tbl = find_table(doc.blocks)
      if tbl then
        tbl.caption = pandoc.Caption(pandoc.Inlines(cap_ast.blocks[1].content))
      end
    end
  end

  -- 补 label（Pandoc 对 table 环境内的 \label 通常已转 id；组合表嵌套时
  -- 可能丢失——找到第一个表格补上，跨列组合表 id 落在最外层容器）
  local label = el.text:match("\\label{([^}]+)}")
  if label then
    local tbl = find_table(doc.blocks)
    if tbl then
      tbl.attr = tbl.attr or pandoc.Attr()
      if tbl.attr.identifier == "" or not tbl.attr.identifier then
        tbl.attr.identifier = label
      end
    end
  end

  -- 整个子文档渲染成 HTML 字符串（保留 div.minipage 等嵌套结构，组合表的
  -- 多个子表一次输出；html-crossref.lua 按 RawBlock 粒度计数，组合表 = 1 个编号）
  local html = pandoc.write(doc, "html")
  -- 去掉包裹的 <p> 或多余结构，只保留表格部分
  html = html:gsub("^%s*<p>", ""):gsub("</p>%s*$", "")
  -- 加 paper-table class（styles.css 的表格样式选择器，否则复杂表无边框、靠左）
  html = html:gsub("<table", '<table class="paper-table"', 1)
  return pandoc.RawBlock("html", html)
end

function Pandoc(doc)
  local bib = doc.meta and doc.meta["bibliography"]
  local bibstr = bib and pandoc.utils.stringify(bib) or nil
  local macros = read_config(doc.meta)

  local function process_blocks(blocks)
    local out = {}
    for _, b in ipairs(blocks) do
      -- format 兼容 "latex"（include 文件）与 "tex"（主文档 {=latex} 块，
      -- 实测两者都会出现——踩坑 19 ③）
      if b.t == "RawBlock" and (b.format == "latex" or b.format == "tex")
        and (b.text:match("\\begin{table%*?}") or b.text:match("\\begin{tabular}")) then
        out[#out + 1] = convert_table(b, bibstr, macros)
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
