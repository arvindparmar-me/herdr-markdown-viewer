# Markdown Viewer (herdr plugin)

Preview a local markdown file in a right-split pane. Select a file path in
any pane, press `prefix+m`, and the markdown renders beside your work —
with [glow](https://github.com/charmbracelet/glow) when installed, plain
`cat` otherwise.

## Requirements

- herdr >= 0.7.4
- bash (macOS `/bin/bash` 3.2 is fine)
- optional: `glow` for rendered markdown (`brew install glow`)
- optional: `python3` for context JSON parsing and pane rename support

## Install

From this directory:

```sh
herdr plugin link "$PWD"
```

Or install from GitHub:

```sh
herdr plugin install arvindparmar-me/herdr-markdown-viewer
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
   working directory, or starting with `~`). Herdr copies the path to the
   clipboard, but clears the visible selection — the plugin reads the
   clipboard as a fallback.
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
- If an unexpected file opens: herdr clears the selection after
  drag-copying, so the plugin falls back to the system clipboard.
  Make sure you drag-select a path immediately before the keybinding.
- See action errors: `herdr plugin log list --plugin herdr.markdown-viewer`.
- Verify registration: `herdr plugin list`, then
  `herdr plugin action list --plugin herdr.markdown-viewer`.

## Uninstall

```sh
herdr plugin unlink herdr.markdown-viewer     # if linked locally (keeps files)
herdr plugin uninstall herdr.markdown-viewer  # if installed from GitHub (removes checkout)
```

## Development

Run the tests:

```sh
bash tests/run.sh
```
