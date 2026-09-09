import QtQuick
import Quickshell.Wayland

Item {
    id:p
    property var handle:null
    property bool capturing:true
    readonly property bool hasContent:!!capture.item&&capture.item.hasContent
    clip:true
    Loader {
        id:capture;anchors.fill:parent;active:p.capturing&&p.handle!==null
        sourceComponent:Component {
            Item {
                readonly property bool hasContent:view.hasContent
                ScreencopyView {
                    id:view;anchors.centerIn:parent
                    width:sourceSize.width>0&&sourceSize.height>0 ? Math.min(p.width,p.height*sourceSize.width/sourceSize.height) : p.width
                    height:sourceSize.width>0&&sourceSize.height>0 ? width*sourceSize.height/sourceSize.width : p.height
                    captureSource:p.handle;live:true;paintCursor:false
                    constraintSize:Qt.size(Math.max(1,p.width),Math.max(1,p.height))
                }
            }
        }
    }
    MText {anchors.centerIn:parent;visible:!p.hasContent;text:p.handle ? "Waiting for window…" : "Preview unavailable";font.pixelSize:11;color:Theme.subtext}
}
