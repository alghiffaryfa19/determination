import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id:a
    property bool showVolume:false
    property bool allowExpand:true
    readonly property bool hasTrack:Hub.status.track!==""
    readonly property bool hasArt:art.status===Image.Ready
    readonly property color ink:hasArt ? "#ffffff" : Theme.text
    implicitHeight:showVolume ? 260 : 180
    radius:28;color:Theme.alpha(Theme.surfaceHigh,.38)
    // Artwork is inset so it never paints over the rounded outer corners.
    Rectangle {id:cover;anchors.left:parent.left;anchors.right:parent.right;anchors.top:parent.top;anchors.margins:8;height:a.showVolume ? parent.height-78 : parent.height-16;radius:22;color:Theme.alpha(Theme.base,.7);clip:true
        Image {id:art;anchors.fill:parent;anchors.margins:8;source:Hub.status.art||"";asynchronous:true;fillMode:Image.PreserveAspectCrop;sourceSize.width:600;sourceSize.height:320;opacity:.48}
        Rectangle {anchors.fill:parent;radius:22;gradient:Gradient {GradientStop {position:0;color:Theme.alpha("#000000",a.hasArt ? .08 : 0)}GradientStop {position:1;color:Theme.alpha("#000000",a.hasArt ? .72 : 0)}}}
        ColumnLayout {anchors.fill:parent;anchors.margins:12;spacing:8
            RowLayout {Layout.fillWidth:true
                Glyph {name:"music";font.pixelSize:16;color:a.ink}
                MText {text:Hub.status.playing ? "Now playing" : a.hasTrack ? "Paused" : "Your soundtrack";font.pixelSize:10;color:a.ink;Layout.fillWidth:true}
                MButton {visible:a.allowExpand;icon:"expand";implicitWidth:32;implicitHeight:32;compact:true;ink:a.ink;tooltip:"Open sound & music";onClicked:Hub.openAudio(Hub.targetScreen)}
            }
            RowLayout {Layout.fillWidth:true;spacing:12
                ColumnLayout {Layout.fillWidth:true;spacing:4
                    MText {text:Hub.status.track||"A little music goes a long way.";Layout.fillWidth:true;wrapMode:Text.WordWrap;maximumLineCount:2;font.pixelSize:16;font.weight:Font.DemiBold;color:a.ink}
                    MText {text:Hub.status.artist||(a.hasTrack ? "Media player" : "Start playback in an MPRIS player");Layout.fillWidth:true;font.pixelSize:11;color:a.hasArt ? "#dddddd" : Theme.subtext}
                }
                MButton {icon:Hub.status.playing ? "pause" : "play";implicitWidth:62;implicitHeight:44;morph:true;checked:Hub.status.playing;filled:true;enabled:a.hasTrack;tooltip:"Play / pause";onClicked:Hub.media("play-pause")}
            }
            RowLayout {Layout.fillWidth:true;spacing:10
                MButton {icon:"previous";implicitWidth:38;implicitHeight:32;compact:true;ink:a.ink;enabled:a.hasTrack;tooltip:"Previous track";onClicked:Hub.media("previous")}
                MText {Layout.fillWidth:true;text:Hub.status.audioOutput||"Media controls";font.pixelSize:10;color:a.hasArt ? "#dddddd" : Theme.subtext}
                MButton {icon:"skip";implicitWidth:38;implicitHeight:32;compact:true;ink:a.ink;enabled:a.hasTrack;tooltip:"Next track";onClicked:Hub.media("next")}
            }
        }
    }
    RowLayout {visible:a.showVolume;anchors.left:parent.left;anchors.right:parent.right;anchors.bottom:parent.bottom;anchors.margins:12;spacing:8
        MButton {icon:Hub.status.muted ? "mute" : "volume";implicitWidth:42;implicitHeight:42;morph:true;checked:Hub.status.muted;filled:checked;tonal:!checked;tooltip:"Toggle mute";onClicked:Hub.command({action:"mute"})}
        ExpressiveSlider {Layout.fillWidth:true;wheelEnabled:false;value:Hub.status.volume;icon:"volume";onMoved:Hub.volume(value)}
        MText {text:Hub.status.volume+"%";font.pixelSize:12;color:Theme.subtext}
    }
}
