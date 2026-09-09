import QtQuick
import QtQuick.Layouts
Rectangle {
    id:f
    implicitHeight:172
    radius:30;color:Theme.primaryContainer
    RowLayout {anchors {fill:parent;margins:22}
spacing:20
        Item {Layout.preferredWidth:105;Layout.preferredHeight:105
            Flower {anchors.fill:parent;fill:Theme.primary;lobes:12}
            Column {anchors.centerIn:parent;spacing:2
                MText {anchors.horizontalCenter:parent.horizontalCenter;text:Math.floor(Hub.focusSeconds/60).toString().padStart(2,"0");font.pixelSize:38;font.weight:Font.Bold;color:Theme.onPrimary}
                MText {anchors.horizontalCenter:parent.horizontalCenter;text:(Hub.focusSeconds%60).toString().padStart(2,"0");font.pixelSize:16;color:Theme.onPrimary}
            }
        }
        ColumnLayout {Layout.fillWidth:true;spacing:8
            MText {text:Hub.focusRunning ? "One thing at a time." : "Find your focus.";font.pixelSize:19;font.weight:Font.DemiBold;color:Theme.onContainer;Layout.fillWidth:true}
            MText {text:Hub.focusRunning ? "You’ve got this. Keep going." : "A little intention. A lot less noise.";font.pixelSize:11;color:Theme.onContainer;Layout.fillWidth:true}
            RowLayout {spacing:4
                MButton {icon:Hub.focusRunning ? "pause" : "play";text:Hub.focusRunning ? "Pause" : "Focus";filled:true;compact:true;onClicked:Hub.timerToggle()}
                MButton {icon:"restart";compact:true;ink:Theme.onContainer;tooltip:"Reset 25 minute timer";onClicked:{Hub.focusRunning=false;Hub.focusSeconds=25*60;}}
                MButton {text:"+5";compact:true;ink:Theme.onContainer;onClicked:Hub.focusSeconds+=300}
            }
        }
    }
}
