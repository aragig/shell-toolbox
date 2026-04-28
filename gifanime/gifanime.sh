#!/usr/bin/env bash
  set -euo pipefail

  input="${1:-}"

  if [ -z "$input" ]; then
    echo "Usage: curl ... | bash -s -- input.mov" >&2
    exit 1
  fi

  if [ ! -f "$input" ]; then
    echo "File not found: $input" >&2
    exit 1
  fi

  command -v ffmpeg >/dev/null || {
    echo "ffmpeg is required" >&2
    exit 1
  }

  command -v gifsicle >/dev/null || {
    echo "gifsicle is required" >&2
    exit 1
  }

  dir="$(dirname "$input")"
  output="$dir/anime.gif"

  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT

  palette="$tmpdir/palette.png"
  tmpgif="$tmpdir/tmp.gif"

  ffmpeg -i "$input" -vf fps=15,scale=320:-1:flags=lanczos,palettegen "$palette"
  ffmpeg -i "$input" -i "$palette" -filter_complex "fps=15,scale=320:-1:flags=lanczos[x];[x][1:v]paletteuse" "$tmpgif"

  gifsicle -O3 --colors=128 --lossy=30 "$tmpgif" -o "$output"

  echo "Created: $output"
