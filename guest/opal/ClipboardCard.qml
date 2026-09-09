import QtQuick
import QtQuick.Layouts

Rectangle {
    id:card
    property bool compact:false
    readonly property bool narrow:compact||width<620
    implicitHeight:Hub.clipboardItems.length>0 ? (narrow ? 260 : 222) : 190
    radius:28;color:Theme.alpha(Theme.tertiary,Theme.light ? .28 : .10)
    ColumnLayout {
        anchors {fill:parent;margins:18}
spacing:10
        RowLayout {Layout.fillWidth:true;spacing:10
            Glyph {name:"clipboard";color:Theme.primary;font.pixelSize:23}
            ColumnLayout {Layout.fillWidth:true;spacing:3
                MText {text:"Clipboard";font.pixelSize:18;font.weight:Font.DemiBold}
                MText {text:Hub.clipboardPaused ? "Paused · your history stays private" : Hub.clipboardItems.length+" clips · memory only";color:Theme.subtext;font.pixelSize:10}
            }
            MButton {icon:"expand";compact:true;implicitWidth:38;implicitHeight:38;tooltip:"Open clipboard · Super+V";onClicked:Hub.toggleClipboard()}
        }
        GridLayout {Layout.fillWidth:true;columns:card.narrow ? 1 : 3;columnSpacing:10;rowSpacing:8
            Repeater {
                model:Hub.clipboardItems.slice(0,card.narrow ? 2 : 3)
                ClipboardEntry {required property var modelData;Layout.fillWidth:true;implicitHeight:card.narrow ? 56 : 86;record:modelData;compact:true;closeAfterCopy:false}
            }
        }
        MText {visible:Hub.clipboardItems.length===0;Layout.fillWidth:true;Layout.fillHeight:true;text:Hub.clipboardPaused ? "Resume collecting whenever you’re ready." : Hub.clipboardAvailable ? "Copied something worth keeping?\nYour latest text will appear here." : Hub.clipboardDetail;wrapMode:Text.Wrap;horizontalAlignment:Text.AlignHCenter;verticalAlignment:Text.AlignVCenter;color:Theme.subtext;font.pixelSize:13}
        RowLayout {Layout.fillWidth:true;spacing:8
            MText {text:"SUPER + V";font.pixelSize:9;font.letterSpacing:1.5;color:Theme.muted;Layout.fillWidth:true}
            MButton {text:Hub.clipboardPaused ? "Resume" : "Pause";icon:Hub.clipboardPaused ? "play" : "pause";compact:true;tooltip:"Pause clipboard collection";onClicked:Hub.pauseClipboard()}
        }
    }
}
