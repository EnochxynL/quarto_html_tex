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
  -- caption 从原文提取（后续剥离 table 外壳会移除 \caption 文本）
  local cap_match = el.text:match("\\caption%b{}")
  -- 预处理：剥离 \cmidrule 行（Pandoc 不认识，会变成垃圾文本）
  local cleaned = el.text:gsub("\\cmidrule[^\n]*\n?", "")

  -- 预处理：剥离 table/table* 浮动体外壳（实证 2026-08-31：quarto main.lua
  -- 之后的 pandoc.read latex reader 不解析浮动体 table 环境——整块变 Para
  -- 导致表格消失；组合表靠 resizebox 剥离侥幸成功，简单表直接暴露。只留
  -- 内核内容，caption/label 已从原文提取）
  cleaned = cleaned:gsub("\\begin{table%*?}%[?[^]]*%]?\n?", "")
  cleaned = cleaned:gsub("\\end{table%*?}\n?", "")
  cleaned = cleaned:gsub("\\caption%b{}\n?", "")
  cleaned = cleaned:gsub("\\label%b{}\n?", "")
  cleaned = cleaned:gsub("\\centering\n?", "")  -- main.lua 环境下与顶层 tabular 组合解析异常（Div>Para）

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

  -- minipage 宽度从 LaTeX 源读取（不猜测、不硬编码）：Pandoc 的 latex reader
  -- 把 minipage 解析成 Div(class="minipage") 但不保留宽度参数——宽度在
  -- 原文文本层提取，按文档顺序对应回 AST 的内层 div（外层载体 >1\textwidth
  -- 的跳过；宽度信息注入 div 的 style，styles.css 不再硬编码 33%）。
  -- 注意：l/c 列的宽度 LaTeX 端本来就不指定（内容自适应），HTML 端
  -- table-layout:auto 即忠实，无需列宽猜测；对齐由 Pandoc colspec 保留。
  local minipage_widths = {}
  for w in cleaned:gmatch("\\begin{minipage}[^\\]*{%s*([%d%.]+)\\textwidth}") do
    minipage_widths[#minipage_widths + 1] = tonumber(w)
  end
  local function is_minipage(b)
    for _, cls in ipairs(b.classes or {}) do
      if cls == "minipage" then return true end
    end
    return false
  end
  local function assign_mp_widths(blocks, idx)
    for _, b in ipairs(blocks) do
      if b.t == "Div" and is_minipage(b) then
        -- 容器检测：content 直接含其他 minipage div（外层载体）→ 加
        -- minipage-row class，CSS 用 flex 排版（消除 inline-block 空白间隙，
        -- 3×33% + 间隙 > 100% 会错误换行）；内层子表仍按注入宽度排布
        local has_child_mp = false
        for _, cb in ipairs(b.content or {}) do
          if cb.t == "Div" and is_minipage(cb) then has_child_mp = true end
        end
        if has_child_mp then
          b.classes = b.classes or {}
          b.classes[#b.classes + 1] = "minipage-row"
        end
        local w = minipage_widths[idx]
        idx = idx + 1
        if w and w <= 1 then
          b.attr = b.attr or pandoc.Attr()
          b.attr.attributes = b.attr.attributes or {}
          b.attr.attributes["style"] = "width: " .. math.floor(w * 1000 + 0.5) / 10 .. "%"
        end
      end
      if b.content then
        idx = assign_mp_widths(b.content, idx)
      end
    end
    return idx
  end
  assign_mp_widths(doc.blocks, 1)

  -- 表格内 \citep/\citet 等：子文档跑 citeproc（主文档 citeproc 不碰 RawBlock 字符串）
  if cleaned:match("\\cite") then
    doc = run_citeproc(doc, bibstr)
  end

  -- 补 caption（Pandoc 的 LaTeX reader 在某些结构下会丢失它们——组合表/嵌套
  -- minipage 时尤其；丢失则从原文重新解析，已有则覆盖为同一内容）；caption 内
  -- 的 \citep 同样过 citeproc。cap_match 已在 convert_table 开头从原文提取
  -- （table 外壳剥离会移除 \caption 文本）
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
  local aliases = {}
  if label then
    local tbl = find_table(doc.blocks)
    if tbl then
      tbl.attr = tbl.attr or pandoc.Attr()
      if tbl.attr.identifier == "" or not tbl.attr.identifier then
        tbl.attr.identifier = label
      end
    end
    -- 别名 label（组合表多 \label：如 SkillOpt 的 tab-transfer-all + cross-* ×3）：
    -- 正文可引用任一别名，全部映射到同一编号（html-ref-tbl 的 gmatch 收集
    -- HTML 里所有 id=，别名锚点保证 tab_nums[alias] 命中）
    for a in el.text:gmatch("\\label{([^}]+)}") do
      if a ~= label then aliases[#aliases + 1] = a end
    end
  end

  -- 整个子文档渲染成 HTML 字符串（保留 div.minipage 等嵌套结构，组合表的
  -- 多个子表一次输出；html-crossref.lua 按 RawBlock 粒度计数，组合表 = 1 个编号）
  local html = pandoc.write(doc, "html")
  -- 去掉包裹的 <p> 或多余结构，只保留表格部分
  html = html:gsub("^%s*<p>", ""):gsub("</p>%s*$", "")
  -- 加 bootstrap table class（与管道表一致——quarto 表格样式 = bootstrap .table，
  -- 用户拍板 2026-08-31：不自定义 class（paper-table 已废弃），遵守 bootstrap 规范，
  -- 复杂表与管道表同一样式源；caption-top 与 quarto 管道表一致）
  -- 全部 <table> 都加（组合表 resizebox+minipage 的多个子表各自独立成表，
  -- 只加第一个会让 (b)(c)... 子表裸奔无边框）
  html = html:gsub("<table", '<table class="caption-top table"')
  -- 组合表（多个 <table>）caption 归属修正：Pandoc 把 table* 的 caption 挂到
  -- 第一个子表（视觉上只出现在 (a) 下方）——移到整组子表之后（minipage-row
  -- 容器闭合 </div> 之后、div.table* 之内），作为独立 caption div
  -- （HTML 的 <caption> 元素只能在 table 内，容器级需换 div）
  local tbl_count = select(2, html:gsub("<table", "<table"))
  if tbl_count > 1 then
    local cs = html:find("<caption>", 1, true)
    if cs then
      local ce = html:find("</caption>", cs, true)
      if ce then
        local cap = html:sub(cs + 9, ce - 1)
        html = html:sub(1, cs - 1) .. html:sub(ce + 10)
        -- 找 minipage-row div 起点，数 <div>/</div> 配对到容器闭合
        local rs = html:find("minipage-row", 1, true)
        if rs then
          local ds = html:sub(1, rs):match(".*()<div")
          if ds then
            local depth = 1  -- minipage-row div 自身算一层
            local pos = ds + 4  -- 跳过自身 <div
            while true do
              -- 注意：查找起点是 pos 而非 pos+4——close 分支后 pos 已指向
              -- </div> 之后，pos+4 会跳过紧邻的下一个 <div（如 (b) 紧跟
              -- (a) 闭合），导致该子表 open 被跳过、闭合被误判为容器闭合
              local od = html:find("<div", pos, true)
              local cd = html:find("</div>", pos, true)
              if not od and not cd then break end
              if od and (not cd or od < cd) then
                depth = depth + 1
                pos = od + 4
              else
                depth = depth - 1
                pos = cd + 6
              end
              if depth == 0 then break end
            end
            html = html:sub(1, pos - 1) .. '<div class="table-caption">' .. cap .. "</div>" .. html:sub(pos)
          else
            -- minipage-row 前的 <div 起点未找到：追加到末尾
            html = html .. '<div class="table-caption">' .. cap .. "</div>"
          end
        else
          -- 无 minipage-row（简单并列 minipage，如 2 个子表无外层载体）：
          -- caption 已从 table 内移出（上面 html:sub 删除），追加到末尾
          -- （避免丢失——实证 2026-08-31：_h2test 组合表 rs=nil 导致 caption 消失）
          html = html .. '<div class="table-caption">' .. cap .. "</div>"
        end
      end
    end
  end
  -- 别名 label 锚点（正文引用任一别名 → 同一编号；html-ref-tbl gmatch 收集）
  for _, a in ipairs(aliases) do
    html = html .. '<span id="' .. a .. '" class="table-alias"></span>'
  end
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
