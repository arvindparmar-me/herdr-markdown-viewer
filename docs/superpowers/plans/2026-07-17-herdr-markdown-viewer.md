# Herdr Markdown Viewer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a herdr plugin that previews a selected local markdown file path in a right-split pane, rendered by `glow` when available and `cat` otherwise.

**Architecture:** Bash plugin linked via `herdr plugin link`. A keybinding (`[[keys.command]] type = "plugin_action"` in user config) invokes the `preview` action, which reads `selected_text` and `focused_pane_cwd` from `HERDR_PLUGIN_CONTEXT_JSON`, resolves/validates the path, and calls `herdr plugin pane open --placement split --direction right` with `MD_PATH` in the pane env. The pane command renders the file.

**Tech Stack:** bash (3.2-compatible), herdr 0.7.4 plugin API, optional `glow`, optional `python3` (JSON parsing).

**Spec:** `docs/superpowers/specs/2026-07-17-herdr-markdown-viewer-design.md`

## Global Constraints

- Plugin id exactly `herdr.markdown-viewer`; action id `preview`; pane entrypoint id `preview`.
- `min_herdr_version = "0.7.4"`; `platforms = ["linux", "macos"]`.
- All bash must run on macOS's /bin/bash 3.2: no `${var,,}`, no associative arrays, no `mapfile`, no `>&-` tricks beyond POSIX.
- No hard runtime dependencies: `python3` optional (preferred JSON parser, sed fallback), `glow` optional (renderer, `cat` fallback).
- Markdown extensions accepted: `.md` and `.markdown`, case-insensitive.
- Renderer chain: `glow -p "$MD_PATH"` if `glow` on PATH → else `cat "$MD_PATH"` + `read` keep-alive.
- Pane open argv: `--plugin herdr.markdown-viewer --entrypoint preview --placement split --direction right [--target-pane ID] --env MD_PATH=ABS --focus`. `--target-pane` only when a pane id is present in context.
- `open.sh` must be safely sourceable for tests: no `set -e`, `main` only runs through the `BASH_SOURCE` guard.
- Errors in `open.sh`: message to stderr prefixed `md-preview: `, exit/return 1, never call herdr.

---

### Task 1: Plugin manifest

**Files:**
- Create: `herdr-plugin.toml`

**Interfaces:**
- Consumes: nothing.
- Produces: plugin registered as `herdr.markdown-viewer` with action `herdr.markdown-viewer.preview` and pane entrypoint `preview` (pane/action command files arrive in Tasks 2–4; herdr validates only argv shape at link time, not file existence).

- [ ] **Step 1: Write the manifest**

```toml
id = "herdr.markdown-viewer"
name = "Markdown Viewer"
version = "0.1.0"
min_herdr_version = "0.7.4"
description = "Preview a selected markdown file path in a right-split pane."
platforms = ["linux", "macos"]

[[actions]]
id = "preview"
title = "Preview markdown file"
command = ["bash", "open.sh"]

[[panes]]
id = "preview"
title = "Markdown preview"
placement = "split"
command = ["bash", "preview.sh"]
```

- [ ] **Step 2: Link and verify registration**

Run: `herdr plugin link "$PWD"`
Expected: exit 0; output mentions the linked plugin `herdr.markdown-viewer`.

Run: `herdr plugin list`
Expected: output lists `herdr.markdown-viewer` as enabled.

Run: `herdr plugin action list --plugin herdr.markdown-viewer`
Expected: output lists action `herdr.markdown-viewer.preview` ("Preview markdown file").

Note: the plugin stays linked for the rest of development. Editing files under the linked root needs no relink.

- [ ] **Step 3: Commit**

```bash
git add herdr-plugin.toml
git commit -m "feat: add plugin manifest"
```

---

### Task 2: `open.sh` pure functions (parse, sanitize, resolve, validate)

