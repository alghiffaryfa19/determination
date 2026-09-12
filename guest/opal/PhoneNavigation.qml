import QtQuick
import QtQuick.Layouts
import Quickshell.Io

Item {
    id:nav
    property var output:null
    Process {
        id:keyboard
        command:["/usr/local/bin/aurora-osk","toggle"]
        onExited:(code,status)=>{if(code!==0)Hub.toast="Keyboard unavailable; check Squeekboard is running.";}
    }
    implicitHeight:Hub.prefs.phoneButtons ? 64 : 48
    function go(tab) {if(output)Hub.targetScreen=output;Hub.mobileTab=tab;Hub.page="launcher";}
    function back() {if(Hub.page==="launcher"&&Hub.mobileTab!=="home")go("home");else Hub.close();}
    Rectangle {anchors.fill:parent;color:Theme.alpha(Theme.base,.92)}
    Rectangle {width:parent.width;height:1;color:Theme.outline}
    RowLayout {
        visible:!!Hub.prefs.phoneButtons;anchors.centerIn:parent;width:Math.min(parent.width-24,480);spacing:8
        MButton {Layout.fillWidth:true;icon:"back";tooltip:"Back within Opal · does not send app keystrokes";onClicked:nav.back()}
        MButton {Layout.fillWidth:true;icon:"home";tonal:Hub.page==="launcher"&&Hub.mobileTab==="home";tooltip:"Home · hold for apps";onClicked:nav.go("home");menuEntries:[{text:"All apps",icon:"apps",run:()=>nav.go("apps")},{text:"Search",icon:"search",run:()=>{nav.go("apps");}}]}
        MButton {Layout.fillWidth:true;icon:"desktop";tonal:Hub.page==="launcher"&&Hub.mobileTab==="recent";tooltip:"Recent apps";onClicked:nav.go("recent")}
        MButton {Layout.preferredWidth:48;icon:"keyboard";tooltip:"Show / hide keyboard";onClicked:keyboard.running=true}
    }
    RowLayout {
        visible:!Hub.prefs.phoneButtons;anchors.centerIn:parent;width:Math.min(parent.width-24,480);spacing:12
        MButton {icon:"back";compact:true;tooltip:"Back within Opal";onClicked:nav.back()}
        Item {
            Layout.fillWidth:true;Layout.preferredHeight:48
            Column {anchors.centerIn:parent;spacing:5
                Rectangle {anchors.horizontalCenter:parent.horizontalCenter;width:96;height:4;radius:2;color:gesture.pressed ? Theme.primary : Theme.subtext}
                MText {text:"Home · slide for recents";font.pixelSize:10;color:Theme.muted}
            }
            MouseArea {id:gesture;anchors.fill:parent;property real startX:0;property bool held:false
                onPressed:e=>{startX=e.x;held=false;}
                onReleased:e=>{if(!held)nav.go(Math.abs(e.x-startX)>40 ? "recent" : "home");}
                onPressAndHold:{held=true;nav.go("recent");}
                onCanceled:held=true
            }
        }
        MButton {icon:"keyboard";compact:true;implicitWidth:48;implicitHeight:48;tooltip:"Show / hide keyboard";onClicked:keyboard.running=true}
        MButton {icon:"apps";compact:true;tooltip:"All apps";onClicked:nav.go("apps")}
    }
}
