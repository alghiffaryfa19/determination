import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
Item {
    id:q
    property string tab:Hub.page==="notifications" ? "inbox" : "controls"
    property string confirm:""
    readonly property var bluetoothDevice:Hub.connectivity.bluetooth.items.find(d=>d.active)||null
    Component.onCompleted:if(tab==="controls")Hub.connection("bluetooth","refresh")
    Connections {target:Hub;function onPageChanged(){if(Hub.page==="notifications")q.tab="inbox";else if(Hub.page==="controls")q.tab="controls";}}
    ColumnLayout {visible:Hub.controlDetail==="";width:Math.min(560,q.width-(q.width<400 ? 32 : 48));anchors.horizontalCenter:parent.horizontalCenter;anchors.top:parent.top;anchors.bottom:parent.bottom;anchors.topMargin:q.width<400 ? 16 : 24;anchors.bottomMargin:q.width<400 ? 16 : 24
spacing:q.height<700 ? 10 : 16
        RowLayout {Layout.fillWidth:true
            ColumnLayout {Layout.fillWidth:true;spacing:4
                MText {text:Qt.formatDateTime(Hub.now,"ddd, d MMM");color:Theme.subtext;font.pixelSize:12}
                MText {text:Qt.formatDateTime(Hub.now,"HH:mm");font.pixelSize:48;font.weight:Font.Medium;font.letterSpacing:-2}
            }
            Item {Layout.fillWidth:true}
            MButton {icon:"palette";tonal:true;tooltip:"Personalize";onClicked:Hub.page="appearance"}
            MButton {icon:"close";tooltip:"Close shade";onClicked:Hub.close()}
        }
        Rectangle {Layout.fillWidth:true;height:48;radius:26;color:Theme.alpha(Theme.surface,.7)
            RowLayout {anchors {fill:parent;margins:4}
spacing:4
                MButton {Layout.fillWidth:true;implicitHeight:40;text:"Quick settings";icon:"settings";filled:q.tab==="controls";compact:true;onClicked:q.tab="controls"}
                MButton {Layout.fillWidth:true;implicitHeight:40;text:"Inbox"+(Hub.unread ? "  "+Hub.unread : "");icon:"bell";filled:q.tab==="inbox";compact:true;onClicked:q.tab="inbox"}
            }
        }
        Flickable {visible:q.tab==="controls";Layout.fillWidth:true;Layout.fillHeight:true;clip:true;contentHeight:controls.implicitHeight;boundsBehavior:Flickable.StopAtBounds
            ScrollBar.vertical:ScrollBar {}
            ColumnLayout {id:controls;width:parent.width;spacing:14
                ColumnLayout {Layout.fillWidth:true;spacing:0
                    RowLayout {Layout.fillWidth:true;spacing:8
                        ExpressiveSlider {Layout.fillWidth:true;icon:Hub.status.muted ? "mute" : "volume";value:Hub.status.volume;onMoved:Hub.volume(value)}
                        MButton {icon:Hub.status.muted ? "mute" : "volume";morph:true;checked:Hub.status.muted;filled:checked;tonal:!checked;tooltip:"Toggle mute";onClicked:Hub.command({action:"mute"})}
                    }
                    RowLayout {Layout.fillWidth:true;visible:Hub.status.brightness>=0;spacing:8
                        ExpressiveSlider {Layout.fillWidth:true;icon:"sun";value:Hub.status.brightness;onMoved:Hub.command({action:"brightness",value:Math.round(value)})}
                        MText {text:Hub.status.brightness+"%";color:Theme.subtext;font.pixelSize:12}
                    }
                }
                GridLayout {columns:2;Layout.fillWidth:true;columnSpacing:10;rowSpacing:10
                    ShadeTile {Layout.fillWidth:true;icon:Hub.status.wifi ? "wifi" : "wifiOff";title:"Internet";subtitle:Hub.status.wifi ? Hub.status.network : "Wi-Fi off";active:Hub.status.wifi;settings:true;onClicked:Hub.settings("network");onOpenSettings:Hub.settings("network")}
                    ShadeTile {Layout.fillWidth:true;icon:"bluetooth";title:"Bluetooth";subtitle:q.bluetoothDevice ? q.bluetoothDevice.name : Hub.status.bluetooth ? "On" : "Off";active:Hub.status.bluetooth;settings:true;onClicked:Hub.settings("bluetooth");onOpenSettings:Hub.settings("bluetooth")}
                    ShadeTile {Layout.fillWidth:true;icon:Hub.dnd ? "quiet" : "bell";title:"Do not disturb";subtitle:Hub.gameSession ? "Play session active" : Hub.dnd ? "Popups silenced" : "Notifications allowed";active:Hub.dnd;onClicked:{if(Hub.gameSession)Hub.toggleGameSession();else Hub.set("dnd",!Hub.dnd);}}
                    ShadeTile {Layout.fillWidth:true;icon:"coffee";title:"Keep awake";subtitle:Hub.gameSession ? "Play session active" : Hub.keepAwake ? "Idle inhibited" : "Rest when you do";active:Hub.keepAwake||Hub.gameSession;onClicked:{if(Hub.gameSession)Hub.toggleGameSession();else Hub.keepAwake=!Hub.keepAwake;}}
                }
                RowLayout {Layout.fillWidth:true;spacing:6
                    MButton {Layout.fillWidth:true;icon:Theme.light ? "sun" : "moon";text:Theme.light ? "Light" : "Dark";morph:true;checked:Theme.light;filled:checked;tonal:!checked;compact:true;onClicked:Hub.set("light",!Theme.light)}
                    MButton {Layout.fillWidth:true;icon:"capture";text:"Capture";tonal:true;compact:true;onClicked:Hub.screenShot()}
                    MButton {Layout.fillWidth:true;icon:"mute";text:Hub.status.micMuted ? "Mic off" : "Mic on";morph:true;checked:!!Hub.status.micMuted;filled:checked;tonal:!checked;compact:true;tooltip:"Toggle microphone mute";onClicked:Hub.command({action:"mic"})}
                }
                MediaCard {Layout.fillWidth:true;compact:true;expandable:true}
                FocusCard {Layout.fillWidth:true}
                ClipboardCard {Layout.fillWidth:true}
                RowLayout {Layout.fillWidth:true;visible:Hub.status.profile!=="";spacing:4
                    Repeater {model:[{id:"power-saver",text:"Saver",icon:"battery"},{id:"balanced",text:"Balanced",icon:"heart"},{id:"performance",text:"Boost",icon:"cpu"}]
                        MButton {required property var modelData;Layout.fillWidth:true;text:modelData.text;icon:modelData.icon;compact:true;morph:true;checked:Hub.status.profile===modelData.id;filled:checked;tonal:!checked;onClicked:Hub.command({action:"profile",value:modelData.id})}
                    }
                }
                MText {text:"CPU "+Hub.status.cpu+"%   ·   RAM "+Hub.status.memory+"%   ·   "+(Hub.status.battery>=0 ? Hub.status.battery+"% battery" : "Plugged in");color:Theme.muted;font.pixelSize:10;Layout.alignment:Qt.AlignHCenter}
            }
        }
        Loader {
            visible:q.tab==="inbox";active:visible;Layout.fillWidth:true;Layout.fillHeight:true
            sourceComponent:Component {NotificationCenter {}}
        }
        RowLayout {Layout.fillWidth:true;spacing:8
            MButton {icon:"convergence";text:"Convergence";compact:true;tonal:true;tooltip:"Choose how your shell adapts";onClicked:Hub.page="convergence"}
            Item {Layout.fillWidth:true}
            MButton {icon:"lock";compact:true;tooltip:"Lock device";onClicked:Hub.settings("lock")}
            MButton {icon:"power";filled:true;tooltip:"Power options";onClicked:q.confirm="menu"}
        }
    }
    Loader {anchors.fill:parent;anchors.margins:20;active:Hub.controlDetail!=="";visible:active;sourceComponent:Component {ConnectionPanel {kind:Hub.controlDetail||"wifi"}}}
    Rectangle {visible:q.confirm!=="";anchors.fill:parent;radius:36;color:Theme.alpha(Theme.base,.98)
        MouseArea {anchors.fill:parent}
        ColumnLayout {anchors {left:parent.left;right:parent.right;verticalCenter:parent.verticalCenter;margins:30}
spacing:16
            Flower {Layout.alignment:Qt.AlignHCenter;width:110;height:110;fill:Theme.tertiary;lobes:8;Glyph {anchors.centerIn:parent;name:"power";font.pixelSize:44;color:"#402431"}}
            MText {text:q.confirm==="menu" ? "Call it a day?" : q.confirm==="suspend" ? "Put your device to sleep?" : q.confirm==="reboot" ? "Restart your device?" : q.confirm==="logout" ? "Log out of your session?" : "Power off your device?";Layout.fillWidth:true;wrapMode:Text.Wrap;horizontalAlignment:Text.AlignHCenter;font.pixelSize:26;font.weight:Font.DemiBold}
            Repeater {model:q.confirm==="menu" ? [{id:"suspend",text:"Sleep",icon:"sleep"},{id:"logout",text:"Log out",icon:"logout"},{id:"reboot",text:"Restart",icon:"restart"},{id:"poweroff",text:"Power off",icon:"power"}] : []
                MButton {required property var modelData;Layout.fillWidth:true;tonal:true;text:modelData.text;icon:modelData.icon;onClicked:q.confirm=modelData.id}
            }
            MButton {visible:q.confirm!=="menu";Layout.fillWidth:true;filled:true;text:"Yes, continue";onClicked:{Hub.command({action:"power",verb:q.confirm});q.confirm="";Hub.close();}}
            MButton {Layout.fillWidth:true;text:"Not now";onClicked:q.confirm=""}
        }
    }
}
