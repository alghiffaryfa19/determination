import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
Rectangle {
    id: a
    property string text: ""
    property string icon: ""
    property string tooltip: text
    property bool filled: false
    property bool tonal: false
    property bool compact: false
    property bool morph: false
    property bool checked: false
    property color accent: Theme.primary
    property color ink: filled ? Theme.onPrimary : Theme.text
    property var menuEntries: []
    property bool scrollable: false
    signal scrolled(int steps)
    signal clicked()
    implicitWidth: Math.max(compact ? 42 : 48, content.implicitWidth + (compact ? 24 : 32))
    implicitHeight: compact ? 38 : 48
    // Original expressive pills: soft at rest, gently compressed on press.
    radius: mouse.pressed ? 14 : morph&&checked ? Math.min(18,height*.30) : height/2
    color: filled ? accent : tonal ? Theme.primaryContainer : mouse.containsMouse || activeFocus ? Theme.surfaceHigh : "transparent"
    border.width: activeFocus ? 2 : 0
    border.color: Theme.primary
    opacity: enabled ? 1 : 0.35
    scale: Theme.reduceMotion ? 1 : mouse.pressed ? 0.95 : 1
    Behavior on radius { NumberAnimation { duration: Theme.motion(220); easing.type: Easing.OutBack } }
    Behavior on scale { NumberAnimation { duration: Theme.motion(mouse.pressed ? 80 : 240); easing.type: mouse.pressed ? Easing.OutCubic : Easing.OutBack; easing.overshoot:0.6 } }
    Behavior on color { ColorAnimation { duration: Theme.motion(140) } }
    RowLayout { id: content; anchors.centerIn: parent; width: Math.min(implicitWidth, Math.max(0,a.width-24)); spacing: 9
        Glyph { visible: a.icon!==""; name:a.icon; color:a.filled ? Theme.onPrimary : a.tonal ? Theme.onContainer : a.ink; font.pixelSize:a.compact ? 19 : 22 }
        MText { visible:a.text!==""; text:a.text; textFormat:Text.PlainText; Layout.fillWidth:true; elide:Text.ElideRight; color:a.filled ? Theme.onPrimary : a.tonal ? Theme.onContainer : a.ink; font.pixelSize:a.compact ? 12 : 14; font.weight:Font.DemiBold }
    }
    activeFocusOnTab: true
    Keys.onReturnPressed: clicked()
    Keys.onSpacePressed: clicked()
    // Keep the Popup in its original coordinate space while avoiding menu-item
    // construction until it is actually open.
    OpalMenu {id:buttonMenu;entries:visible ? a.menuEntries : []}
    MouseArea {
        id:mouse;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor
        acceptedButtons:Qt.LeftButton|Qt.RightButton
        property bool held:false
        onWheel:e=>{if(a.scrollable){a.scrolled(e.angleDelta.y>0 ? 1 : -1);e.accepted=true;}else e.accepted=false;}
        onPressed:held=false
        onClicked:e=>{if(held)return;if(e.button===Qt.RightButton){if(a.menuEntries.length)buttonMenu.popup(e.x,e.y);}else a.clicked();}
        onPressAndHold:e=>{if(a.menuEntries.length){held=true;buttonMenu.popup(e.x,e.y);}}
    }
    ToolTip.visible: mouse.containsMouse && tooltip!==""
    ToolTip.text: tooltip
    ToolTip.delay: 650
    Accessible.role: Accessible.Button
    Accessible.name: tooltip
    Accessible.onPressAction: clicked()
}
