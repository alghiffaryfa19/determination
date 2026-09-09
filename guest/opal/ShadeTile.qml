import QtQuick
import QtQuick.Layouts

Rectangle {
    id:t
    property string icon:""
    property string title:""
    property string subtitle:""
    property bool active:false
    property bool settings:false
    signal openSettings()
    signal clicked()
    implicitHeight:72
    radius:mouse.pressed ? 18 : active ? 22 : height/2
    color:active ? Theme.primary : Theme.alpha(Theme.surfaceHigh,mouse.containsMouse ? .60 : .32)
    Behavior on color {ColorAnimation {duration:Theme.motion(220)}}
    scale:mouse.pressed ? .975 : 1
    Behavior on radius {NumberAnimation {duration:Theme.motion(220);easing.type:Easing.OutBack}}
    Behavior on scale {NumberAnimation {duration:Theme.motion(180)}}
    RowLayout {anchors.fill:parent;anchors.margins:8;spacing:10
        Rectangle {Layout.preferredWidth:48;Layout.preferredHeight:48;radius:t.active ? 16 : 24;color:t.active ? Theme.primary : Theme.alpha(Theme.surfaceHigh,.8)
            Behavior on radius {NumberAnimation {duration:Theme.motion(240)}}
            Behavior on color {ColorAnimation {duration:Theme.motion(200)}}
            Glyph {anchors.centerIn:parent;name:t.icon;font.pixelSize:26;color:t.active ? Theme.onPrimary : Theme.text}
        }
        ColumnLayout {Layout.fillWidth:true;spacing:3
            MText {Layout.fillWidth:true;text:t.title;wrapMode:Text.WordWrap;maximumLineCount:2;font.pixelSize:12;font.weight:Font.DemiBold;color:t.active ? Theme.onPrimary : Theme.text}
            MText {visible:t.subtitle!=="";Layout.fillWidth:true;text:t.subtitle;font.pixelSize:10;color:t.active ? Theme.alpha(Theme.onPrimary,.8) : Theme.subtext}
        }
    }
    MouseArea {id:mouse;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;onClicked:t.clicked();onPressAndHold:if(t.settings)t.openSettings()}
    activeFocusOnTab:true
    border.width:activeFocus ? 2 : 0;border.color:Theme.primary
    Keys.onReturnPressed:clicked()
    Keys.onSpacePressed:clicked()
    Accessible.role:Accessible.Button;Accessible.name:title+", "+subtitle;Accessible.onPressAction:clicked()
}
