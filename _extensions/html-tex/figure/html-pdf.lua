-- Local PDF images -> Cairo SVG, keeping native Image attributes and captions.
-- Run post-quarto so format-hidden images are removed before opening files.
if not quarto.format.is_html_output() then return {} end

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

local function decode_path(path)
  return path:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
end

function Pandoc(doc)
  local converted = {}
  local count = 0
  return doc:walk({Image = function(image)
    local path, suffix = image.src:match("^([^?#]+)(.*)$")
    if not path then return nil end
    path = decode_path(path)
    if not path:lower():match("%.pdf$") then return nil end
    -- URL resources remain native images; this filter does not download files.
    if path:match("^%a[%w+.-]*:") and not path:match("^%a:[/\\]") then return nil end
    local page = image.attributes.page or suffix:match("[#&]page=([^&]+)")
    local key = path .. "\0" .. (page or "")
    if converted[key] == nil then
      count = count + 1
      local cache = ".quarto/pdf-images"
      pandoc.system.make_directory(cache, true)
      local svg_path = cache .. "/image-" .. count .. ".svg"
      local svg = pdf_to_svg(path, svg_path, page)
      converted[key] = "data:image/svg+xml;base64," .. quarto.base64.encode(svg)
    end
    image.src = converted[key]
    return image
  end})
end
