import QtQuick
import QtQuick.Controls
Flickable {
    id:scroller
    clip:true
    flickableDirection:Flickable.HorizontalFlick
    boundsBehavior:Flickable.StopAtBounds
    contentHeight:height
    ScrollBar.horizontal:ScrollBar {policy:ScrollBar.AsNeeded;height:3}
    // Vertical mouse wheels and horizontal trackpad deltas both move a horizontal shelf.
    WheelHandler {
        target:null
        onWheel:event=>{
            const delta=event.pixelDelta.x||event.pixelDelta.y||event.angleDelta.x/3||event.angleDelta.y/3;
            scroller.contentX=Math.max(0,Math.min(Math.max(0,scroller.contentWidth-scroller.width),scroller.contentX-delta));
            event.accepted=true;
        }
    }
}
