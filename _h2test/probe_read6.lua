-- 探针6：main.lua 环境下 \centering 对顶层 tabular 解析的影响
-- 模拟：剥离 \centering 后 pandoc.read
local s1 = [[\begin{tabular}{ll}
A & B \\
1 & 2 \\
\end{tabular}
]]
local s2 = [[\centering
\begin{tabular}{ll}
A & B \\
1 & 2 \\
\end{tabular}
]]
local d1 = pandoc.read(s1, "latex")
io.stderr:write("无centering: " .. tostring(d1.blocks[1] and d1.blocks[1].t) .. "\n")
local d2 = pandoc.read(s2, "latex")
io.stderr:write("有centering: " .. tostring(d2.blocks[1] and d2.blocks[1].t) .. "\n")
if d2.blocks[1] and d2.blocks[1].content then
  io.stderr:write("  c1=" .. tostring(d2.blocks[1].content[1] and d2.blocks[1].content[1].t) .. "\n")
end
-- 有 \begin{center} 包裹呢
local s3 = [[\begin{center}
\begin{tabular}{ll}
A & B \\
\end{tabular}
\end{center}
]]
local d3 = pandoc.read(s3, "latex")
io.stderr:write("center环境: " .. tostring(d3.blocks[1] and d3.blocks[1].t) .. "\n")
