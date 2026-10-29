-- Raw LaTeX environments -> scoped HTML through lwarp, including tables.
-- TeX executes table structure, package commands, colors and nested layouts;
-- Lua only prepares the document, joins parent citations/references, and embeds
-- the generated HTML/CSS. No table-to-Pandoc conversion or syntax stripping.
--
-- Requires explicitly declared html-tex.include-in-header.
-- Each block retains its TeX and logs in .quarto/lwarp/block-N/.
-- The parent counter pass supplies starting values; lwarp emits captions and
-- source label anchors. Bibliographic commands use the parent's citeproc data.
-- Table macros/boxed tables use lwarp's StartDefiningTabulars mechanism.
-- Failed blocks stop rendering with retained diagnostics; PDF input is untouched.
--
-- Limitations: no compilation cache; multirow continuations require mrowcell;
-- declaration-style color may need textcolor in the source for HTML output.
if FORMAT ~= "html" and FORMAT ~= "html5" then
  return {}
end

local state_key = "html-tex-lwarp-pending"
local marker = "data-html-tex-lwarp"
local citation_marker = "data-html-tex-lwarp-citation"
local placeholder = "data:image/svg+xml;base64," .. quarto.base64.encode(
  '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="50"></svg>')

-- Expose block citations to the parent's normal citeproc pass at the block's
-- position. Keep the TeX block intact apart from numbered substitution slots;
-- do not run a separate bibliography processor with a different citation order.
local function prepare_citations(source, citations)
  local result, position = {}, 1
  while position <= #source do
    local char = source:sub(position, position)
    if char == "%" then
      local last = source:find("\n", position, true) or #source
      result[#result + 1] = source:sub(position, last)
      position = last + 1
    elseif char == "\\" then
      local command = source:match("^(\\cite%a*%*?)", position)
      local last = command and position + #command or position
      if command then
        local function skip_space()
          local space = source:match("^%s*", last)
          last = last + #space
        end
        skip_space()
        while source:sub(last, last) == "[" do
          local option = source:match("^%b[]", last)
          if not option then break end
          last = last + #option
          skip_space()
        end
        local argument = source:match("^%b{}", last)
        if argument then
          last = last + #argument
          local parsed = pandoc.read(source:sub(position, last - 1), "latex")
          local found = false
          parsed:walk({Cite = function() found = true end})
          if found then
            local inlines = pandoc.Inlines({})
            for _, block in ipairs(parsed.blocks) do inlines:extend(block.content) end
            local index = tostring(#citations + 1)
            citations:insert(pandoc.Span(inlines, pandoc.Attr("", {}, {[citation_marker] = index})))
            result[#result + 1] = "\\htmltexcitation{" .. index .. "}"
            position = last
          else command = nil end
        else command = nil end
      end
      if not command then
        -- Copy escaped percent signs/backslashes together so they cannot start
        -- comments or citation commands on the next iteration.
        result[#result + 1] = source:sub(position, position + 1)
        position = position + 2
      end
    else
      result[#result + 1] = char
      position = position + 1
    end
  end
  return table.concat(result)
end

local CACHE = ".quarto/lwarp"
local BLOCK_PREFIX = "lwarp-block"

-- Compile environment blocks, including tables; skip PDF control fragments.
local function is_compile_candidate(text)
  return text:match("\\begin%s*{") ~= nil or text:match("\\tikz%f[^%a]") ~= nil
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

-- Read ordered file/text entries; bare strings are filenames.
local function header_text(v)
  local typ = pandoc.utils.type(v)
  if typ == "Blocks" or typ == "MetaBlocks" then
    local parts = {}
    for _, b in ipairs(v) do
      parts[#parts + 1] = b.t == "RawBlock" and b.text or pandoc.utils.stringify(b)
    end
    return table.concat(parts, "\n")
  end
  return pandoc.utils.stringify(v)
end
local function read_header(meta)
  local config, parts = meta["html-tex"] or {}, {}
  local function append(v)
    local typ = pandoc.utils.type(v)
    if typ == "List" or typ == "MetaList" then
      for _, item in ipairs(v) do append(item) end
    elseif type(v) == "table" and (v.file ~= nil or v.text ~= nil) then
      if v.file ~= nil and v.text == nil then append(v.file)
      elseif v.text ~= nil and v.file == nil then parts[#parts + 1] = header_text(v.text)
      else assert(false, "html-tex.include-in-header: specify exactly one of file or text") end
    else
      local file, message = io.open(header_text(v), "rb")
      assert(file, "html-tex.include-in-header: " .. tostring(message))
      parts[#parts + 1] = file:read("*a")
      file:close()
    end
  end
  if config["include-in-header"] ~= nil then append(config["include-in-header"]) end
  return table.concat(parts, "\n")
end


-- D_\text{sel} 等含花括号的数学；[^}]* 单层匹配会截断，实证括号错乱）
-- Extract balanced braces, including nested macro arguments.
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
-- 收集 \CMD——对每个命令在"用户定义源"（块内/include-in-header 的
-- \newcommand/\def）与"include-in-header 声明包的源"查定义——找到则翻译
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
  -- Only discover package names for MathJax; TeX executes the full header.
  local header = read_header(doc.meta):gsub("%%[^\n]*", "")
  for names in header:gmatch("\\usepackage%s*%b[]%s*{([^}]+)}") do
    for name in names:gmatch("[^,%s]+") do packages[name] = true end
  end
  for names in header:gmatch("\\usepackage%s*{([^}]+)}") do
    for name in names:gmatch("[^,%s]+") do packages[name] = true end
  end
  -- include-in-header（用户宏定义区）
  local macros_tex = read_header(doc.meta)
  collect_user_defs(macros_tex, defs)
  -- 全文 RawBlock
  doc:walk({
    Math = function(math)
      for cmd in math.text:gmatch("\\([a-zA-Z]+)") do cmds[cmd] = true end
    end,
    RawBlock = function(blk)
      if blk.format == "tex" or blk.format == "latex" then
        collect_math_cmds(blk.text, cmds)
        collect_user_defs(blk.text, defs)
      end
    end,
    RawInline = function(node)
      if node.format == "tex" or node.format == "latex" then
        collect_math_cmds(node.text, cmds)
        collect_user_defs(node.text, defs)
      end
    end,
  })
  -- bm implements TeX font machinery rather than a portable macro definition.
  -- Use MathJax's boldsymbol for the declared package, preserving user overrides.
  if packages.bm and not defs.bm then
    defs.bm = { nargs = 1, body = "\\boldsymbol{#1}" }
  end
  -- 需要定义的命令 = 数学里出现且用户定义没有的
  local need = {}
  for cmd in pairs(cmds) do
    if not defs[cmd] then need[cmd] = true end
  end
  -- 包源补定义（include-in-header 声明驱动）
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
    if not (labelset and labelset[ref]) and not ref:find("#", 1, true) then
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
local function refs_inside(seg, references)
  return seg:gsub("%\\ref%s*{([^}]+)}", function(ref)
    return references and references[ref] and pandoc.utils.stringify(references[ref]) or "@@REF:{" .. ref .. "}@@"
  end)
end

-- 数学预处理（只作用于 lwarp 编译副本 block.tex——qmd 源不动、PDF 端不动）：
--   \ref：数学段外原样保留（lwarp 原生 + \newlabel 注入）、数学段内
--   一律 @@REF:{X}@@（MathJax 不执行 \ref）——返回 (body, ref_out)
-- 文本命令进数学（\Call 等）不再预处理展开——MathJax 宏注入
-- （extract_mathjax_macros，主页面级）让 MathJax 侧认识命令
local function math_preprocess(body, labelset, references)
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
    out[#out + 1] = refs_inside(body:sub(d1, d2), references)
    pos = d2 + 1
  end
  return table.concat(out), ref_out
end

-- 组装独立 .tex：lwarp 必须最先加载（\LWR@ProvidesPackagePass 包装
-- 机制需要先于目标包）；中文字体无条件注入（用户拍板 2026-09-02——
-- 不必检测 CJK：fontspec 无副作用，块内中文需要字体、英文块加载无害，
-- 检测是多余的智能）；include-in-header（文档层声明）随后；计数器注入
-- = 全文编号对齐（值来自 html-latex-counters.lua——本文件不持有任何
-- 环境/计数器知识）；\@ifundefined 保护：计数器实际不存在（float 惯例
-- 误判，如裸 algorithmic）则跳过注入——块从 1 编号，不崩
local function build_tex(body, counter_name, counter_start, macros, ref_out, packages, references, preamble)
  local t = { "\\documentclass{article}", "\\usepackage[mathjax]{lwarp}" }
  -- 中文块字体支持（实证 2026-09-02）：块编译默认无 CJK 字体——中文字形
  -- 缺失 → pdftotext 提取层乱码。fontspec + 倒序平铺探测（\IfFontExistsTF
  -- 各独立、无嵌套——后设者赢 = 优先级 Noto > SimSun > YaHei 天然正确；
  -- Linux/TeX Live 与 Windows 双覆盖）；不用 ctex（ctexhook 与 lwarp
  -- hook 机制冲突——全篇 lwarp 方案实证）
  t[#t + 1] = "\\usepackage{fontspec}"
  -- All text families need Unicode coverage: texttt/textsf in a Chinese cell
  -- otherwise falls back to Latin-only fonts and loses the source characters.
  t[#t + 1] = "\\IfFontExistsTF{Microsoft YaHei}{\\setmainfont{Microsoft YaHei}\\setsansfont{Microsoft YaHei}\\setmonofont{Microsoft YaHei}}{}"
  t[#t + 1] = "\\IfFontExistsTF{SimSun}{\\setmainfont{SimSun}\\setsansfont{SimSun}\\setmonofont{SimSun}}{}"
  t[#t + 1] = "\\IfFontExistsTF{Noto Serif CJK SC}{\\setmainfont{Noto Serif CJK SC}\\setsansfont{Noto Serif CJK SC}\\setmonofont{Noto Serif CJK SC}}{}"
  -- TikZ builds a fading mask in an internal hbox. lwarp's pgfpicture hook
  -- must not start a new HTML image/page in that box (or in the preamble).
  -- Treat only the mask construction as nested; normal drawings still use
  -- lwarp's regular lateximage backend. Keep this private-package adapter here.
  t[#t + 1] = [[\AddToHook{package/tikz/after}{%
\usetikzlibrary{fadings}%
\ifcsname c@LWR@lateximagedepth\endcsname
\pretocmd{\tikzfading}{\addtocounter{LWR@lateximagedepth}{1}}{}{\PackageError{html-tex}{Cannot protect fading mask}{}}
\apptocmd{\tikzfading}{\addtocounter{LWR@lateximagedepth}{-1}}{}{\PackageError{html-tex}{Cannot protect fading mask}{}}
\fi}]]
  -- The current lwarp-siunitx quantity formatter drops quantities inside
  -- lateximages. Save siunitx's native formatter before the HTML adapter is
  -- applied and restore it only in image groups; ordinary HTML keeps lwarp's
  -- formatter. This adapter deliberately touches just the affected command.
  t[#t + 1] = [[\AddToHook{package/siunitx/after}{%
\ifcsname siunitx_quantity:nn\endcsname
\expandafter\let\expandafter\HTMLTexQuantity\csname siunitx_quantity:nn\endcsname
\ifcsname LWR@restoreorigformatting\endcsname
\expandafter\appto\csname LWR@restoreorigformatting\endcsname{%
\expandafter\let\csname siunitx_quantity:nn\endcsname\HTMLTexQuantity}
\fi\fi}]]
  if preamble and preamble ~= "" then t[#t + 1] = preamble end
  for _, p in ipairs(packages or {}) do
    t[#t + 1] = "\\usepackage{" .. p .. "}"
  end
  t[#t + 1] = "\\usepackage{hyperref}"
  -- Bibliography anchors belong to the parent HTML, not this lwarp document.
  -- A fragment href avoids lwarp's hypertarget/page lookup for local links.
  t[#t + 1] = [[\DeclareRobustCommand{\citeproc}[2]{%
\ifcsname c@LWR@lateximagedepth\endcsname
  \ifnum\value{LWR@lateximagedepth}>0 #2\else\href{\##1}{#2}\fi
\else #2\fi}]]
  if macros and macros ~= "" then
    -- Load declared packages before lwarp changes tabular-definition catcodes.
    -- Retain the original declarations/options; the full header below executes
    -- again with already-loaded packages, preserving declaration order and macros.
    local declarations = macros:gsub("%%[^\n]*", "")
    local commands = {}
    for _, pattern in ipairs({"()\\usepackage%s*%b[]%s*%b{}", "()\\usepackage%s*%b{}"}) do
      for position in declarations:gmatch(pattern) do
        local command = declarations:match("^\\usepackage%s*%b[]%s*%b{}", position)
            or declarations:match("^\\usepackage%s*%b{}", position)
        commands[#commands + 1] = { position = position, text = command }
      end
    end
    table.sort(commands, function(a, b) return a.position < b.position end)
    for _, command in ipairs(commands) do t[#t + 1] = command.text end
    t[#t + 1] = "\\StartDefiningTabulars"
    t[#t + 1] = macros
    t[#t + 1] = "\\StopDefiningTabulars"
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
  for lab in pairs(references or {}) do ref_out[lab] = true end
  for lab in pairs(ref_out or {}) do
    t[#t + 1] = "\\newlabel{" .. lab .. "}{{" .. (references and references[lab] and pandoc.utils.stringify(references[lab]) or "@@REF:{" .. lab .. "}@@") .. "}{1}{}{" .. lab .. "}{}}"
    t[#t + 1] = "\\newlabel{" .. lab .. "@lwarp}{{" .. lab .. "}{1}{block}{}{}}"
    t[#t + 1] = "\\newlabel{" .. lab .. "@lwarp@image}{{0}{0}{}{}{}}"
  end
  -- The HTML transport is extracted from PDF text. A declared legacy fontenc
  -- must not replace fontspec's Unicode encoding and turn ligatures into C0
  -- control bytes. Native standalone drawings use their separate compiler.
  t[#t + 1] = "\\AtBeginDocument{\\renewcommand\\encodingdefault{TU}\\fontencoding{TU}\\selectfont}"
  t[#t + 1] = "\\begin{document}"
  t[#t + 1] = "\\StartDefiningTabulars"
  t[#t + 1] = body
  t[#t + 1] = "\\StopDefiningTabulars"
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
-- counter_name/counter_start：计数器注入（html-latex-counters.lua 提供）
-- lateximage resources are separate pages in block_html.pdf. Follow lwarp's
-- manifest and conversion sequence synchronously before embedding the HTML.
local function read_lateximages(cache)
  local f = io.open(cache .. "/block-images.txt", "r")
  if not f then return {}, true end
  local images, ready, finished = {}, true, false
  for line in f:lines() do
    if line == "|end|end|end|" then finished = true end
    local page, name = line:match("^|(%d+)|[^|]+|([%w_-]+)|")
    if page then
      page = tonumber(page)
      if page == 0 then ready = false end
      images[name] = page
    end
  end
  f:close()
  if next(images) and not finished then ready = false end
  return images, ready
end

local function generate_lateximages(cache, images)
  if not next(images) then return end
  assert(ensure_dir(cache .. "/block-images"), "cannot create lateximage directory")
  os.remove(cache .. "/image-tools.log")
  local prefix = ""
  local git = (os.getenv("ProgramFiles") or "C:/Program Files") .. "/Git/usr/bin"
  local perl = package.config:sub(1, 1) == "\\" and io.open(git .. "/perl.exe", "rb")
  if perl then
    perl:close()
    prefix = 'set "PATH=' .. git .. ';%PATH%" && '
  end
  local function run(command)
    assert(os.execute("cd " .. cache .. " && " .. prefix .. command .. " >>image-tools.log 2>&1"),
      "lateximage conversion failed; see " .. cache .. "/image-tools.log")
  end
  local function convert()
    for name, page in pairs(images) do
      assert(page > 0, "unresolved lateximage page for " .. name)
      os.remove(cache .. "/block-images/" .. name .. ".svg")
      run("pdfseparate -f " .. page .. " -l " .. page .. " block_html.pdf lateximage-page-%d.pdf")
      run('pdfcrop --hires --margins "0 1 0 0" lateximage-page-' .. page .. '.pdf lateximage-cropped.pdf')
      run("pdftocairo -svg -noshrink lateximage-cropped.pdf block-images/" .. name .. ".svg")
    end
  end
  convert()
end

local function embed_lateximages(html, cache)
  return html:gsub('src="(block%-images[/\\][^"]+%.svg)"', function(src)
    local f = io.open(cache .. "/" .. src:gsub("\\", "/"), "rb")
    assert(f, "missing lateximage: " .. src)
    local svg = f:read("*a")
    f:close()
    assert(svg:find("<svg", 1, true), "invalid lateximage: " .. src)
    return 'src="data:image/svg+xml;base64,' .. quarto.base64.encode(svg) .. '"'
  end)
end

local function compile_block(body, counter_name, counter_start, macros, labels, packages, index, references, preamble, inline)
  -- Isolate auxiliary files and retain diagnostics for each source block.
  local CACHE = CACHE .. "/block-" .. tostring(index)
  local scope = BLOCK_PREFIX .. "-" .. tostring(index)
  if not ensure_dir(CACHE) then
    io.stderr:write("[html-latex-lwarp] mkdir " .. CACHE .. " failed\n")
    return nil
  end
  -- A failed previous build must not seed malformed or unrelated labels.
  -- These two auxiliary files are generated again by the two compilation passes.
  os.remove(CACHE .. "/block.aux")
  os.remove(CACHE .. "/block_html.aux")

  local tex_path = CACHE .. "/block.tex"
  local f = io.open(tex_path, "wb")
  if not f then return nil end
  -- 块内 label 集合（labelset）：数学外引用本块 label 时保留原样走
  -- lwarp 原生（真实 aux），不注入假条目
  local labelset = {}
  if labels then
    for _, lab in ipairs(labels) do labelset[lab] = true end
  end
  local body_pp, ref_out = math_preprocess(body, labelset, references)
  for lab in pairs(ref_out) do
    assert(labelset[lab] or references[lab] or lab:find("#", 1, true),
      "html-latex-lwarp: unresolved block reference: " .. lab)
  end
  local external = {}
  for lab, number in pairs(references or {}) do if not labelset[lab] then external[lab] = number end end
  f:write(build_tex(body_pp, counter_name, counter_start, macros, ref_out, packages, external, preamble))
  f:close()

  -- 双编译：打印版（lwarp 在 \end{document} 写 block_html.tex +
  -- lwarpmk.conf）→ HTML 版（写 block_html.html + block_html.css）
  local function latex(name)
    -- Compile from the parent document directory so relative inputs resolve
    -- naturally. TeX also searches its output directory for generated inputs.
    -- Avoid with_environment: Windows drive entries can appear as an empty
    -- environment name in Pandoc and make unsetEnv fail before compilation.
    local ok, output = pcall(pandoc.pipe, "lualatex", {
      "-interaction=nonstopmode", "-halt-on-error",
      "-output-directory=" .. CACHE, CACHE .. "/" .. name}, "")
    local log = assert(io.open(CACHE .. "/driver-" .. name .. ".log", "wb"))
    log:write(tostring(output)); log:close()
    return ok
  end
  local ok = latex("block.tex")
  if not ok then
    io.stderr:write("[html-latex-lwarp] lualatex (print) failed\n")
    return nil
  end
  if not io.open(CACHE .. "/block_html.tex") then
    io.stderr:write("[html-latex-lwarp] lualatex (print) produced no _html.tex\n")
    return nil
  end
  ok = latex("block_html.tex")
  if not ok then
    io.stderr:write("[html-latex-lwarp] lualatex (html) failed\n")
    return nil
  end
  -- Fresh auxiliary files can leave references to local labels unresolved on
  -- the first HTML pass, including a float referencing its own caption label.
  -- Honor TeX's rerun request instead of depending on a previous render's aux.
  local log = io.open(CACHE .. "/block_html.log", "r")
  local needs_refs = false
  if log then
    needs_refs = log:read("*a"):find("There were undefined references", 1, true) ~= nil
    log:close()
  end
  if needs_refs then
    ok = latex("block_html.tex")
    if not ok then
      io.stderr:write("[html-latex-lwarp] lualatex (references) failed\n")
      return nil
    end
  end
  local images, ready = read_lateximages(CACHE)
  -- The first HTML pass records page zero until image locations reach the aux
  -- file. Only blocks containing images need these additional passes.
  for pass = 1, 2 do
    if ready then break end
    if not latex("block_html.tex") then
      assert(false, "lateximage page pass failed: " .. CACHE .. "/block_html.log")
    end
    images, ready = read_lateximages(CACHE)
  end
  assert(ready, "lateximage pages did not stabilize: " .. CACHE .. "/block-images.txt")
  generate_lateximages(CACHE, images)
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
  -- Image pages are also copied into HTML comments by pdftotext. They are
  -- compiler transport, not HTML content, and may contain unmapped math glyphs.
  inner = inner:gsub('(<span[^>]-class="lateximagesource"[^>]*>)%s*<!%-%-.-%-%->', '%1')
  inner = embed_lateximages(inner, CACHE)
  -- 删 <link>（改内联 css）
  inner = inner:gsub("<link[^>]*>", "")
  -- lwarp 跨文件链接改页内锚点：href="block.html#label" → href="#label"
  -- （lwarp 用 homehtmlfilename 拼 href；嵌入主页面后 *.html 前缀是死链）
  inner = inner:gsub('href="[^"]*%.html#', 'href="#')
  inner = inner:gsub("href='[^']*%.html#", "href='#")
  -- Generated page IDs repeat in independently compiled documents. Keep source
  -- labels public, and namespace only lwarp's private anchors.
  local public = {}
  for _, label in ipairs(labels or {}) do public[label:gsub(":", "-")] = true end
  local private = {}
  for id in inner:gmatch('id="([^"]+)"') do
    if not public[id] then private[id] = scope .. "-" .. id end
  end
  inner = inner:gsub('id="([^"]+)"', function(id) return 'id="' .. (private[id] or id) .. '"' end)
  inner = inner:gsub('href="#([^"]+)"', function(id) return 'href="#' .. (private[id] or id) .. '"' end)

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
        css_parts[#css_parts + 1] = scope_css(css, scope)
      end
    end
  end
  local css = table.concat(css_parts, "\n")

  -- 容器：lwarp 原生 <a id="label"> 锚点已输出（探针实证），容器
  -- div 不再重复 id——块内 \ref 的 href="#label" 指向原生锚点
  if inline then return { html = inner, css = css, scope = scope } end
  return '<div class="' .. BLOCK_PREFIX .. ' ' .. scope .. '"><style>' .. css .. "</style>" .. inner .. "</div>"
end

-- Read only block compilation context; reference lookup belongs to html-ref.
local function read_counters(meta)
  local c = meta["html-tex-lwarp-counters"]
  local blocks = {}
  if c == nil then return blocks end
  local bl = c["blocks"]
  if bl and pandoc.utils.type(bl) == "List" then
    for _, item in ipairs(bl) do
      local counter = item["counter"] and pandoc.utils.stringify(item["counter"]) or ""
      local start = item["start"] and pandoc.utils.stringify(item["start"]) or "0"
      blocks[#blocks + 1] = { counter = counter, start = tonumber(start) or 0 }
    end
  end
  return blocks
end

-- One backend for every raw LaTeX environment. Prepare before Quarto, then
-- render after indexing; the reference bridge runs again on generated HTML.
function Pandoc(doc)
  local pending = doc.meta[state_key]
  if pending == nil then
    local mj_macros = extract_mathjax_macros(doc)
    if mj_macros ~= "" then doc.blocks:insert(1, pandoc.RawBlock("html", mj_macros)) end
    pending = pandoc.MetaList({})
    local citations = pandoc.Inlines({})
    doc = doc:walk({RawBlock = function(block)
      if (block.format ~= "latex" and block.format ~= "tex") or
          not is_compile_candidate(block.text) then return nil end
      local first = #citations + 1
      pending:insert(pandoc.MetaString(prepare_citations(block.text, citations)))
      local index = tostring(#pending)
      local blocks
      if block.text:match("\\begin%s*{tikzpicture}") or block.text:match("\\tikz%f[^%a]") then
        -- The image is only a layout placeholder; the backend still renders the
        -- complete block as HTML, including any surrounding text and tables.
        blocks = {pandoc.Para({pandoc.Image({pandoc.Str("Diagram")}, placeholder, "",
          pandoc.Attr("", {}, {[marker] = index, width = "100%"}))})}
      else
        blocks = {pandoc.Div({}, pandoc.Attr("", {}, {[marker] = index}))}
      end
      if #citations >= first then
        local slots = pandoc.Inlines({})
        for i = first, #citations do slots:insert(citations[i]) end
        blocks[#blocks + 1] = pandoc.Plain(slots)
      end
      return blocks
    end})
    local inline_pending = pandoc.MetaList({})
    doc = doc:walk({traverse = "topdown", Cite = function(node) return node, false end, RawInline = function(node)
      if node.format ~= "latex" and node.format ~= "tex" then return nil end
      local first = #citations + 1
      inline_pending:insert(pandoc.MetaString(prepare_citations(node.text, citations)))
      local slots = pandoc.Inlines({pandoc.Span({}, pandoc.Attr("", {}, {
        ["data-html-tex-inline"] = tostring(#inline_pending)}))})
      for i = first, #citations do slots:insert(citations[i]) end
      return slots
    end})
    doc.meta["html-tex-lwarp-inline"] = inline_pending
    doc.meta[state_key] = pending
    return doc
  end
  local inline_pending = doc.meta["html-tex-lwarp-inline"] or {}
  if #pending == 0 and #inline_pending == 0 then
    doc.meta[state_key] = nil; doc.meta["html-tex-lwarp-inline"] = nil; return doc
  end
  local citations = {}
  local has_citations = false
  doc:walk({Span = function(span)
    if span.attributes[citation_marker] then has_citations = true end
  end})
  if has_citations then
    local available = {}
    for _, reference in ipairs(pandoc.utils.references(doc)) do
      available[pandoc.utils.stringify(reference.id)] = true
    end
    doc:walk({Span = function(span)
      if not span.attributes[citation_marker] then return nil end
      span:walk({Cite = function(cite)
        for _, citation in ipairs(cite.citations) do
          assert(available[citation.id], "html-latex-lwarp: unresolved block citation: " .. citation.id)
        end
      end})
    end})
    -- Use all parent citations, preserving first-use order and disambiguation.
    local rendered = pandoc.utils.citeproc(doc:clone())
    rendered:walk({Span = function(span)
      local index = span.attributes[citation_marker]
      if index then citations[index] = pandoc.write(pandoc.Pandoc({pandoc.Plain(span.content)}), "latex"):gsub("%s+$", "") end
    end})
    doc = doc:walk({Span = function(span)
      if not span.attributes[citation_marker] then return nil end
      span.attributes[citation_marker] = nil
      span.attributes.style = "display:none"
      span.attributes["aria-hidden"] = "true"
      return span
    end})
  end
  local macros, packages = read_header(doc.meta), {}
  local preamble = ""
  local references = assert(doc.meta["html-tex-lwarp-references"], "html-latex-lwarp: reference bridge must run before rendering")
  local function resolve_citations(body)
    return body:gsub("\\htmltexcitation{(%d+)}", function(slot)
      return assert(citations[slot], "html-latex-lwarp: missing processed citation " .. slot)
    end)
  end
  local fragments = {}
  for _, body in ipairs(inline_pending) do fragments[#fragments + 1] = pandoc.utils.stringify(body) end
  do
    if #fragments > 0 then
      local body = {}
      for index, text in ipairs(fragments) do
        body[#body + 1] = "\\begingroup\\InlineClass{html-tex-fragment-" .. index
            .. "}{" .. resolve_citations(text) .. "}\\endgroup\\par"
      end
      local result = assert(compile_block(table.concat(body, "\n"), "", 0,
          macros, extract_labels(table.concat(fragments, "\n")), packages, "inline", references, preamble, true),
          "lwarp inline compilation failed; see .quarto/lwarp/block-inline/")
      local rendered = {}
      for index in ipairs(fragments) do
        local _, first = result.html:find('<span class="html%-tex%-fragment%-' .. index .. '">')
        assert(first, "lwarp did not emit inline fragment " .. index)
        local position, depth = first + 1, 1
        while depth > 0 do
          local open, close, slash = result.html:find("<(/?)span[%s>]", position)
          assert(open, "unbalanced lwarp inline fragment " .. index)
          depth = depth + (slash == "/" and -1 or 1)
          if depth == 0 then
            rendered[index] = result.html:sub(first + 1, open - 1)
          end
          position = close + 1
        end
        -- A RawInline cannot safely carry a paragraph or block environment.
        assert(not rendered[index]:match("</?p[%s>]")
            and not rendered[index]:match("</?div[%s>]")
            and not rendered[index]:match("</?table[%s>]"),
            "block content in inline LaTeX fragment " .. index .. "; use a raw LaTeX block")
      end
      local index = 0
      doc = doc:walk({Span = function(node)
        if node.attributes["data-html-tex-inline"] then
          index = tonumber(node.attributes["data-html-tex-inline"])
          return pandoc.RawInline("html", '<span class="lwarp-inline ' .. result.scope
              .. '">' .. rendered[index] .. '</span>')
        end
      end})
      table.insert(doc.blocks, 1, pandoc.RawBlock("html", "<style>" .. result.css .. "</style>"))
    end
    local counters = read_counters(doc.meta)
    local function render(index)
      local body = pandoc.utils.stringify(assert(pending[tonumber(index)]))
      body = body:gsub("\\htmltexcitation{(%d+)}", function(slot)
        return assert(citations[slot], "html-latex-lwarp: missing processed citation " .. slot)
      end)
      local counter = counters[tonumber(index)] or {counter = "", start = 0}
      local ok, html = pcall(compile_block, body, counter.counter, counter.start, macros,
        extract_labels(body), packages, tonumber(index), references, preamble)
      assert(ok and html, "html-latex-lwarp: block " .. index .. " failed; see .quarto/lwarp/block-" .. index .. "/block*.log; " .. tostring(html))
      return pandoc.RawBlock("html", html)
    end
    doc = doc:walk({
      Div = function(div)
        local index = div.attributes[marker]
        if index then return render(index) end
      end,
      Para = function(para)
        if #para.content == 1 and para.content[1].t == "Image" then
          local index = para.content[1].attributes[marker]
          if index then return render(index) end
        end
      end,
    })
  end
  doc.meta["html-tex-lwarp-inline"] = nil
  doc.meta[state_key] = nil
  doc.meta["html-tex-lwarp-references"] = nil
  return doc
end
