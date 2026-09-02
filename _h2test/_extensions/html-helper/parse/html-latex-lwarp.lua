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
--   2) RawBlock(tex) 非表格块（\begin{algorithm 等）：
--      a. 数序：第 N 个算法块 → 注入 \setcounter{algorithm}{N-1}
--      b. 生成独立 block.tex：\usepackage[mathjax]{lwarp}（先于一切）
--         + 宏包检测注入 + latex-macros + 计数器
--      c. 双编译：lualatex block.tex（打印版，lwarp 自动生成
--         block_html.tex）→ lualatex block_html.tex（HTML 版，
--         生成 block_html.html）——工作目录 .quarto/lwarp/
--      d. 剥壳取 <main class="bodycontainer"> 内容 + lwarp.css
--         作用域化内联 → <div class="lwarp-block">
--      失败回退：可见警告块（div.lwarp-failed + 原 LaTeX 源码）
--   3) 正文 \ref{alg-X}（RawInline tex / Math / Link）→ <a href="#alg-X">N</a>
--   4) 块内 \ref{X}（跨文档引用协议）：
--      数学外：\ref 原样保留——块内 label 由真实 aux 解析（lwarp 原生
--        链接）；块外 label 由 preamble 注入 \newlabel 假条目喂值
--        （显示文本=@@REF:X@@ 占位、href=#X），lwarp 原生输出
--        <a href="#X">@@REF:X@@</a>——Pandoc 回调第二遍填编号
--      数学内：一律 @@REF:{X}@@ 纯文本占位（lwarp mathjax 模式
--        detokenize 不执行 \ref；数学内不能放 HTML 链接）——第二遍
--        填纯文本编号
--      第二遍解析（alg_nums 齐后，前向引用可解析）：
--        已知 label → 编号；未知 → [X] 占位（保留名可诊断）

-- 数学预处理（只作用于 lwarp 编译副本 block.tex——qmd 源不动、PDF 端不动）：
--   1) \Call{f}{a} → \mathrm{f}(a)：\Call 是 algpseudocode 的文本层命令
--      （\textsc{#1}(#2)，algpseudocode.sty:81）——被写进数学时 lwarp
--      detokenize 给 MathJax 会红字（MathJax 不认识 \textsc/\ifthenelse）；
--      展开为标准数学命令，语义等价（\textsc 小型大写 ≈ \mathrm 正体）
--   2) \ref：数学段外原样保留（lwarp 原生 + \newlabel 假条目注入）、
--      数学段内一律 @@REF:{X}@@（detokenize 不执行 \ref）——返回 (body, ref_out)
--
-- 边界（与其它模块解耦）：
--   - 表格块跳过——html-latex-tables.lua 处理
--   - 未知 latex 块：原样保留（回退原则）
--   - 宏包检测从块内容读取——零硬编码，不猜
--
-- 已知限制：
--   - 每次渲染重新编译（无缓存）；lualatex 无 tex4ht 死锁历史
--   - lwarp.css 全量作用域化内联（1871 行，块多时冗余——后续按
--     实际使用的 class 筛选；lwarp 输出单 css：<link href="lwarp.css">）
--   - lwarp 双编译（打印版 + HTML 版）比 make4ht 单编译多一次
--     lualatex；块小文档秒级
--   - lwarp 的 <div data-nosnippet>（\newcommand 定义输出区，供
--     MathJax 读取）保留在剥壳结果内——删了会丢宏定义
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

local function is_algorithm_block(text)
  return text:find("\\begin{algorithm", 1, true) ~= nil
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

