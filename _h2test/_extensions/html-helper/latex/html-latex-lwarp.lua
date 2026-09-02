-- html-latex-lwarp.lua — lwarp 子页面通道（复杂 latex 块 → 语义化子页面）
--
-- 设计哲学（用户拍板 2026-09-01，替代 tex4ht 通道）：lwarp 在 TeX 宏层
-- 重定义并直接输出 HTML5 语义结构（figure/ul/li），而非 tex4ht 的 DVI
-- 层排版模拟（ALCitem span 堆/pt 宽度断言/字体 class）。数学走原生
-- mathjax 选项（\(...\) 文本由主页面 MathJax 渲染）——\mathrm bug、
-- 位图 base64、字体 class 清洗等 tex4ht 补丁全部消失；块内自引用
-- （label 同块）由 aux 跨遍原生解析为 <a href> 链接。
--
-- 职责：
--   1) FORMAT 守卫：PDF 端 return {}——{=latex} 原样走 LaTeX 原生编译
--   2) RawBlock(tex) 非表格块（任意 latex 环境——计数器注入与引用
--      编号由 html-latex-counters.lua 提供，本文件不持有环境/算法知识）：
--      a. 生成独立 block.tex：\usepackage[mathjax]{lwarp}（先于一切）
--         + latex-packages（文档层声明，html-helper: latex-packages）
--         + latex-macros + \setcounter（counters.lua 的起始值，\@ifundefined
--         保护——计数器不存在则跳过）
--      b. 双编译：lualatex block.tex（打印版，lwarp 自动生成
--         block_html.tex）→ lualatex block_html.tex（HTML 版，
--         生成 block_html.html）→ pdftotext 提取——工作目录 .quarto/lwarp/
--      c. 剥壳取 <main class="bodycontainer"> 内容 + lwarp.css
--         作用域化内联 → <div class="lwarp-block">
--      失败回退：可见警告块（div.lwarp-failed + 原 LaTeX 源码）
--   3) 正文 \ref{label}（RawInline tex / Math / Link）→ <a href="#label">N</a>
--   4) 块内 \ref{X}（跨文档引用协议）：
--      数学外：\ref 原样保留——块内 label 由真实 aux 解析（lwarp 原生
--        链接）；块外 label 由 preamble 注入 \newlabel 假条目喂值
--        （显示文本=@@REF:X@@ 占位、href=#X），lwarp 原生输出
--        <a href="#X">@@REF:X@@</a>——Pandoc 回调第二遍填编号
--      数学内：一律 @@REF:{X}@@ 纯文本占位（lwarp mathjax 模式
--        detokenize 不执行 \ref；数学内不能放 HTML 链接）——第二遍
--        填纯文本编号
--      第二遍解析（refs 齐备——counters.lua 全文编号，前向引用可解析）：
--        已知 label → 编号；未知 → [X] 占位（保留名可诊断）

-- 数学预处理（只作用于 lwarp 编译副本 block.tex——qmd 源不动、PDF 端不动）：
--   \ref：数学段外原样保留（lwarp 原生 + \newlabel 假条目注入）、
--   数学段内一律 @@REF:{X}@@（detokenize 不执行 \ref）——返回 (body, ref_out)
-- 文本命令进数学（\Call 等）：不预处理展开——extract_mathjax_macros
-- 从宏包源提取定义 → MathJax 翻译（\newcommand）注入主页面 body 开头，
-- MathJax 侧认识命令后原样渲染（视觉实证通过 2026-09-02）
--
-- 边界（与其它模块解耦）：
--   - 表格块跳过——html-latex-tables.lua 处理
--   - 宏包不从块内容猜（detect_packages 已删）——块编译所需宏包由
--     文档层声明（html-helper: latex-packages，与 latex-macros 平行）；
--     项目用 lwarp 不支持的包（老式 algorithmic 等）→ 编译失败走
--     可见警告块——适配发生在项目层（换包/换写法），filter 不强行适配
--
-- 已知限制：
--   - 每次渲染重新编译（无缓存）；lualatex 无 tex4ht 死锁历史
--   - lwarp.css 全量作用域化内联（1871 行，块多时冗余——后续按
--     实际使用的 class 筛选；lwarp 输出单 css：<link href="lwarp.css">）
--   - lwarp 双编译（打印版 + HTML 版）比 make4ht 单编译多一次
--     lualatex；块小文档秒级
--   - lwarp 的 <div data-nosnippet>（\newcommand 定义输出区，供
--     MathJax 读取）保留在剥壳结果内——删了会丢宏定义
--   - lwarp-algorithmicx 包装缺陷（2026-09-02 实证）：嵌套 \State
--     （For/While 内）的行号 span 输出在行尾而非行首（顶层行正常）——
--     lwarp 对 algorithmicx 嵌套 item 的生成问题，引擎层缺陷非 filter
--     职责；filter 不修（不背算法结构知识）——CSS/项目层可选缓解
if FORMAT ~= "html" and FORMAT ~= "html5" then
  return {}
