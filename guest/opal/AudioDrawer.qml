import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    // Input-only, unblurred click-away surfaces. They never take keyboard focus.
    Variants {
        model:Quickshell.screens
        delegate:PanelWindow {
            required property var modelData
            screen:modelData;visible:Hub.audioOpen
            anchors {top:true;bottom:true;left:true;right:true}
            exclusionMode:ExclusionMode.Ignore
            WlrLayershell.layer:WlrLayer.Overlay
            WlrLayershell.namespace:"opal-audio-dismiss"
            WlrLayershell.keyboardFocus:WlrKeyboardFocus.None
            color:"transparent"
            MouseArea {anchors.fill:parent;acceptedButtons:Qt.AllButtons;onPressed:Hub.closeAudio()
                onWheel:event=>{
                    if(event.y<=112){const delta=event.angleDelta.y||event.pixelDelta.y;if(delta)Hub.volume(Math.max(0,Math.min(100,Hub.status.volume+(delta>0 ? 2 : -2))));}
                    else Hub.closeAudio();
                    event.accepted=true;
                }
            }
        }
    }
    PanelWindow {
        id:drawer
        screen:Hub.audioScreen||Quickshell.screens[0]
        property bool presenting:false
        property real progress:0
        visible:presenting
        anchors {top:true;right:true}
        margins.top:56
        implicitWidth:Math.min(444,screen ? screen.width : 444)
        implicitHeight:Math.min(354,screen ? screen.height-70 : 354)
        exclusionMode:ExclusionMode.Ignore
        WlrLayershell.layer:WlrLayer.Overlay
        WlrLayershell.namespace:"opal-audio"
        WlrLayershell.keyboardFocus:WlrKeyboardFocus.None
        color:"transparent"
        mask:Region {item:card}
        Connections {target:Hub;function onAudioOpenChanged(){
            if(Hub.audioOpen)Qt.callLater(()=>{
                if(!Hub.audioOpen)return;
                drawer.presenting=true;slide.to=1;slide.restart();
            });
            else {slide.to=0;slide.restart();}
        }}
        NumberAnimation {id:slide;target:drawer;property:"progress";duration:Theme.motion(280);easing.type:Easing.OutCubic;onFinished:if(!Hub.audioOpen)drawer.presenting=false}
        Surface {id:card;width:drawer.width-12;height:drawer.height;x:12+(1-drawer.progress)*drawer.width;radius:30;translucency:Hub.prefs.glass
            enabled:Hub.audioOpen
            AudioPanel {anchors.fill:parent}
        }
    }
}
