-- ara.lua — 自定义命令的跨格式短代码
-- PDF 出 LaTeX 宏；HTML 出带 class 的 span（供 CSS 样式化）。
-- Phase 1 只需 ara；cmd/layer/storytax/engtax/cmark/xmark 在 Phase 2 处理 .tex 时再补。

local function is_pdf()
  if quarto.doc and quarto.doc.isFormat then
    return quarto.doc.isFormat("pdf")
  end
  return false
end

return {
  ["ara"] = function(args, kwargs, meta)
    if is_pdf() then
      return { pandoc.RawInline("latex", "\\textsc{Ara}") }
    else
      return { pandoc.RawInline("html", '<span class="ara">Ara</span>') }
    end
  end,
}
