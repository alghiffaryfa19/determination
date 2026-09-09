import QtQuick
import QtQuick.Layouts

Item {
    id:p
    ColumnLayout {anchors.fill:parent;anchors.margins:18;spacing:8
        RowLayout {Layout.fillWidth:true
            Glyph {name:"music";color:Theme.primary}
            MText {text:"Sound & music";font.pixelSize:18;font.weight:Font.DemiBold;Layout.fillWidth:true}
            MButton {icon:"close";implicitWidth:38;implicitHeight:38;tooltip:"Close sound & music";onClicked:Hub.closeAudio()}
        }
        AudioCard {Layout.fillWidth:true;Layout.fillHeight:true;showVolume:true;allowExpand:false}
        MText {Layout.fillWidth:true;text:"Scroll to change volume · click outside to dismiss";font.pixelSize:10;color:Theme.subtext;horizontalAlignment:Text.AlignHCenter}
    }
    WheelHandler {target:null;onWheel:event=>{
        const delta=event.angleDelta.y||event.pixelDelta.y;
        if(delta){Hub.volume(Math.max(0,Math.min(100,Hub.status.volume+(delta>0 ? 2 : -2))));event.accepted=true;}
    }}
}
