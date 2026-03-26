#!/bin/bash
#set -e

# ============================================================
# xls2html_dbdoc.sh
#
# Excel(.xls) の DB設計書を HTML に変換し、
# 表示用に最低限の整形を行って Chrome で開くスクリプト
#
# 主な処理:
# - 指定ディレクトリ内の .xls ファイルを LibreOffice で HTML 変換
# - 最新の HTML ファイルを取得
# - <font> タグを削除
# - 表の文字サイズ・フォントを調整
# - Overview を含む目次ブロックを右上固定表示に変更
# - Google Chrome で自動表示
#
# ------------------------------------------------------------
# usage:
#   ./xls2html_dbdoc.sh <input_dir> <output_dir> <file_glob>
#
# example:
#   ./xls2html_dbdoc.sh \
#     ~/document_root \
#     ~/output_dist \
#     'filename_[0-9]*.xls'
#
# arguments:
#   <input_dir>
#       変換対象の .xls ファイルが置かれているディレクトリ
#
#   <output_dir>
#       HTML の出力先ディレクトリ
#       既に存在する場合はいったん削除して作り直す
#
#   <file_glob>
#       変換対象ファイルのパターン
#       シェル展開を避けるため、通常はシングルクォートで囲って渡す
#
#
# requirement:
# - macOS
# - Bash
# - LibreOffice
# - Google Chrome
#
#
# author:
#   Toshihiko Arai 2026/03/26
#   https://araisun.com
#
# ============================================================

INPUT_DIR="${1:?usage: $0 <input_dir> <output_dir> <file_glob>}"
OUTPUT_DIR="${2:?usage: $0 <input_dir> <output_dir> <file_glob>}"
FILE_GLOB="${3:?usage: $0 <input_dir> <output_dir> <file_glob>}"

# 既存HTMLを削除
if [ -e "$OUTPUT_DIR" ]; then
  rm -rf "$OUTPUT_DIR"
fi


mkdir -p "$OUTPUT_DIR"

# glob展開
shopt -s nullglob
files=( "$INPUT_DIR"/$FILE_GLOB )
shopt -u nullglob

[ "${#files[@]}" -eq 0 ] && { echo "対象ファイルが見つかりません: $INPUT_DIR/$FILE_GLOB"; exit 1; }

# LibreOffice変換
/Applications/LibreOffice.app/Contents/MacOS/soffice \
  --headless \
  --convert-to "html:HTML (StarCalc)" \
  --outdir "$OUTPUT_DIR" \
  "${files[@]}"

# 最新HTML取得
latest_html=$(ls -t "$OUTPUT_DIR"/*.html 2>/dev/null | head -n 1)
[ -z "$latest_html" ] && { echo "HTMLファイルが見つかりません"; exit 1; }

# <font>タグ削除
sed -i '' -E 's/<font[^>]*>//g' "$latest_html"
sed -i '' -E 's#</font>##g' "$latest_html"

# CSSを<head>直後に追加
sed -i '' '/<head>/a\
<style>\
table, td, th {\
  font-size: 14px !important;\
  font-family: "Helvetica", "Arial", sans-serif !important;\
}\
th { background-color: #f0f0f0; }\
</style>' "$latest_html"

# 目次を右上固定
perl -0777 -i -pe 's|<center>(.*?<h1>Overview</h1>.*)</center>|<div id="toc" class="toc-fixed">$1</div>|s' "$latest_html"

# フローティングTOC用CSS追加
sed -i '' '/<head>/a\
<style>\
.toc-fixed { position: fixed; top: 12px; right: 12px; width: 320px; max-height: 85vh; overflow: auto; background: rgba(255,255,255,.95); border: 1px solid #ddd; padding: 10px 12px; box-shadow: 0 2px 8px rgba(0,0,0,.1); z-index: 9999; }\
.toc-fixed h1 { font-size: 18px; margin: 0 0 6px; }\
.toc-fixed a { display: block; margin: 2px 0; text-decoration: none; }\
body { padding-right: 340px; }\
</style>' "$latest_html"

# Chromeで開く
open -a "Google Chrome" "$latest_html"