import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    id:notice
    readonly property var phoneScreen:Quickshell.screens.find(s=>Hub.dockScreen&&s.name!==Hub.dockScreen.name&&Hub.layoutFor(s.width,s.height,s.name)==="phone")||null
    readonly property var targets:Hub.dockScreen ? (phoneScreen ? [Hub.dockScreen,phoneScreen] : [Hub.dockScreen]) : []
    Variants {
        model:notice.targets
        delegate:PanelWindow {
            id:window
            required property var modelData
            screen:modelData
            readonly property bool phone:Hub.layoutFor(screen.width,screen.height,screen.name)==="phone"
            readonly property bool wanted:Hub.dockNotice&&(Hub.page===""||Hub.page==="launcher")&&!Hub.audioOpen
            property bool presenting:false
            property real arrival:0
            function sync(){if(wanted){presenting=true;card.replay();}animation.to=wanted ? 1 : 0;animation.restart();}
            onWantedChanged:Qt.callLater(sync)
            Component.onCompleted:Qt.callLater(sync)
            visible:presenting
            anchors {bottom:true;right:true}
            margins {bottom:window.phone ? 36 : 82;right:12}
            implicitWidth:Math.min(window.phone ? 520 : 580,screen.width-24)
            implicitHeight:card.implicitHeight
            exclusionMode:ExclusionMode.Ignore
            WlrLayershell.layer:WlrLayer.Overlay
            WlrLayershell.namespace:"opal-toast"
            WlrLayershell.keyboardFocus:WlrKeyboardFocus.None
            color:"transparent"
            mask:Region {item:card}
            NumberAnimation {id:animation;target:window;property:"arrival";to:1;duration:Theme.motion(window.wanted ? 520 : 260);easing.type:Easing.OutCubic;onFinished:if(!window.wanted)window.presenting=false}
            DockWelcome {id:card;width:window.width;height:window.height;phone:window.phone;sourcePhoneScreen:notice.phoneScreen
                x:window.phone ? 0 : (1-window.arrival)*window.width
                y:window.phone ? (1-window.arrival)*window.height : 0
                opacity:window.arrival
            }
        }
    }
}
