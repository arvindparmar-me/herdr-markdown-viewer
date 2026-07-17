#!/usr/bin/env bash
# Pane command for herdr.markdown-viewer: render MD_PATH with glow when
# available, else print it with cat. The pane closes when this script exits,
# so every non-glow path waits on Enter to keep the output visible.
set -u

md_path="${MD_PATH:-}"

wait_close() {
  printf '\npress enter to close this preview...'
  read -r _ || true
  printf '\n'
}

if [[ -z "$md_path" ]]; then
  echo "md-preview: MD_PATH is not set; open this pane through the preview action."
  wait_close
  exit 0
fi

if [[ ! -f "$md_path" ]]; then
  echo "md-preview: file not found: $md_path"
  wait_close
  exit 0
fi

if command -v glow >/dev/null 2>&1; then
  exec glow -p "$md_path"
fi

cat "$md_path"
wait_close
