# PasteImage

An Omarchy shell plugin that lets you paste clipboard images into terminal TUIs —
the way pasting into a terminal works on macOS.

Copy a screenshot, focus Claude Code, hit `SUPER+V`, get `[Image #1]`.

## The problem

Nothing about the terminal is actually in the way. Ghostty binds only
`ctrl+shift+v` for paste, so `ctrl+v` reaches the running program untouched, and
Claude Code already knows how to read a clipboard image on Linux — it shells out
to `wl-paste --type image/png` and attaches the result.

The keybinding is what swallows it. Omarchy's stock `SUPER+V` — "Universal
paste", in `/usr/share/omarchy/default/hypr/bindings/clipboard.lua` — sends
**Shift+Insert** whenever the focused window carries Hyprland's `terminal` tag.
Terminals implement Shift+Insert as `paste_from_clipboard`, which is text-only.
An image clipboard is a silent no-op.

## What it does

Claims `SUPER+V` and makes it image-aware. When a terminal is focused **and** the
clipboard holds an image, it sends **Ctrl+V**, which terminals pass straight
through to the running program. Every other case keeps stock behaviour:

| Focused window | Clipboard | Sent |
| --- | --- | --- |
| Terminal | image | `Ctrl+V` ← the fix |
| Terminal | text | `Shift+Insert` (stock) |
| Anything else | either | `Ctrl+V` (stock) |

## Install

```bash
omarchy plugin add https://github.com/matheusrrocha/omarchy-pasteimage.git --enable
```

That's all — the service claims `SUPER+V` when it loads. Nothing to edit.

Optionally put the CLI on your PATH:

```bash
~/.config/omarchy/plugins/rocha.pasteimage/install
omarchy-pasteimage check     # dependencies, focused window, clipboard contents
```

### Removing it

```bash
omarchy plugin remove rocha.pasteimage
```

The first `SUPER+V` after that reloads your Hyprland config and hands the key
back to your own binding; press it again and you get stock paste. Nothing else to
run. See [Why the binding heals itself](#why-the-binding-heals-itself) for why
that press is needed at all.

## How it claims the binding

Omarchy 4 configures Hyprland in Lua, and Hyprland's Lua parser refuses
`hyprctl keyword` outright — *"keyword can't work with non-legacy parsers. Use
eval."* So `Service.qml` evaluates Lua in the config state instead:

```lua
hl.unbind("SUPER + V")
hl.bind("SUPER + V", hl.dsp.exec_cmd(".../bin/omarchy-pasteimage paste"),
        { description = "Universal paste" })
```

The `unbind` matters — without it the config's own `SUPER+V` stays registered
alongside this one and both fire. A config reload re-registers the stock binding,
so the service listens for Hyprland's `configreloaded` event and claims it back
~250ms later. There is a brief window right after a reload where stock behaviour
applies.

### Why the binding heals itself

Hyprland keybindings live in runtime state, so this one outlives the plugin. The
obvious cleanup — restore the config when the service shuts down — is not
available: `omarchy-shell` never destroys a service component, and
`Component.onDestruction` does not fire on either `plugin disable` or
`plugin remove`. A bind pointing straight at the plugin directory would therefore
go dead the moment the plugin was removed.

So the exec is guarded instead:

```sh
test -x <plugin>/bin/omarchy-pasteimage && exec <plugin>/bin/omarchy-pasteimage paste \
  || hyprctl reload config-only
```

If the script is gone, the keypress reloads the config, which re-registers the
user's own `SUPER+V`. The plugin cannot leave a dead key behind.

Keystrokes are injected with Hyprland's `send_key_state` dispatcher rather than
`wtype`: a physically-held SUPER merges into a wtype-injected chord at the seat,
which would turn `Ctrl+V` into `SUPER+CTRL+V` — the clipboard manager.

## Optional: clipboard history images

The clipboard history overlay (`SUPER+CTRL+V`) has the same gap — it hands image
rows to `omarchy-clipboard-paste-file`, which also sends Shift+Insert. Fixing that
means cloning the built-in overlay, since `/usr/share/omarchy` is package-owned:

```bash
~/.config/omarchy/plugins/rocha.pasteimage/extras/patch-clipboard-overlay
```

That clones `omarchy.clipboard` into `<you>.clipboard` and repoints one call site.
Re-run it after `omarchy update` — plugin clones live in `~/.config` and are never
updated in place, so the copy goes stale silently.

## Caveats

- **Only helps TUIs that read the clipboard themselves.** Claude Code does.
  `codex`, `opencode`, `crush`, `gemini`, and `grok` mostly do not — they receive a
  bare `0x16`, and in a plain shell that's readline's `quoted-insert`. Harmless, but
  nothing pastes.
- The binding is applied at runtime, so it will not appear in your `bindings.lua`.
  `omarchy menu keybindings --print` still shows it.
- Removing the plugin costs you one `SUPER+V` press, which is spent restoring the
  stock binding.
- Plugins run unsandboxed inside `omarchy-shell`. Read `Service.qml` before you
  enable it — it's about 60 lines.

## Requires

Omarchy 4 (Hyprland 0.56+, Lua config), `wl-clipboard`, `jq`.

## License

MIT. The optional overlay patch derives from Omarchy (MIT, Basecamp).
