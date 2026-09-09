import QtQuick
Rectangle {
    id: root
    property string text: ""
    property color ink: "#eee8f5"
    property bool selected: false
    signal clicked()
    implicitWidth: label.implicitWidth + 30
    implicitHeight: 38
    radius: height / 2
    color: selected ? "#d8c5ff" : mouse.containsMouse ? "#35ffffff" : "transparent"
    Behavior on color { ColorAnimation { duration: 160 } }
    scale: mouse.pressed ? 0.95 : 1
    Behavior on scale { NumberAnimation { duration: 120 } }
    Text { id: label; anchors.centerIn: parent; text: root.text; color: root.selected ? "#302044" : root.ink; font.family: "Inter"; font.pixelSize: 13; font.weight: Font.DemiBold }
    MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.clicked() }
}
