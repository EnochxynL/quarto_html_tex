-- term.lua — 术语跨格式 shortcode（独立插件，2026-09-02 定案）
--
-- {{< term X >}} → 查 meta.terms[X]，按渲染格式取字段输出：
--   terms:
--     skillopt:
--       pdf: '\ourmethod{}'                                  # latex 片段
--       html: '<span class="smallcaps">SkillOpt</span>'      # html 片段（用户手写——样式自由，不限于 span）
--
-- 背景：双端共享 sections 里方法名/术语的排版——markdown 表达不了
-- "格式对应的样式"（quarto markdown 无 raw_tex——正文 latex 命令全被
-- pandoc 吞空，唯 \ref 系数学化保留——实证 2026-09-02）。shortcode 是
-- quarto 正文跨格式内联唯一桥。
--
-- 挂载：本扩展放 _extensions/ 即自动注册（官方实证——无需 yaml 声明）。
-- 曾并入 html-tex/pdf-helper（html-md-shortcode/pdf-md-shortcode）——
-- 两版 fn 完全等价（quarto 项目级注册所有扩展 shortcode，需 isFormat 分派
-- 兜底）——伪分工——独立成 term 插件，配置字段 pdf/html 由用户手写片段
-- （样式是术语自定义的一部分）。
--
-- 保真取回（实证坑）：yaml 值含 latex 命令/html 标签会被 pandoc 读成
-- MetaInlines（stringify 丢内容：RawInline→空、Span→纯文本）——按类型
-- 分派：MetaString 直接取；inlines 序列化回目标格式原文。
-- 降级：术语未定义 → 字面 [term X]（可见——不静默）。

local function raw_value(v, fmt)
  local tp = pandoc.utils.type(v)
  if tp == "MetaString" or tp == "String" then
    return pandoc.utils.stringify(v)
  end
  local content = v.content or v
  local s = pandoc.write(pandoc.Pandoc({ pandoc.Para(content) }), fmt)
  return s:gsub("%s+$", "")
end

return {
  ["term"] = function(args, kwargs, meta)
    -- args 元素是 Pandoc inlines（官方文档）——须 stringify 拿纯字符串
    local name = args and args[1] and pandoc.utils.stringify(args[1])
    local t = meta and meta["terms"] and meta["terms"][name]
    local pdf = quarto.doc and quarto.doc.isFormat and quarto.doc.isFormat("pdf")
    local key = pdf and "pdf" or "html"    -- 配置字段名（terms.X.pdf/html）
    local fmt = pdf and "latex" or "html"  -- pandoc 格式名（RawInline/write 用）
    local def = t and raw_value(t[key], fmt) or ""
    if def == "" then
      return { pandoc.RawInline(fmt, "[term " .. tostring(name) .. "]") }
    end
    return { pandoc.RawInline(fmt, def) }
  end,
}
