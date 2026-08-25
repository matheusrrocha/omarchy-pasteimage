# PasteImage

An Omarchy shell plugin for pasting screenshots into **AI coding agents running
in your terminal** — Claude Code and the like — the way it already works on macOS.

Copy a screenshot, focus Claude Code, hit `SUPER+V`, get `[Image #1]`. Show the
agent a broken layout, a stack trace, a design mockup, a chart that looks wrong,
instead of describing it in words.

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

## Which agents this works with

The plugin's job ends at delivering `Ctrl+V` to whatever is running in the
terminal. The agent has to read the clipboard itself, and that is what decides
whether an image actually lands:

| Agent | Status |
| --- | --- |
| **Claude Code** | Verified. It shells out to `wl-paste --type image/png` on Linux and attaches the result as `[Image #1]`. |
| Other terminal agents (`codex`, `opencode`, `crush`, `gemini`, `grok`, …) | Untested. Works if the agent reads clipboard images on `Ctrl+V`; if it does not, it receives a bare `0x16` and nothing pastes. |

Nothing here is Claude-specific — any TUI that reads the clipboard on `Ctrl+V`
benefits. Claude Code is simply the one this was built against and verified on.

If your agent falls in the second row, the fallback is to paste a file *path*
instead: clipboard images are already on disk at
`~/.local/state/omarchy/clipboard-images/`, and most agents will read an image
path handed to them as text. That is not wired up here — open an issue if you
want it.

## Install

```bash
omarchy plugin add https://github.com/matheusrrocha/omarchy-pasteimage.git --enable
~/.config/omarchy/plugins/rocha.pasteimage/install && omarchy-pasteimage enable
```

The second line is the opt-in. **Claiming `SUPER+V` is deliberate, never
automatic** — installing and enabling the plugin does nothing on its own, because
`SUPER+V` is a key your own Hyprland config defines and this should not take it
without you asking. `install` puts the CLI on your PATH; `enable` claims the key.

```bash
omarchy-pasteimage check      # opt-in state, dependencies, what paste would do now
omarchy-pasteimage disable    # hand SUPER+V back to your config, keep the plugin
```

Nothing under `~/.config` is written at any point. The binding is installed into
Hyprland's *runtime* state, so your config always wins on the next reload — the
service simply re-claims the key afterwards while you are opted in.

### Removing it

```bash
omarchy-pasteimage disable
omarchy plugin remove rocha.pasteimage
```

`disable` alone is enough to get `SUPER+V` back. If you remove the plugin without
disabling first, the next `SUPER+V` press restores your binding by itself — see
[Why the binding heals itself](#why-the-binding-heals-itself).

## How it claims the binding

Once you have opted in with `enable`, Omarchy 4 configures Hyprland in Lua, and
Hyprland's Lua parser refuses `hyprctl keyword` outright — *"keyword can't work
with non-legacy parsers. Use eval."* So the binding goes in through
`hyprctl eval`, which evaluates Lua in the config state:

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

- **Only helps programs that read the clipboard themselves** — see
  [Which agents this works with](#which-agents-this-works-with). At a plain shell
  prompt `Ctrl+V` is readline's `quoted-insert`: harmless, but nothing pastes.
- The binding is applied at runtime, so it will not appear in your `bindings.lua`.
  `omarchy menu keybindings --print` still shows it.
- Until you run `enable`, the plugin is inert — it binds nothing and changes no
  behaviour, even when installed and enabled in the shell.
- Removing the plugin costs you one `SUPER+V` press, which is spent restoring the
  stock binding.
- Plugins run unsandboxed inside `omarchy-shell`. Read `Service.qml` before you
  enable it — it's about 60 lines.

## Requires

Omarchy 4 (Hyprland 0.56+, Lua config), `wl-clipboard`, `jq`.

## License

MIT. The optional overlay patch derives from Omarchy (MIT, Basecamp).
