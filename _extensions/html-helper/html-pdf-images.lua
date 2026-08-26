-- html-pdf-images.lua — HTML 端把 .pdf 源图替换为同名 .png（浏览器原生 <img>）
--
-- 背景：quarto 对 .pdf 源图在 HTML 端输出 <embed>（浏览器 PDF viewer 嵌入），
-- 表现不可控：宽度不撑满（img-fluid 的 max-width 只设上限）、强制 width 后
-- 高度又不按原图比例（viewer 行为）。PNG 位图 <img> 无此问题（固有尺寸比例天然正确）。
--
-- 约定：预处理把 figures/*.pdf 转成同名 .png（pdftoppm -f 1 -l 1 -png -r 300），
-- 此 filter 在 HTML 端把 Image src 的 .pdf 换 .png → pandoc 输出 <img>。
-- PDF 端不受影响（.pdf 矢量保真）。
--
-- 注意（踩坑记录）：
--   本 pandoc 版本的函数 filter（function Image()）不可靠（README 踩坑 1），
--   用 Pandoc(doc) 回调 + 手写递归遍历 Image。
if FORMAT ~= "html" and FORMAT ~= "html5" then
  return {}
end

-- 递归替换 inlines 里的 Image src
local function walk_inlines(inlines)
  for _, il in ipairs(inlines) do
    if il.t == "Image" then
      if il.src:match("%.pdf$") then
        local png = il.src:gsub("%.pdf$", ".png")
        -- 文件存在才替换（转换缺失时保留原路径，宁可 embed 也不 broken image）
        local f = io.open(png, "r")
        if f then
          f:close()
          il.src = png
        end
      end
    elseif il.content then
      walk_inlines(il.content)
    end
  end
end

local function process_blocks(blocks)
  for _, b in ipairs(blocks) do
    if b.t == "Para" or b.t == "Plain" then
      walk_inlines(b.content)
    elseif b.t == "Div" or b.t == "BlockQuote" or b.t == "Figure" then
      process_blocks(b.content)
    end
  end
end

function Pandoc(doc)
  process_blocks(doc.blocks)
  return doc
end
