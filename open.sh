#!/usr/bin/env bash
# Action command for herdr.markdown-viewer: resolve the selected markdown
# path and open the preview pane. Source-safe: main only runs via the guard
# at the bottom; no `set -e` so tests can source this file.

# --- JSON -----------------------------------------------------------------

# json_get KEY — read JSON from stdin, print the string value of KEY.
# Prefers python3; set MD_PREVIEW_JSON_PARSER=sed to force the fallback.
# The sed fallback is best-effort (no escaped-quote support) and only used
# on machines without python3.
json_get() {
  local key="$1"
  if [[ "${MD_PREVIEW_JSON_PARSER:-auto}" != "sed" ]] && command -v python3 >/dev/null 2>&1; then
    json_get_py "$key"
  else
    json_get_sed "$key"
  fi
}

json_get_py() {
  python3 -c '
import json, sys
try:
    data = json.loads(sys.stdin.read())
except ValueError:
    sys.exit(0)
value = data.get(sys.argv[1])
if isinstance(value, str):
    sys.stdout.write(value)
' "$1"
}

json_get_sed() {
  sed -n 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1
}

# --- selection cleanup -----------------------------------------------------

# sanitize_selection TEXT — first line, trimmed, one layer of matching
# surrounding quotes/backticks stripped.
sanitize_selection() {
  local s="$1"
  s="${s%%$'\n'*}"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  if [[ ${#s} -ge 2 ]]; then
    case "$s" in
      \"*\") s="${s:1:${#s}-2}" ;;
      \'*\') s="${s:1:${#s}-2}" ;;
      \`*\`) s="${s:1:${#s}-2}" ;;
    esac
  fi
  printf '%s' "$s"
}

# --- path resolution -------------------------------------------------------

# resolve_path RAW CWD — print absolute path. Expands leading ~ and ~/;
# joins relative paths to CWD.
resolve_path() {
  local p="$1" cwd="$2"
  case "$p" in
    "~")   p="$HOME" ;;
    "~/"*) p="$HOME/${p:2}" ;;
  esac
  if [[ "$p" != /* ]]; then
    p="${cwd%/}/$p"
  fi
  printf '%s' "$p"
}

# --- validation ------------------------------------------------------------

# validate_markdown_path ABS — 0 if existing regular .md/.markdown file.
validate_markdown_path() {
  local p="$1"
  if [[ ! -e "$p" ]]; then
    echo "md-preview: file not found: $p" >&2
    return 1
  fi
  if [[ ! -f "$p" ]]; then
    echo "md-preview: not a regular file: $p" >&2
    return 1
  fi
  case "$p" in
    *.[mM][dD]|*.[mM][aA][rR][kK][dD][oO][wW][nN]) return 0 ;;
    *)
      echo "md-preview: not a markdown file (want .md or .markdown): $p" >&2
      return 1
      ;;
  esac
}
