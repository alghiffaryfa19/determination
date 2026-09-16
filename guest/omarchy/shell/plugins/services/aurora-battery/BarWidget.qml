import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

BarWidget {
  id: root
  moduleName: "aurora.battery"

  property int percentage: -1
  property string state: ""

  readonly property string glyph: {
    if (percentage < 0) return "󰂑"
    if (state === "Charging") return "󰂄"
    if (percentage <= 10) return "󰁺"
    if (percentage <= 30) return "󰁼"
    if (percentage <= 60) return "󰁾"
    if (percentage <= 85) return "󰂀"
    return "󰁹"
  }

  function refresh() {
    if (!probe.running) probe.running = true
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: probe
    command: [
      "sh", "-c",
      "for node in bms battery; do "
        + "cap=/sys/class/power_supply/$node/capacity; "
        + "[ -r \"$cap\" ] || continue; "
        + "state=/sys/class/power_supply/$node/status; "
        + "printf \"%s %s\\n\" \"$(cat \"$cap\")\" \"$(cat \"$state\" 2>/dev/null)\"; exit; "
        + "done"
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var match = String(text || "").trim().match(/^(\d{1,3})(?:\s+(.*))?$/)
        if (!match) return
        root.percentage = Math.max(0, Math.min(100, Number(match[1])))
        root.state = String(match[2] || "").trim()
      }
    }
  }

  Timer {
    interval: 15000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  IpcHandler {
    target: "aurora.battery"
    function refresh(): void { root.broadcast("refresh") }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.percentage < 0 ? "" : root.glyph + " " + root.percentage + "%"
    tooltipText: root.percentage < 0 ? "Battery unavailable"
      : "Battery " + root.percentage + "%" + (root.state ? " · " + root.state : "")
    onPressed: function(button) {
      if (button === Qt.LeftButton && root.bar)
        root.bar.run("omarchy-shell shell toggle omarchy.audio")
    }
  }
}
