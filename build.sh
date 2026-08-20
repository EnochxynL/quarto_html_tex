#!/bin/bash
# 单源多格式构建：index.qmd → index.pdf + index.html
set -e
cd "$(dirname "$0")"

echo "=== 渲染 PDF + HTML ==="
quarto render index.qmd

echo ""
echo "=== 完成：index.pdf + index.html ==="
ls -la index.pdf index.html