**Files:**
- Create: `open.sh`
- Create: `tests/assert.sh`
- Create: `tests/test_open.sh`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces (used by Task 3):
  - `json_get KEY` — reads JSON from stdin, prints string value of KEY or nothing (null/missing/invalid). Env override `MD_PREVIEW_JSON_PARSER=sed` forces the no-python fallback; default `auto` prefers `python3`.
  - `sanitize_selection TEXT` — prints cleaned path: first line, trimmed, one layer of surrounding `"`/`'`/`` ` `` stripped.
  - `resolve_path RAW CWD` — prints absolute path: leading `~`/`~/` expands to `$HOME`; relative RAW joins to CWD (CWD trailing slash tolerated); absolute RAW unchanged.
  - `validate_markdown_path ABS` — returns 0 if ABS exists, is a regular file, ends `.md`/`.markdown` (case-insensitive); else prints `md-preview: ...` to stderr, returns 1.

- [ ] **Step 1: Write the failing tests**

`tests/assert.sh`:

```bash
#!/usr/bin/env bash
# Minimal assertion helpers, sourced by test files.
failures=0
tests_run=0

assert_eq() {
  # $1 expected, $2 actual, $3 message
  tests_run=$((tests_run + 1))
  if [[ "$1" == "$2" ]]; then
    printf 'ok %d - %s\n' "$tests_run" "$3"
  else
    printf 'not ok %d - %s\n' "$tests_run" "$3" >&2
    printf '  expected: %s\n  actual:   %s\n' "$1" "$2" >&2
    failures=$((failures + 1))
  fi
}

assert_contains() {
  # $1 haystack, $2 needle, $3 message
  tests_run=$((tests_run + 1))
  case "$1" in
    *"$2"*) printf 'ok %d - %s\n' "$tests_run" "$3" ;;
    *)
      printf 'not ok %d - %s\n' "$tests_run" "$3" >&2
      printf '  expected to contain: %s\n  in: %s\n' "$2" "$1" >&2
      failures=$((failures + 1))
      ;;
  esac
}

finish_tests() {
  if [[ "$failures" -gt 0 ]]; then
    printf '%d of %d tests failed\n' "$failures" "$tests_run" >&2
    exit 1
  fi
  printf '%d tests passed\n' "$tests_run"
}
```

`tests/test_open.sh`:

```bash
#!/usr/bin/env bash
set -u
cd "$(dirname "$0")/.."
source tests/assert.sh
source open.sh

# sanitize_selection
assert_eq "docs/guide.md" "$(sanitize_selection '  docs/guide.md  ')" "trims whitespace"
assert_eq "docs/guide.md" "$(sanitize_selection $'docs/guide.md\nother line')" "first line wins"
assert_eq "docs/guide.md" "$(sanitize_selection '"docs/guide.md"')" "strips double quotes"
assert_eq "docs/guide.md" "$(sanitize_selection "'docs/guide.md'")" "strips single quotes"
assert_eq 'docs/guide.md' "$(sanitize_selection '`docs/guide.md`')" "strips backticks"
assert_eq "a b.md" "$(sanitize_selection '  a b.md ')" "keeps inner spaces"

# resolve_path
assert_eq "/tmp/x.md" "$(resolve_path /tmp/x.md /home/u/proj)" "absolute path unchanged"
assert_eq "/home/u/proj/docs/g.md" "$(resolve_path docs/g.md /home/u/proj)" "relative joins cwd"
assert_eq "/home/u/proj/docs/g.md" "$(resolve_path docs/g.md /home/u/proj/)" "cwd trailing slash"
assert_eq "$HOME/g.md" "$(resolve_path '~/g.md' /tmp)" "tilde slash expands"
assert_eq "$HOME" "$(resolve_path '~' /tmp)" "bare tilde expands"

# validate_markdown_path
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
touch "$tmp/note.md" "$tmp/guide.MD" "$tmp/readme.markdown" "$tmp/code.py"
mkdir "$tmp/dir.md"

assert_eq 0 "$(validate_markdown_path "$tmp/note.md" >/dev/null 2>&1; echo $?)" "accepts .md"
assert_eq 0 "$(validate_markdown_path "$tmp/guide.MD" >/dev/null 2>&1; echo $?)" "accepts uppercase .MD"
assert_eq 0 "$(validate_markdown_path "$tmp/readme.markdown" >/dev/null 2>&1; echo $?)" "accepts .markdown"
assert_eq 1 "$(validate_markdown_path "$tmp/code.py" >/dev/null 2>&1; echo $?)" "rejects non-markdown"
assert_eq 1 "$(validate_markdown_path "$tmp/missing.md" >/dev/null 2>&1; echo $?)" "rejects missing file"
assert_eq 1 "$(validate_markdown_path "$tmp/dir.md" >/dev/null 2>&1; echo $?)" "rejects directory"

