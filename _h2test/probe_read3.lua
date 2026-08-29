-- 探针3：宏定义前缀 + 单栏 table 环境
local prefix = "\\newcommand{\\ara}{\\textsc{ARA}}\n"
local s = prefix .. [[\begin{table}[h]
\centering
\begin{tabular}{ll}
A & B \\
1 & 2 \\
\end{tabular}
\caption{simple latex table}
\label{tab-simple-latex}
\end{table}
]]
local doc = pandoc.read(s, "latex")
io.stderr:write("blocks=" .. #doc.blocks .. " first=" .. tostring(doc.blocks[1] and doc.blocks[1].t) .. "\n")
if doc.blocks[1] and doc.blocks[1].content then
  local c1 = doc.blocks[1].content[1]
  io.stderr:write("  first-content=" .. tostring(c1 and c1.t) .. "\n")
end
-- 探针4：multicolumn 展开后的形态（含 multicolumn）
local s2 = prefix .. [[\begin{table}[h]
\centering
\begin{tabular}{ll}
\multicolumn{2}{c}{X} \\
\end{tabular}
\caption{c}
\end{table}
]]
local d2 = pandoc.read(s2, "latex")
io.stderr:write("s2 blocks=" .. #d2.blocks .. " first=" .. tostring(d2.blocks[1] and d2.blocks[1].t) .. "\n")
