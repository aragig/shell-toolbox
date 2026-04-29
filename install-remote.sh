#!/usr/bin/env bash
set -euo pipefail

REPO="${SHELL_TOOLBOX_REPO:-aragig/shell-toolbox}"
REF="${SHELL_TOOLBOX_REF:-main}"
INSTALL_DIR="${SHELL_TOOLBOX_INSTALL_DIR:-$HOME/.local/share/shell-toolbox}"
BIN_DIR="${SHELL_TOOLBOX_BIN_DIR:-$HOME/.local/bin}"
TARBALL_URL="${SHELL_TOOLBOX_TARBALL_URL:-https://github.com/$REPO/archive/$REF.tar.gz}"
TMP_DIR=""

exec 3<&0

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

download_install_tree() {
  local tmpdir archive extract_dir first_entry backup_dir

  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/shell-toolbox.XXXXXX")"
  TMP_DIR="$tmpdir"
  archive="$tmpdir/source.tar.gz"
  extract_dir="$tmpdir/source"
  mkdir -p "$extract_dir"

  echo "Downloading shell-toolbox:"
  echo "  repository: $REPO"
  echo "  ref:        $REF"
  echo "  url:        $TARBALL_URL"

  curl -fsSL "$TARBALL_URL" -o "$archive"
  tar -xzf "$archive" -C "$extract_dir"

  first_entry="$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  if [ -z "$first_entry" ] || [ ! -f "$first_entry/install.sh" ]; then
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

  echo "Installed source tree: $(display_path "$INSTALL_DIR")"
}

need_cmd curl
need_cmd tar
need_cmd find
need_cmd head
need_cmd date
need_cmd mktemp

echo "shell-toolbox remote installer"
echo "Install source: $(display_path "$INSTALL_DIR")"
echo "Command dir:    $(display_path "$BIN_DIR")"

if [ -e "$INSTALL_DIR" ]; then
  echo
  echo "Existing install found: $(display_path "$INSTALL_DIR")"
  if prompt_yn "Update source tree before command selection? [y/N] "; then
    download_install_tree
  else
    echo "Using existing source tree."
  fi
else
  download_install_tree
fi

if [ ! -f "$INSTALL_DIR/install.sh" ]; then
  echo "install.sh not found in install source: $(display_path "$INSTALL_DIR")" >&2
  exit 1
fi

echo
echo "Select commands to install."
SHELL_TOOLBOX_BIN_DIR="$BIN_DIR" "$INSTALL_DIR/install.sh"
