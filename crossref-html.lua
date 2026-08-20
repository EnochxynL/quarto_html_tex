-- crossref-html.lua — HTML 里 raw \ref{X} 是 RawInline("tex")，之后会被 Quarto 转成坏数学。
-- 这里把它们转成占位符 [§X]。Phase 2 换成真正的链接。
function RawInline(el)
  if FORMAT ~= "html" then
    return nil
  end
  if el.format ~= "tex" then
    return nil
  end
  local ref = el.text:match("^\\ref{([^}]+)}$")
  if ref then
    return pandoc.Str("[§" .. ref .. "]")
  end
  ref = el.text:match("^\\S\\ref{([^}]+)}$")
  if ref then
    return pandoc.Str("[§" .. ref .. "]")
  end
  return nil
end
