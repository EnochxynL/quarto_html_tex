-- 探针4：显式 reader 扩展对 table 环境解析的影响
local s = [[\begin{table}[h]
\centering
\begin{tabular}{ll}
A & B \\
\end{tabular}
\caption{c}
\end{table}
]]
local d1 = pandoc.read(s, "latex")
io.stderr:write("plain latex: " .. tostring(d1.blocks[1] and d1.blocks[1].t) .. "\n")
local d2 = pandoc.read(s, "latex+tables")
io.stderr:write("latex+tables: " .. tostring(d2.blocks[1] and d2.blocks[1].t) .. "\n")
local ok, d3 = pcall(function() return pandoc.read(s, "latex", {extensions = {tables = true}}) end)
io.stderr:write("opts tables=true: " .. (ok and tostring(d3.blocks[1] and d3.blocks[1].t) or "ERR " .. tostring(d3)) .. "\n")
