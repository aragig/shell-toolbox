#!/bin/bash

# ============================================================
# toc.sh
#
# 指定した Markdown ファイルから "## 見出し" を抽出して
# Markdown形式の目次（TOC）を生成するスクリプト
#
# 出力形式:
#   - [タイトル](#タイトル)
#
# ------------------------------------------------------------
# Author:
#   Toshihiko Arai
#   https://araisun.com
#
# Environment:
#   macOS (Bash 3.x)
#
# ------------------------------------------------------------
# 注意:
# - Windows改行（CRLF）の場合、行末に \r が含まれるため
#   そのままだと表示が崩れる
# - tr -d '\r' で除去して対策している
# - 見出し内のスペースは GitHub のアンカーに合わせて
#   ハイフン `-` に変換している
#
# usage:
#   ./toc.sh README.md
# ============================================================

FILE="${1:?usage: $0 <markdown_file>}"

grep '^## ' "$FILE" | while IFS= read -r line
do
  line=$(printf '%s' "$line" | tr -d '\r')
  title="${line#\#\# }"

  [ "$title" = "Contents" ] && continue

  anchor=$(printf '%s' "$title" | sed 's/ /-/g')

  echo "- [$title](#$anchor)"
done