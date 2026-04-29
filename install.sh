#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${SHELL_TOOLBOX_INSTALL_DIR:-$HOME/.local/share/shell-toolbox}"
BIN_DIR="${SHELL_TOOLBOX_BIN_DIR:-$HOME/.local/bin}"
TARBALL_URL="https://github.com/aragig/shell-toolbox/archive/main.tar.gz"
FORCE_REMOTE="${SHELL_TOOLBOX_REMOTE:-0}"
TMP_DIR=""
SOURCE_DIR=""
PROMPT_TTY=0

if ( : <>/dev/tty ) 2>/dev/null; then
  exec 3<>/dev/tty
  PROMPT_TTY=1
else
  exec 3<&0
fi

cleanup() {
  if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
    rm -rf "$TMP_DIR"
  fi
}

trap cleanup EXIT

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "command not found: $1" >&2
    exit 1
  }
}

prompt_yn() {
  local prompt="$1"
  local answer

  while :; do
    if [ "$PROMPT_TTY" -eq 1 ]; then
      printf '%s' "$prompt" >&3
    else
      printf '%s' "$prompt"
    fi
    if ! IFS= read -r answer <&3; then
      answer=""
    fi

    case "$answer" in
      y|Y|yes|YES)
        return 0
        ;;
      n|N|no|NO|'')
        return 1
        ;;
      *)
        echo "Please answer y or n." >&2
        ;;
    esac
  done
}

