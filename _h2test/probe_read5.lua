-- 探针5：剥离 table 外壳 + caption/label 后的解析
local s = [[\begin{table}[h]
\centering
\begin{tabular}{ll}
A & B \\
1 & 2 \\
\end{tabular}
\end{table}
]]
-- 模拟剥离：table 外壳、caption、label 去掉
local cleaned = s:gsub("\\begin{table%*?}%[?[^]]*%]?\n?", "")
cleaned = cleaned:gsub("\\end{table%*?}\n?", "")
cleaned = cleaned:gsub("\\caption%b{}\n?", ""):gsub("\\label%b{}\n?", "")
io.stderr:write("cleaned=[" .. cleaned .. "]\n")
local doc = pandoc.read(cleaned, "latex")
io.stderr:write("blocks=" .. #doc.blocks .. " first=" .. tostring(doc.blocks[1] and doc.blocks[1].t) .. "\n")
-- 组合表剥离后形态
local s2 = [[\begin{table*}[h]
\centering
\caption{resizebox 组合表}
\label{tab-complex}
\resizebox{1.12\textwidth}{!}{
\begin{minipage}{0.33\textwidth}
\begin{tabular}{ll}
A & B \\
\end{tabular}
\end{minipage}
}
\end{table*}
]]
local c2 = s2:gsub("\\begin{table%*?}%[?[^]]*%]?\n?", "")
c2 = c2:gsub("\\end{table%*?}\n?", "")
c2 = c2:gsub("\\caption%b{}\n?", ""):gsub("\\label%b{}\n?", "")
c2 = c2:gsub("\\resizebox%b{}%b{}%b{}", function(m)
  local inner = m:match("^\\resizebox%b{}%b{}(%b{})$")
  return inner and inner:sub(2, -2) or m
end)
io.stderr:write("c2=[" .. c2:sub(1, 80) .. "]\n")
local d2 = pandoc.read(c2, "latex")
io.stderr:write("s2 blocks=" .. #d2.blocks .. " first=" .. tostring(d2.blocks[1] and d2.blocks[1].t) .. "\n")
