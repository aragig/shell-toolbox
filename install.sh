#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$SCRIPT_DIR/bin"

exec 3<&0

prompt_yn() {
  local prompt="$1"
  local answer

  while :; do
    printf '%s' "$prompt"
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
  case "$BIN_DIR" in
    "$HOME"/*)
      printf '$HOME%s\n' "${BIN_DIR#"$HOME"}"
      ;;
    *)
      printf '%s\n' "$BIN_DIR"
      ;;
  esac
}

print_path_help() {
  local bin_for_shell
  bin_for_shell="$(display_path)"

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
  local target_abs="$SCRIPT_DIR/$target_rel"
  local link_path="$BIN_DIR/$command_name"
  local link_target="../$target_rel"
  local current_target

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
    if [ "$current_target" = "$link_target" ] || [ "$current_target" = "$target_abs" ]; then
      echo "  already installed: bin/$command_name -> $current_target"
      return 0
    fi

    echo "  existing symlink: bin/$command_name -> $current_target"
    if ! prompt_yn "Replace it? [y/N] "; then
      echo "  skipped"
      return 0
    fi
    rm -f "$link_path"
  elif [ -e "$link_path" ]; then
    echo "  existing path: bin/$command_name"
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

  ln -s "$link_target" "$link_path"
  echo "  installed: bin/$command_name -> $link_target"
}

echo "shell-toolbox command installer"
echo "Repository: $SCRIPT_DIR"
echo "Install dir: $BIN_DIR"

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
