-- skillopt.lua — SkillOpt 论文自定义命令的跨格式短代码
-- PDF 出 LaTeX 宏；HTML 出带 class 的 span（供 CSS 样式化）。
-- 仿 arXiv-2604.24658v3/ara.lua 模式；宏定义本身在 index.qmd 的
-- latex-macros 配置（表格子文档解析用）+ include-in-header（PDF 端）。

local function is_pdf()
  if quarto.doc and quarto.doc.isFormat then
    return quarto.doc.isFormat("pdf")
  end
  return false
end

return {
  ["skillopt"] = function(args, kwargs, meta)
    if is_pdf() then
      return { pandoc.RawInline("latex", "\\textsc{SkillOpt}") }
    else
      return { pandoc.RawInline("html", '<span class="smallcaps">SkillOpt</span>') }
    end
  end,
}