-- 宏包检测（从块内容读取实际使用的宏包，不猜）
-- 算法包互斥注入：驼峰系（\Call/\Require/\State）→ algpseudocode（algorithmicx）；
-- 大写系（\REQUIRE/\STATE）→ algorithmic（algorithms）——两者都定义
-- algorithmic 环境，同注必冲突（实证：Command \algorithmic already defined）
-- lwarp 下加载原包即自动挂钩对应 lwarp-*.sty 包装（\LWR@ProvidesPackagePass）
local function detect_packages(text, macros)
  local src = text .. "\n" .. (macros or "")
  local pkgs = {}
  if is_algorithm_block(src) then
    pkgs[#pkgs + 1] = "algorithm"
  end
  if src:find("\\Call", 1, true) or src:find("\\Require", 1, true)
    or src:find("\\State", 1, true) then
    pkgs[#pkgs + 1] = "algpseudocode"
  elseif src:find("\\REQUIRE", 1, true) or src:find("\\STATE", 1, true) then
    pkgs[#pkgs + 1] = "algorithmic"
  end
  if src:find("\\color", 1, true) or src:find("\\textcolor", 1, true) then
    pkgs[#pkgs + 1] = "xcolor"
  end
  if src:find("%$") or src:find("\\text", 1, true) or src:find("\\mathrm", 1, true) then
    pkgs[#pkgs + 1] = "amsmath"
  end
  if src:find("\\xspace", 1, true) then
    pkgs[#pkgs + 1] = "xspace"
  end
  return pkgs
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

-- 平衡花括号提取（深度计数，支持嵌套参数——\Call 的 args 里可能嵌
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

-- 数学内的 \Call{f}{a} → \mathrm{f}(a)（旧 html-latex-algorithm.lua 方法移植：
-- MathJax 不认识 \Call 会红字——\mathrm + 括号是标准数学命令；参数内可能
-- 再嵌套 \Call，循环处理；plain find 避 pattern 转义坑；balanced_brace
-- 深度计数支持嵌套。lwarp 下 \mathrm 无 tex4ht bug，无需再转 \text）
local function expand_call(x)
  local out = x
  local pos = out:find("\\Call{", 1, true)
  while pos do
    local fn, rest = balanced_brace(out:sub(pos + 5))
    if not fn then break end
    local args = balanced_brace(rest)
    if not args then break end
    local seg_len = 6 + #fn + #args + 3 -- \Call{ + fn + }{ + args + }
    out = out:sub(1, pos - 1) .. "\\mathrm{" .. fn .. "}(" .. args .. ")" .. out:sub(pos + seg_len)
    pos = out:find("\\Call{", pos + 1, true)
  end
  return out
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
--   1) \Call → \mathrm{f}(a)（MathJax 不认自定义宏，红字）
--   2) \ref：数学段外原样保留（lwarp 原生 + \newlabel 注入）、数学段内
--      一律 @@REF:{X}@@（MathJax 不执行 \ref）——返回 (body, ref_out)
-- tex4ht 时代的 \mathrm→\text、下标加括号不再需要（lwarp 数学原样
-- 给 MathJax，无 MiKTeX tex4ht 2022 \new:mfont bug 路径）
local function math_preprocess(body, labelset)
  body = expand_call(body)
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
-- 机制需要先于目标包）；计数器注入 = 全文编号对齐；块外 label 预注入
-- \newlabel 假条目（preamble 专用）——LaTeX 层（\ref 显示文本=@@REF
-- 占位）+ @lwarp 层（fileref → href=label 真名）+ @lwarp@image 层
local function build_tex(body, counter_before, macros, ref_out)
  local t = { "\\documentclass{article}", "\\usepackage[mathjax]{lwarp}" }
  for _, p in ipairs(detect_packages(body, macros)) do
    t[#t + 1] = "\\usepackage{" .. p .. "}"
  end
  if macros and macros ~= "" then
    t[#t + 1] = macros
  end
  if counter_before and counter_before > 0 then
    t[#t + 1] = "\\setcounter{algorithm}{" .. counter_before .. "}"
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
local function compile_block(body, counter_before, macros, labels)
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
  f:write(build_tex(body_pp, counter_before, macros, ref_out))
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

-- 正文引用：\ref{alg-X} → <a href="#alg-X">N</a>（照搬旧 filter 协议）
local function walk_inlines(inlines, alg_nums)
  local out = pandoc.List({})
  for _, inl in ipairs(inlines) do
    local handled = false
    if (inl.t == "RawInline" and inl.format == "tex") or inl.t == "Math" then
      local ref = inl.text:match("\\ref{([^}]+)}")
      if ref and alg_nums[ref] then
        out:insert(pandoc.RawInline("html",
          '<a href="#' .. ref:gsub(":", "-") .. '">' .. alg_nums[ref] .. "</a>"))
        handled = true
      end
    elseif inl.t == "Link" and inl.attr and inl.attr.attributes
      and inl.attr.attributes["reference-type"] == "ref" then
      local target = inl.attr.attributes["reference"]
      if target and alg_nums[target] then
        out:insert(pandoc.RawInline("html",
          '<a href="#' .. target:gsub(":", "-") .. '">' .. alg_nums[target] .. "</a>"))
        handled = true
      end
    end
    if not handled then out:insert(inl) end
  end
  return out
end

return {
  {
    Pandoc = function(doc)
      local macros = read_config(doc.meta)
      local alg_nums = {}
      local n = 0
      for i = 1, #doc.blocks do
        local blk = doc.blocks[i]
        if blk.t == "RawBlock" and (blk.format == "tex" or blk.format == "latex") then
          local text = blk.text
          if is_table_block(text) then
            -- 表格块：html-latex-tables.lua 的领地，跳过
          elseif is_algorithm_block(text) then
            n = n + 1
            local labels = extract_labels(text)
            if labels[1] then alg_nums[labels[1]] = n end
            local ok, html = pcall(compile_block, text, n - 1, macros, labels)
            if ok and html then
              -- pandoc 3 AST 节点只读（'tag' 不可写）——替换整个节点
              doc.blocks[i] = pandoc.RawBlock("html", html)
            else
              -- 编译失败不静默消失：原 LaTeX 源码为可见警告块（可诊断）
              -- lwarp 明确不支持老式 algorithmic 包（checkloadnever 拦截，
              -- 'Package algorithmic is not yet supported'）——检测到老式
              -- 大写命令时说明原因，避免用户对着原源码猜
              local why = ""
              if text:find("\\REQUIRE", 1, true) or text:find("\\STATE", 1, true)
                or text:find("\\FOR{", 1, true) or text:find("\\WHILE", 1, true)
                or text:find("\\RETURN", 1, true) then
                why = "（lwarp 不支持老式 algorithmic 包——请改用 algpseudocode 风格：\\State/\\For/\\While/\\Return）"
              end
              doc.blocks[i] = pandoc.RawBlock("html",
                '<div class="lwarp-failed" title="lwarp 编译失败' .. why .. '，原 LaTeX 块如下">'
                .. '<pre>' .. text:gsub("&", "&amp;"):gsub("<", "&lt;") .. "</pre></div>")
            end
          else
            -- 未知 latex 块：原样保留（回退原则）
          end
        end
      end
      -- 正文引用链接化（顶层块；嵌套结构后续扩展）
      for _, blk in ipairs(doc.blocks) do
        if blk.t == "Para" or blk.t == "Plain" then
          blk.content = walk_inlines(blk.content, alg_nums)
        end
      end
      -- 第二遍：块内 \ref 占位解析（此时 alg_nums 已含全部块，前向
      -- 引用可解析）。两种形态：
      --   数学内 @@REF:{X}@@（带花括号——lwarp 数学文本保留 { }，
      --     MathJax 不执行 \ref 所以一律占位）→ 纯文本编号
      --   数学外 @@REF:X@@（无花括号——\newlabel 假条目的显示文本，
      --     TeX 分组吞；链接 <a href="#X"> 由 lwarp 原生输出）→
      --     编号（链接保留，块内/跨块锚点都在主页面可跳转）
      -- 数学内不能放 HTML 链接（MathJax 不渲染 <a>），全部纯文本
      for _, blk in ipairs(doc.blocks) do
        if blk.t == "RawBlock" and blk.format == "html" then
          blk.text = blk.text:gsub("@@REF:{([^@]+)}@@", function(ref)
            if alg_nums[ref] then
              return tostring(alg_nums[ref])
            end
            return "[" .. ref .. "]"
          end)
          blk.text = blk.text:gsub("@@REF:([^@]+)@@", function(ref)
            if alg_nums[ref] then
              return tostring(alg_nums[ref])
            end
            return "[" .. ref .. "]"
          end)
        end
      end
      return doc
    end,
  },
}
