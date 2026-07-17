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
