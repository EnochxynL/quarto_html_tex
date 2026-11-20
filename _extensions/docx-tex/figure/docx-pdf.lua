-- PDF figures become SVG. Existing SVG is left to the DOCX writer.
-- Equations never enter this path. Registered as its own filter.
if FORMAT ~= "docx" then return {} end

-- Same conversion helper as the independent HTML/TikZ backend.
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
  local converted, count = {}, 0
  return doc:walk({Image=function(image)
    local path = image.src:gsub('%%(%x%x)',function(h) return string.char(tonumber(h,16)) end)
    if not path:lower():match('%.pdf$') then return end
    local key=path .. '\0' .. (image.attributes.page or '1')
    if not converted[key] then
      count=count+1
      local name='docx-tex-figure-'..count..'.svg'
      local cache='.quarto/docx-tex/pdf-images'
      pandoc.system.make_directory(cache, true)
      local bytes=pdf_to_svg(path, cache..'/'..name, image.attributes.page)
      -- Cairo writes PDF point lengths as unitless SVG attributes. Mark those
      -- generated root lengths as points so the writer does not read them as px.
      bytes=bytes:gsub('<svg%s[^>]*>', function(root)
        return root:gsub('(%swidth=")([%d%.]+)(")', '%1%2pt%3')
                   :gsub('(%sheight=")([%d%.]+)(")', '%1%2pt%3')
      end, 1)
      pandoc.mediabag.insert(name,'image/svg+xml',bytes)
      converted[key]=name
    end
    image.src=converted[key]
    return image
  end})
end
