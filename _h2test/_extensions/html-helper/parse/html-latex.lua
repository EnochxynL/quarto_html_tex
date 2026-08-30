-- html-latex.lua — make4ht 子页面通道（复杂 latex 块 → 精确呈现子页面）
--
-- 设计哲学（用户拍板 2026-09-01）：复杂 latex 块（算法等 pandoc 解析不了的）
-- 的定位是"精确呈现"——嵌入的 make4ht HTML 块近似为一个子页面，忠实呈现
-- TeX 排版值（pt 缩进/字体 class/编号），不迎合主页面 CSS 体系。
--
-- 职责：
--   1) FORMAT 守卫：PDF 端 return {}——{=latex} 原样走 LaTeX 原生编译
--      （PDF 端编号天然由 LaTeX 计数器给出，与本 filter 注入的计数器同源）
--   2) RawBlock(tex) 非表格块（\begin{algorithm 等）：
--      a. 数序：第 N 个算法块（算法计数器只被算法块占用——管道表/图独立计数器）
--      b. 生成独立 .tex：注入 \setcounter{algorithm}{N-1}——块内编号 = 全文编号
--         （与 PDF 端 LaTeX 计数器完全对齐；骨架先支持算法块）
--      c. make4ht 编译（工作目录 .quarto/tex4ht/）→ 读产物 html/css
--      d. 剥文档壳取 <body> 内容 + css 内联 <style> → <div class="tex4ht-block">
--      失败回退：原样保留 RawBlock(tex)（回退原则：未识别/失败不静默吞）
--   3) 正文 \ref{alg-X}（RawInline tex / Math / Link）→ <a href="#alg-X">N</a>
--      N = 算法块序号（与块内 caption 编号同源一致）
--
-- 边界（与其它模块解耦）：
--   - 表格块（\begin{tabular/\begin{table）跳过——html-latex-tables.lua 处理
--   - 未知 latex 块：原样保留（不翻译、不报错）——未来按需扩展
--   - 宏包检测从块内容读取（\color→xcolor、$→amsmath）——零硬编码，不猜
--
-- 已知限制（骨架阶段）：
--   - 每次渲染重新编译（无缓存）——块数量少时秒级，可接受；优化后补
--   - make4ht 输出无超时保护——tex4ht 转换器在 MiKTeX 有间歇死锁记录
--     （tabular 系实证挂起；表格已避开，算法块实证稳定）
--   - 块内 \ref{X}（跨块引用）尚是 ?? 或未定义——.4ht 占位符协议待做
--   - 数学预处理（make4ht 副本内等价变换，qmd 源不动）：
--     \mathrm→\text（tex4ht 2022 版 \new:mfont 单 token 参数 bug——
--     多字符内容必崩，\mathbf{x} 单字符侥幸成功）+ 无括号下标/上标加
--     花括号（Gurari 规则：tex4ht 要求多部分下标必须括号）——见 math_preprocess
if FORMAT ~= "html" and FORMAT ~= "html5" then
  return {}
end

-- 注意：quarto 的 main.lua 包装了 require（白名单），lfs 不可用——
-- 目录探测用 io.open，创建用 os.execute（cmd/sh 单层 mkdir 语法一致）
local CACHE = ".quarto/tex4ht"

-- 表格块：跳过（html-latex-tables.lua 的领地）
local function is_table_block(text)
  return text:find("\\begin{tabular", 1, true) ~= nil
      or text:find("\\begin{table", 1, true) ~= nil
end

local function is_algorithm_block(text)
  return text:find("\\begin{algorithm", 1, true) ~= nil
end

local function extract_label(text)
  return text:match("\\label{([^}]+)}")
end

-- 宏包检测（从块内容读取实际使用的宏包，不猜）
-- 算法包互斥注入：驼峰系（\Call/\Require/\State）→ algpseudocode（algorithmicx）；
-- 大写系（\REQUIRE/\STATE）→ algorithmic（algorithms）——两者都定义
-- algorithmic 环境，同注必冲突（实证：Command \algorithmic already defined）
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
-- 深度计数支持嵌套。后续 math_preprocess 第一阶段把 \mathrm 转 \text）
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

-- 数学预处理（只作用于 make4ht 编译副本 block.tex——qmd 源不动、PDF 端不动，
-- 等价变换不改语义）：
--   1) \Call{f}{a} → \mathrm{f}(a)（MathJax 不认 \Call——红字实证 7 处；
--      移植旧 filter 的 balanced_brace 方法，支持嵌套参数）
--   2) \mathrm → \text：tex4ht 2022 版 \new:mfont 只吃单 token 参数（\protect
--      链剥参数括号），\mathrm{多字符} 必崩（\mathbf{x} 单字符侥幸成功）；
--      \text（amsmath）同为 upright，实证 exit 0（Gurari 邮件线索）
--   3) 无括号下标/上标加花括号：tex4ht 要求多部分下标必须括号（Gurari 规则：
--      "tex4ht insists that multi parts subscripts and superscripts should
--      be braced"）——`_\text{train}` → `_{\text{train}}`（无括号时
--      \n:text@: 崩）；已有括号/_单字符下标不匹配不受影响
local function math_preprocess(body)
  body = expand_call(body)
  body = body:gsub("%\\mathrm", "\\text")
  body = body:gsub("([_^])(\\[a-zA-Z]+)(%b{})", "%1{%2%3}")
  return body
