import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

// Command-backed counterpart to the audio widget. This intentionally avoids
// importing QuickShell's optional PipeWire QML service, which Opal does not
// ship in its current runtime.
BarWidget {
  id: root
  moduleName: "omarchy.microphone"

  property bool muted: true
  property bool available: false

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function updateStatus(raw) {
    var match = String(raw || "").trim().match(/^([01])$/)
    if (!match) return
    muted = match[1] === "1"
    available = true
  }

  function toggleMute() {
    Quickshell.execDetached(["omarchy-audio-input-toggle-mute"])
    muted = !muted
    refreshDelay.restart()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  visible: available

  Process {
    id: statusProc
    command: ["omarchy-audio-input-status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateStatus(text)
    }
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: refreshDelay
    interval: 150
    repeat: false
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.muted ? "󰍭" : "󰍬"
    tooltipText: root.muted ? "Microphone muted" : "Microphone live"
    onPressed: function(button) {
      if (button === Qt.MiddleButton) root.bar.run("omarchy-shell shell toggle omarchy.audio")
      else root.toggleMute()
    }
  }
}
