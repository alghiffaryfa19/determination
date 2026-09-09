import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.SystemTray

ShellRoot {
    id:root
    Component.onCompleted:Quickshell.watchFiles=false
    function show(page) {Hub.targetScreen=Hub.chooseScreen();Hub.toggle(page);}
    IpcHandler {
        target:"opal"
        function launcher():void {Hub.launcherSection="apps";root.show("launcher");}
        function clipboard():void {Hub.targetScreen=Hub.chooseScreen();Hub.toggleClipboard();}
        function controls():void {root.show("controls");}
        function audio():void {Hub.toggleAudio(Hub.chooseScreen());}
        function notifications():void {root.show("notifications");}
        function phone():void {Hub.targetScreen=Hub.chooseScreen();Hub.mode("phone");}
        function gaming():void {Hub.mode("console");}
        function desktop():void {Hub.mode("desktop");}
        function adaptive():void {Hub.mode("auto");}
        function appearance():void {root.show("appearance");}
        function convergence():void {root.show("convergence");}
        function close():void {Hub.close();}
        function navigate(key:string):void {Hub.navigate(key);}
        function search(text:string):void {Hub.targetScreen=Hub.chooseScreen();Hub.openSection("apps");Hub.query=text;if(text.startsWith("="))Hub.command({action:"calculate",text:text.slice(1).trim()});}
        function inspect():string {return JSON.stringify({page:Hub.page,mode:Hub.prefs.mode,apps:Hub.apps.length,query:Hub.query,controller:Hub.controller,notifications:Hub.unread,gameSession:Hub.gameSession,status:Hub.status});}
    }
    Variants {
        model:Quickshell.screens
        delegate:Scope {
            id:output
            required property var modelData
            readonly property string layoutMode:Hub.layoutFor(modelData.width,modelData.height,modelData.name)
            function show(page) {Hub.targetScreen=modelData;Hub.toggle(page);}
            PanelWindow {
                id:desktop
                screen:output.modelData
                anchors {top:true;bottom:true;left:true;right:true}
                exclusionMode:ExclusionMode.Ignore
                WlrLayershell.layer:WlrLayer.Background
                WlrLayershell.namespace:"opal-wallpaper"
                WlrLayershell.keyboardFocus:WlrKeyboardFocus.None
                color:Theme.base
                IdleInhibitor {window:desktop;enabled:Hub.keepAwake||Hub.gameSession}
                Wallpaper {anchors.fill:parent;showWidgets:output.layoutMode==="desktop"&&Hub.prefs.desktopWidgets!==false}
                // Non-exclusive homes live behind applications. Only the explicit overlay takes keys.
                Loader {
                    anchors {fill:parent;topMargin:Hub.prefs.mode==="console" ? 0 : 56;bottomMargin:Hub.prefs.mode==="console" ? 0 : output.layoutMode==="phone" ? (Hub.prefs.phoneButtons ? 64 : 48) : 84}
                    active:output.layoutMode!=="desktop"&&Hub.page===""
                    sourceComponent:output.layoutMode==="phone" ? phoneHome : gameHome
                }
                Component {id:phoneHome;MobileHome {embedded:true}}
                Component {id:gameHome;ConsoleHome {embedded:true}}
                OpalMenu {id:desktopMenu;entries:[
                    {text:"Applications",icon:"apps",run:()=>{Hub.launcherSection="apps";output.show("launcher");}},
                    {text:"Personalize desktop",icon:"palette",run:()=>output.show("appearance")},
                    {text:Theme.light ? "Dark appearance" : "Light appearance",icon:"moon",run:()=>Hub.set("light",!Theme.light)},
                    {text:"Taskbar options",icon:"settings",run:()=>output.show("appearance")}
                ]}
                MouseArea {anchors.fill:parent;acceptedButtons:Qt.RightButton;onClicked:e=>{Hub.targetScreen=output.modelData;desktopMenu.popup(e.x,e.y);}}
            }
            PanelWindow {
                id:statusbar
                screen:output.modelData
                visible:Hub.prefs.mode!=="console"
                anchors {top:true;left:true;right:true}
                implicitHeight:output.layoutMode==="phone" ? 48 : 44
                exclusiveZone:Hub.prefs.mode==="console" ? 0 : implicitHeight
                WlrLayershell.namespace:"opal-bar"
                color:Theme.alpha(Theme.base,.48)
                Rectangle {anchors.bottom:parent.bottom;width:parent.width;height:1;color:Theme.outline}
                PhoneStatus {visible:output.layoutMode==="phone";anchors.fill:parent;output:statusbar.screen}
                RowLayout {
                    visible:output.layoutMode!=="phone"
                    anchors {left:parent.left;verticalCenter:parent.verticalCenter;leftMargin:8}
                    spacing:6
                    MButton {visible:output.layoutMode!=="phone";icon:"apps";compact:true;implicitWidth:32;implicitHeight:30;tooltip:"All apps";menuEntries:Hub.taskbarMenu();onClicked:{Hub.launcherSection="apps";output.show("launcher");}}
                    MText {text:Qt.formatDateTime(Hub.now,statusbar.width<700 ? "HH:mm" : "HH:mm   ddd, d MMM");font.pixelSize:12;font.weight:Font.DemiBold}
                    MButton {visible:statusbar.width>1300&&output.layoutMode==="desktop";text:Hub.status.title.substring(0,36);compact:true;implicitHeight:30;ink:Theme.subtext;tooltip:"Running windows";onClicked:{Hub.targetScreen=output.modelData;Hub.openSection("windows");}}
                }
                Rectangle {
                    visible:statusbar.width>800&&Hub.status.hypr&&output.layoutMode!=="phone"
                    anchors.centerIn:parent
                    width:workspaces.implicitWidth+16;height:32;radius:16;color:Theme.alpha(Theme.surfaceHigh,.65)
                    Row {
                        id:workspaces;anchors.centerIn:parent;spacing:4
                        Repeater {
                            model:Math.min(12,Math.max(5,Hub.status.workspace))
                            Rectangle {
                                id:ws
                                required property int index
                                property bool current:Hub.status.workspace===index+1
                                width:current ? 32 : 24;height:24;radius:12
                                color:current ? Theme.primary : Hub.status.workspaces.indexOf(index+1)>=0 ? Theme.alpha(Theme.primary,.3) : "transparent"
                                Behavior on width {NumberAnimation {duration:120;easing.type:Easing.OutCubic}}
                                MText {anchors.centerIn:parent;text:String(index+1);font.pixelSize:ws.current ? 10 : 15;color:ws.current ? Theme.onPrimary : Theme.muted}
                                OpalMenu {id:workspaceMenu;entries:[{text:"Switch to workspace "+(ws.index+1),icon:"desktop",run:()=>Hub.workspace(ws.index+1)},
                                    {text:"Show running windows",icon:"list",run:()=>{Hub.targetScreen=output.modelData;Hub.openSection("windows");}}]}
                                MouseArea {anchors.fill:parent
acceptedButtons:Qt.LeftButton|Qt.RightButton;onClicked:e=>{if(e.button===Qt.RightButton)workspaceMenu.popup(e.x,e.y);else Hub.workspace(ws.index+1);}}
                            }
                        }
                    }
                }
                RowLayout {
                    visible:output.layoutMode!=="phone"
                    anchors {right:parent.right;verticalCenter:parent.verticalCenter;rightMargin:8}
                    spacing:2
                    MButton {visible:Hub.focusRunning&&statusbar.width>1300;icon:"timer";text:Math.floor(Hub.focusSeconds/60)+":"+(Hub.focusSeconds%60).toString().padStart(2,"0");filled:true;compact:true;implicitHeight:28;onClicked:output.show("controls")}
                    MButton {visible:Hub.status.track!==""&&statusbar.width>1600;icon:Hub.status.playing ? "music" : "pause";text:Hub.status.track.substring(0,20);compact:true;implicitHeight:30;tooltip:"Sound & music · scroll for volume";scrollable:true;onScrolled:steps=>Hub.audioScroll(steps,output.modelData);onClicked:Hub.toggleAudio(output.modelData);menuEntries:[{text:"Previous track",icon:"previous",run:()=>Hub.media("previous")},{text:"Next track",icon:"skip",run:()=>Hub.media("next")}]}
                    Repeater {
                        model:statusbar.width>600 ? SystemTray.items : null
                        Item {required property var modelData;width:24;height:30
                            Image {anchors.centerIn:parent;width:16;height:16;source:modelData.icon}
                            MouseArea {anchors.fill:parent;acceptedButtons:Qt.LeftButton|Qt.RightButton;onClicked:e=>{if(e.button===Qt.RightButton&&modelData.hasMenu)modelData.display(statusbar,statusbar.width-40,30);else modelData.activate();}}
                        }
                    }
                    MButton {icon:Hub.dnd ? "quiet" : "bell";text:Hub.unread ? String(Hub.unread) : "";compact:true;implicitHeight:30;implicitWidth:Hub.unread ? 48 : 30;tooltip:"Notifications";onClicked:output.show("notifications");menuEntries:[{text:Hub.dnd ? "Allow notifications" : "Do not disturb",icon:"quiet",run:()=>Hub.set("dnd",!Hub.dnd)}]}
                    MButton {icon:Hub.status.wifi ? "wifi" : "wifiOff";compact:true;implicitWidth:30;implicitHeight:30;tooltip:Hub.status.network;onClicked:output.show("controls");menuEntries:[{text:"Network settings",icon:"wifi",run:()=>Hub.settings("network")}]}
                    MButton {icon:Hub.status.muted ? "mute" : "volume";compact:true;implicitWidth:30;implicitHeight:30;tooltip:"Sound & music · "+Hub.status.volume+"% · scroll to adjust";scrollable:true;onScrolled:steps=>Hub.audioScroll(steps,output.modelData);onClicked:Hub.toggleAudio(output.modelData);menuEntries:[{text:"Toggle mute",icon:"mute",run:()=>Hub.command({action:"mute"})},{text:"Audio mixer",icon:"volume",run:()=>Hub.settings("audio")}]}
                    MButton {visible:Hub.status.battery>=0;icon:Hub.status.charging ? "charging" : "battery";text:Hub.status.battery+"%";compact:true;implicitHeight:30;onClicked:output.show("controls")}
                    MButton {icon:"settings";compact:true;implicitWidth:30;implicitHeight:30;onClicked:output.show("controls")}
                }
            }
            Taskbar {screen:output.modelData}
            PanelWindow {
                screen:output.modelData
                visible:(Hub.toast!==""||Hub.osd!=="")&&Hub.page===""&&!Hub.audioOpen
                anchors {bottom:true;right:true}
                margins {bottom:90;right:12}
                implicitWidth:Math.min(390,output.modelData.width-24);implicitHeight:Hub.toast!=="" ? 100 : 60
                exclusionMode:ExclusionMode.Ignore
                WlrLayershell.namespace:"opal-toast"
                color:"transparent"
                Surface {
                    anchors.fill:parent;radius:30
                    RowLayout {anchors {fill:parent;margins:18} spacing:12
                        Glyph {name:Hub.toast!=="" ? "bell" : "volume";color:Theme.primary}
                        MText {text:Hub.toast||Hub.osd;Layout.fillWidth:true;font.pixelSize:13;maximumLineCount:4;wrapMode:Text.Wrap}
                    }
                    MouseArea {anchors.fill:parent;onClicked:{Hub.toast="";Hub.osd="";}}
                }
            }
        }
    }
    AudioDrawer {}
    ShadeWindow {}
    DockWelcomeWindow {}
    PanelWindow {
        id:notificationPopups
        screen:Notifier.popupScreen || Quickshell.screens[0]
        visible:Notifier.popups.length>0 && Hub.page===""&&!Hub.audioOpen
        anchors {top:true;right:true}
        margins {top:64;right:12}
        implicitWidth:Math.min(390,screen ? screen.width-24 : 390)
        implicitHeight:Math.min(popupColumn.implicitHeight,screen ? screen.height-110 : 700)
        exclusionMode:ExclusionMode.Ignore
        WlrLayershell.layer:WlrLayer.Overlay
        WlrLayershell.namespace:"opal-toast"
        WlrLayershell.keyboardFocus:WlrKeyboardFocus.None
        color:"transparent"
        Flickable {
            anchors.fill:parent;contentHeight:popupColumn.implicitHeight;clip:true;boundsBehavior:Flickable.StopAtBounds
            Column {id:popupColumn;width:parent.width;spacing:10
                Repeater {model:Notifier.popups;NotificationCard {required property var modelData;entry:modelData;popup:true;width:popupColumn.width}}
            }
        }
    }
    PanelWindow {
        id:overlay
        screen:Hub.targetScreen || Quickshell.screens[0]
        visible:Hub.page!==""&&Hub.page!=="controls"&&Hub.page!=="notifications"
        readonly property string layoutMode:Hub.layoutFor(width,height,screen ? screen.name : "")
        anchors {top:true;bottom:true;left:true;right:true}
        exclusionMode:ExclusionMode.Ignore
        WlrLayershell.layer:WlrLayer.Overlay
        WlrLayershell.namespace:"opal-overlay"
        WlrLayershell.keyboardFocus:visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        // Frosted summon: strong backdrop blur from the compositor, low dim so
        // the desktop behind stays visible for terminal use.
        color:Theme.alpha(Theme.base,.12)
        MouseArea {anchors.fill:parent;onClicked:Hub.close()}
        Surface {
            id:panel
            property real arrival:1
            opacity:arrival
            scale:.965+.035*arrival
            transform:Translate {y:(1-panel.arrival)*24}
            Connections {target:overlay;function onVisibleChanged(){if(overlay.visible)panelArrival.restart();}}
            NumberAnimation {id:panelArrival;target:panel;property:"arrival";from:0;to:1;duration:Theme.motion(360);easing.type:Easing.OutCubic}
            readonly property bool phone:overlay.layoutMode==="phone"
            readonly property bool game:overlay.layoutMode==="console"
            readonly property bool launcher:Hub.page==="launcher"
            width:phone||game&&launcher ? overlay.width : Math.min(overlay.width-24,launcher ? 960 : Hub.page==="windows" ? 1100 : Hub.page==="convergence"||Hub.page==="wallpaper" ? 800 : Hub.page==="appearance" ? 660 : 490)
            height:phone||game&&launcher ? overlay.height : Math.min(overlay.height-88,launcher ? 740 : Hub.page==="clipboard" ? 650 : 860)
            x:phone||game&&launcher ? 0 : launcher||Hub.page==="appearance"||Hub.page==="convergence"||Hub.page==="wallpaper" ? (overlay.width-width)/2 : overlay.width-width-12
            y:phone||game&&launcher ? 0 : launcher ? Math.max(60,(overlay.height-height)/2) : 62
            radius:phone||game&&launcher ? 0 : 36
            translucency:phone&&launcher ? Math.min(.35,Hub.prefs.glass) : Hub.prefs.glass
            MouseArea {anchors.fill:parent}
            Loader {
                id:overlayContent
                anchors.fill:parent;anchors.topMargin:panel.phone ? 48 : 0;anchors.bottomMargin:panel.phone ? (Hub.prefs.phoneButtons ? 64 : 48) : 0;active:overlay.visible
                onLoaded:contentArrival.restart()
                NumberAnimation {id:contentArrival;target:overlayContent;property:"opacity";from:0;to:1;duration:Theme.motion(180)}
                sourceComponent:Hub.page==="launcher" ? (panel.phone ? mobileComponent : panel.game ? consoleComponent : launcherComponent) : Hub.page==="clipboard" ? clipboardComponent : Hub.page==="appearance" ? appearanceComponent : Hub.page==="convergence" ? convergenceComponent : Hub.page==="wallpaper" ? wallpaperComponent : Hub.page==="windows" ? windowsComponent : controlsComponent
            }
            PhoneStatus {visible:panel.phone;anchors.top:parent.top;width:parent.width;height:48;output:overlay.screen}
            PhoneNavigation {visible:panel.phone;anchors.bottom:parent.bottom;width:parent.width;height:implicitHeight;output:overlay.screen}
            Rectangle {visible:Hub.toast!=="";anchors {bottom:parent.bottom;left:parent.left;right:parent.right;margins:12} height:72;radius:24;color:Theme.surfaceHigh;z:5
                MText {anchors {fill:parent;margins:14} text:Hub.toast;font.pixelSize:12;wrapMode:Text.Wrap;maximumLineCount:3;verticalAlignment:Text.AlignVCenter}
                MouseArea {anchors.fill:parent;onClicked:Hub.toast=""}
            }
        }
        Component {id:windowsComponent;ColumnLayout {anchors.fill:parent;anchors.margins:24;spacing:16
            RowLayout {Layout.fillWidth:true;MText {text:"App switcher";font.pixelSize:28;Layout.fillWidth:true}MButton {icon:"close";onClicked:Hub.close()}}
            WindowSwitcher {Layout.fillWidth:true;Layout.fillHeight:true;layoutMode:panel.game ? "console" : panel.phone ? "phone" : "desktop";focus:true}
        }}
        Component {id:wallpaperComponent;WallpaperPicker {}}
        Component {id:convergenceComponent;Convergence {}}
        Component {id:launcherComponent;Launcher {}}
        Component {id:mobileComponent;MobileHome {}}
        Component {id:consoleComponent;ConsoleHome {}}
        Component {id:controlsComponent;QuickSettings {}}
        Component {id:clipboardComponent;ClipboardPanel {touchMode:panel.phone}}
        Component {id:appearanceComponent;ColumnLayout {
            anchors {fill:parent;margins:20} spacing:16
            RowLayout {Layout.fillWidth:true;MText {text:"Make it yours";font.pixelSize:26;font.weight:Font.DemiBold;Layout.fillWidth:true}MButton {icon:"close";tonal:true;onClicked:Hub.close()}}
            Appearance {Layout.fillWidth:true;Layout.fillHeight:true;compact:panel.phone}
        }}
        Shortcut {sequence:"Escape";enabled:!(panel.game&&panel.launcher);onActivated:Hub.close()}
    }
}
