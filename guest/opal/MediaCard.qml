import QtQuick
import QtQuick.Layouts
Rectangle {
    id:m
    property bool compact:false
    property bool expandable:false
    implicitHeight:compact ? 150 : 176
    radius:30;color:Theme.alpha(Theme.secondary,Theme.light ? .5 : .16);clip:true
    Image {anchors.fill:parent;source:Hub.status.art;fillMode:Image.PreserveAspectCrop;opacity:.13;visible:source!=="";asynchronous:true}
    MButton {visible:m.expandable;anchors.right:parent.right;anchors.top:parent.top;anchors.margins:6;implicitWidth:32;implicitHeight:32;compact:true;icon:"expand";tooltip:"Open sound & music";z:2;onClicked:Hub.openAudio(Hub.targetScreen)}
    RowLayout {anchors {fill:parent;margins:20}
spacing:18
        Item {Layout.preferredWidth:m.compact ? 80 : 110;Layout.preferredHeight:width
            Flower {id:disc;anchors.fill:parent;fill:Theme.secondary;lobes:10
                NumberAnimation on rotation {from:0;to:360;duration:45000;loops:Animation.Infinite;running:Hub.status.playing}
            }
            Rectangle {anchors.centerIn:parent;width:parent.width*.58;height:width;radius:width/2;color:Theme.base
                Glyph {anchors.centerIn:parent;name:"music";color:Theme.secondary;font.pixelSize:28}
            }
        }
        ColumnLayout {Layout.fillWidth:true;spacing:8
            MText {text:Hub.status.playing ? "NOW PLAYING" : "YOUR SOUNDTRACK";color:Theme.subtext;font.pixelSize:9;font.letterSpacing:1.8}
            MText {text:Hub.status.track||"A little music goes a long way.";Layout.fillWidth:true;maximumLineCount:2;wrapMode:Text.Wrap;font.pixelSize:m.compact ? 16 : 19;font.weight:Font.DemiBold}
            MText {text:Hub.status.artist||"Start playback in any MPRIS player";color:Theme.subtext;font.pixelSize:11;Layout.fillWidth:true}
            RowLayout {spacing:8
                MButton {icon:"previous";compact:true;enabled:Hub.status.track!=="";onClicked:Hub.media("previous")}
                MButton {icon:Hub.status.playing ? "pause" : "play";filled:true;accent:Theme.secondary;ink:"#23331d";implicitWidth:66;implicitHeight:42;enabled:Hub.status.track!=="";onClicked:Hub.media("play-pause")}
                MButton {icon:"skip";compact:true;enabled:Hub.status.track!=="";onClicked:Hub.media("next")}
            }
        }
    }
}
