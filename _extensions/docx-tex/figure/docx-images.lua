-- PDF figures -> PNG. Equations stay native and never enter this path.
local M = {}
function M.convert(doc, directory)
  local converted, count = {}, 0
  return doc:walk({Image=function(image)
    local path = image.src:gsub('%%(%x%x)',function(h) return string.char(tonumber(h,16)) end)
    if path:match('^data:image/svg%+xml') or path:lower():match('%.svg$') then
      if not converted[path] then
        local mime, svg = pandoc.mediabag.fetch(image.src)
        assert(svg and mime:find('svg'), 'Cannot read SVG: '..image.src:sub(1,100))
        local png = pandoc.pipe('uv', {'run','--locked','--script',directory .. '/figure/svg-to-png.py'}, svg)
        count=count+1
        local name='docx-tex-figure-'..count..'.png'
        pandoc.mediabag.insert(name,'image/png',png)
        converted[path]=name
      end
      image.src=converted[path]
      return image
    end
    if not path:lower():match('%.pdf$') then return end
    local key=path .. '\0' .. (image.attributes.page or '1')
    if not converted[key] then
      local info = pandoc.pipe('pdfinfo',{path},'')
      local pages = assert(tonumber(info:match('Pages:%s*(%d+)')),'Cannot inspect PDF: '..path)
      local page = tonumber(image.attributes.page or '1')
      assert(pages==1 or image.attributes.page,'Multi-page PDF needs {page=N}: '..path)
      assert(page>=1 and page<=pages and page==math.floor(page),'Invalid PDF page: '..path)
      local bytes = pandoc.pipe('pdftoppm',{'-png','-singlefile','-scale-to','2400','-f',tostring(page),'-l',tostring(page),path},'')
      count=count+1
      local name='docx-tex-figure-'..count..'.png'
      pandoc.mediabag.insert(name,'image/png',bytes)
      converted[key]=name
    end
    image.src=converted[key]
    return image
  end})
end
return M
