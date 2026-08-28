-- html-algorithm.lua — HTML 算法块翻译（algorithmic 环境 → algorithm-box div）
--
-- 职责：
--   1) 检测 {=latex} RawBlock 含 \begin{algorithm → 翻译 algorithmic 体为
--      嵌套列表 HTML（纯字符串翻译，pandoc 解析 algorithmic 不可用——
--      命令被静默吞、\Else→\ESClse，见 README.design-notes.md 实证）
--   2) 编号：\begin{algorithm 文档顺序 → caption 前缀 "Algorithm N: "
--      （配置化：algo-caption-prefix / algo-caption-sep）
--   3) 正文引用 \ref{alg-X}（Math / RawInline / Link）→ <a href="#alg-X">N</a>
--      label 冒号转连字符（alg:inference → #alg-inference，CSS 选择器友好）
--
-- 翻译管线（每行）：
--   数学 $...$ 先保护为原子占位（\frac 等大括号不干扰结构分析）
--   \\ → <br> 占位（LaTeX 手动换行）
--   行级命令分发：\REQUIRE/\ENSURE/\STATE/\FOR/\WHILE/\REPEAT/\UNTIL/\ENDFOR/\ENDWHILE
--   token 栈扫描：{\color{X} → <span style="color:HEX">、\emph/\textbf/\textit/\texttt
--   → 对应标签、} → 弹栈（嵌套任意深度正确）
--   行尾注释：\STATE 内 $\vartriangleleft$ 之后的片段包 <span class="algo-comment">
--
-- 输出：<div class="algorithm-box" id="alg-X">
--         <div class="algorithm-caption">Algorithm N: ...</div>
--         <div class="algo-require">Require: ...</div>
--         <ol><li>...</li></ol>
--       </div>
--
-- 颜色：xcolor 常用命名色内置映射 → 内联 style（通用标准库，非论文特有宏）；
-- 未知色剥掉 \color 保留内容。
--
-- 回退原则：未识别的行/命令原样保留（不静默吞）。
if FORMAT ~= "html" and FORMAT ~= "html5" then
  return {}
end

-- xcolor 常用命名色 → CSS hex（子集；未知色剥 \color 保留内容）
local XCOLOR = {
  black = "#000000", white = "#FFFFFF", red = "#FF0000", green = "#008000",
  blue = "#0000FF", cyan = "#00FFFF", magenta = "#FF00FF", yellow = "#FFFF00",
  orange = "#FFA500", violet = "#EE82EE", purple = "#800080", pink = "#FFC0CB",
  brown = "#A52A2A", teal = "#008080", lime = "#00FF00", gray = "#808080",
  darkgray = "#A9A9A9", lightgray = "#D3D3D3", olive = "#808000", navy = "#000080",
  maroon = "#800000", gold = "#FFD700", silver = "#C0C0C0",
  CadetBlue = "#5F9EA0", MidnightBlue = "#191970", BrickRed = "#B22222",
  RoyalBlue = "#4169E1", SkyBlue = "#87CEEB", SeaGreen = "#2E8B57",
  ForestGreen = "#228B22", DarkBlue = "#00008B", DarkGreen = "#006400",
  DarkRed = "#8B0000", OrangeRed = "#FF4500", DarkOrange = "#FF8C00",
  DarkViolet = "#9400D3", BlueViolet = "#8A2BE2", LightGray = "#D3D3D3",
}

local function read_config(meta)
  local pt = meta["html-helper"] or meta["paper-tables"] or {}
  local pv = pt["algo-caption-prefix"]
  local sv = pt["algo-caption-sep"]
  local prefix = pv and (pandoc.utils.stringify(pv) .. " ") or "Algorithm "
  local sep = sv and (pandoc.utils.stringify(sv) .. " ") or ": "
  return prefix, sep
end

