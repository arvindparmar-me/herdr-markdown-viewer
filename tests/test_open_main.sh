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
export MD_PREVIEW_NO_CLIPBOARD=1  # tests check selected_text from context, not clipboard

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
