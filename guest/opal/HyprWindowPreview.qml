import QtQuick
import Quickshell.Hyprland

WindowPreview {
    property string address:""
    readonly property var target:Hyprland.toplevels.values.find(t=>t.address.replace(/^0x/,"")===address.replace(/^0x/,""))||null
    handle:target ? target.wayland : null
}