-- 平衡提取 {X}（X 可含嵌套大括号；调用前数学已保护为占位）
-- s 以 { 开头（可前带命令名）；返回内容、闭合后剩余
local function balanced_brace(s)
  local depth = 0
  for i = 1, #s do
    local c = s:sub(i, i)
    if c == "{" then depth = depth + 1
    elseif c == "}" then
      depth = depth - 1
      if depth == 0 then
        return s:sub(2, i - 1), s:sub(i + 1)
      end
    end
  end
  return nil, nil  -- 未闭合
end

-- 数学保护：$...$ / $$...$$ → 占位符表，返回（文本, 表）
local function protect_math(text)
  local m = {}
  local n = 0
  text = text:gsub("%$%$.-%$%$", function(x) n = n + 1; m[n] = x; return "\x01" .. n .. "\x01" end)
  text = text:gsub("%$[^%$\n]-%$", function(x) n = n + 1; m[n] = x; return "\x01" .. n .. "\x01" end)
  return text, m
end

-- 数学还原：$X$ → <span class="math inline">\(X\)</span>
-- （filter 输出是 HTML RawBlock，quarto 不二次解析 $...$——须自转；
--   \(...\) 是 quarto HTML 数学输出的标准形态，由 MathJax 渲染，内容原样保真）
local function math_span(x)
  local inner = x:sub(2, -2)
  inner = inner:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
  return '<span class="math inline">\\(' .. inner .. '\\)</span>'
end

local function restore_math(text, m)
  return (text:gsub("\x01(%d+)\x01", function(i) return math_span(m[tonumber(i)]) end))
end

-- token 栈扫描：{\color{X} / \emph / \textbf / \textit / \texttt / } → HTML 标签
-- 输入已做数学保护和 \\ → 占位 预处理
local function scan_tokens(text)
  local out = {}
  local stack = {}
  local i = 1
  local n = #text
  while i <= n do
    local rest = text:sub(i)
    if rest:match("^{\\color{%a+}") then
      local cname = rest:match("^{\\color{(%a+)}")
      local hex = XCOLOR[cname]
      if hex then
        table.insert(out, '<span style="color:' .. hex .. '">')
        table.insert(stack, "span")
      else
        table.insert(out, "{\\color{" .. cname .. "}")  -- 未知色原样保留
        table.insert(stack, "raw")
      end
      i = i + #("{\\color{" .. cname .. "}")
    elseif rest:match("^\\emph{") then
      table.insert(out, "<em>"); table.insert(stack, "emph"); i = i + 6
    elseif rest:match("^\\textbf{") then
      table.insert(out, "<strong>"); table.insert(stack, "textbf"); i = i + 8
    elseif rest:match("^\\textit{") then
      table.insert(out, "<em>"); table.insert(stack, "textit"); i = i + 8
    elseif rest:match("^\\texttt{") then
      table.insert(out, "<code>"); table.insert(stack, "texttt"); i = i + 8
    elseif rest:sub(1, 1) == "{" then
      -- 裸 {（非命令参数，如 \ref{...} 的参数）：压 brace 标记并输出字面
      -- （否则 } 弹空栈被当跨行颜色闭合，\ref{eq:...} 的 } 会丢失）
      table.insert(stack, "brace")
      table.insert(out, "{")
      i = i + 1
    elseif rest:sub(1, 1) == "}" then
      local top = table.remove(stack)
      if top == "span" then table.insert(out, "</span>")
      elseif top == "emph" or top == "textit" then table.insert(out, "</em>")
      elseif top == "textbf" then table.insert(out, "</strong>")
      elseif top == "texttt" then table.insert(out, "</code>")
      elseif top == "brace" then table.insert(out, "}")
      else table.insert(out, "\x04") end  -- 栈空：标记 → 弹跨行颜色栈
      i = i + 1
    else
      table.insert(out, rest:sub(1, 1))
      i = i + 1
    end
  end
  -- 未闭合栈：补闭标签（防御）
  for k = #stack, 1, -1 do
    local top = stack[k]
    if top == "span" then table.insert(out, "</span>")
    elseif top == "emph" or top == "textit" then table.insert(out, "</em>")
    elseif top == "textbf" then table.insert(out, "</strong>")
    elseif top == "texttt" then table.insert(out, "</code>")
    elseif top == "brace" then table.insert(out, "}") end
  end
  return table.concat(out)
