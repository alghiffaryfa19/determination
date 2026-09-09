import QtQuick
import QtQuick.Layouts
Item {
    id:w
    property bool showWidgets:Hub.prefs.desktopWidgets!==false
    property string imagePath:Hub.prefs.wallpaperPath||""
    property int composition:Hub.prefs.wallpaper||0
    property string fit:Hub.prefs.wallpaperFit||"crop"
    property real dim:Hub.prefs.wallpaperDim||0
    readonly property bool custom:!!imagePath
    readonly property bool imageReady:!custom||photo.status===Image.Ready
    clip:true
    Rectangle {anchors.fill:parent;color:Theme.base
        gradient:Gradient {GradientStop {position:0;color:Theme.light ? Theme.palette.light : "#13111b"}GradientStop {position:.6;color:Theme.light ? Theme.palette.light : Theme.palette.dark}GradientStop {position:1;color:Theme.light ? Theme.alpha(Theme.primary,.3) : Theme.alpha(Theme.palette.seed,.28)}}
    }
    Item {anchors.fill:parent;visible:!w.custom&&w.composition===0
        Flower {width:Math.max(w.width*.68,w.height*.95);height:width;x:w.width*.43;y:-height*.34;lobes:10;depth:.09;fill:Theme.alpha(Theme.primary,Theme.light ? .33 : .16);rotation:13}
        Flower {width:w.height*.84;height:width;x:w.width*.48;y:w.height*.31;lobes:6;depth:.13;fill:Theme.alpha(Theme.secondary,Theme.light ? .58 : .21);rotation:-16}
        Rectangle {width:w.width*.44;height:w.height*.5;radius:height/2;x:-width*.2;y:w.height*.62;rotation:-28;color:Theme.alpha(Theme.tertiary,Theme.light ? .55 : .24)}
        Rectangle {width:w.height*.36;height:width;radius:width/2;x:w.width*.71;y:w.height*.13;color:Theme.alpha(Theme.tertiary,Theme.light ? .65 : .32)}
        Flower {width:w.height*.3;height:width;x:w.width*.81;y:w.height*.71;lobes:8;fill:Theme.alpha(Theme.primary,Theme.light ? .8 : .38);rotation:18}
    }
    Item {anchors.fill:parent;visible:!w.custom&&w.composition===1
        Repeater {model:6
            Rectangle {required property int index;width:w.width*(.45+index*.12);height:width;radius:width/2;x:w.width*.56-width/2;y:w.height*.55-height/2;color:"transparent";border.width:30+index*9;border.color:Theme.alpha([Theme.primary,Theme.secondary,Theme.tertiary][index%3],Theme.light ? .45 : .10+index*.025);rotation:20}
        }
        Flower {width:220;height:220;x:w.width*.16;y:w.height*.15;fill:Theme.primary;lobes:12;opacity:.6}
    }
    Item {anchors.fill:parent;visible:!w.custom&&w.composition===2
        Repeater {model:12
            Rectangle {required property int index;width:w.width/4.4;height:w.height/2.6;radius:index%2===0 ? width/2 : 45;rotation:index%2===0 ? 14 : -14;x:(index%4)*w.width/3.6-w.width*.08;y:Math.floor(index/4)*w.height/2.7-40;color:Theme.alpha([Theme.primary,Theme.secondary,Theme.tertiary][index%3],Theme.light ? .4 : .18)}
        }
    }
    Item {anchors.fill:parent;visible:!w.custom&&w.composition===3
        Rectangle {width:w.width*.9;height:w.height*.12;radius:height/2;x:w.width*.35;y:w.height*.62;rotation:-32;color:Theme.alpha(Theme.primary,Theme.light ? .35 : .09)}
        Rectangle {width:w.width*.8;height:w.height*.12;radius:height/2;x:w.width*.31;y:w.height*.82;rotation:-32;color:Theme.alpha(Theme.secondary,Theme.light ? .4 : .13)}
    }
    Image {id:photo;anchors.fill:parent;visible:w.custom;source:w.imagePath;fillMode:w.fit==="fit" ? Image.PreserveAspectFit : Image.PreserveAspectCrop;asynchronous:true;autoTransform:true;sourceSize.width:Math.max(1,w.width);sourceSize.height:Math.max(1,w.height)}
    Rectangle {anchors.fill:parent;visible:w.custom;color:Theme.alpha("#000000",w.dim)}
    MText {visible:w.custom&&photo.status===Image.Error;anchors.centerIn:parent;text:"Wallpaper unavailable · choose another image in Appearance";color:Theme.text}
    Column {
        visible:w.showWidgets;x:w.width*.085;y:Math.max(76,w.height*.19);width:Math.min(330,w.width-60);spacing:20
        Column {spacing:-34
            MText {text:Qt.formatDateTime(Hub.now,"HH");font.pixelSize:Math.min(172,w.height*.22);font.weight:Font.Black;font.letterSpacing:-12;color:Theme.primary;style:w.custom ? Text.Outline : Text.Normal;styleColor:Theme.alpha(Theme.base,.2)}
            MText {text:Qt.formatDateTime(Hub.now,"mm");font.pixelSize:Math.min(172,w.height*.22);font.weight:Font.Black;font.letterSpacing:-12;color:Theme.primary;style:w.custom ? Text.Outline : Text.Normal;styleColor:Theme.alpha(Theme.base,.2)}
        }
        Surface {width:dateLabel.implicitWidth+40;height:46;radius:23
            MText {id:dateLabel;anchors.centerIn:parent;text:Qt.formatDateTime(Hub.now,"dddd, MMM d");font.pixelSize:16;font.weight:Font.Medium}
            MouseArea {anchors.fill:parent;onClicked:Hub.openSection("widgets")}
        }
        Surface {visible:Hub.focusRunning;width:220;height:50;radius:25
            MButton {anchors.fill:parent;icon:"timer";text:Math.ceil(Hub.focusSeconds/60)+" min · Pause focus";onClicked:Hub.timerToggle()}
        }
        MediaCard {visible:Hub.status.track!==""&&w.height>850;width:parent.width;compact:true}
    }
}
