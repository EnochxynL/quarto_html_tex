-- html-md-shortcode.lua — markdown 正文术语调用渲染（HTML 插件侧）
--
-- {{< term X >}} → 查 meta.terms[X] → 按格式输出。
-- 背景（定案 2026-09-02）：双端共享 sections 里方法名/术语的排版标记
-- （smallcaps 等）——markdown 表达不了"格式对应的样式"（\textsc 在
-- HTML 端字面、<span> 在 PDF 端字面——实证）。quarto shortcode 机制
-- （contributes.shortcodes）在渲染时展开。术语定义单一 yaml：
--   terms:
--     skillopt: {pdf: '\ourmethod{}', html: '<span class="smallcaps">SkillOpt</span>'}
--
-- 为什么 fn 内做 isFormat 分派（实证 2026-09-02）：quarto **项目级注册**
-- _extensions/ 下所有扩展的 shortcodes（不区分 filters 引用）——html-helper
-- 与 pdf-helper 的同名 term 必然共存、注册覆盖顺序不定——若只输出 html，
-- PDF 渲染时被覆盖版本调用会输出错误格式。故本文件与 pdf-md-shortcode.lua
-- 功能等价（各自按 quarto.doc.isFormat 输出正确格式），归属差异只在插件侧。
-- 降级：术语未定义 → 字面 [term X]（可见——不静默）。

local function is_pdf()
  if quarto.doc and quarto.doc.isFormat then
    return quarto.doc.isFormat("pdf")
  end
  return false
end

return {
  ["term"] = function(args, kwargs, meta)
    -- args 元素是 Pandoc inlines（官方文档）——须 stringify 拿纯字符串
    local name = args and args[1] and pandoc.utils.stringify(args[1])
    local t = meta and meta["terms"] and meta["terms"][name]
    local pdf = is_pdf()
    local fmt = pdf and "latex" or "html"
    local def
    if pdf then
      -- pdf 字段含 latex 命令（'\ourmethod{}'）会被 pandoc 读成
      -- MetaInlines/RawInline——stringify 返回空（实证 2026-09-02）——
      -- 须按类型分派：纯字符串直接取；inlines 序列化回 latex 原文
      local v = t and t["pdf"]
      if v then
        local tp = pandoc.utils.type(v)
        if tp == "MetaString" or tp == "String" then
          def = pandoc.utils.stringify(v)
        else
          local content = v.content or v
          def = pandoc.write(pandoc.Pandoc({ pandoc.Para(content) }), "latex")
          def = def:gsub("%s+$", "")
        end
      end
    else
      -- HTML 端结构化拼装：text（纯文本）+ html-class——配置不手写标签
      -- （实证 2026-09-02：yaml 值含 <tag> 会被 pandoc 读成 MetaInlines/Span，
      -- stringify 提取文本丢标签——故 text 必须纯文本、样式走 class 字段）
      local text = t and pandoc.utils.stringify(t["text"]) or ""
      local cls = t and pandoc.utils.stringify(t["html-class"]) or ""
      if text ~= "" then
        if cls ~= "" then
          def = '<span class="' .. cls .. '">' .. text .. "</span>"
        else
          def = text
        end
      end
    end
    if not def or def == "" then
      return { pandoc.RawInline(fmt, "[term " .. tostring(name) .. "]") }
    end
    return { pandoc.RawInline(fmt, def) }
  end,
}