end

-- 行内容翻译：数学保护 → 扫描 → 还原 → \\ 转 <br>；~ 对齐序列 → 单空格
local function translate_inline(line)
  local t, m = protect_math(line)
  t = t:gsub("\\\\", "\x02")
  t = scan_tokens(t)
  t = restore_math(t, m)
  t = t:gsub("\x02", "<br>")
  t = t:gsub("~+", " ")  -- LaTeX ~ 对齐空格在 HTML 无意义（caption 的 ~~ 已先转 &nbsp;）
  return t
end

-- 算法块翻译：整个 RawBlock 文本（含 \begin{figure} 外层可丢弃）
-- 返回翻译后 HTML 字符串、编号、label 映射
local function translate_block(text, num, cap_prefix, cap_sep)
  -- 定位 \begin{algorithm 与配对 \end{algorithm}（精确子串，不误伤 algorithmic）
  local start = text:find("\\begin{algorithm}")
  if not start then return nil end
  local finish = text:find("\\end{algorithm}")
  if not finish then return nil end
  local body = text:sub(start, finish + #"\\end{algorithm}" - 1)

  -- 提取 caption / label
  local caption, label = nil, nil
  local rest = body
  local cpos = body:find("\\caption{")
  if cpos then
    local inner = balanced_brace(body:sub(cpos + #"\\caption"))
    if inner then caption = inner end
  end
  local lpos = body:find("\\label{")
  if lpos then
    local inner = balanced_brace(body:sub(lpos + #"\\label"))
    if inner then label = inner end
  end

  -- algorithmic 体（\begin{algorithmic}[1] 与 \end{algorithmic} 之间）
  local ab = body:find("\\begin{algorithmic}")
  local ae = body:find("\\end{algorithmic}")
  local algo = ""
  if ab and ae then
    algo = body:sub(ab + #"\\begin{algorithmic}", ae - 1)
    -- 剥行号参数残留：\begin{algorithmic}[1] 的 [1]（在 algorithmic 体开头）
    algo = algo:gsub("^%s*%[%d+%]\r?\n?", "")
  end

  -- caption 翻译（~~ → 空格；token 扫描）
  local cap_html = ""
  if caption then
    local t = caption:gsub("~~", "&nbsp;&nbsp;")
    cap_html = translate_inline(t)
  end

  -- 逐行翻译 algorithmic 体
  local kw = '<span class="algo-kw">'  -- 关键词样式
  local lines_out = {}
  local indent = 0
  local require_html, ensure_html = nil, nil
  local block_kind = nil       -- REQUIRE/ENSURE 续行模式（上一行以 \\ 结尾）
  local color_stack = {}       -- 跨行颜色块（{\color{X} 独立行压栈；孤立 } 弹栈）
  -- li 的跨行颜色（最内层 hex；span 包不了跨 li 的颜色，颜色上 li）
  local function li_style()
    if #color_stack > 0 then
      local hex = XCOLOR[color_stack[#color_stack]]
      if hex then return ' style="color:' .. hex .. '"' end
    end
    return ""
  end
  -- translate_inline 输出里的 \x04（scan_tokens 弹空栈标记）→ 弹跨行颜色栈
  local function pop_colors(html)
    while html:find("\x04") do
      html = html:gsub("\x04", "", 1)
      table.remove(color_stack)
    end
    return html
  end
  for line in algo:gmatch("[^\r\n]+") do
    local trimmed = line:match("^%s*(.*)%s*$") or ""
    if trimmed ~= "" and not trimmed:match("^%%") then
      -- 跨行颜色块：整行 {\color{X} → 压栈；整行 } → 弹栈
      -- （纯字符串检查：pattern 匹配 {\color 踩 \c 转义/捕获组坑，实证 nil）
      local copen = nil
      if trimmed:sub(1, 8) == "{\\color{" and trimmed:sub(-1) == "}" then
        local name = trimmed:sub(9, -2)
        if name:match("^%a+$") then copen = name end
      end
      if copen then
        table.insert(color_stack, copen)
      elseif trimmed == "}" then
        table.remove(color_stack)
      else
        local cmd = trimmed:match("^(\\[A-Za-z]+)")
        -- 非 REQUIRE/ENSURE 的命令行出现 → 退出续行模式
        if cmd and cmd ~= "\\REQUIRE" and cmd ~= "\\ENSURE" then block_kind = nil end
        if cmd == "\\REQUIRE" or cmd == "\\ENSURE" then
          local content = trimmed:sub(#cmd + 1)
          -- 不手动拼 <br>：translate_inline 已把 \\ 转 <br>（否则双 <br>）
          local html = pop_colors(translate_inline(content))
          if cmd == "\\REQUIRE" then
            require_html = (require_html or "") .. html
          else
            ensure_html = (ensure_html or "") .. html
          end
          if trimmed:sub(-2) == "\\\\" then
            block_kind = (cmd == "\\REQUIRE") and "require" or "ensure"
          else
            block_kind = nil
          end
        elseif block_kind and not cmd then
          -- REQUIRE/ENSURE 续行（无命令前缀的缩进行）
          local html = pop_colors(translate_inline(trimmed))
          if block_kind == "require" then
            require_html = (require_html or "") .. html
          else
            ensure_html = (ensure_html or "") .. html
          end
          if trimmed:sub(-2) ~= "\\\\" then block_kind = nil end
        elseif cmd == "\\STATE" then
          local content = trimmed:sub(#cmd + 1)
          -- 行尾注释：翻译后找 $\vartriangleleft$ 数学 span，其后片段 → algo-comment
          -- （plain find：分割 pattern 会消费掉 \vartriangleleft 数学本身——实证
          --   main 停在 {\color{CadetBlue} 且数学丢失；且 \v 转义坑）
          local html = translate_inline(content)
          local marker = '<span class="math inline">\\(\\vartriangleleft\\)</span>'
          local pos = html:find(marker, 1, true)
          if pos then
            local before = html:sub(1, pos + #marker - 1)
            local after = html:sub(pos + #marker)
            if after ~= "" then
              html = before .. '<span class="algo-comment">' .. after .. "</span>"
            end
          end
          html = pop_colors(html)
          lines_out[#lines_out + 1] = string.rep("  ", indent)
            .. "<li" .. li_style() .. ">" .. html .. "</li>"
        elseif cmd == "\\FOR" or cmd == "\\WHILE" or cmd == "\\REPEAT" then
          local kwd = cmd == "\\FOR" and "for" or (cmd == "\\WHILE" and "while" or "repeat")
          local cond = ""
          if cmd ~= "\\REPEAT" then
            -- sub(#cmd+1)：跳过命令名本身（off-by-one 教训：sub(#cmd) 会残留末字符）
            local inner = balanced_brace(trimmed:sub(#cmd + 1))
            if inner then cond = translate_inline(inner) end
          end
          lines_out[#lines_out + 1] = string.rep("  ", indent)
            .. "<li" .. li_style() .. ">" .. kw .. kwd .. '</span> ' .. cond .. " " .. kw .. "do</span>"
          indent = indent + 1
          lines_out[#lines_out + 1] = string.rep("  ", indent) .. "<ol>"
        elseif cmd == "\\ENDFOR" or cmd == "\\ENDWHILE" or cmd == "\\UNTIL" then
          if indent > 0 then
            lines_out[#lines_out + 1] = string.rep("  ", indent) .. "</ol>"
            indent = indent - 1
            local tail = ""
            if cmd == "\\UNTIL" then
              local inner = balanced_brace(trimmed:sub(#cmd + 1))
              if inner then tail = " " .. kw .. "until</span> " .. translate_inline(inner) end
            end
            lines_out[#lines_out + 1] = string.rep("  ", indent) .. "</li>" .. tail
          end
        else
          -- 未知命令/裸文本：原样保留（回退原则）
          lines_out[#lines_out + 1] = string.rep("  ", indent) .. pop_colors(translate_inline(trimmed))
        end
      end
    end
  end

  local out = {}
  local id = label and (" id=\"" .. (label:gsub(":", "-")) .. "\"") or ""
  table.insert(out, '<div class="algorithm-box"' .. id .. ">")
  if cap_html ~= "" then
    table.insert(out, '  <div class="algorithm-caption">' .. cap_prefix .. num .. cap_sep .. cap_html .. "</div>")
  end
  if require_html then
    table.insert(out, '  <div class="algo-require"><strong>Require:</strong> ' .. require_html:gsub("<br>$", "") .. "</div>")
  end
  if ensure_html then
    table.insert(out, '  <div class="algo-ensure"><strong>Ensure:</strong> ' .. ensure_html:gsub("<br>$", "") .. "</div>")
  end
  if #lines_out > 0 then
    table.insert(out, "  <ol>")
    for _, l in ipairs(lines_out) do table.insert(out, "    " .. l) end
    table.insert(out, "  </ol>")
  end
  table.insert(out, "</div>")
  return table.concat(out, "\n"), label
end

function Pandoc(doc)
  local cap_prefix, cap_sep = read_config(doc.meta)

  -- 1) 收集算法块（文档顺序）编号
  local alg_nums = {}
  local counter = 0
  local raw_algos = {}
  local function collect(blocks)
    for _, b in ipairs(blocks) do
      if b.t == "RawBlock" and (b.format == "tex" or b.format == "latex")
        and b.text:find("\\begin{algorithm}") then
        counter = counter + 1
        raw_algos[#raw_algos + 1] = { rb = b, num = counter }
      elseif b.t == "Div" then
        collect(b.content)
      end
    end
  end
  collect(doc.blocks)

  -- 2) 翻译算法块（直接改 RawBlock 对象字段：text + format 都改，
  --    format 必须 html 否则 HTML writer 丢弃；不能替换包装表字段——
  --    doc.blocks 持有原对象引用，替换包装表对文档无效果）
  for _, t in ipairs(raw_algos) do
    local html, label = translate_block(t.rb.text, t.num, cap_prefix, cap_sep)
    if html then
      if label then alg_nums[label] = t.num end
      t.rb.format = "html"
      t.rb.text = html
    end
  end

  -- 3) 正文引用 \ref{alg-X} → <a href="#alg-X">N</a>（RawInline + Math）
  local function ref_link(ref)
    if alg_nums[ref] then
      return '<a href="#' .. ref:gsub(":", "-") .. '">' .. alg_nums[ref] .. "</a>"
    end
    return nil
  end

  local function walk_inlines(inlines)
    local out = pandoc.List({})
    for _, inl in ipairs(inlines) do
      local handled = false
      if (inl.t == "RawInline" and inl.format == "tex") or inl.t == "Math" then
        -- 提取完整 label（含 alg: 前缀，与 alg_nums 的 key 一致）
        local ref = inl.text:match("^\\ref{(alg:[^}]+)}")
        if not ref then ref = inl.text:match("^\\S\\ref{(alg:[^}]+)}") end
        if ref then
          local link = ref_link(ref)
          if link then
            out:insert(pandoc.RawInline("html", link))
            handled = true
          end
        end
      elseif inl.t == "Link" and inl.attr and inl.attr.attributes
        and inl.attr.attributes["reference-type"] == "ref" then
        local ref = inl.attr.attributes["reference"]
        if ref and ref:match("^alg:") then
          local link = ref_link(ref)
          if link then
            out:insert(pandoc.RawInline("html", link))
            handled = true
          end
        end
      end
      if not handled then
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