# json_get (preferred parser)
json='{"selected_text":"docs/a.md","focused_pane_cwd":"/work","focused_pane_id":"w1:p1","clicked_url":null}'
assert_eq "docs/a.md" "$(json_get selected_text <<< "$json")" "json_get selected_text"
assert_eq "/work" "$(json_get focused_pane_cwd <<< "$json")" "json_get cwd"
assert_eq "w1:p1" "$(json_get focused_pane_id <<< "$json")" "json_get pane id"
assert_eq "" "$(json_get clicked_url <<< "$json")" "json_get null is empty"
assert_eq "" "$(json_get missing_key <<< "$json")" "json_get missing key"
assert_eq "" "$(json_get selected_text <<< 'not json')" "json_get invalid json"

# json_get sed fallback
assert_eq "docs/a.md" "$(MD_PREVIEW_JSON_PARSER=sed json_get selected_text <<< "$json")" "sed fallback selected_text"
assert_eq "" "$(MD_PREVIEW_JSON_PARSER=sed json_get clicked_url <<< "$json")" "sed fallback null is empty"

finish_tests
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test_open.sh`
Expected: FAIL — `open.sh: No such file or directory` on the `source` line.

- [ ] **Step 3: Implement `open.sh` functions**

`open.sh`:

```bash
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test_open.sh`
Expected: all `ok` lines, final line `25 tests passed` (count may differ if assertions were adjusted — must be 0 failures, exit 0).

- [ ] **Step 5: Commit**

```bash
chmod +x open.sh tests/assert.sh tests/test_open.sh
git add open.sh tests/
git commit -m "feat: add path parsing and validation for preview action"
```

---

### Task 3: `open.sh` main flow and herdr invocation

**Files:**
- Modify: `open.sh` (append `main` + source guard)
- Create: `tests/test_open_main.sh`

**Interfaces:**
- Consumes: `json_get`, `sanitize_selection`, `resolve_path`, `validate_markdown_path` from Task 2.
- Produces: action behavior invoked by herdr as `bash open.sh` with env `HERDR_PLUGIN_CONTEXT_JSON` (keys used: `selected_text`, `focused_pane_cwd`, `focused_pane_id`) and `HERDR_BIN_PATH`. Side effect on success: runs `herdr plugin pane open ... --env MD_PATH=ABS`. Task 4's `preview.sh` consumes `MD_PATH`.

- [ ] **Step 1: Write the failing integration tests**

`tests/test_open_main.sh`:

```bash
#!/usr/bin/env bash
set -u
cd "$(dirname "$0")/.."
source tests/assert.sh

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Stub herdr binary: records argv, one arg per line, to $HERDR_STUB_LOG.
cat > "$tmp/herdr" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$HERDR_STUB_LOG"
EOF
chmod +x "$tmp/herdr"
export HERDR_STUB_LOG="$tmp/argv.log"
export HERDR_BIN_PATH="$tmp/herdr"

mkdir -p "$tmp/proj/docs"
printf '# Hello\n' > "$tmp/proj/docs/guide.md"
printf 'x\n' > "$tmp/proj/code.py"

run_action() {
  # $1 = context json; captures status in $action_status
  HERDR_PLUGIN_CONTEXT_JSON="$1" bash open.sh 2> "$tmp/err.log"
  action_status=$?
}

# --- happy path with pane id ---
: > "$HERDR_STUB_LOG"
ctx="{\"selected_text\":\"docs/guide.md\",\"focused_pane_cwd\":\"$tmp/proj\",\"focused_pane_id\":\"w1:p1\"}"
run_action "$ctx"
assert_eq 0 "$action_status" "happy path exits 0"
expected="plugin
pane
open
--plugin
herdr.markdown-viewer
--entrypoint
preview
--placement
split
--direction
right
--target-pane
w1:p1
--env
MD_PATH=$tmp/proj/docs/guide.md
--focus"
assert_eq "$expected" "$(cat "$HERDR_STUB_LOG")" "herdr argv with target pane"

