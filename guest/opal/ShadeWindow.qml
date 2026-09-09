import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    id:shadeScope
    readonly property bool opened:Hub.page==="controls"||Hub.page==="notifications"
    property bool presentCard:false
    onOpenedChanged:{if(opened)Qt.callLater(()=>presentCard=opened);else presentCard=false;}
    Component.onCompleted:if(opened)Qt.callLater(()=>presentCard=opened)
    PanelWindow {
        screen:Hub.targetScreen||Quickshell.screens[0]
        visible:shadeScope.opened
        anchors {top:true;bottom:true;left:true;right:true}
        exclusionMode:ExclusionMode.Ignore
        WlrLayershell.layer:WlrLayer.Overlay
        WlrLayershell.namespace:"opal-shade-dismiss"
        WlrLayershell.keyboardFocus:WlrKeyboardFocus.None
        color:"transparent"
        MouseArea {anchors.fill:parent;acceptedButtons:Qt.AllButtons;onPressed:Hub.close()}
    }
    PanelWindow {
        id:shade
        screen:Hub.targetScreen||Quickshell.screens[0]
        readonly property bool phone:Hub.layoutFor(screen ? screen.width : 1920,screen ? screen.height : 1080,screen ? screen.name : "")==="phone"&&(screen ? screen.width<680 : true)
        visible:shadeScope.opened&&shadeScope.presentCard
        anchors {top:true;right:true}
        margins {top:shade.phone ? 0 : 56;right:shade.phone ? 0 : 12}
        implicitWidth:phone ? (screen ? screen.width : 390) : Math.min(490,screen ? screen.width-24 : 490)
        implicitHeight:phone ? (screen ? screen.height : 844) : Math.min(820,screen ? screen.height-80 : 820)
        exclusionMode:ExclusionMode.Ignore
        WlrLayershell.layer:WlrLayer.Overlay
        WlrLayershell.namespace:"opal-shade"
        WlrLayershell.keyboardFocus:visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color:"transparent"
        Surface {id:shadeCard;anchors.fill:parent;radius:shade.phone ? 0 : 32;translucency:Hub.prefs.glass
            property real reveal:1
            opacity:reveal;transform:Translate {y:-12*(1-shadeCard.reveal)}
            Connections {target:shade;function onVisibleChanged(){if(shade.visible)enter.restart();}}
            NumberAnimation {id:enter;target:shadeCard;property:"reveal";from:0;to:1;duration:Theme.motion(240);easing.type:Easing.OutCubic}
            Loader {anchors.fill:parent;active:shade.visible;sourceComponent:Component {QuickSettings {}}}
            Rectangle {visible:Hub.toast!=="";anchors.left:parent.left;anchors.right:parent.right;anchors.bottom:parent.bottom;anchors.margins:12;height:70;radius:22;color:Theme.surfaceHigh;z:5
                MText {anchors.fill:parent;anchors.margins:12;text:Hub.toast;font.pixelSize:12;wrapMode:Text.Wrap;maximumLineCount:3;verticalAlignment:Text.AlignVCenter}
                MouseArea {anchors.fill:parent;onClicked:Hub.toast=""}
            }
            Shortcut {sequence:"Escape";onActivated:Hub.close()}
        }
    }
}
