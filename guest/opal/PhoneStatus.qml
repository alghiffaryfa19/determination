import QtQuick
import QtQuick.Layouts

Item {
    id:bar
    property var output:null
    implicitHeight:48
    function show(page) {if(output)Hub.targetScreen=output;Hub.toggle(page);}
    RowLayout {
        anchors.fill:parent;anchors.leftMargin:12;anchors.rightMargin:12;spacing:4
        MButton {
            text:Qt.formatDateTime(Hub.now,"HH:mm");compact:true;implicitHeight:40
            tooltip:Qt.formatDateTime(Hub.now,"dddd, d MMMM")+" · tap for notifications"
            onClicked:bar.show("notifications")
            menuEntries:[{text:Hub.dnd ? "Allow notifications" : "Quiet notifications",icon:"quiet",run:()=>Hub.set("dnd",!Hub.dnd)},{text:"Personalize phone",icon:"palette",run:()=>bar.show("appearance")}]
        }
        Rectangle {
            visible:Hub.focusRunning;Layout.preferredWidth:64;Layout.preferredHeight:28;radius:14;color:Theme.primaryContainer
            MText {anchors.centerIn:parent;text:Math.ceil(Hub.focusSeconds/60)+"m focus";font.pixelSize:10;color:Theme.onContainer}
            MouseArea {anchors.fill:parent;onClicked:bar.show("controls")}
        }
        Item {Layout.fillWidth:true}
        MButton {visible:Hub.unread>0||Hub.dnd;icon:Hub.dnd ? "quiet" : "bell";text:Hub.unread ? String(Math.min(99,Hub.unread)) : "";compact:true;implicitHeight:40;tooltip:"Notification inbox";onClicked:bar.show("notifications")}
        MButton {icon:Hub.status.playing ? "music" : Hub.status.muted ? "mute" : "volume";compact:true;implicitWidth:40;implicitHeight:40;tooltip:"Sound & now playing";onClicked:Hub.toggleAudio(bar.output||Hub.chooseScreen())}
        MButton {
            icon:Hub.status.wifi ? "wifi" : "wifiOff";text:Hub.status.battery>=0 ? (Hub.status.charging ? "+ " : "")+Hub.status.battery+"%" : "";compact:true;implicitHeight:40
            tooltip:"Quick Settings · "+(Hub.status.network||"Offline")+(Hub.status.charging ? " · Charging" : "")
            tonal:true;onClicked:bar.show("controls")
            menuEntries:[{text:"Wi-Fi",icon:"wifi",run:()=>Hub.settings("network")},{text:"Dock & displays",icon:"convergence",run:()=>bar.show("convergence")}].concat(Hub.systemOskAvailable ? [{text:Hub.systemOskVisible ? "Hide keyboard" : "Show keyboard",icon:"keyboard",run:()=>Hub.systemOsk("toggle")}] : [])
        }
    }
}
