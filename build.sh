#!/usr/bin/env bash
# 构建脚本：qmd -> PDF（绕开 Quarto 内置引擎在 MiKTeX/Windows 下的文件锁竞态）
set -e
cd "$(dirname "$0")"

# 1. markdown -> latex（生成带完整 pdf preamble 的 index.tex；PDF 编译步骤的文件锁错误可忽略）
quarto render index.qmd --to pdf >/dev/null 2>&1 || true

# 2. 手动 LaTeX 管线：xelatex -> bibtex -> xelatex x2
run_xelatex() {
  for i in 1 2 3 4 5; do
    xelatex -interaction=nonstopmode -halt-on-error index.tex >/dev/null 2>&1 && return 0
    sleep 1
  done
  echo "xelatex failed after retries" >&2
  return 1
}

run_xelatex
bibtex index >/dev/null 2>&1
run_xelatex
run_xelatex

echo "Done: index.pdf"