end

local CACHE = ".quarto/lwarp"
local BLOCK_PREFIX = "lwarp-block"

-- 表格块：跳过（html-latex-tables.lua 的领地）
local function is_table_block(text)
  return text:find("\\begin{tabular", 1, true) ~= nil
      or text:find("\\begin{table", 1, true) ~= nil
end

-- 编译候选判定：非表格 + 含 \begin{ENV} 环境结构——{=latex} 块分两类：
--   内容块（算法/定理/图——\begin{ENV} 自包含结构）→ 编译
--   PDF 控制片段（\FloatBarrier/\bibliography/\thispagestyle 等无 \begin
--   的命令序列——给 LaTeX 排版用，HTML 端无意义）→ 跳过（结构判据，
--   非猜内容）
local function is_compile_candidate(text)
  if is_table_block(text) then return false end
  return text:find("\\begin{", 1, true) ~= nil
end

-- 提取全部 label（复合块可含多 label——lwarp 原生为每个 \label 输出
-- <a id> 锚点，故不需要容器 id/别名 span；labels 表用于构建 labelset
-- （数学外引用本块 label 时无需注入假条目——真实 aux 自解析）
local function extract_labels(text)
  local labels = {}
  for lab in text:gmatch("\\label{([^}]+)}") do
    labels[#labels + 1] = lab
  end
  return labels
end

-- 宏包声明：从 doc.meta 读取 latex-packages（html-helper: latex-packages:
-- [pkg1, pkg2]——块独立编译所需宏包由文档层声明，不从块内容猜；
-- 与 latex-macros 平行）。pandoc 3 MetaList → 字符串数组
local function read_packages(meta)
  local pt = meta["html-helper"] or {}
  local v = pt["latex-packages"]
  if v == nil then return {} end
  local typ = pandoc.utils.type(v)
  if typ == "List" or typ == "MetaList" then
    local out = {}
    for _, item in ipairs(v) do
      out[#out + 1] = pandoc.utils.stringify(item)
    end
    return out
  end
  return { pandoc.utils.stringify(v) }
end

-- 从 doc.meta 读取 latex-macros（嵌套优先、平铺回退，模式同 html-latex-tables；
-- pandoc 3 块标量 → MetaBlocks，手动提取 RawBlock 文本）
local function read_config(meta)
  local pt = meta["html-helper"] or {}
  local v = pt["latex-macros"]
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
  return pandoc.utils.stringify(v)
end

-- 平衡花括号提取（深度计数，支持嵌套——\Call 的 args 里可能嵌
-- D_\text{sel} 等含花括号的数学；[^}]* 单层匹配会截断，实证括号错乱）
local function balanced_brace(s)
  local depth = 0
  for i = 1, #s do
    local c = s:sub(i, i)
    if c == "{" then
      depth = depth + 1
    elseif c == "}" then
      depth = depth - 1
      if depth == 0 then return s:sub(2, i - 1), s:sub(i + 1) end
    end
  end
  return nil, nil
end

-- \ifthenelse{C}{A}{B} → B（MathJax 宏定义无条件；balanced 取第三组——
-- \Call 族形态：\ifthenelse{\equal{#2}{}}{}{(#2)} 的空参无括号是边缘，
-- 取 else 分支恒输出括号）
local function strip_ifthenelse(s)
  local out, pos = {}, 1
  while true do
    local idx = s:find("\\ifthenelse", pos, true)
    if not idx then
      out[#out + 1] = s:sub(pos)
      break
    end
    out[#out + 1] = s:sub(pos, idx - 1)
    local rest = s:sub(idx + #"\\ifthenelse")
    local g1, r1 = balanced_brace(rest)
    local g2, r2 = balanced_brace(r1)
    local g3, r3 = balanced_brace(r2)
    if not g3 then
      out[#out + 1] = s:sub(idx) -- 解析失败：保原样（MathJax 侧红字，不崩）
      break
    end
    out[#out + 1] = g3
    pos = #s - #r3 + 1
  end
  return table.concat(out)
end

-- MathJax 宏自动注入（零显式配置——与 counters.lua 同构的扫描发现，
-- 用户拍板 2026-09-02）：
-- 背景：\Call 等文本命令被写进数学时，lwarp 数学文本 detokenize 原样
-- 给 MathJax——不认识红字。方案：扫描全文 RawBlock 数学内容（$...$）
-- 收集 \CMD——对每个命令在"用户定义源"（块内/latex-macros 的
-- \newcommand/\def）与"latex-packages 声明包的源"查定义——找到则翻译
-- 成 MathJax tex.macros 注入。
-- 定义驱动过滤：MathJax 内建命令（\mathrm/\gets/\mathcal…）在定义源
-- 找不到 → 自动跳过——无需 MathJax 命令白名单。
-- 翻译规则：\ifthenelse 剥离（取 else 分支）+ 无参别名展开
-- （\textproc→\textsc——查同源定义）；翻译后仍含未知命令（如 \textsc
-- MathJax 侧不支持时）由 MathJax 渲染暴露——降级不崩。
-- 注入机制（实证 2026-09-02）：MathJax 4 不处理文档文本中的
-- \newcommand；tex.macros 须加载前配置——filter 只动 body，故输出
-- body 开头同步 <script>window.MathJax=...>（同步 script 先于 head 的
-- defer tex-chtml.js 执行）。
-- 返回 script 文本（无命令/无定义/翻译失败返回空——红字降级）

-- 收集文本 $...$ 数学段里的 \CMD 控制序列
local function collect_math_cmds(text, cmds)
  local pos = 1
  while true do
    local d1 = text:find("%$", pos)
    if not d1 then break end
    local d2 = text:find("%$", d1 + 1)
    if not d2 then break end
    for cmd in text:sub(d1 + 1, d2 - 1):gmatch("\\([a-zA-Z]+)") do
      cmds[cmd] = true
    end
    pos = d2 + 1
  end
end

-- 平衡提取（从 src 的 open 位置数深度到匹配 }——返回内部内容）
local function take_balanced(src, open)
  local depth, k = 0, open
  while k <= #src do
    local c = src:sub(k, k)
    if c == "{" then depth = depth + 1
    elseif c == "}" then
      depth = depth - 1
      if depth == 0 then return src:sub(open + 1, k - 1) end
    end
    k = k + 1
  end
  return nil
end

-- 收集用户 \newcommand 定义（{name, nargs=nil|N, body}——body 平衡提取）
-- 形态：\newcommand{\X}[N]{body} / \newcommand\X[N]{body} / \newcommand{\X}{body}
local function collect_user_defs(text, defs)
  local pos = 1
  while true do
    local i = text:find("\\newcommand", pos, true)
    if not i then break end
    local j = i + #"\\newcommand"
    if text:sub(j, j) == "*" then j = j + 1 end -- \newcommand*
    local name, rest
    if text:sub(j, j) == "{" then
      local nb = text:find("}", j + 1, true)
      if not nb then break end
      name = text:sub(j + 2, nb - 1) -- 剥 {\X
      rest = text:sub(nb + 1)
    else
      local m = text:sub(j):match("^\\([a-zA-Z]+)")
      if not m then break end
      name = m
      rest = text:sub(j + 1 + #m)
    end
    local nargs
    local nb = rest:match("^%[([^%]]+)%]")
    if nb then nargs = tonumber(nb) end
    local open = rest:find("{", 1, true)
    local body = open and take_balanced(rest, open)
    if body then
      defs[name] = { nargs = nargs, body = body }
      pos = i + 1
    else
      break
    end
  end
end

-- 包源找数学命令的定义（同时收集包内全部定义——别名展开用）
-- 返回 defs（name → {nargs, body}）——只含 want 命令 + 无参别名候选
local function collect_pkg_defs(pkg, want, out_defs)
  local p = io.popen("kpsewhich " .. pkg .. ".sty 2>nul")
  if not p then return end
  local path = p:read("*l")
  p:close()
  if not path or path == "" then return end
  local f = io.open(path, "r")
  if not f then return end
  local src = f:read("*a")
  f:close()
  -- 各类定义形态：\algnewcommand\X[N]{...} / \newcommand\X[N]{...} /
  -- \newcommand{\X}[N]{...} / \def\X#1#2{...}
  local function try_find(prefix)
    local pos = 1
    while true do
      local i = src:find(prefix, pos, true)
      if not i then break end
      local j = i + #prefix
      if src:sub(j, j) == "*" then j = j + 1 end
      local name, rest
      if src:sub(j, j) == "{" then
        local nb = src:find("}", j + 1, true)
        if not nb then break end
        name = src:sub(j + 2, nb - 1)
        rest = src:sub(nb + 1)
      else
        local m = src:sub(j):match("^\\([a-zA-Z]+)")
        if not m then pos = i + 1 break end
        name = m
        rest = src:sub(j + 1 + #m)
      end
      local nargs
      local nb2 = rest:match("^%[([^%]]+)%]")
      if nb2 then nargs = tonumber(nb2) end
      local open = rest:find("{", 1, true)
      if open then
        local body = take_balanced(rest, open)
        if body then
          out_defs[name] = { nargs = nargs, body = body }
        end
      end
      pos = i + 1
    end
  end
  try_find("\\newcommand")
  try_find("\\algnewcommand")
  try_find("\\providecommand")
  try_find("\\def\\")
end

-- 内核文本字体命令 → MathJax \text 内等价映射（实证 2026-09-02：
-- \textsc 在 MathJax 渲染为松散字面 \textsc𝐸𝑣𝑎𝑙𝑢𝑎𝑡𝑒——官方 unlikely to
-- support——smallcaps 无可用等价 → 正体 \text 近似（smallcaps 本质是
-- 正体字形）；仅收录实证失败项——其余内核字体命令（\textbf/\textit/
-- \textrm/\textsf/\texttt）MathJax 支持，无需映射——零猜测）
local TEXT_FONT_MAP = {
  textsc = "text",
}

-- 翻译文本字体：body 里 \textsc{X} → \text{X}
local function translate_text_fonts(body)
  for from, to in pairs(TEXT_FONT_MAP) do
    body = body:gsub("\\" .. from .. "{", "\\" .. to .. "{")
  end
  return body
end

-- 无参别名展开：\A{X} → A 的定义体{X}（A 无参且定义体是纯命令）
local function expand_aliases(body, defs)
  local changed = true
  while changed do
    changed = false
    for name, d in pairs(defs) do
      if not d.nargs and d.body:match("^%\\[a-zA-Z]+$") then
        local pat = "\\" .. name .. "{"
        if body:find(pat, 1, true) then
          body = body:gsub(pat, d.body .. "{", 1)
          changed = true
        end
      end
    end
  end
  return body
end

-- 主流程：扫描全文 → 收集数学命令 + 用户定义 → 包源补定义 → 翻译注入
local function extract_mathjax_macros(doc)
  local cmds, defs = {}, {}
  local packages = {}
  for _, p in ipairs(read_packages(doc.meta)) do packages[p] = true end
  -- latex-macros（用户宏定义区）
  local macros_tex = read_config(doc.meta)
  collect_user_defs(macros_tex, defs)
  -- 全文 RawBlock
  for _, blk in ipairs(doc.blocks) do
    if blk.t == "RawBlock" and (blk.format == "tex" or blk.format == "latex") then
      collect_math_cmds(blk.text, cmds)
      collect_user_defs(blk.text, defs)
    end
  end
  -- 需要定义的命令 = 数学里出现且用户定义没有的
  local need = {}
  for cmd in pairs(cmds) do
    if not defs[cmd] then need[cmd] = true end
  end
  -- 包源补定义（latex-packages 声明驱动）
  if next(need) then
    for pkg in pairs(packages) do
      collect_pkg_defs(pkg, need, defs)
    end
  end
  -- 翻译注入（只对数学里出现的命令）
  local macros = {}
  for cmd in pairs(cmds) do
    local d = defs[cmd]
    if d and d.body then
      local body = expand_aliases(d.body, defs)
      body = translate_text_fonts(body)
      body = strip_ifthenelse(body)
      if body ~= "" and not body:match("^\\[a-zA-Z]+$") then
        -- 空参命令或无参（如 \textproc 定义体 \textsc——纯命令）跳过：
        -- 无参命令 MathJax 宏无意义（除非定义体是文本）
        local nargs = d.nargs or 0
        local js_body = body:gsub("\\", "\\\\")
        macros[#macros + 1] = '"' .. cmd .. '": ["' .. js_body .. '", ' .. nargs .. "]"
      end
    end
  end
  if #macros == 0 then return "" end
  return "<script>window.MathJax = {tex: {macros: {" .. table.concat(macros, ", ")
    .. "}}};</script>"
end

-- 数学段外 \ref 处理：\ref 一律保留原样（lwarp 原生处理）——块内
-- label 由真实 aux 解析（<a href="#X">编号</a>）；块外 label 由
-- preamble 预注入的 \newlabel 假条目解析（编号=@@REF 显示文本占位、
-- href=label 真名——lwarp 原生输出 <a href="#X">@@REF:X@@</a>，
-- 第二遍把显示文本换成编号）。块外被引用 label 收集进 ref_out_labels
-- 供 build_tex 注入（探针实证：三条目 LaTeX 层/@lwarp/@lwarp@image）
local function refs_outside(seg, labelset, ref_out)
  return seg:gsub("%\\ref%s*{([^}]+)}", function(ref)
    if not (labelset and labelset[ref]) then
      ref_out[ref] = true -- 块外 label：注入假条目（去重）
    end
    return "\\ref{" .. ref .. "}" -- 原样保留（块内外都走 lwarp 原生）
  end)
end

-- 数学段内（$...$）\ref：一律占位 @@REF:{X}@@——lwarp mathjax 模式
-- 数学内容 detokenize 原样给 MathJax，\ref 不被 LaTeX 执行（实证：
-- \ref {alg-test2} 原样进数学文本 → MathJax 红字）；数学文本里
-- { } 保留（无分组吞），第二遍按带花括号形态解析。数学内不能放
-- HTML 链接（MathJax 不渲染 <a>），第二遍输出纯文本编号
local function refs_inside(seg)
  return seg:gsub("%\\ref%s*{([^}]+)}", "@@REF:{%1}@@")
end

-- 数学预处理（只作用于 lwarp 编译副本 block.tex——qmd 源不动、PDF 端不动）：
--   \ref：数学段外原样保留（lwarp 原生 + \newlabel 注入）、数学段内
--   一律 @@REF:{X}@@（MathJax 不执行 \ref）——返回 (body, ref_out)
-- 文本命令进数学（\Call 等）不再预处理展开——MathJax 宏注入
-- （extract_mathjax_macros，主页面级）让 MathJax 侧认识命令
local function math_preprocess(body, labelset)
  local ref_out = {}
  -- $...$ 数学段切分（算法块实证用行内数学；\\(...\\) 形态后续扩展）
  local out = {}
  local pos = 1
  while true do
    local d1 = body:find("%$", pos)
    if not d1 then
      out[#out + 1] = refs_outside(body:sub(pos), labelset, ref_out)
      break
    end
    out[#out + 1] = refs_outside(body:sub(pos, d1 - 1), labelset, ref_out)
    local d2 = body:find("%$", d1 + 1)
    if not d2 then
      out[#out + 1] = body:sub(d1)
      break
    end
    out[#out + 1] = refs_inside(body:sub(d1, d2))
    pos = d2 + 1
  end
  return table.concat(out), ref_out
end

-- 组装独立 .tex：lwarp 必须最先加载（\LWR@ProvidesPackagePass 包装
-- 机制需要先于目标包）；latex-packages（文档层声明）随后；计数器注入
-- = 全文编号对齐（值来自 html-latex-counters.lua——本文件不持有任何
-- 环境/计数器知识）；\@ifundefined 保护：计数器实际不存在（float 惯例
-- 误判，如裸 algorithmic）则跳过注入——块从 1 编号，不崩
local function build_tex(body, counter_name, counter_start, macros, ref_out, packages)
  local t = { "\\documentclass{article}", "\\usepackage[mathjax]{lwarp}" }
  for _, p in ipairs(packages or {}) do
    t[#t + 1] = "\\usepackage{" .. p .. "}"
  end
  if macros and macros ~= "" then
    t[#t + 1] = macros
  end
  if counter_name and counter_name ~= "" and counter_start and counter_start > 0 then
    -- makeatletter：\@ifundefined 含 @；\c@NAME 是计数器的内部宏
    t[#t + 1] = "\\makeatletter\\@ifundefined{c@" .. counter_name .. "}{}{\\setcounter{"
      .. counter_name .. "}{" .. counter_start .. "}}\\makeatother"
  end
  -- 块外引用 label 的假条目（唯一性保证：ref_out 是 set）
  -- @lwarp 条目的 fileref（第三参数）固定用 block（BaseJobname）——
  -- 实证：fileref 用 label 名时，含数字的 label（alg-test2）会被 lwarp
  -- 的 \LWR@htmlsectionfilename 当文件编号解析（显示 2 而非占位）；
  -- 剥壳时 href 统一改 #label，文件名部分无所谓
  for lab in pairs(ref_out or {}) do
    t[#t + 1] = "\\newlabel{" .. lab .. "}{{@@REF:{" .. lab .. "}@@}{1}{}{" .. lab .. "}{}}"
    t[#t + 1] = "\\newlabel{" .. lab .. "@lwarp}{{" .. lab .. "}{1}{block}{}{}}"
    t[#t + 1] = "\\newlabel{" .. lab .. "@lwarp@image}{{0}{0}{}{}{}}"
  end
  t[#t + 1] = "\\begin{document}"
  t[#t + 1] = body
  t[#t + 1] = "\\end{document}"
  return table.concat(t, "\n")
end

-- 确保目录存在（逐级创建——cmd 的 mkdir 不递归；.quarto 在 filter
-- 阶段可能尚未创建；已存在的目录 mkdir 报错但 2>nul 吞掉，最终 probe 验证）
local function ensure_dir(path)
  if io.open(path .. "/.probe", "w") ~= nil then return true end
  local acc = ""
  for p in path:gmatch("[^/]+") do
    acc = acc == "" and p or (acc .. "/" .. p)
    os.execute("mkdir " .. acc:gsub("/", "\\") .. " 2>nul")
  end
  return io.open(path .. "/.probe", "w") ~= nil
end

-- 从 open_pos 的 { 开始深度计数找匹配的 }（@media/@supports 嵌套块提取）
local function find_matching(css, open_pos)
  local depth = 0
  for i = open_pos, #css do
    local c = css:sub(i, i)
    if c == "{" then
      depth = depth + 1
    elseif c == "}" then
      depth = depth - 1
      if depth == 0 then return i end
    end
  end
  return nil
end

-- css 作用域化（lwarp 版——tex4ht 版同款逻辑，前缀参数化）：
-- lwarp.css 是文档级（body/html 裸选择器），内联后污染主页面——
-- body/html 级规则丢弃（子页面无 body），其余选择器加 .lwarp-block 前缀；
-- @media/@supports 块内部递归作用域化（lwarp.css 实证含
-- @supports (display: grid){ body{overflow-y...} }——原样保留会污染）
local function scope_css(css, prefix)
  -- 剥离注释（/* */）——lwarp.css 在 @media/@supports 前带注释头
  -- （/* Page layout */ @supports ...），不剥则 ^@ 匹配失败、@块内
  -- body 规则漏网（实证：body{overflow-y} 污染主页面）
  css = css:gsub("/%*.-%*/", "")
  local out = {}
  local pos = 1
  while pos <= #css do
    local open = css:find("{", pos)
    if not open then break end
    local close = find_matching(css, open)
    if not close then break end
    local sel = css:sub(pos, open - 1)
    local decl = css:sub(open + 1, close - 1)
    sel = sel:gsub("%s+", " ")
    sel = sel:gsub("^%s+", "") -- 注释剥离后开头残留空白会挡 ^@/^body 匹配
    if sel:match("^body") or sel:match("^html") then
      -- body/html 级规则丢弃（子页面无 body 元素）
    elseif sel:match("^@") then
      -- @media/@supports 块：内部规则递归作用域化（body 级随之丢弃）
      out[#out + 1] = sel .. "{\n" .. scope_css(decl, prefix) .. "\n}"
    else
      local prefixed = {}
      for s in sel:gmatch("[^,]+") do
        s = s:gsub("^%s+", "")
        prefixed[#prefixed + 1] = "." .. prefix .. " " .. s
      end
      out[#out + 1] = table.concat(prefixed, ", ") .. "{" .. decl .. "}"
    end
    pos = close + 1
  end
  return table.concat(out, "\n")
end

-- 编译块 → 子页面 HTML；失败返回 nil（调用方走可见警告块）
-- labels：本块全部 label（块内 \ref 解析用——lwarp 原生锚点已输出）
-- packages：文档层声明的宏包（latex-packages）
-- counter_name/counter_start：计数器注入（html-latex-counters.lua 提供）
local function compile_block(body, counter_name, counter_start, macros, labels, packages)
  if not ensure_dir(CACHE) then
    io.stderr:write("[html-latex-lwarp] mkdir " .. CACHE .. " failed\n")
    return nil
  end

  local tex_path = CACHE .. "/block.tex"
  local f = io.open(tex_path, "w")
  if not f then return nil end
  -- 块内 label 集合（labelset）：数学外引用本块 label 时保留原样走
  -- lwarp 原生（真实 aux），不注入假条目
  local labelset = {}
  if labels then
    for _, lab in ipairs(labels) do labelset[lab] = true end
  end
  local body_pp, ref_out = math_preprocess(body, labelset)
  f:write(build_tex(body_pp, counter_name, counter_start, macros, ref_out, packages))
  f:close()

  -- 双编译：打印版（lwarp 在 \end{document} 写 block_html.tex +
  -- lwarpmk.conf）→ HTML 版（写 block_html.html + block_html.css）
  local ok = os.execute("cd " .. CACHE .. " && lualatex -interaction=nonstopmode block.tex >nul 2>&1")
  if not ok then
    io.stderr:write("[html-latex-lwarp] lualatex (print) failed\n")
    return nil
  end
  if not io.open(CACHE .. "/block_html.tex") then
    io.stderr:write("[html-latex-lwarp] lualatex (print) produced no _html.tex\n")
    return nil
  end
  ok = os.execute("cd " .. CACHE .. " && lualatex -interaction=nonstopmode block_html.tex >nul 2>&1")
  if not ok then
    io.stderr:write("[html-latex-lwarp] lualatex (html) failed\n")
    return nil
  end
  -- lwarp 把 HTML 源码嵌入 block_html.pdf 的不可见文本层——需
  -- pdftotext -layout 提取成 .html（lwarpmk.lua:388 同款命令；
  -- lwarp v0.922 架构：打印层 + HTML 文本层共用一份 PDF）
  ok = os.execute("cd " .. CACHE .. " && pdftotext -enc UTF-8 -nopgbrk -layout block_html.pdf block_html.html >nul 2>&1")
  if not ok then
    io.stderr:write("[html-latex-lwarp] pdftotext extraction failed\n")
    return nil
  end

  local html_file = io.open(CACHE .. "/block_html.html")
  if not html_file then
    io.stderr:write("[html-latex-lwarp] lualatex (html) produced no .html\n")
    return nil
  end
  local html = html_file:read("*a")
  html_file:close()

  -- 剥壳：取 <main class="bodycontainer">…</main>（lwarp 内容主体；
  -- 含 <div data-nosnippet> 的 \newcommand 定义输出区——保留，MathJax 读）
  local inner = html:match('<main class="bodycontainer">(.*)</main>')
    or html:match("<main[^>]*>(.*)</main>")
    or html:match("<body>(.*)</body>")
    or html
  -- 删 <link>（改内联 css）
  inner = inner:gsub("<link[^>]*>", "")
  -- lwarp 跨文件链接改页内锚点：href="block.html#label" → href="#label"
  -- （lwarp 用 homehtmlfilename 拼 href；嵌入主页面后 *.html 前缀是死链）
  inner = inner:gsub('href="[^"]*%.html#', 'href="#')
  inner = inner:gsub("href='[^']*%.html#", "href='#")

  -- css：从原 html 的 <link> 收集文件名（零硬编码——lwarp 版本不同
  -- 可能输出多 css）→ 逐个读 → 作用域化 → 内联
  local css_parts = {}
  local seen = {}
  for name in html:gmatch('href="([^"]+%.css)"') do
    if not seen[name] then
      seen[name] = true
      local cf = io.open(CACHE .. "/" .. name)
      if cf then
        local css = cf:read("*a")
        cf:close()
        css_parts[#css_parts + 1] = scope_css(css, BLOCK_PREFIX)
      end
    end
  end
  local css = table.concat(css_parts, "\n")

  -- 容器：lwarp 原生 <a id="label"> 锚点已输出（探针实证），容器
  -- div 不再重复 id——块内 \ref 的 href="#label" 指向原生锚点
  return '<div class="' .. BLOCK_PREFIX .. '"><style>' .. css .. "</style>" .. inner .. "</div>"
end

-- 正文引用：\ref{alg-X} → <a href="#alg-X">N</a>（照搬旧 filter 协议；
-- N 来自 html-latex-counters.lua 的 label→编号表）
local function walk_inlines(inlines, refs)
  local out = pandoc.List({})
  for _, inl in ipairs(inlines) do
    local handled = false
    if (inl.t == "RawInline" and inl.format == "tex") or inl.t == "Math" then
      local ref = inl.text:match("\\ref{([^}]+)}")
      if ref and refs[ref] then
        out:insert(pandoc.RawInline("html",
          '<a href="#' .. ref:gsub(":", "-") .. '">' .. refs[ref] .. "</a>"))
        handled = true
      end
    elseif inl.t == "Link" and inl.attr and inl.attr.attributes
      and inl.attr.attributes["reference-type"] == "ref" then
      local target = inl.attr.attributes["reference"]
      if target and refs[target] then
        out:insert(pandoc.RawInline("html",
          '<a href="#' .. target:gsub(":", "-") .. '">' .. refs[target] .. "</a>"))
        handled = true
      end
    end
    if not handled then out:insert(inl) end
  end
  return out
end

-- 从 doc.meta 读 html-latex-counters.lua 的输出：
-- blocks（每 tex 非表格块的 {counter, start}）+ refs（label→编号）
local function read_counters(meta)
  local c = meta["html-helper-lwarp-counters"]
  local blocks, refs = {}, {}
  if c == nil then return blocks, refs end
  local bl = c["blocks"]
  if bl and pandoc.utils.type(bl) == "List" then
    for _, item in ipairs(bl) do
      local counter = item["counter"] and pandoc.utils.stringify(item["counter"]) or ""
      local start = item["start"] and pandoc.utils.stringify(item["start"]) or "0"
      blocks[#blocks + 1] = { counter = counter, start = tonumber(start) or 0 }
    end
  end
  local rf = c["refs"]
  if rf ~= nil then
    for k, v in pairs(rf) do
      refs[k] = pandoc.utils.stringify(v)
    end
  end
  return blocks, refs
end

return {
  {
    Pandoc = function(doc)
      -- MathJax 宏注入（主页面级——扫描全文自动发现数学里的文本命令，
      -- 定义来自用户/latex-packages 包源——body 开头同步 script 设
      -- window.MathJax tex.macros；零显式配置）
      local mj_macros = extract_mathjax_macros(doc)
      if mj_macros ~= "" then
        table.insert(doc.blocks, 1, pandoc.RawBlock("html", mj_macros))
      end
      local macros = read_config(doc.meta)
      local packages = read_packages(doc.meta)
      local counter_blocks, refs = read_counters(doc.meta)
      local k = 0 -- 编译候选序（与 counters.lua 的 blocks 列表对齐）
      for i = 1, #doc.blocks do
        local blk = doc.blocks[i]
        if blk.t == "RawBlock" and (blk.format == "tex" or blk.format == "latex") then
          local text = blk.text
          if is_compile_candidate(text) then
            k = k + 1
            local cinfo = counter_blocks[k] or { counter = "", start = 0 }
            local labels = extract_labels(text)
            local ok, html = pcall(compile_block, text,
              cinfo.counter, cinfo.start, macros, labels, packages)
            if ok and html then
              -- pandoc 3 AST 节点只读（'tag' 不可写）——替换整个节点
              doc.blocks[i] = pandoc.RawBlock("html", html)
            else
              -- 编译失败不静默消失：原 LaTeX 源码为可见警告块（可诊断）。
              -- 失败原因归项目层（latex-packages 声明与 lwarp 能力冲突等
              -- ——如老式 algorithmic 包 lwarp 明确拒绝）——filter 不强行适配
              doc.blocks[i] = pandoc.RawBlock("html",
                '<div class="lwarp-failed" title="lwarp 编译失败，原 LaTeX 块如下（检查 latex-packages 声明或块内容）">'
                .. '<pre>' .. text:gsub("&", "&amp;"):gsub("<", "&lt;") .. "</pre></div>")
            end
          else
            -- PDF 控制片段（无 \begin 结构）：跳过——quarto HTML writer
            -- 丢弃 latex RawBlock——PDF 专用命令在 HTML 端无意义的语义
          end
        end
      end
      -- 正文引用链接化（顶层块；嵌套结构后续扩展）
      for _, blk in ipairs(doc.blocks) do
        if blk.t == "Para" or blk.t == "Plain" then
          blk.content = walk_inlines(blk.content, refs)
        end
      end
      -- 第二遍：块内 \ref 占位解析（refs 来自 counters.lua——全文 label
      -- 编号齐备，前向引用可解析）。两种形态：
      --   数学内 @@REF:{X}@@（带花括号——lwarp 数学文本保留 { }，
      --     MathJax 不执行 \ref 所以一律占位）→ 纯文本编号
      --   数学外 @@REF:X@@（无花括号——\newlabel 假条目的显示文本，
      --     TeX 分组吞；链接 <a href="#X"> 由 lwarp 原生输出）→
      --     编号（链接保留，块内/跨块锚点都在主页面可跳转）
      -- 数学内不能放 HTML 链接（MathJax 不渲染 <a>），全部纯文本
      for _, blk in ipairs(doc.blocks) do
        if blk.t == "RawBlock" and blk.format == "html" then
          blk.text = blk.text:gsub("@@REF:{([^@]+)}@@", function(ref)
            if refs[ref] then
              return refs[ref]
            end
            return "[" .. ref .. "]"
          end)
          blk.text = blk.text:gsub("@@REF:([^@]+)@@", function(ref)
            if refs[ref] then
              return refs[ref]
            end
            return "[" .. ref .. "]"
          end)
        end
      end
      return doc
    end,
  },
}
