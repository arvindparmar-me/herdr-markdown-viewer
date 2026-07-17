# Herdr Markdown Viewer — Design

Date: 2026-07-17
Status: approved by user

## Goal

A herdr plugin that lets the user preview a local markdown (`.md`) file in a
vertical (right-split) pane. The user selects a markdown file path visible in
any pane, presses a keybinding, and the rendered markdown opens in a split
pane beside it.

## Platform constraints (verified against herdr 0.7.4 docs and source)

These facts shaped the design; they are hard constraints of herdr v1, not
choices:

- A plugin is a directory with a `herdr-plugin.toml` manifest declaring
  `[[actions]]`, `[[panes]]`, `[[link_handlers]]`, `[[events]]`. Commands are
  argv arrays (no shell expansion unless the command starts a shell).
- Development install is `herdr plugin link <path>` (no build step run).
- Link handlers only fire on **Ctrl+left-click** on **http(s):// URLs**
  (plain-text URLs or OSC-8 hyperlinks). Verified in source:
  - `modified_url_click_modifier()` returns `KeyModifiers::CONTROL`
    (`src/app/input/mod.rs`); terminal mouse reports cannot distinguish
    Cmd/Super from a plain click.
  - `url_spans()` + `safe_web_url()` (`src/app/actions.rs`) only match
    `http://`/`https://`; bare paths and `file://` URLs are explicitly
    excluded.
  - Right-click opens herdr's pane menu; it is not a link trigger.
  - There is no keyboard (Enter) activation for links.
- Plugin actions can be invoked from keybindings via
  `[[keys.command]] type = "plugin_action"` in `~/.config/herdr/config.toml`.
  Keybindings live in user config; a plugin cannot self-install them.
- Action commands receive env: `HERDR_BIN_PATH`, `HERDR_SOCKET_PATH`,
  `HERDR_PLUGIN_ID`, `HERDR_PLUGIN_ROOT`, `HERDR_PLUGIN_CONFIG_DIR`,
  `HERDR_PLUGIN_STATE_DIR`, `HERDR_PLUGIN_ACTION_ID`,
  `HERDR_PLUGIN_CONTEXT_JSON`, and when available `HERDR_WORKSPACE_ID`,
  `HERDR_TAB_ID`, `HERDR_PANE_ID`.
- `HERDR_PLUGIN_CONTEXT_JSON` (PluginInvocationContext) can include:
  `workspace_id/label/cwd`, `tab_id/label`, `focused_pane_id/cwd/agent/status`,
  `selected_text`, `worktree`, `invocation_source`, `correlation_id`,
  `clicked_url`, `link_handler_id`. `selected_text` is the current mouse
  selection in the focused pane, when one is visible.
- `herdr plugin pane open --plugin ID --entrypoint ID` supports
  `--placement overlay|popup|split|tab|zoomed`, `--direction right|down`,
  `--target-pane PANE`, `--env KEY=VALUE`, `--focus|--no-focus`. The pane runs
  the manifest `[[panes]]` command and closes when that command exits.
- `herdr plugin log list [--plugin ID]` surfaces action/pane stdout/stderr.

## Non-goals (out of scope)

- Hover/highlight/Cmd/right-click/Enter triggers for local paths (impossible
  in herdr v1, see constraints).
- Previewing remote http(s) markdown URLs (a future `[[link_handlers]]`
  addition; the `github-link-preview` example shows the pattern).
- Live-reload on file change; preview pane reuse/singleton behavior.
- A bundled/custom markdown renderer (considered, rejected by user).

## Approach

**Selection + keybinding.** The user drag-selects the path text (herdr copies
it and keeps the selection visible), then presses `prefix+m`. The action reads
`selected_text` and `focused_pane_cwd` from the context JSON, resolves and
validates the path, and opens the preview pane. This works in any app (agent
TUI, `ls` output, `cat`, editor) because it acts on the terminal selection,
not on app cooperation.

