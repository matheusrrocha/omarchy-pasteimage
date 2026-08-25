import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Claims SUPER+V for the image-aware paste script.
//
// Omarchy's stock "Universal paste" sends Shift+Insert to anything tagged
// `terminal` (default/hypr/bindings/clipboard.lua). Terminals implement that as
// paste_from_clipboard, which is text-only, so pasting an image into a TUI is a
// silent no-op. bin/omarchy-pasteimage sends Ctrl+V for images instead and keeps
// the stock behaviour for everything else.
Item {
  id: root

  // omarchy-shell injects this into first-party services. Unused here; declared
  // so the loader has somewhere to put it.
  property var shell: null

  // Wherever this plugin was installed. The binding calls the script by absolute
  // path so it does not depend on ~/.local/bin being on Hyprland's PATH.
  readonly property string pluginDir: String(Qt.resolvedUrl("."))
    .replace(/^file:\/\//, "")
    .replace(/\/$/, "")
  readonly property string scriptPath: pluginDir + "/bin/omarchy-pasteimage"

  function luaString(value) {
    return '"' + String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"'
  }

  function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  // The binding outlives the plugin. omarchy-shell never destroys a service
  // component — Component.onDestruction does not fire on disable or remove — so
  // there is no teardown hook to clean up from, and a bind pointing straight at
  // the plugin directory would go dead the moment the plugin is removed. Guard
  // the exec instead: if the script is gone, the first SUPER+V press reloads the
  // config, which hands the key straight back to the user's own binding.
  readonly property string pasteCommand:
    "test -x " + shellQuote(scriptPath) +
    " && exec " + shellQuote(scriptPath) + " paste" +
    " || hyprctl reload config-only"

  // Hyprland's Lua parser refuses `hyprctl keyword` outright ("keyword can't work
  // with non-legacy parsers. Use eval."), so the bind is installed by evaluating
  // Lua in the config state. The unbind matters: without it the config's own
  // SUPER+V stays registered alongside this one and both fire.
  readonly property string bindLua:
    'hl.unbind("SUPER + V") ' +
    'hl.bind("SUPER + V", hl.dsp.exec_cmd(' + luaString(pasteCommand) + '), ' +
    '{ description = "Universal paste" })'

  function applyBinding() {
    bindProcess.running = false
    bindProcess.running = true
  }

  Component.onCompleted: applyBinding()

  Process {
    id: bindProcess
    command: ["hyprctl", "eval", root.bindLua]
  }

  // A config reload re-registers the stock SUPER+V, so claim it back. The delay
  // lets Hyprland finish parsing before replacing what it just installed.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event && String(event.name) === "configreloaded") rebindTimer.restart()
    }
  }

  Timer {
    id: rebindTimer
    interval: 250
    repeat: false
    onTriggered: root.applyBinding()
  }
}
