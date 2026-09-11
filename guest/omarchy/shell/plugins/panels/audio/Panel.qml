import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Opal's shipped QuickShell has MPRIS, tray and notifications, but not the
// optional PipeWire QML module. Keep this widget on the command audio API so
// the shell remains loadable on that runtime and can still control the default
// sink when PipeWire/Pulse tools are present in the guest.
Panel {
  id: root
  moduleName: "omarchy.audio"
  ipcTarget: "omarchy.audio"

  property int outputPercent: -1
  property bool outputMuted: true
  property string outputName: ""

  readonly property bool audioAvailable: outputPercent >= 0
  readonly property string outputIcon: {
    if (!audioAvailable || outputMuted) return ""
    if (outputPercent >= 67) return ""
    if (outputPercent >= 34) return ""
    return ""
  }
  readonly property string outputLabel: !audioAvailable ? "Audio unavailable"
    : outputMuted ? "Muted" : outputPercent + "%"

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function updateStatus(raw) {
    var match = String(raw || "").trim().match(/^(-?\d+)\s+([01])(?:\s+(.*))?$/)
    if (!match) return
    outputPercent = Math.max(-1, Math.min(150, Number(match[1])))
    outputMuted = match[2] === "1"
    outputName = String(match[3] || "").trim()
  }

  function showVolumeOsd() {
    if (!bar || !bar.shell || !audioAvailable) return
    bar.shell.summon("omarchy.osd", JSON.stringify({
      icon: outputIcon,
      value: outputPercent
    }))
  }

  function setOutputVolume(percent) {
    var next = Math.max(0, Math.min(150, Math.round(percent)))
    outputPercent = next
    outputMuted = false
    Quickshell.execDetached(["omarchy-audio-output-volume", String(next)])
    refreshDelay.restart()
    showVolumeOsd()
  }

  function adjustOutput(delta) {
    if (!audioAvailable) return
    setOutputVolume(outputPercent + delta)
  }

  function toggleOutputMute() {
    Quickshell.execDetached(["omarchy-audio-output-toggle-mute"])
    outputMuted = !outputMuted
    refreshDelay.restart()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: statusProc
    command: ["omarchy-audio-status"]
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
    text: root.outputIcon
    active: root.opened
    tooltipText: root.outputName ? root.outputLabel + " · " + root.outputName : root.outputLabel

    onPressed: function(button) {
      if (button === Qt.RightButton) root.toggleOutputMute()
      else root.toggle()
    }

    onWheelMoved: function(delta) {
      root.adjustOutput(delta > 0 ? 5 : -5)
    }
  }

  PopupCard {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.opened
    contentWidth: popup.fittedContentWidth(Style.space(320))
    contentHeight: popup.fittedContentHeight(panelColumn.implicitHeight)

    Column {
      id: panelColumn
      anchors.fill: parent
      spacing: Style.space(12)

      Row {
        width: parent.width
        spacing: Style.space(12)

        Text {
          text: root.outputIcon
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.display
          anchors.verticalCenter: parent.verticalCenter
        }

        Column {
          width: parent.width - muteButton.width - Style.space(12)
          spacing: Style.space(2)

          Text {
            width: parent.width
            text: "Audio"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            text: root.outputName || root.outputLabel
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        Button {
          id: muteButton
          iconText: root.outputMuted ? "󰝟" : "󰕾"
          foreground: root.bar.foreground
          tooltipText: root.outputMuted ? "Unmute output" : "Mute output"
          onClicked: root.toggleOutputMute()
        }
      }

      PanelSeparator { foreground: root.bar.foreground }

      Text {
        text: root.audioAvailable ? "OUTPUT  " + root.outputPercent + "%" : "NO DEFAULT OUTPUT"
        color: Qt.darker(root.bar.foreground, 1.4)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.1
      }

      PanelSlider {
        id: outputSlider
        bar: root.bar
        width: parent.width
        minimum: 0
        maximum: 150
        step: 5
        value: root.outputPercent < 0 ? 0 : root.outputPercent
        opacity: root.outputMuted ? 0.5 : 1.0
        enabled: root.audioAvailable
        onMoved: function(value) { root.setOutputVolume(value) }
        onRightClicked: root.toggleOutputMute()
      }

      Text {
        width: parent.width
        text: root.audioAvailable
          ? "Scroll the bar icon to adjust. Right-click it to mute."
          : "Start PipeWire or PulseAudio to expose a default output."
        color: Qt.darker(root.bar.foreground, 1.55)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }
  }
}
