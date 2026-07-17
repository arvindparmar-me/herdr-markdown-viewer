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
