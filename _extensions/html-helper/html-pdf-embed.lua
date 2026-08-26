-- html-pdf-embed.lua — HTML 端：.pdf 源图 → embed + 自动比例（读 MediaBox 算 aspect-ratio）
--
-- 背景：浏览器 <img> 不支持 PDF，pandoc 对 .pdf 图输出裸 <embed>（无尺寸），
-- 浏览器 PDF viewer 嵌入不可控：宽度不撑满（img-fluid 的 max-width 只设上限）、
-- 强制 width 后高度又不按原图比例。转 PNG 会损失矢量（且需预处理）。
--
-- 方案：Lua 直接读 PDF 文件头部的 /MediaBox（明文，如 [0 0 612 792]），
-- 算 aspect-ratio = W/H，输出 <embed style="width:100%; aspect-ratio:W/H">——
-- 现代浏览器按 width + aspect-ratio 自动计算高度，比例与原图一致，且保留 PDF 矢量。
-- 多页 PDF 取第一页（页面对象通常未压缩，MediaBox 明文可读）。
--
-- 降级：MediaBox 读不到（对象流压缩等）→ 返回原 Image（quarto 默认 embed + img-fluid，
-- styles.css 的 embed[src$=".pdf"] { width:100% } 兜底宽度）。
--
-- 注意（踩坑记录）：
--   本 pandoc 版本的函数 filter 不可靠（README 踩坑 1），用 Pandoc(doc) 回调 +
--   手写递归遍历 Image；Image attr 的 style 键被 pandoc 丢弃（实测），只能 RawInline。
if FORMAT ~= "html" and FORMAT ~= "html5" then
  return {}
end

-- 读 PDF MediaBox 计算宽高比（第一页）
local function pdf_aspect(src)
  local f = io.open(src, "rb")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  local w, h = content:match("/MediaBox%s*%[%s*[%d%.]+%s+[%d%.]+%s+([%d%.]+)%s+([%d%.]+)%s*%]")
  if w and h then
    local hh = tonumber(h)
    if hh and hh > 0 then
      return string.format("%.3f", tonumber(w) / hh)
    end
  end
  return nil
end

-- 递归替换 inlines 里的 PDF Image → RawInline embed
local function walk_inlines(inlines)
  local out = {}
  for _, il in ipairs(inlines) do
    if il.t == "Image" and il.src:match("%.pdf$") then
      local ratio = pdf_aspect(il.src)
      if ratio then
        -- #toolbar=0&navpanes=0：隐藏 Chrome/Edge PDF viewer 的工具栏与侧栏
        -- #view=FitH：强制 fit width（viewer 默认缩放会留白，FitH 让页面水平占满框，
        -- 框 aspect-ratio=页面比例 → 高度自然吻合）。fragment 不随请求发送
        out[#out + 1] = pandoc.RawInline("html",
          '<embed src="' .. il.src .. '#toolbar=0&navpanes=0&view=FitH" style="width:100%; aspect-ratio:' .. ratio .. '">')
      else
        out[#out + 1] = il
      end
    elseif il.content then
      il.content = pandoc.List(walk_inlines(il.content))
      out[#out + 1] = il
    else
      out[#out + 1] = il
    end
  end
  return out
end

local function process_blocks(blocks)
  local out = {}
  for _, b in ipairs(blocks) do
    if b.t == "Para" or b.t == "Plain" then
      b.content = pandoc.List(walk_inlines(b.content))
      out[#out + 1] = b
    elseif b.t == "Div" or b.t == "BlockQuote" or b.t == "Figure" then
      b.content = pandoc.List(process_blocks(b.content))
      out[#out + 1] = b
    else
      out[#out + 1] = b
    end
  end
  return out
end

function Pandoc(doc)
  doc.blocks = pandoc.List(process_blocks(doc.blocks))
  return doc
end
