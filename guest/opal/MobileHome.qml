import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id:mobile
    property bool embedded:false
    property bool reachable:false
    readonly property bool landscape:width>height
    readonly property bool wide:width>=720
    readonly property int columns:Math.max(3,Math.min(7,Math.floor((Math.min(width,1080)-32)/128)))
    property bool keyboardOpen:false
    property string filter:""
    property string appCategory:"All apps"
    property var results:Hub.searchApps(filter,filter ? "All apps" : appCategory)
    function openApps() {
        Hub.mobileTab="apps";
        if(embedded)Hub.page="launcher";
        else mobileSearch.forceActiveFocus();
    }
    function go(tab) {keyboardOpen=false;Hub.mobileTab=tab;if(embedded&&tab==="recent")Hub.page="launcher";}
    Connections {target:Hub;function onMobileTabChanged(){if(Hub.mobileTab!=="apps")mobile.keyboardOpen=false;tabArrival.restart();}}
    ColumnLayout {
        id:mobileBody
        property real arrival:1
        opacity:arrival;transform:Translate {y:12*(1-mobileBody.arrival)}
        NumberAnimation {id:tabArrival;target:mobileBody;property:"arrival";from:0;to:1;duration:Theme.motion(240);easing.type:Easing.OutCubic}
        width:Math.min(mobile.width-32,1080)
        anchors.horizontalCenter:parent.horizontalCenter;anchors.top:parent.top;anchors.bottom:parent.bottom;anchors.bottomMargin:16
        anchors.topMargin:mobile.reachable&&mobile.height>600 ? Math.min(150,mobile.height*.18) : 16
        spacing:12
        RowLayout {
            Layout.fillWidth:true
            MText {Layout.fillWidth:true;text:Hub.mobileTab==="home" ? "" : Hub.mobileTab==="apps" ? "Your apps" : "App switcher";font.pixelSize:26;font.weight:Font.DemiBold}
            MButton {icon:"convergence";implicitWidth:48;implicitHeight:48;tooltip:"Dock & displays";onClicked:Hub.page="convergence"}
            MButton {icon:"settings";implicitWidth:48;implicitHeight:48;tooltip:"Open Quick Settings";onClicked:Hub.page="controls"}
            MButton {visible:!mobile.embedded;icon:"close";implicitWidth:48;implicitHeight:48;tooltip:"Return to your app";onClicked:Hub.close()}
        }
        Flickable {
            id:home
            visible:Hub.mobileTab==="home"
            Layout.fillWidth:true;Layout.fillHeight:true
            contentHeight:homeBody.implicitHeight+16;clip:true;boundsBehavior:Flickable.StopAtBounds
            ScrollBar.vertical:ScrollBar {}
            GridLayout {
                id:homeBody;width:parent.width;columns:mobile.wide ? 2 : 1;uniformCellWidths:true;columnSpacing:32;rowSpacing:22
                Item {
                    Layout.fillWidth:true;Layout.preferredHeight:mobile.landscape ? 176 : Math.min(260,mobile.height*.30)
                    Layout.rowSpan:mobile.wide ? 2 : 1
                    Column {anchors.centerIn:parent;spacing:4
                        MText {anchors.horizontalCenter:parent.horizontalCenter;text:Qt.formatDateTime(Hub.now,"dddd, d MMMM");font.pixelSize:14;color:Theme.subtext}
                        MText {anchors.horizontalCenter:parent.horizontalCenter;text:Qt.formatDateTime(Hub.now,"HH:mm");font.pixelSize:mobile.wide ? 88 : 80;font.weight:Font.Medium;font.letterSpacing:-5}
                        MText {anchors.horizontalCenter:parent.horizontalCenter;text:Hub.focusRunning ? "Focus · "+Math.ceil(Hub.focusSeconds/60)+" min left" : "Make room for your day.";font.pixelSize:12;color:Theme.subtext}
                    }
                    MouseArea {anchors.fill:parent;onPressAndHold:Hub.page="appearance"}
                }
                MButton {Layout.fillWidth:true;implicitHeight:56;icon:"search";text:"Find an app";tonal:true;onClicked:mobile.openApps()}
                ColumnLayout {
                    Layout.fillWidth:true;spacing:12
                    RowLayout {Layout.fillWidth:true
                        MText {text:"Favorites";font.pixelSize:14;font.weight:Font.DemiBold;Layout.fillWidth:true;color:Theme.subtext}
                        MButton {text:"All apps";icon:"next";compact:true;onClicked:mobile.openApps()}
                    }
                    GridLayout {
                        Layout.fillWidth:true;columns:mobile.wide ? 4 : mobile.columns;rowSpacing:6;columnSpacing:6
                        Repeater {model:Hub.favoriteApps.slice(0,8)
                            AppTile {required property var modelData;required property int index;app:modelData;tintIndex:index;Layout.fillWidth:true;Layout.preferredHeight:108;showPin:false;bare:true;touch:true;onActivated:Hub.launch(app)}
                        }
                    }
                    MText {visible:Hub.favoriteApps.length===0;Layout.fillWidth:true;wrapMode:Text.Wrap;text:"Your favorites belong here. Long-press an app in All apps to pin it.";font.pixelSize:13;color:Theme.subtext}
                }
                Rectangle {
                    visible:Hub.status.track!=="";Layout.fillWidth:true;Layout.preferredHeight:76;radius:24;color:Theme.alpha(Theme.surfaceHigh,.42)
                    RowLayout {anchors.fill:parent;anchors.margins:14;spacing:12
                        Glyph {name:"music";color:Theme.primary}
                        ColumnLayout {Layout.fillWidth:true;spacing:4
                            MText {text:Hub.status.track;Layout.fillWidth:true;font.pixelSize:13;font.weight:Font.DemiBold}
                            MText {text:Hub.status.artist||"Now playing";Layout.fillWidth:true;font.pixelSize:11;color:Theme.subtext}
                        }
                        MButton {icon:Hub.status.playing ? "pause" : "play";tooltip:"Play / pause";onClicked:Hub.media("play-pause")}
                    }
                }
                ColumnLayout {
                    visible:Hub.windows.length>0;Layout.fillWidth:true;spacing:12
                    RowLayout {Layout.fillWidth:true
                        MText {text:"Pick up where you left off";Layout.fillWidth:true;font.pixelSize:14;font.weight:Font.DemiBold;color:Theme.subtext}
                        MButton {icon:"next";compact:true;tooltip:"App switcher";onClicked:mobile.go("recent")}
                    }
                    Repeater {model:Hub.windows.slice(0,2)
                        Rectangle {required property var modelData;Layout.fillWidth:true;Layout.preferredHeight:68;radius:20;color:Theme.alpha(Theme.surfaceHigh,.35)
                            RowLayout {anchors.fill:parent;anchors.margins:14;spacing:12
                                Image {Layout.preferredWidth:32;Layout.preferredHeight:32;source:Quickshell.iconPath((Hub.appForWindow(modelData)||{}).icon||"application-x-executable",true)}
                                ColumnLayout {Layout.fillWidth:true;spacing:4
                                    MText {Layout.fillWidth:true;text:modelData.title;font.pixelSize:13}
                                    MText {Layout.fillWidth:true;text:modelData.className;font.pixelSize:10;color:Theme.subtext}
                                }
                            }
                            MouseArea {anchors.fill:parent;onClicked:Hub.focusWindow(modelData)}
                        }
                    }
                }
            }
        }
        ColumnLayout {
            visible:Hub.mobileTab==="apps";Layout.fillWidth:true;Layout.fillHeight:true;spacing:12
            TextField {
                id:mobileSearch;Layout.fillWidth:true;Layout.preferredHeight:54
                placeholderText:"Search your apps";font.family:Theme.font;font.pixelSize:16;leftPadding:20
                color:Theme.text;placeholderTextColor:Theme.muted;selectByMouse:true
                background:Rectangle {radius:27;color:Theme.alpha(Theme.surfaceHigh,.65)}
                onTextEdited:mobile.filter=text
                onActiveFocusChanged:if(activeFocus){if(mobile.embedded){Hub.mobileTab="apps";Hub.page="launcher";}else mobile.keyboardOpen=true;}
                onAccepted:if(mobile.results.length)Hub.launch(mobile.results[0])
            }
            Flickable {Layout.fillWidth:true;Layout.preferredHeight:42;contentWidth:appFilters.width;clip:true;flickableDirection:Flickable.HorizontalFlick
                Row {id:appFilters;spacing:6
                    Repeater {model:["All apps","Pinned","Games","Create","Work","Internet","System"]
                        MButton {required property string modelData;text:modelData;compact:true;filled:mobile.appCategory===modelData;onClicked:mobile.appCategory=modelData}
                    }
                }
            }
            GridView {
                Layout.fillWidth:true;Layout.fillHeight:true;clip:true
                model:mobile.results;cellWidth:width/mobile.columns;cellHeight:mobile.wide ? 144 : 128
                boundsBehavior:Flickable.StopAtBounds
                delegate:Item {
                    required property var modelData;required property int index
                    width:GridView.view.cellWidth;height:GridView.view.cellHeight
                    AppTile {anchors.fill:parent;anchors.margins:4;app:modelData;tintIndex:index;showPin:false;bare:true;touch:true;onActivated:Hub.launch(app)}
                }
                ScrollBar.vertical:ScrollBar {}
                MText {anchors.centerIn:parent;visible:mobile.results.length===0;text:"No apps match that search.";color:Theme.subtext}
            }
        }
        WindowSwitcher {visible:Hub.mobileTab==="recent";Layout.fillWidth:true;Layout.fillHeight:true;layoutMode:"phone";active:visible&&!mobile.embedded}
        SearchKeyboard {
            visible:Hub.mobileTab==="apps"&&mobile.keyboardOpen
            Layout.fillWidth:true;Layout.preferredHeight:Math.min(244,mobile.height*.42)
            onInsert:text=>{mobile.filter+=text;mobileSearch.text=mobile.filter;}
            onErase:{mobile.filter=mobile.filter.slice(0,-1);mobileSearch.text=mobile.filter;}
            onAccept:{mobile.keyboardOpen=false;mobileSearch.focus=false;}
            onDismiss:{mobile.keyboardOpen=false;mobileSearch.focus=false;}
        }
        Rectangle {
            Layout.fillWidth:true;Layout.preferredHeight:56;radius:28;color:Theme.alpha(Theme.surface,.50)
            RowLayout {anchors.fill:parent;anchors.margins:4;spacing:4
                Repeater {model:[{id:"home",icon:"home",name:"Home"},{id:"apps",icon:"apps",name:"Apps"},{id:"recent",icon:"desktop",name:"Recent"}]
                    MButton {required property var modelData;Layout.fillWidth:true;implicitHeight:48;icon:modelData.icon;text:mobile.width>390 ? modelData.name : "";filled:Hub.mobileTab===modelData.id;tooltip:modelData.name;onClicked:mobile.go(modelData.id)}
                }
                MButton {visible:!mobile.wide;icon:"phone";compact:true;implicitWidth:44;tooltip:mobile.reachable ? "Full height" : "One-handed reach";tonal:mobile.reachable;onClicked:mobile.reachable=!mobile.reachable}
            }
        }
    }
}
