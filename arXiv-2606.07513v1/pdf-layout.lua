-- The source contains page-sized case-study and prompt tables. Keep their
-- captions outside the box and constrain the body to leave space for them.
if FORMAT ~= "latex" and FORMAT ~= "pdf" then return {} end

function Pandoc(doc)
  local file = assert(io.open("Sections/0_abstract.md", "r"))
  local abstract = file:read("*a")
  file:close()
  doc.meta.abstract = pandoc.MetaBlocks(pandoc.read(abstract, "markdown").blocks)
  return doc
end

function RawBlock(block)
  if (block.format ~= "latex" and block.format ~= "tex")
    or not block.text:match("\\begin{table%*?}") then return end
  local function fit(body)
    return "\\adjustbox{max totalsize={\\linewidth}{0.8\\textheight}}{" .. body .. "}"
  end
  local resized = false
  block.text = block.text:gsub("\\resizebox%b{}%b{}%b{}", function(box)
    if box:find("\\begin{tabular}", 1, true) then
      resized = true
      return fit(box)
    end
    return box
  end)
  if not resized then
    block.text = block.text:gsub("(\\begin{tabular}.*\\end{tabular})", fit)
  end
  return block
end