end

-- 组装独立 .tex：计数器注入 = 全文编号对齐的关键；宏定义注入 = 块内
-- \ourmethod{} 等自定义宏可编译（从 doc.meta 读，零硬编码）
local function build_tex(body, counter_before, macros)
  local t = { "\\documentclass{article}" }
  for _, p in ipairs(detect_packages(body, macros)) do
    t[#t + 1] = "\\usepackage{" .. p .. "}"
  end
  if macros and macros ~= "" then
    t[#t + 1] = macros
  end
  if counter_before and counter_before > 0 then
    t[#t + 1] = "\\setcounter{algorithm}{" .. counter_before .. "}"
  end
  t[#t + 1] = "\\begin{document}"
  t[#t + 1] = body
  t[#t + 1] = "\\end{document}"
  return table.concat(t, "\n")
end

-- 编译块 → 子页面 HTML；失败返回 nil（调用方原样保留）
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

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function base64(data)
  local out = {}
  for i = 1, #data, 3 do
    local a, b, c = data:byte(i, i + 2)
    local n = (a or 0) * 65536 + (b or 0) * 256 + (c or 0)
    out[#out + 1] = B64:sub(math.floor(n / 262144) % 64 + 1, math.floor(n / 262144) % 64 + 1)
    out[#out + 1] = B64:sub(math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1)
    out[#out + 1] = (b and B64:sub(math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1)) or "="
    out[#out + 1] = (c and B64:sub(n % 64 + 1, n % 64 + 1)) or "="
  end
  return table.concat(out)
end

-- tex4ht 符号位图（\tilde{s} 等）base64 内联——make4ht 工作目录相对路径
-- 渲染后断裂（404 裂图），内联后子页面完全自包含
local function inline_images(html)
  -- tex4ht 输出单引号属性（src='block0x.png'）——双引号兼容
  local out = html:gsub("src=['\"](block%d+x%.png)['\"]", function(fname)
    local f = io.open(CACHE .. "/" .. fname, "rb")
    if not f then return 'src="' .. fname .. '"' end
    local data = f:read("*a")
    f:close()
    return 'src="data:image/png;base64,' .. base64(data) .. '"'
  end)
  return out
end

-- css 作用域化：tex4ht css 是文档级（body/p 等裸选择器），内联后污染
-- 主页面（实证：body{max-width:80ch} 把整个页面限宽 80ch）——body 级
-- 规则丢弃（子页面无 body），其余选择器加 .tex4ht-block 前缀
local function scope_css(css)
  local out = {}
  for rule in css:gmatch("[^}]+}") do
    local sel, decl = rule:match("^%s*([^{]+)%s*{([^}]*)}")
    if sel and decl then
      sel = sel:gsub("%s+", " ")
      if sel:match("^body") or sel:match("^html") then
        -- body/html 级规则丢弃（子页面无 body 元素；@media print 内
        -- body{max-width:none} 同被滤掉——嵌套 @media 少见，先整体滤）
      elseif sel:match("^@") then
        -- @media 块原样（其内部规则影响面小，后续完善）
        out[#out + 1] = rule
      else
        local prefixed = {}
        for s in sel:gmatch("[^,]+") do
          s = s:gsub("^%s+", "")
          prefixed[#prefixed + 1] = ".tex4ht-block " .. s
        end
        out[#out + 1] = table.concat(prefixed, ", ") .. "{" .. decl .. "}"
      end
    end
  end
  return table.concat(out, "\n")
end

-- 编译块 → 子页面 HTML；失败返回 nil（调用方原样保留）
local function compile_block(body, counter_before, macros, label)
  if not ensure_dir(CACHE) then
    io.stderr:write("[html-latex] mkdir " .. CACHE .. " failed\n")
    return nil
  end

  local tex_path = CACHE .. "/block.tex"
  local f = io.open(tex_path, "w")
  if not f then return nil end
  f:write(build_tex(math_preprocess(body), counter_before, macros))
  f:close()

  -- mathjax 模式 config（\Preamble{mathjax}：html4-math.4ht 的
  -- \:CheckOption{mathjax} 命中 → 数学输出 \(...\) LaTeX 文本 + MathJax
  -- 脚本，位图/字体 class 归零（\tilde{s} 不再渲染成 block*.png）；
  -- 数学由主页面 MathJax 渲染（quarto html 默认 mathjax 方法）
  local cf = io.open(CACHE .. "/mj.cfg", "w")
  if cf then
    cf:write("\\Preamble{mathjax}\n\\begin{document}\n\\EndPreamble\n")
    cf:close()
  end

  -- make4ht 编译（-c mj：mathjax 模式；cmd 语法；工作目录=缓存目录）
  local ok = os.execute("cd " .. CACHE .. " && make4ht -c mj block.tex >nul 2>&1")
  if not ok then
    io.stderr:write("[html-latex] make4ht failed for block\n")
    return nil
  end

  local html_file = io.open(CACHE .. "/block.html")
  local css_file = io.open(CACHE .. "/block.css")
  if not html_file or not css_file then
    if html_file then html_file:close() end
    if css_file then css_file:close() end
    io.stderr:write("[html-latex] make4ht produced no output (deadlock?)\n")
    return nil
  end
  local html = html_file:read("*a")
  local css = css_file:read("*a")
  html_file:close()
  css_file:close()

  -- 剥文档壳取 body 内容；删 <link ...css>（改内联）
  local inner = html:match("<body>(.*)</body>") or html
  inner = inner:gsub("<link[^>]*>", "")
  -- 图片 base64 内联（路径断裂修复）+ css 作用域化（主页面污染修复）
  inner = inline_images(inner)
  css = scope_css(css)
  -- 锚点：tex4ht 用 caption slug 做 id（skillopt-skill-optimization），
  -- \label 名不输出——容器 id 补上 label（正文 \ref{alg-X} → #alg-X 可达）
  local id_attr = (label and label ~= "") and (' id="' .. label .. '"') or ""
  return '<div class="tex4ht-block"' .. id_attr .. "><style>" .. css .. "</style>" .. inner .. "</div>"
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
            local label = extract_label(text)
            if label then alg_nums[label] = n end
            local ok, html = pcall(compile_block, text, n - 1, macros, label)
            if ok and html then
              -- pandoc 3 AST 节点只读（'tag' 不可写）——替换整个节点
              doc.blocks[i] = pandoc.RawBlock("html", html)
            else
              -- 编译失败不静默消失：保留 LaTeX 源码为可见警告块（可诊断）
              -- （\mathrm 等命令在 MiKTeX tex4ht 2022 版有数学转换 bug）
              doc.blocks[i] = pandoc.RawBlock("html",
                '<div class="tex4ht-failed" title="make4ht 编译失败，原 LaTeX 块如下">'
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
      return doc
    end,
  },
}
