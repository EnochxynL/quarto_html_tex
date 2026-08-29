-- 探针：pandoc.read 对 table 环境的 Lua API 行为
local s = [[\begin{table*}[h]
\centering
\caption{resizebox 组合表}
\label{tab-complex}
\begin{minipage}{0.33\textwidth}
\begin{tabular}{ll}
A & B \\
\end{tabular}
\end{minipage}
\end{table*}
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
