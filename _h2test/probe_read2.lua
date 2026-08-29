-- 探针2：pandoc.read 对单栏 table 环境
local s = [[\begin{table}[h]
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
  if c1 and c1.content then
    io.stderr:write("    c1-content=" .. tostring(c1.content[1] and c1.content[1].t) .. "\n")
  end
end
-- 对比：无 caption 的裸 table
local s2 = [[\begin{table}[h]
\begin{tabular}{ll}
A & B \\
\end{tabular}
\end{table}
]]
local d2 = pandoc.read(s2, "latex")
io.stderr:write("s2 blocks=" .. #d2.blocks .. " first=" .. tostring(d2.blocks[1] and d2.blocks[1].t) .. "\n")
