-- ara.lua — 自定义命令的跨格式短代码
-- PDF 输出 LaTeX 宏；HTML 输出带 class 的 span（供 CSS 样式化）。

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

  ["cmd"] = function(args, kwargs, meta)
    local name = args[1] and pandoc.utils.stringify(args[1]) or ""
    if is_pdf() then
      return { pandoc.RawInline("latex", "\\texttt{ara~" .. name .. "}") }
    else
      return { pandoc.RawInline("html", "<code>ara " .. name .. "</code>") }
    end
  end,

  ["layer"] = function(args, kwargs, meta)
    local name = args[1] and pandoc.utils.stringify(args[1]) or ""
    if is_pdf() then
      return { pandoc.RawInline("latex", "\\texttt{/" .. name .. "}") }
    else
      return { pandoc.RawInline("html", "<code>/" .. name .. "</code>") }
    end
  end,
}