display_path() {
  local path="$1"
  case "$path" in
    "$HOME"/*)
      printf '$HOME%s\n' "${path#"$HOME"}"
      ;;
    *)
      printf '%s\n' "$path"
      ;;
  esac
}

abs_dir() {
  local path="$1"
  (cd "$path" && pwd -P)
}

same_existing_dir() {
  local left right
  [ -d "$1" ] || return 1
  [ -d "$2" ] || return 1
  left="$(abs_dir "$1")"
  right="$(abs_dir "$2")"
  [ "$left" = "$right" ]
}

looks_like_source_tree() {
  local dir="$1"
  [ -f "$dir/news-topics/news-topics.sh" ] &&
    [ -f "$dir/gray/gray.sh" ] &&
    [ -f "$dir/toc/toc.sh" ] &&
    [ -f "$dir/fish-info/fish-info.sh" ]
}

detect_local_source() {
  local script_path script_dir
  script_path="${BASH_SOURCE[0]:-}"

  [ -n "$script_path" ] || return 1
  [ -f "$script_path" ] || return 1

  script_dir="$(cd "$(dirname "$script_path")" && pwd -P)"
  looks_like_source_tree "$script_dir" || return 1
  printf '%s\n' "$script_dir"
}

download_install_tree() {
  local tmpdir archive extract_dir first_entry backup_dir

  need_cmd curl
  need_cmd tar
  need_cmd find
  need_cmd head
  need_cmd date
  need_cmd mktemp

  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/shell-toolbox.XXXXXX")"
  TMP_DIR="$tmpdir"
  archive="$tmpdir/source.tar.gz"
  extract_dir="$tmpdir/source"
  mkdir -p "$extract_dir"

  echo "Downloading shell-toolbox:"
  echo "  url: $TARBALL_URL"

  curl -fsSL "$TARBALL_URL" -o "$archive"
  tar -xzf "$archive" -C "$extract_dir"

  first_entry="$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  if [ -z "$first_entry" ] || ! looks_like_source_tree "$first_entry"; then
    echo "downloaded archive does not look like shell-toolbox" >&2
    exit 1
  fi

  mkdir -p "$(dirname "$INSTALL_DIR")"

  if [ -e "$INSTALL_DIR" ]; then
    backup_dir="${INSTALL_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
    mv "$INSTALL_DIR" "$backup_dir"
    echo "Previous install moved to: $(display_path "$backup_dir")"
  fi

  mv "$first_entry" "$INSTALL_DIR"
  chmod +x "$INSTALL_DIR/install.sh"

  SOURCE_DIR="$(abs_dir "$INSTALL_DIR")"
  echo "Installed source tree: $(display_path "$INSTALL_DIR")"
}

select_source_tree() {
  local local_source=""

  if local_source="$(detect_local_source)"; then
    if [ "$FORCE_REMOTE" != "1" ] && ! same_existing_dir "$local_source" "$INSTALL_DIR"; then
      SOURCE_DIR="$local_source"
      echo "Using local source tree: $(display_path "$SOURCE_DIR")"
      return 0
    fi
  fi

  if [ -e "$INSTALL_DIR" ]; then
    echo
    echo "Existing install found: $(display_path "$INSTALL_DIR")"
    if prompt_yn "Update source tree before command selection? [y/N] "; then
      download_install_tree
    else
      if ! looks_like_source_tree "$INSTALL_DIR"; then
        echo "install source is incomplete: $(display_path "$INSTALL_DIR")" >&2
        exit 1
      fi
      SOURCE_DIR="$(abs_dir "$INSTALL_DIR")"
      echo "Using existing source tree."
    fi
  else
    download_install_tree
  fi
}

print_path_help() {
  local bin_for_shell
  bin_for_shell="$(display_path "$BIN_DIR")"

  cat <<EOF

PATH の設定方法:

  zsh:
    echo 'export PATH="$bin_for_shell:\$PATH"' >> ~/.zshrc
    source ~/.zshrc

  bash:
    echo 'export PATH="$bin_for_shell:\$PATH"' >> ~/.bashrc
    source ~/.bashrc

  fish:
    fish_add_path $bin_for_shell

設定後、新しいターミナルでインストールしたコマンドを確認してください:
  command -v <command>

例:
  command -v news
EOF
}

install_command() {
  local command_name="$1"
  local target_rel="$2"
  local description="$3"
  local target_abs="$SOURCE_DIR/$target_rel"
  local link_path="$BIN_DIR/$command_name"
  local current_target
  local link_display

  link_display="$(display_path "$link_path")"

  echo
  echo "$command_name"
  echo "  $description"
  echo "  -> $target_rel"

  if ! prompt_yn "Install $command_name? [y/N] "; then
    echo "  skipped"
    return 0
  fi

  if [ ! -f "$target_abs" ]; then
    echo "  target not found: $target_rel" >&2
    return 1
  fi

  chmod +x "$target_abs"
  mkdir -p "$BIN_DIR"

  if [ -L "$link_path" ]; then
    current_target="$(readlink "$link_path")"
    if [ "$current_target" = "$target_abs" ]; then
      echo "  already installed: $link_display -> $current_target"
      return 0
    fi

    echo "  existing symlink: $link_display -> $current_target"
    if ! prompt_yn "Replace it? [y/N] "; then
      echo "  skipped"
      return 0
    fi
    rm -f "$link_path"
  elif [ -e "$link_path" ]; then
    echo "  existing path: $link_display"
    if [ -d "$link_path" ]; then
      echo "  skipped: directory exists and will not be replaced" >&2
      return 0
    fi
    if ! prompt_yn "Replace it? [y/N] "; then
      echo "  skipped"
      return 0
    fi
    rm -f "$link_path"
  fi

  ln -s "$target_abs" "$link_path"
  echo "  installed: $link_display -> $target_abs"
}

echo "shell-toolbox installer"
echo "Install source: $(display_path "$INSTALL_DIR")"
echo "Command dir:    $(display_path "$BIN_DIR")"

select_source_tree

echo
echo "Select commands to install."
echo "Source dir:  $(display_path "$SOURCE_DIR")"
echo "Command dir: $(display_path "$BIN_DIR")"

while IFS='|' read -r command_name target_rel description; do
  [ -n "$command_name" ] || continue
  install_command "$command_name" "$target_rel" "$description"
done <<'COMMANDS'
fish-info|fish-info/fish-info.sh|釣り向け情報を Markdown で出力する
gifanime|gifanime/gifanime.sh|動画ファイルを GIF アニメに変換する
gray|gray/gray.sh|画像を JPEG に変換・軽量化する
news|news-topics/news-topics.sh|海外ニュース RSS を偏りを抑えて一覧表示する
toc|toc/toc.sh|Markdown の見出しから TOC を生成する
dump_all_pgdbs|postgres/dump_all_pgdbs.sh|~/.pgpass を使って PostgreSQL DB をまとめてダンプする
xls2html_dbdoc|xls2html_dbdoc/xls2html_dbdoc.sh|Excel の DB 設計書を HTML に変換する
COMMANDS

print_path_help
