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
--     （tabular 系实证挂起；算法块实证稳定——表格已避开，算法风险低）
--   - 块内 \ref{X}（跨块引用）尚是 ?? 或未定义——.4ht 占位符协议待做
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
local function detect_packages(text)
  local pkgs = {}
  if is_algorithm_block(text) then
    pkgs[#pkgs + 1] = "algorithm"
    pkgs[#pkgs + 1] = "algorithmic"
  end
  if text:find("\\color", 1, true) then
    pkgs[#pkgs + 1] = "xcolor"
  end
  if text:find("%$") then
    pkgs[#pkgs + 1] = "amsmath"
  end
  return pkgs
end

-- 组装独立 .tex：计数器注入 = 全文编号对齐的关键
local function build_tex(body, counter_before)
  local t = { "\\documentclass{article}" }
  for _, p in ipairs(detect_packages(body)) do
    t[#t + 1] = "\\usepackage{" .. p .. "}"
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

-- 编译块 → 子页面 HTML；失败返回 nil（调用方原样保留）
local function compile_block(body, counter_before)
  if not ensure_dir(CACHE) then
    io.stderr:write("[html-latex] mkdir " .. CACHE .. " failed\n")
    return nil
  end

  local tex_path = CACHE .. "/block.tex"
  local f = io.open(tex_path, "w")
  if not f then return nil end
  f:write(build_tex(body, counter_before))
  f:close()

  -- make4ht 编译（cmd 语法；工作目录=缓存目录，输出 block.html/block.css）
  local ok = os.execute("cd " .. CACHE .. " && make4ht block.tex >nul 2>&1")
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
  return '<div class="tex4ht-block"><style>' .. css .. "</style>" .. inner .. "</div>"
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
            local ok, html = pcall(compile_block, text, n - 1)
            if ok and html then
              -- pandoc 3 AST 节点只读（'tag' 不可写）——替换整个节点
              doc.blocks[i] = pandoc.RawBlock("html", html)
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
