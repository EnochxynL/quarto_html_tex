-- 探针7：组合表多 label 的 pandoc.read → HTML 输出
local s = [[\begin{table*}[h]
\centering
\caption{transfer across model scales}
\label{tab-transfer-all}
\resizebox{1.12\textwidth}{!}{
\begin{minipage}{0.33\textwidth}
\begin{tabular}{ll}
A & B \\
\end{tabular}
\label{tab-transfer-cross-model}
\end{minipage}
\begin{minipage}{0.33\textwidth}
\begin{tabular}{ll}
C & D \\
\end{tabular}
\label{tab-transfer-cross-harness}
\end{minipage}
}
\end{table*}
]]
-- 模拟 html-latex-tables 处理链
local cleaned = s:gsub("\\begin{table%*?}%[?[^]]*%]?\n?", "")
cleaned = cleaned:gsub("\\end{table%*?}\n?", "")
cleaned = cleaned:gsub("\\caption%b{}\n?", ""):gsub("\\label%b{}\n?", "")
cleaned = cleaned:gsub("\\centering\n?", "")
cleaned = cleaned:gsub("\\resizebox%b{}%b{}%b{}", function(m)
  local inner = m:match("^\\resizebox%b{}%b{}(%b{})$")
  return inner and inner:sub(2, -2) or m
end)
local doc = pandoc.read(cleaned, "latex")
local html = pandoc.write(doc, "html")
io.stderr:write("ids: ")
for id in html:gmatch('id="([^"]+)"') do io.stderr:write(id .. " ") end
io.stderr:write("\n")
