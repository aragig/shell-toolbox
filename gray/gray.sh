#!/bin/bash
set -euo pipefail

# ============================================================
# gray.sh
#
# 指定した画像ファイルをグレースケールJPEGへ変換する
#
# 主な仕様:
# - 単体/複数ファイル対応
# - 出力先ディレクトリを指定可能
# - 元画像はバックアップディレクトリへ保存
# - 同名ファイル衝突時は連番で退避/出力
#
# usage:
#   ./gray.sh image.jpg
#   ./gray.sh -o ./dist image1.jpg image2.png
#   ./gray.sh -o ./dist -b ./backup *.jpg
#
# option:
#   -o <dir>   出力先ディレクトリ
#   -b <dir>   オリジナル保存先ディレクトリ
#   -h         ヘルプ
#
# requirement:
#   - macOS
#   - Bash 3.x
#   - ImageMagick (magick)
# ============================================================

OUT_DIR="."
BACKUP_DIR=""
MAX_GEOMETRY="2000x2000>"
TARGET_EXTENT="600KB"

usage() {
  cat <<'EOF'
usage:
  gray.sh [-o output_dir] [-b backup_dir] <image_file> [image_file ...]

example:
  gray.sh receipt.jpg
  gray.sh -o ./dist IMG_0001.JPG IMG_0002.JPG
  gray.sh -o ./dist -b ./originals *.jpg

option:
  -o <dir>   出力先ディレクトリ (default: .)
  -b <dir>   オリジナル保存先ディレクトリ
             (default: ./originals_YYYYmmdd_HHMMSS)
  -h         show help
EOF
}

command -v magick >/dev/null 2>&1 || {
  echo "error: magick コマンドが見つかりません" >&2
  exit 1
}

while getopts "o:b:h" opt; do
  case "$opt" in
    o) OUT_DIR="$OPTARG" ;;
    b) BACKUP_DIR="$OPTARG" ;;
    h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done
shift $((OPTIND - 1))

[ "$#" -gt 0 ] || {
  usage >&2
  exit 1
}

mkdir -p "$OUT_DIR"

if [ -z "$BACKUP_DIR" ]; then
  BACKUP_DIR="./originals_$(date +%Y%m%d_%H%M%S)"
fi
mkdir -p "$BACKUP_DIR"

is_image_file() {
  case "${1##*.}" in
    jpg|JPG|jpeg|JPEG|png|PNG|webp|WEBP|heic|HEIC|tif|TIF|tiff|TIFF|bmp|BMP|gif|GIF)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

unique_path() {
  local dir="$1"
  local filename="$2"
  local base ext candidate n

  if [[ "$filename" == *.* ]]; then
    base="${filename%.*}"
    ext=".${filename##*.}"
  else
    base="$filename"
    ext=""
  fi

  candidate="$dir/$filename"
  n=1
  while [ -e "$candidate" ]; do
    candidate="$dir/${base}_$n${ext}"
    n=$((n + 1))
  done

  printf '%s\n' "$candidate"
}

for src in "$@"; do
  [ -e "$src" ] || {
    echo "skip: ファイルが見つかりません: $src" >&2
    continue
  }

  [ -f "$src" ] || {
    echo "skip: 通常ファイルではありません: $src" >&2
    continue
  }

  is_image_file "$src" || {
    echo "skip: 非対応ファイルです: $src" >&2
    continue
  }

  src_abs="$src"
  src_name="$(basename "$src")"
  src_stem="${src_name%.*}"

  backup_path="$(unique_path "$BACKUP_DIR" "$src_name")"
  out_name="${src_stem}.jpg"
  out_path="$(unique_path "$OUT_DIR" "$out_name")"

  cp -p "$src_abs" "$backup_path"

  if magick "$src_abs" \
    -auto-orient \
    -strip \
    -resize "$MAX_GEOMETRY" \
    -colorspace Gray \
    -depth 8 \
    -sampling-factor 4:2:0 \
    -interlace Plane \
    -define jpeg:extent="$TARGET_EXTENT" \
    "$out_path"
  then
    rm -f -- "$src_abs"
    echo "ok: $src_abs -> $out_path"
    echo "backup: $backup_path"
  else
    rm -f -- "$out_path" 2>/dev/null || true
    echo "error: 変換失敗: $src_abs" >&2
  fi
done