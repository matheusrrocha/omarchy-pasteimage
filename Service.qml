import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Re-asserts PasteImage's SUPER+V binding.
//
// All of the logic lives in bin/omarchy-pasteimage; this service only decides
// *when* to run it — once at load, and again after every Hyprland config reload,
// which re-registers the stock SUPER+V and would otherwise take the key back.
//
// The binding is opt-in: `apply-binding` is a no-op until the user has run
// `omarchy-pasteimage enable`, so a plugin that is installed and enabled in the
// shell but never opted into stays completely inert and touches no keybinding.
Item {
  id: root

  // omarchy-shell injects this into first-party services. Unused here; declared
  // so the loader has somewhere to put it.
  property var shell: null

  // Wherever this plugin was installed. The script is called by absolute path so
  // nothing depends on ~/.local/bin being on Hyprland's PATH.
  readonly property string pluginDir: String(Qt.resolvedUrl("."))
    .replace(/^file:\/\//, "")
    .replace(/\/$/, "")
  readonly property string scriptPath: pluginDir + "/bin/omarchy-pasteimage"

  function applyBinding() {
    bindProcess.running = false
    bindProcess.running = true
  }

  Component.onCompleted: applyBinding()

  Process {
    id: bindProcess
    command: [root.scriptPath, "apply-binding"]
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event && String(event.name) === "configreloaded") rebindTimer.restart()
    }
  }

  // The delay lets Hyprland finish parsing before we replace what it just
  // installed.
  Timer {
    id: rebindTimer
    interval: 250
    repeat: false
    onTriggered: root.applyBinding()
  }
}
