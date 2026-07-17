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

# extract_pane_id RESPONSE_JSON — print pane_id from a plugin pane open
# response. Best-effort; returns nothing on parse failure.
extract_pane_id() {
  if ! command -v python3 >/dev/null 2>&1; then
    return
  fi
  python3 -c '
import json, sys
try:
    data = json.loads(sys.stdin.read())
    print(data["result"]["plugin_pane"]["pane"]["pane_id"])
except (KeyError, ValueError, TypeError):
    pass
' <<< "$1"
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

# --- main ------------------------------------------------------------------

main() {
  local context="${HERDR_PLUGIN_CONTEXT_JSON:-}"
  local selected cwd pane_id raw abs
  selected="$(json_get selected_text <<< "$context")"
  cwd="$(json_get focused_pane_cwd <<< "$context")"
  pane_id="$(json_get focused_pane_id <<< "$context")"

  if [[ -z "$selected" ]]; then
    # Fall back to clipboard — herdr's default copy_on_select clears the
    # selection after copying, so selected_text is often unavailable at
    # keybinding time. The clipboard still holds the copied text.
    # Set MD_PREVIEW_NO_CLIPBOARD=1 to skip this fallback (for testing).
    if [[ "${MD_PREVIEW_NO_CLIPBOARD:-0}" != "1" ]]; then
      if command -v pbpaste >/dev/null 2>&1; then
        selected="$(pbpaste | head -n 1)"
      elif command -v xclip >/dev/null 2>&1; then
        selected="$(xclip -o -selection clipboard 2>/dev/null | head -n 1)"
      fi
      selected="${selected:+$selected}"
    fi
  fi
  if [[ -z "$selected" ]]; then
    echo "md-preview: no selection; drag-select a markdown file path, then run this action" >&2
    return 1
  fi

  raw="$(sanitize_selection "$selected")"
  if [[ -z "$raw" ]]; then
    echo "md-preview: selection is empty after cleanup" >&2
    return 1
  fi

  if [[ "$raw" != /* && "$raw" != "~" && "$raw" != "~"/* && -z "$cwd" ]]; then
    echo "md-preview: cannot resolve relative path without the focused pane's cwd: $raw" >&2
    return 1
  fi

  abs="$(resolve_path "$raw" "$cwd")"
  if ! validate_markdown_path "$abs"; then
    return 1
  fi

  local herdr_bin="${HERDR_BIN_PATH:-herdr}"
  local args=(plugin pane open
    --plugin herdr.markdown-viewer
    --entrypoint preview
    --placement split
    --direction right)
  if [[ -n "$pane_id" ]]; then
    args+=(--target-pane "$pane_id")
  fi
  args+=(--env "MD_PATH=$abs" --focus)

  local output open_status
  output="$("$herdr_bin" "${args[@]}" 2>&1)"
  open_status=$?

  if [[ $open_status -ne 0 ]]; then
    printf '%s\n' "$output" >&2
    return "$open_status"
  fi

  # Rename the new pane to the filename (best-effort; pane already opened).
  local pane_id_from_output base
  pane_id_from_output="$(extract_pane_id "$output")"
  if [[ -n "$pane_id_from_output" ]]; then
    base="$(basename "$abs")"
    "$herdr_bin" pane rename "$pane_id_from_output" "$base" >/dev/null 2>&1 || true
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -u
  main "$@"
fi
