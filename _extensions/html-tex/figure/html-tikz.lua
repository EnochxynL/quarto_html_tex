-- Raw TikZ drawing bodies -> PDF -> Cairo SVG for HTML.
-- Register twice: prepare native images before Quarto, then compile after the
-- reference bridge has supplied document numbers. PDF keeps the original TeX.
if not quarto.format.is_html_output() then return {} end

local state_key = "html-tex-tikz-pending"
local marker = "data-html-tex-tikz"
local citation_marker = "data-html-tex-tikz-citation"
local placeholder = 'data:image/svg+xml;base64,' .. quarto.base64.encode(
  '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="50"></svg>')

local function text(value, default)
  if value == nil then return default end
  return pandoc.utils.stringify(value)
end

-- Expose drawing citations to the parent's normal citeproc pass at the drawing's
-- position. Keep the TeX drawing intact apart from numbered substitution slots;
-- do not run a separate bibliography processor with a different citation order.
local function prepare_citations(source, citations)
  local result, position = {}, 1
  while position <= #source do
    local char = source:sub(position, position)
    if char == "%" then
      local last = source:find("\n", position, true) or #source
      result[#result + 1] = source:sub(position, last)
      position = last + 1
    elseif char == "\\" then
      local command = source:match("^(\\cite%a*%*?)", position)
      local last = command and position + #command or position
      if command then
        local function skip_space()
          local space = source:match("^%s*", last)
          last = last + #space
        end
        skip_space()
        while source:sub(last, last) == "[" do
          local option = source:match("^%b[]", last)
          if not option then break end
          last = last + #option
          skip_space()
        end
        local argument = source:match("^%b{}", last)
        if argument then
          last = last + #argument
          local parsed = pandoc.read(source:sub(position, last - 1), "latex")
          local found = false
          parsed:walk({Cite = function() found = true end})
          if found then
            local inlines = pandoc.Inlines({})
            for _, block in ipairs(parsed.blocks) do inlines:extend(block.content) end
            local index = tostring(#citations + 1)
            citations:insert(pandoc.Span(inlines, pandoc.Attr("", {}, {[citation_marker] = index})))
            result[#result + 1] = "\\htmltextikzcitation{" .. index .. "}"
            position = last
          else command = nil end
        else command = nil end
      end
      if not command then
        -- Copy escaped percent signs/backslashes together so they cannot start
        -- comments or citation commands on the next iteration.
        result[#result + 1] = source:sub(position, position + 1)
        position = position + 2
      end
    else
      result[#result + 1] = char
      position = position + 1
    end
  end
  return table.concat(result)
end

local function write(path, value)
  local file = assert(io.open(path, "wb"), "html-tikz: cannot write " .. path)
  file:write(value)
  file:close()
end

local function read(path)
  local file = assert(io.open(path, "rb"), "html-tikz: cannot read " .. path)
  local value = file:read("*a")
  file:close()
  return value
end

local function run(program, args, log)
  local ok, output = pcall(pandoc.pipe, program, args, "")
  write(log, tostring(output))
  assert(ok, "html-tikz: " .. program .. " failed; see " .. log .. "\n" .. tostring(output))
end

-- Keep this helper identical in html-pdf.lua and html-tikz.lua. Deliberately
-- self-contained: no module loading or filter-relative path resolution.
local function pdf_to_svg(pdf_path, svg_path, page)
  os.remove(svg_path .. ".log")
  local function command(program, args)
    local ok, output = pcall(pandoc.pipe, program, args, "")
    local log = assert(io.open(svg_path .. ".log", "ab"))
    log:write(program .. "\n" .. tostring(output) .. "\n")
    log:close()
    assert(ok, "html-tex: " .. program .. " failed for " .. pdf_path
      .. "; see " .. svg_path .. ".log\n" .. tostring(output))
    return output
  end
  local info = command("pdfinfo", {pdf_path})
  local pages = assert(tonumber(info:match("Pages:%s*(%d+)")),
    "html-tex: could not read PDF page count: " .. pdf_path)
  if page == nil then
    assert(pages == 1, "html-tex: " .. pdf_path .. " has " .. pages
      .. " pages; explicitly select an image page with {page=N}")
    page = 1
  end
  page = tonumber(page)
  assert(page and page >= 1 and page <= pages and page == math.floor(page),
    "html-tex: invalid PDF image page for " .. pdf_path .. " (1.." .. pages .. ")")
  command("pdftocairo", {"-svg", "-noshrink", "-f", tostring(page), "-l", tostring(page), pdf_path, svg_path})
  local file = assert(io.open(svg_path, "rb"), "html-tex: missing converted SVG " .. svg_path)
  local svg = file:read("*a")
  file:close()
  assert(svg:find("<svg", 1, true), "html-tex: invalid converted SVG " .. svg_path)
  return svg
end


function Pandoc(doc)
  local pending = doc.meta[state_key]
  if pending == nil then
    pending = pandoc.MetaList({})
    local citations = pandoc.Inlines({})
    doc = doc:walk({RawBlock = function(block)
      if block.format ~= "latex" and block.format ~= "tex" then return nil end
      if not block.text:match("\\begin%s*{tikzpicture}") and
          not block.text:match("\\tikz%f[^%a]") then return nil end
      -- A table/algorithm containing a small drawing belongs to the existing
      -- environment renderer, not to the standalone figure compiler.
      if block.text:match("\\begin%s*{table%*?}") or
          block.text:match("\\begin%s*{algorithm%*?}") then return nil end
      assert(not block.text:match("\\begin%s*{figure%*?}"),
        "html-tikz: put the drawing body in a raw LaTeX block inside a #fig- Div; keep its caption as Markdown")
      local first = #citations + 1
      pending:insert(pandoc.MetaString(prepare_citations(block.text, citations)))
      local blocks = {pandoc.Para({pandoc.Image({pandoc.Str("Diagram")}, placeholder, "",
        pandoc.Attr("", {"html-tex-tikz"}, {[marker] = tostring(#pending), width = "100%"}))})}
      if #citations >= first then
        local slots = pandoc.Inlines({})
        for i = first, #citations do slots:insert(citations[i]) end
        blocks[#blocks + 1] = pandoc.Plain(slots)
      end
      return blocks
    end})
    doc.meta[state_key] = pending
    return doc
  end
  if #pending == 0 then return doc end

  local config = (doc.meta["html-tex"] or {}).tikz or {}
  local engine = text(config.engine, "pdflatex")
  assert(engine == "pdflatex" or engine == "lualatex" or engine == "xelatex",
    "html-tikz: engine must be pdflatex, lualatex or xelatex")
  local header = config["preamble-file"] and read(text(config["preamble-file"])) or ""
  local references = assert(doc.meta["html-tex-tikz-references"],
    "html-tikz: compile after latex/html-latex-ref.lua at post-quarto")
  local definitions = {}
  for identifier, number in pairs(references) do
    definitions[#definitions + 1] = "\\newlabel{" .. identifier .. "}{{" .. text(number) .. "}{1}}"
  end
  table.sort(definitions)
  local citations = {}
  local has_citations = false
  doc:walk({Span = function(span)
    if span.attributes[citation_marker] then has_citations = true end
  end})
  if has_citations then
    local available = {}
    for _, reference in ipairs(pandoc.utils.references(doc)) do
      available[pandoc.utils.stringify(reference.id)] = true
    end
    doc:walk({Span = function(span)
      if not span.attributes[citation_marker] then return nil end
      span:walk({Cite = function(cite)
        for _, citation in ipairs(cite.citations) do
          assert(available[citation.id],
            "html-tikz: unresolved drawing citation: " .. citation.id)
        end
      end})
    end})
  end
  -- post-quarto precedes Pandoc's final citeproc pass. Process a full-document
  -- copy, never individual citations, so numbering/disambiguation matches the
  -- parent. Leave invisible citation nodes in the parent for its final pass;
  -- removing them would change first-use order and omit drawing-only sources.
  local rendered = has_citations and pandoc.utils.citeproc(doc:clone()) or doc
  rendered:walk({Span = function(span)
    local index = span.attributes[citation_marker]
    if not index then return nil end
    citations[index] = pandoc.write(pandoc.Pandoc({pandoc.Plain(span.content)}), "latex")
      :gsub("%s+$", "")
  end})
  doc = doc:walk({Span = function(span)
    if not span.attributes[citation_marker] then return nil end
    span.attributes[citation_marker] = nil
    span.attributes.style = "display:none"
    span.attributes["aria-hidden"] = "true"
    return span
  end})
  doc = doc:walk({Image = function(image)
    local index = image.attributes[marker]
    if not index then return nil end
    local body = assert(pending[tonumber(index)], "html-tikz: missing drawing " .. index)
    local cache = ".quarto/tikz/figure-" .. index
    pandoc.system.make_directory(cache, true)
    -- Recompile every render so changes in input CSV files/images are observed.
    os.remove(cache .. "/figure.aux")
    local drawing = text(body):gsub("\\htmltextikzcitation{(%d+)}", function(slot)
      return assert(citations[slot], "html-tikz: missing processed drawing citation " .. slot)
    end)
    local source = "\\documentclass{article}\n" .. header
      .. "\n\\usepackage{tikz}\n\\usepackage[active,tightpage]{preview}\n"
      .. "\\providecommand{\\citeproc}[2]{#2}\n"
      .. "\\setlength{\\PreviewBorder}{2pt}\n" .. table.concat(definitions, "\n")
      .. "\n\\begin{document}\n\\begin{preview}\n\\begin{minipage}{\\textwidth}\n"
      .. drawing .. "\n\\end{minipage}\n\\end{preview}\n\\end{document}\n"
    write(cache .. "/figure.tex", source)
    for pass = 1, 2 do
      run(engine, {"-interaction=nonstopmode", "-halt-on-error", "-jobname=figure",
        "-output-directory=" .. cache, cache .. "/figure.tex"}, cache .. "/pass-" .. pass .. ".txt")
    end
    local log = read(cache .. "/figure.log")
    assert(not log:find("There were undefined references", 1, true),
      "html-tikz: unresolved drawing references; see " .. cache .. "/figure.log")
    assert(not log:find("There were undefined citations", 1, true) and not log:match("Citation.-undefined"),
      "html-tikz: unresolved drawing citations; see " .. cache .. "/figure.log")
    assert(not log:find("Missing character:", 1, true),
      "html-tikz: missing drawing glyphs; check fonts in " .. cache .. "/figure.log")
    image.src = "data:image/svg+xml;base64," .. quarto.base64.encode(
      pdf_to_svg(cache .. "/figure.pdf", cache .. "/figure.svg"))
    image.attributes[marker] = nil
    return image
  end})
  -- Quarto may intentionally remove prepared images through content-visible
  -- conditions. Compile only surviving nodes, not every early source block.
  doc.meta[state_key] = nil
  doc.meta["html-tex-tikz-references"] = nil
  return doc
end
