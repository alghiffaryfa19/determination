import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import QtQml.Models
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Notifications
import Quickshell.Services.SystemTray
import Quickshell.Wayland

ShellRoot {
    Component.onCompleted: {
        console.log("OPAL_QML_IMPORTS_OK")
    }
    Timer { interval: 100; running: true; onTriggered: Qt.quit() }
}
