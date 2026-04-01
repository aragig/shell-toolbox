#!/bin/bash
# macOS標準 bash 3.x 対応
# ~/.pgpass を参照して全DBをダンプし、tar.gz に圧縮する
#
# usage:
#   ./dump_all_pgdbs.sh
#   ./dump_all_pgdbs.sh -o ~/Downloads/backups
#   ./dump_all_pgdbs.sh --pgpass ~/.pgpass
#
# options:
#   -o, --output-dir DIR   出力先ディレクトリ（既定: ~/Downloads）
#   -p, --pgpass FILE      .pgpass のパス（既定: ~/.pgpass）
#   -k, --keep-dir         圧縮後も展開ディレクトリを残す
#   -h, --help             ヘルプ表示
#   -v, --version          バージョン表示

set -euo pipefail

VERSION="1.1.0"
OUTPUT_BASE_DIR="$HOME/Downloads"
PGPASS_FILE="$HOME/.pgpass"
KEEP_DIR=0
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SCRIPT_NAME=$(basename "$0")

usage() {
  cat <<USAGE
Usage: $SCRIPT_NAME [options]

Options:
  -o, --output-dir DIR   Output base directory (default: ~/Downloads)
  -p, --pgpass FILE      Path to .pgpass file (default: ~/.pgpass)
  -k, --keep-dir         Keep extracted dump directory after archiving
  -h, --help             Show this help
  -v, --version          Show version
USAGE
}

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

error() {
  printf '[ERROR] %s\n' "$*" >&2
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    error "必要なコマンドが見つかりません: $1"
    exit 1
  }
}

sanitize_name() {
  printf '%s' "$1" | sed 's/[^A-Za-z0-9._-]/_/g'
}

while [ $# -gt 0 ]; do
  case "$1" in
    -o|--output-dir)
      [ $# -ge 2 ] || { error "--output-dir には値が必要です"; exit 1; }
      OUTPUT_BASE_DIR="$2"
      shift 2
      ;;
    -p|--pgpass)
      [ $# -ge 2 ] || { error "--pgpass には値が必要です"; exit 1; }
      PGPASS_FILE="$2"
      shift 2
      ;;
    -k|--keep-dir)
      KEEP_DIR=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -v|--version)
      printf '%s %s\n' "$SCRIPT_NAME" "$VERSION"
      exit 0
      ;;
    *)
      error "不明なオプションです: $1"
      usage >&2
      exit 1
      ;;
  esac
done

require_cmd pg_dump
require_cmd tar
require_cmd date
require_cmd sed

if [ ! -f "$PGPASS_FILE" ]; then
  error ".pgpass が見つかりません: $PGPASS_FILE"
  exit 1
fi

OUTDIR="${OUTPUT_BASE_DIR%/}/pg_dumps_${TIMESTAMP}"
ARCHIVE="${OUTPUT_BASE_DIR%/}/pg_dumps_${TIMESTAMP}.tar.gz"

mkdir -p "$OUTDIR"

log "ダンプを開始します"

while IFS=: read -r HOST PORT DB USER PASS EXTRA; do
  [ -n "${HOST:-}" ] || continue

  case "$HOST" in
    \#*) continue ;;
  esac

  if [ -n "${EXTRA:-}" ] || [ -z "${PORT:-}" ] || [ -z "${DB:-}" ] || [ -z "${USER:-}" ] || [ -z "${PASS:-}" ]; then
    log "スキップ: .pgpass の形式が不正です -> ${HOST}:${PORT:-}:${DB:-}:${USER:-}:*****"
    continue
  fi

  SAFE_HOST=$(sanitize_name "$HOST")
  SAFE_PORT=$(sanitize_name "$PORT")
  SAFE_DB=$(sanitize_name "$DB")
  SAFE_USER=$(sanitize_name "$USER")
  DUMP_FILE="$OUTDIR/${SAFE_HOST}_${SAFE_PORT}_${SAFE_DB}_${SAFE_USER}.dump"

  log "Dumping db=${DB} host=${HOST} port=${PORT} user=${USER}"
  pg_dump -h "$HOST" -p "$PORT" -U "$USER" -Fc -f "$DUMP_FILE" "$DB"
done < "$PGPASS_FILE"

log "圧縮しています: $ARCHIVE"
tar -czf "$ARCHIVE" -C "$(dirname "$OUTDIR")" "$(basename "$OUTDIR")"

if [ "$KEEP_DIR" -eq 0 ]; then
  log "一時ディレクトリを削除します: $OUTDIR"
  rm -rf "$OUTDIR"
fi

log "完了しました"
printf 'archive: %s\n' "$ARCHIVE"
if [ "$KEEP_DIR" -eq 1 ]; then
  printf 'directory: %s\n' "$OUTDIR"
fi