# --- happy path without pane id (null) ---
: > "$HERDR_STUB_LOG"
ctx="{\"selected_text\":\"docs/guide.md\",\"focused_pane_cwd\":\"$tmp/proj\",\"focused_pane_id\":null}"
run_action "$ctx"
assert_eq 0 "$action_status" "null pane id still exits 0"
assert_eq "" "$(grep -e '--target-pane' "$HERDR_STUB_LOG" || true)" "no --target-pane without pane id"

# --- no selection ---
: > "$HERDR_STUB_LOG"
run_action '{"selected_text":null,"focused_pane_cwd":"/x","focused_pane_id":"w1:p1"}'
assert_eq 1 "$action_status" "no selection exits 1"
assert_contains "$(cat "$tmp/err.log")" "md-preview: no selection" "no selection message"
assert_eq "" "$(cat "$HERDR_STUB_LOG")" "herdr not called on failure"

# --- missing context entirely ---
: > "$HERDR_STUB_LOG"
HERDR_BIN_PATH="$tmp/herdr" bash open.sh 2> "$tmp/err.log"
assert_eq 1 "$?" "missing context exits 1"

# --- relative path without cwd ---
: > "$HERDR_STUB_LOG"
run_action '{"selected_text":"docs/guide.md","focused_pane_cwd":null,"focused_pane_id":"w1:p1"}'
assert_eq 1 "$action_status" "relative path without cwd exits 1"
assert_contains "$(cat "$tmp/err.log")" "md-preview: cannot resolve relative path" "no-cwd message"

# --- non-markdown file ---
: > "$HERDR_STUB_LOG"
run_action "{\"selected_text\":\"code.py\",\"focused_pane_cwd\":\"$tmp/proj\",\"focused_pane_id\":\"w1:p1\"}"
assert_eq 1 "$action_status" "non-markdown exits 1"
assert_contains "$(cat "$tmp/err.log")" "not a markdown file" "non-markdown message"
assert_eq "" "$(cat "$HERDR_STUB_LOG")" "herdr not called for non-markdown"

# --- missing file ---
: > "$HERDR_STUB_LOG"
run_action "{\"selected_text\":\"nope.md\",\"focused_pane_cwd\":\"$tmp/proj\",\"focused_pane_id\":\"w1:p1\"}"
assert_eq 1 "$action_status" "missing file exits 1"
assert_contains "$(cat "$tmp/err.log")" "file not found" "missing file message"

finish_tests
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test_open_main.sh`
Expected: FAIL — happy-path assertions fail (`action_status` is 0 but argv log is empty / herdr stub never called) because `open.sh` has no `main` yet and exits silently.

- [ ] **Step 3: Append `main` and the source guard to `open.sh`**

Append to the end of `open.sh`:

```bash
# --- main ------------------------------------------------------------------

