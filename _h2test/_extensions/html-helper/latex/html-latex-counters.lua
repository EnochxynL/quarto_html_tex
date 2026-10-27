-- html-latex-counters.lua — 全文计数器注册与编号（latex 块 caption 排序）
--
-- 职责（caption 排序与 ref 模块的 fig/tbl/sec 同构——独立成模块，
-- lwarp 管道不持有任何"算法"概念）：
--   1) 扫描全文 RawBlock(tex/latex) 非表格块 + latex-macros（文档层注册区）
--   2) 收集计数器注册：\newfloat{X} / \newtheorem{X} / \newtheorem{X}[共享] /
--      \newcounter{X}——注册源：块内（本块自洽）与 latex-macros（跨块共享
--      由文档层声明）；块内注册不强求跨块（用户拍板 2026-09-02）
--   3) 每块主计数器判定（第一个 \begin{ENV}）：
--      注册表共享（\newtheorem{X}[Y]）→ 计数器 Y（惯例猜不到，必须注册表）
--      否则 float 惯例 → 计数器 = 环境名（LaTeX float 注册惯例：
--      \newfloat{algorithm} → 计数器 algorithm）
--      无 \begin 环境 → 不计数（LaTeX 语义：环境本身不编号，编号是
--      \caption/\refstepcounter 对已注册计数器的步进——无注册不编号）
--   4) 按计数器名分组计数 → 每块起始值 start（第 N 个使用该计数器的块
--      → start = N-1——lwarp 侧注入 \setcounter{counter}{start}）
--   5) 块内 label → 全文编号 = start+1（块内 \caption/\refstepcounter
--      步进后捕获；正文 \ref 与块内 @@REF 解析都用它）
--
-- 输出写 doc.meta["html-tex-lwarp-counters"]（lwarp filter 读）：
--   blocks: MetaList——第 k 个编译候选块（含 \begin{ENV}，与 lwarp 的
--           is_compile_candidate 分派一致）的 {counter=计数器名, start=起始值}
--   refs:   MetaMap——label → 编号（start+1）
--
-- 已知限制：
--   - float 惯例对"环境名≠计数器名"的非注册环境会误判（如裸 algorithmic——
--     algorithmicx 内部行号计数器是 ALG@line）——lwarp 侧注入
--     \@ifundefined{c@ENV} 保护兜底：计数器实际不存在则跳过注入（不崩）
--   - 无 \begin{ENV} 的块（PDF 控制片段）不发 blocks 条目也不登记 refs
if FORMAT ~= "html" and FORMAT ~= "html5" then
  return {}
end

-- 表格块：跳过（html-latex-tables.lua 的领地——它已先跑把表格 RawBlock
-- 转 HTML；此处防御性保留）
local function is_table_block(text)
  return text:find("\\begin{tabular", 1, true) ~= nil
      or text:find("\\begin{table", 1, true) ~= nil
end

-- 提取块内全部 label
local function extract_labels(text)
  local labels = {}
  for lab in text:gmatch("\\label{([^}]+)}") do
    labels[#labels + 1] = lab
  end
  return labels
end

-- 从 latex-macros 读取（与 html-latex-lwarp 的 read_config 同逻辑——块状
-- MetaBlocks 手动提取 RawBlock 文本；注册区可能含 \newtheorem 等定义）
local function read_macros(meta)
  local pt = meta["html-tex"] or {}
  local v = pt["latex-macros"]
  if v == nil then return "" end
  local typ = pandoc.utils.type(v)
  if typ == "Blocks" or typ == "MetaBlocks" then
    local parts = {}
    for _, b in ipairs(v) do
      if b.t == "RawBlock" and (b.format == "latex" or b.format == "tex") then
        parts[#parts + 1] = b.text
      elseif b.t == "Para" or b.t == "Plain" then
        parts[#parts + 1] = pandoc.utils.stringify(b)
      end
    end
    return table.concat(parts, "\n")
  end
  return pandoc.utils.stringify(v)
end

-- 收集注册：共享表 shared_of（\newtheorem{X}[Y] → X 用 Y 计数器）+
-- 同名注册集 regs（\newfloat{X}/\newtheorem{X}/\newcounter{X}——计数器
-- 与 X 同名，惯例即可覆盖；regs 仅作语义记录）
local function collect_registrations(src, shared_of)
  for name, shared in src:gmatch("\\newtheorem{([^}]+)}%[([^%]]+)%]") do
    shared_of[name] = shared
  end
  -- \newtheorem{NAME} 的普通 gmatch 会匹配到共享形式的前半（NAME）——
  -- shared_of 已记录则跳过
  for name in src:gmatch("\\newtheorem{([^}]+)}") do
    if not shared_of[name] then shared_of[name] = name end
  end
  for name in src:gmatch("\\newfloat{([^}]+)}") do
    shared_of[name] = name
  end
  for name in src:gmatch("\\newcounter{([^}]+)}") do
    shared_of[name] = name
  end
end

return {
  {
    Pandoc = function(doc)
      local macros = read_macros(doc.meta)
      local shared_of = {}
      collect_registrations(macros, shared_of)

      -- 第一遍收集所有 tex 非表格块（块内注册也进 shared_of——本块自洽）
      local tex_blocks = {}
      for _, blk in ipairs(doc.blocks) do
        if blk.t == "RawBlock" and (blk.format == "tex" or blk.format == "latex") then
          if not is_table_block(blk.text) then
            tex_blocks[#tex_blocks + 1] = blk.text
            collect_registrations(blk.text, shared_of)
          end
        end
      end

      -- 第二遍：每块主环境 → 计数器 → 分组计数
      -- 只对有 \begin{ENV} 的块发条目（无环境=PDF 控制片段——与 lwarp
      -- 的 is_compile_candidate 分派一致，保证 blocks 索引对齐）
      local counts = {}  -- 计数器名 → 已出现次数（下一个块的 start）
      local blocks = {}
      local refs = {}
      for _, text in ipairs(tex_blocks) do
        local env = text:match("\\begin{([^}]+)}")
        if env then
          -- 共享注册优先（\newtheorem{X}[Y]——惯例猜不到）；否则环境名
          --（float 惯例 / 同名注册）
          local counter = shared_of[env] or env
          local info = { counter = counter, start = counts[counter] or 0 }
          counts[counter] = (counts[counter] or 0) + 1
          -- 块内 label → 全文编号（start+1——注入后块内步进捕获）
          for _, lab in ipairs(extract_labels(text)) do
            refs[lab] = tostring(info.start + 1)
          end
          blocks[#blocks + 1] = pandoc.MetaMap({
            counter = pandoc.MetaString(info.counter),
            start = pandoc.MetaInlines({ pandoc.Str(tostring(info.start)) }),
          })
        end
      end

      -- 写输出（独立顶层 key——不碰 html-tex 现有配置结构）
      local refs_map = pandoc.MetaMap({})
      for lab, num in pairs(refs) do
        refs_map[lab] = pandoc.MetaString(num)
      end
      doc.meta["html-tex-lwarp-counters"] = pandoc.MetaMap({
        blocks = pandoc.MetaList(blocks),
        refs = refs_map,
      })
      return doc
    end,
  },
}
