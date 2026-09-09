import QtQuick
import QtQuick.Controls

Slider {
    id:s
    property string icon:"volume"
    from:0;to:100;stepSize:1
    implicitHeight:56
    hoverEnabled:true;wheelEnabled:true
    background:Item {
        x:s.leftPadding;y:(s.height-height)/2;width:s.availableWidth;height:36
        readonly property real split:2+(width-4)*s.visualPosition
        Rectangle {
            width:Math.max(0,parent.split-8);height:parent.height
            topLeftRadius:14;bottomLeftRadius:14;topRightRadius:3;bottomRightRadius:3
            color:Theme.primary
        }
        Rectangle {
            x:parent.split+8;width:Math.max(0,parent.width-x);height:parent.height
            topLeftRadius:3;bottomLeftRadius:3;topRightRadius:14;bottomRightRadius:14
            color:Theme.alpha(Theme.surfaceHigh,.78)
        }
        Glyph {x:16;anchors.verticalCenter:parent.verticalCenter;name:s.icon;color:parent.split>46 ? Theme.onPrimary : Theme.subtext;font.pixelSize:21}
    }
    handle:Rectangle {
        x:s.leftPadding+s.visualPosition*(s.availableWidth-width)
        y:(s.height-height)/2;width:4;height:s.pressed ? 52 : 46;radius:2;color:Theme.primary
        Behavior on height {NumberAnimation {duration:Theme.motion(160);easing.type:Easing.OutCubic}}
    }
    ToolTip.visible:s.pressed||s.hovered
    ToolTip.text:Math.round(s.value)+"%"
    ToolTip.delay:500
    Accessible.name:icon
}
