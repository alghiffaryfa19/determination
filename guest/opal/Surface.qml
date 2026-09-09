import QtQuick
Rectangle {
    property real translucency: Hub.prefs.glass
    property bool elevated: false
    radius: 32
    color: Theme.alpha(elevated ? Theme.surfaceHigh : Theme.base, translucency)
    border.width: 1
    border.color: Theme.outline
    Behavior on color { ColorAnimation { duration: 240 } }
}
