import QtQuick
import QtQuick.Layouts

Surface {
    id:d
    property string displayName:Hub.dockScreen ? Hub.dockScreen.name : "External display"
    property bool phone:false
    property var sourcePhoneScreen:null
    property real connection:0
    implicitHeight:phone&&width<420 ? 374 : 290
    radius:32;translucency:Math.min(Hub.prefs.glass,.72)
    function replay(){connectAnimation.restart();}
    Component.onCompleted:replay()
    SequentialAnimation {id:connectAnimation
        PauseAnimation {duration:Theme.motion(100)}
        NumberAnimation {target:d;property:"connection";from:0;to:1;duration:Theme.motion(650);easing.type:Easing.OutCubic}
    }
    HoverHandler {onHoveredChanged:{if(hovered)Hub.pauseDockNotice();else Hub.resumeDockNotice();}}
    ColumnLayout {anchors.fill:parent;anchors.margins:20;spacing:12
        RowLayout {Layout.fillWidth:true
            MText {text:"DISPLAY CONNECTED";Layout.fillWidth:true;font.pixelSize:10;font.letterSpacing:1.5;color:Theme.primary}
            MButton {icon:"close";implicitWidth:36;implicitHeight:36;tooltip:"Dismiss docking welcome";onClicked:Hub.dockNotice=false}
        }
        RowLayout {Layout.fillWidth:true;spacing:14
            Item {Layout.preferredWidth:132;Layout.preferredHeight:92
                Rectangle {x:43+16*(1-d.connection);y:9;width:88;height:59;radius:12;color:Theme.alpha(Theme.primary,.12);border.width:2;border.color:Theme.primary;opacity:d.connection;scale:.8+.2*d.connection
                    Row {anchors.centerIn:parent;spacing:5
                        Repeater {model:3;Rectangle {required property int index;width:17;height:23+index*3;radius:5;color:Theme.alpha(Theme.primary,.4+index*.2)}}
                    }
                    Rectangle {anchors.top:parent.bottom;anchors.horizontalCenter:parent.horizontalCenter;width:4;height:9;color:Theme.primary}
                    Rectangle {anchors.top:parent.bottom;anchors.topMargin:9;anchors.horizontalCenter:parent.horizontalCenter;width:36;height:3;radius:1.5;color:Theme.primary}
                }
                Rectangle {x:4+20*(1-d.connection);y:22;width:34;height:62;radius:10;color:Theme.base;border.width:2;border.color:Theme.primary
                    Rectangle {anchors.horizontalCenter:parent.horizontalCenter;y:7;width:12;height:3;radius:1.5;color:Theme.primary}
                    Glyph {anchors.centerIn:parent;name:"apps";font.pixelSize:20;color:Theme.primary}
                    Rectangle {anchors.horizontalCenter:parent.horizontalCenter;anchors.bottom:parent.bottom;anchors.bottomMargin:6;width:12;height:2;radius:1;color:Theme.primary}
                }
                Row {x:45;y:82;spacing:5
                    Repeater {model:4;Rectangle {required property int index;width:4;height:4;radius:2;color:Theme.primary;opacity:Math.max(0,Math.min(1,(d.connection-.2-index*.12)*4))}}
                }
            }
            ColumnLayout {Layout.fillWidth:true;spacing:6
                MText {text:d.phone ? "Your phone.\nMore room." : "Room to do more.";Layout.fillWidth:true;wrapMode:Text.WordWrap;font.pixelSize:d.phone ? 23 : 25;font.weight:Font.DemiBold}
                MText {text:d.displayName;Layout.fillWidth:true;font.pixelSize:12;color:Theme.primary;maximumLineCount:2;wrapMode:Text.WrapAnywhere}
            }
        }
        MText {Layout.fillWidth:true;Layout.fillHeight:true;wrapMode:Text.WordWrap;verticalAlignment:Text.AlignVCenter;text:d.phone ? "Keep your touch home here. Give the monitor its own desktop—your apps stay where you left them." : "A bigger canvas, without losing your place. Choose a workspace for this screen; your existing windows stay put.";font.pixelSize:13;color:Theme.subtext}
        GridLayout {Layout.fillWidth:true;columns:d.phone&&d.width<420 ? 1 : 2;columnSpacing:8;rowSpacing:8
            MButton {Layout.fillWidth:true;filled:true;icon:"expand";text:d.phone ? "Use monitor" : "Open workspace";onClicked:Hub.useDockedWorkspace(d.sourcePhoneScreen)}
            MButton {Layout.fillWidth:true;text:"Layout options";tonal:true;onClicked:{Hub.targetScreen=d.phone ? d.sourcePhoneScreen||Hub.dockScreen : Hub.dockScreen;Hub.dockNotice=false;Hub.page="convergence";}}
        }
    }
}