main() {
  local context="${HERDR_PLUGIN_CONTEXT_JSON:-}"
  local selected cwd pane_id raw abs
  selected="$(json_get selected_text <<< "$context")"
  cwd="$(json_get focused_pane_cwd <<< "$context")"
  pane_id="$(json_get focused_pane_id <<< "$context")"

  if [[ -z "$selected" ]]; then
    echo "md-preview: no selection; drag-select a markdown file path, then run this action" >&2
    return 1
  fi

  raw="$(sanitize_selection "$selected")"
  if [[ -z "$raw" ]]; then
    echo "md-preview: selection is empty after cleanup" >&2
    return 1
  fi

  if [[ "$raw" != /* && "$raw" != "~" && "$raw" != "~/"* && -z "$cwd" ]]; then
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

  "$herdr_bin" "${args[@]}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -u
  main "$@"
fi
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test_open_main.sh`
Expected: all `ok` lines, `0 failures`, exit 0.

Also re-run Task 2 tests to confirm no regression: `bash tests/test_open.sh` — still all passing.

- [ ] **Step 5: Commit**

```bash
chmod +x tests/test_open_main.sh
git add open.sh tests/test_open_main.sh
git commit -m "feat: wire preview action to herdr pane open"
```

---

### Task 4: `preview.sh` pane command with glow/cat fallback

**Files:**
- Create: `preview.sh`
- Create: `tests/test_preview.sh`
- Create: `tests/run.sh`

**Interfaces:**
- Consumes: `MD_PATH` env var (absolute path to a markdown file), injected by Task 3's `--env MD_PATH=ABS`.
- Produces: pane process behavior — interactive renderer that keeps the pane open until the user quits.

- [ ] **Step 1: Write the failing tests**

`tests/test_preview.sh`:

```bash
#!/usr/bin/env bash
set -u
cd "$(dirname "$0")/.."
source tests/assert.sh

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
printf '# Title\n\nbody text\n' > "$tmp/doc.md"

# Stub glow that records its argv.
mkdir "$tmp/bin"
cat > "$tmp/bin/glow" <<'EOF'
#!/usr/bin/env bash
printf 'GLOW CALLED:' > "$GLOW_STUB_LOG"
printf ' %s' "$@" >> "$GLOW_STUB_LOG"
EOF
chmod +x "$tmp/bin/glow"
export GLOW_STUB_LOG="$tmp/glow.log"

# --- glow preferred when on PATH ---
PATH="$tmp/bin:/usr/bin:/bin" MD_PATH="$tmp/doc.md" bash preview.sh </dev/null
assert_eq 0 "$?" "preview exits 0 with glow"
assert_eq "GLOW CALLED: -p $tmp/doc.md" "$(cat "$GLOW_STUB_LOG")" "glow -p used when available"

# --- cat fallback when glow absent ---
out="$(PATH="/usr/bin:/bin" MD_PATH="$tmp/doc.md" bash preview.sh </dev/null)"
assert_contains "$out" "# Title" "cat fallback prints file content"
assert_contains "$out" "press enter to close" "cat fallback prompts to close"

# --- missing MD_PATH ---
out="$(PATH="/usr/bin:/bin" bash preview.sh </dev/null)"
assert_contains "$out" "md-preview: MD_PATH is not set" "missing MD_PATH message"
assert_contains "$out" "press enter to close" "missing MD_PATH still waits"

# --- file vanished ---
out="$(PATH="/usr/bin:/bin" MD_PATH="$tmp/nope.md" bash preview.sh </dev/null)"
assert_contains "$out" "md-preview: file not found" "missing file message"

finish_tests
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test_preview.sh`
Expected: FAIL — `bash: preview.sh: No such file or directory`.

- [ ] **Step 3: Implement `preview.sh`**

`preview.sh`:

```bash
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test_preview.sh`
Expected: all `ok` lines, `0 failures`, exit 0.

- [ ] **Step 5: Add the test runner and run the full suite**

`tests/run.sh`:

```bash
#!/usr/bin/env bash
set -u
cd "$(dirname "$0")"
status=0
for t in test_*.sh; do
  printf '\n== %s ==\n' "$t"
  bash "$t" || status=1
done
exit "$status"
```

Run: `bash tests/run.sh`
Expected: three test files run, all pass, exit 0.

- [ ] **Step 6: Commit**

```bash
chmod +x preview.sh tests/run.sh tests/test_preview.sh
git add preview.sh tests/
git commit -m "feat: add preview pane renderer with glow/cat fallback"
```

---

### Task 5: README and live-session verification

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: everything above (linked plugin from Task 1, action/pane wiring from Tasks 2–4).
- Produces: user-facing setup instructions; verified live behavior.

- [ ] **Step 1: Write the README**

`README.md`:

````markdown
# Markdown Viewer (herdr plugin)

Preview a local markdown file in a right-split pane. Select a file path in
any pane, press `prefix+m`, and the markdown renders beside your work —
with [glow](https://github.com/charmbracelet/glow) when installed, plain
`cat` otherwise.

## Requirements

- herdr >= 0.7.4
- bash (macOS /bin/bash 3.2 is fine)
- optional: `glow` for rendered markdown (`brew install glow`)
- optional: `python3` for more robust context JSON parsing

## Install

From this directory:

```sh
herdr plugin link "$PWD"
```

Or install from GitHub once published:

```sh
herdr plugin install <owner>/herdr-markdown-viewer
```

## Keybinding (required)

Herdr plugins cannot install keybindings themselves. Add this to
`~/.config/herdr/config.toml`:

```toml
[[keys.command]]
key = "prefix+m"
type = "plugin_action"
command = "herdr.markdown-viewer.preview"
description = "preview selected markdown file"
```

Then run `herdr server reload-config` (or restart herdr).

## Usage

1. Drag-select a markdown path in any pane (absolute, relative to the pane's
   working directory, or starting with `~`). Herdr copies the selection and
   keeps it visible.
2. Press `prefix+m`.
3. The preview opens in a right split. With glow, press `q` to close;
   without glow, press Enter.

Accepted extensions: `.md`, `.markdown` (case-insensitive).

## Why selection + keybinding?

Herdr 0.7.x only makes `http(s)://` URLs clickable (Ctrl+click); bare file
paths, `file://` URLs, and Cmd-based triggers are not available to plugins.
Selection + keybinding is the supported way to act on a local path shown in
a pane.

## Troubleshooting

- Nothing happens on `prefix+m`: check the keybinding block and
  `herdr server reload-config`.
- See action errors: `herdr plugin log list --plugin herdr.markdown-viewer`.
- Verify registration: `herdr plugin list`, then
  `herdr plugin action list --plugin herdr.markdown-viewer`.

## Uninstall

```sh
herdr plugin unlink herdr.markdown-viewer   # keeps this directory
# or: herdr plugin uninstall herdr.markdown-viewer
```

## Development

Run the tests:

```sh
bash tests/run.sh
```
````

- [ ] **Step 2: Verify plugin wiring in the live session**

The plugin is already linked (Task 1). Verify herdr sees the final state:

Run: `herdr plugin list`
Expected: `herdr.markdown-viewer` listed, enabled.

Run: `herdr plugin action list --plugin herdr.markdown-viewer`
Expected: action `herdr.markdown-viewer.preview`.

Run: `herdr plugin action invoke herdr.markdown-viewer.preview`
Expected: non-zero exit with an error mentioning the failed action (no selection exists when invoked from the CLI). Then:

Run: `herdr plugin log list --plugin herdr.markdown-viewer`
Expected: recent log entry containing `md-preview: no selection`. This proves herdr launches `open.sh` and the context/env plumbing works.

- [ ] **Step 3: Manual happy-path verification (user)**

Agent prints these instructions for the user:

1. Add the keybinding block from the README to `~/.config/herdr/config.toml`, then run `herdr server reload-config`.
2. In any pane: `cd /Users/arvind/Projects/herdr-markdown-viewer && ls`
3. Drag-select the text `README.md` in the pane output.
4. Press `prefix+m` — a right split opens showing this README (rendered if `glow` is installed, raw otherwise).
5. Press `q` (glow) or Enter (cat fallback) to close the preview.
6. Also try an absolute path, a `./docs/...` relative path, and a non-markdown file (should show a toast/log error and open nothing).

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: add README with setup and verification"
```

---

## Self-Review Notes (filled by plan author)

- **Spec coverage:** manifest (Task 1), trigger flow + sanitize/resolve/validate (Tasks 2–3), pane open argv incl. `--focus` and conditional `--target-pane` (Task 3), renderer chain glow→cat + keep-alive (Task 4), error handling to plugin log (Tasks 3, 5), JSON parsing python3→sed (Task 2), README keybinding setup (Task 5), tests incl. E2E (Tasks 2–5). Platform constraints (Ctrl/click/http-only) are documented in README "Why selection + keybinding?".
- **Placeholder scan:** none — every step has complete code or exact commands.
- **Type consistency:** function names (`json_get`, `sanitize_selection`, `resolve_path`, `validate_markdown_path`, `main`, `wait_close`), env vars (`HERDR_PLUGIN_CONTEXT_JSON`, `HERDR_BIN_PATH`, `MD_PATH`, `MD_PREVIEW_JSON_PARSER`, stub-only `HERDR_STUB_LOG`/`GLOW_STUB_LOG`), and ids (`herdr.markdown-viewer`, `preview`) are used identically across tasks.
