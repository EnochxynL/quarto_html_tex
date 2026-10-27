-- html-css.lua — 插件默认样式注入
--
-- 作用：把同目录 html-css.css 注入文档（<style> RawBlock，文档开头）。
--   默认生效（挂上 html-tex 即有），零配置。
--
-- 覆盖机制：html-css.css 全部规则用 :where() 包裹（零特异性 0,0,0）——
--   项目 styles.css 的正常规则（特异性 ≥ 0,1,0）天然压过默认，无需 !important、
--   无需调整加载顺序。论文想改观感：styles.css 写同选择器规则即可覆盖。
--
-- 定位 css：debug.getinfo 取本文件路径 → 同目录 html-css.css
--   （filter 执行时 cwd 是项目根，不能直接用相对路径）
if FORMAT ~= "html" and FORMAT ~= "html5" then
  return {}
end

local src = debug.getinfo(1, "S").source:sub(2)  -- 去掉开头的 @
local dir = src:match("^(.*)[/\\]") or "."
local css_path = dir .. "/" .. "html-css.css"  -- dir 末尾无分隔符，需补 /（Lua io.open 支持）
local f, err = io.open(css_path, "r")
local css = f and f:read("*a") or ""
if f then f:close() end

function Pandoc(doc)
  if css ~= "" then
    doc.blocks:insert(1, pandoc.RawBlock("html", "<style>\n" .. css .. "\n</style>"))
  end
  return doc
end