Alternatives considered:

- *Picker popup* (scrape pane output for `.md`-looking tokens, present a
  picker): one keystroke but more moving parts and heuristics. Rejected
  (YAGNI for v1).
- *Hover/click link handler*: impossible for local paths (constraints above).

## Structure

No build step; pure bash + manifest.

```
herdr-markdown-viewer/
├── herdr-plugin.toml      # manifest: 1 action, 1 pane entrypoint
├── open.sh                # action: resolve selection -> open preview pane
├── preview.sh             # pane command: glow -p, else cat + read
├── tests/
│   ├── test_open.sh       # path resolution/validation + herdr argv
│   └── test_preview.sh    # renderer fallback chain
└── README.md              # install, keybinding setup, usage
```

## Manifest

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

No `[[link_handlers]]` (local paths are not clickable) and no `[[events]]`.

## Trigger flow

1. User drag-selects a path in any pane (herdr copies it; selection stays
   visible).
2. User presses `prefix+m`. This requires one snippet in
   `~/.config/herdr/config.toml` (documented in README):

   ```toml
   [[keys.command]]
   key = "prefix+m"
   type = "plugin_action"
   command = "herdr.markdown-viewer.preview"
   description = "preview selected markdown file"
   ```

3. `open.sh` parses `HERDR_PLUGIN_CONTEXT_JSON` for `selected_text`,
   `focused_pane_cwd`, `focused_pane_id`.
4. Sanitize the selection: take the first line, trim whitespace, strip one
   layer of surrounding quotes/backticks, expand a leading `~` or `~/`.
5. Resolve: if relative, join with `focused_pane_cwd`.
6. Validate: must exist, be a regular file, and end in `.md` or `.markdown`
   (case-insensitive).
7. Open the pane:

   ```sh
   "$HERDR_BIN_PATH" plugin pane open \
     --plugin herdr.markdown-viewer \
     --entrypoint preview \
     --placement split \
     --direction right \
     --target-pane "$focused_pane_id" \
     --env "MD_PATH=$abs_path" \
     --focus
   ```

   `--focus` is required because both preview paths are interactive (glow's
   pager, or the read-to-close prompt).

## Preview pane (`preview.sh`)

Renderer chain (user decision: no bundled renderer):

1. `glow -p "$MD_PATH"` if `glow` is on PATH — full glamour rendering with
   built-in pager; `q` exits and the pane closes automatically.
2. Else `cat "$MD_PATH"` followed by `read` ("press enter to close this
   preview..."), the same keep-alive pattern as the official
   `github-link-preview` example; Enter exits and the pane closes.

If `MD_PATH` is unset or the file vanished, print the problem and wait on
`read` so the message stays visible.

## Error handling

All failure cases in `open.sh` (no selection, empty after sanitize,
unresolvable path, missing/non-regular file, non-markdown extension) behave
the same way: print a message to stderr (visible via
`herdr plugin log list --plugin herdr.markdown-viewer`) and exit non-zero.
No pane is opened. JSON parsing uses `python3` when available and falls back
to targeted sed/grep extraction when it is not, so the plugin works on
machines without python3.

## Testing

- `tests/test_open.sh`: runs `open.sh` with a stubbed `HERDR_BIN_PATH`
  (records argv) and fixture context JSON. Covers: relative path, absolute
  path, `~` expansion, quoted/backticked selection, path with spaces,
  multi-line selection (first line wins), missing selection, missing file,
  wrong extension. Asserts the exact `plugin pane open` argv and that no pane
  opens on failure.
- `tests/test_preview.sh`: runs `preview.sh` with a stubbed `glow` on PATH /
  without it, asserting glow is preferred and the cat+read fallback engages
  otherwise (read fed `</dev/null`).
- Manual E2E in a live session: `herdr plugin link .`, add the keybinding,
  `herdr server reload-config`, select a path in a pane, `prefix+m`, verify
  the right split opens with rendered markdown; repeat without glow.
