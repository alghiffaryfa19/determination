import QtQuick
import QtQuick.Controls
import Quickshell

Rectangle {
    id:tile
    required property var app
    property bool selected:false
    property var art:Hub.artFor(app)
    signal activated()
    radius:24
    color:selected ? Theme.primaryContainer : Theme.alpha(Theme.surface,.85)
    border.width:selected ? 3 : 0
    border.color:Theme.primary
    scale:mouse.pressed ? .97 : 1
    Behavior on scale {NumberAnimation {duration:140}}
    Item {
        x:10;y:10;width:parent.width-20;height:parent.height-62
        Image {id:cover;anchors.fill:parent;source:tile.art.header||tile.art.cover||"";fillMode:Image.PreserveAspectCrop;asynchronous:true}
        Rectangle {visible:cover.status!==Image.Ready;anchors.fill:parent;radius:18;color:Theme.alpha(Theme.primary,.12)
            Flower {anchors.centerIn:parent;width:Math.min(parent.height-10,100);height:width;fill:Theme.alpha(Theme.primary,.22);lobes:8}
            Image {id:icon;anchors.centerIn:parent;width:58;height:58;source:Quickshell.iconPath(tile.app.icon,true);sourceSize:Qt.size(width,height);asynchronous:true;cache:true}
            Glyph {visible:icon.status!==Image.Ready;anchors.centerIn:parent;name:"game";color:Theme.primary;font.pixelSize:34}
        }
    }
    MText {anchors {left:parent.left;right:parent.right;bottom:parent.bottom;leftMargin:16;rightMargin:16;bottomMargin:18}
text:app.name;font.pixelSize:16;font.weight:Font.DemiBold;color:selected ? Theme.onContainer : Theme.text}
    OpalMenu {id:gameMenu;entries:visible ? Hub.appMenu(tile.app) : []}
    MouseArea {id:mouse;anchors.fill:parent;hoverEnabled:true;acceptedButtons:Qt.LeftButton|Qt.RightButton
        property bool held:false
        onPressed:held=false
        onClicked:e=>{if(held)return;if(e.button===Qt.RightButton)gameMenu.popup(e.x,e.y);else tile.activated();}
        onPressAndHold:e=>{held=true;gameMenu.popup(e.x,e.y);}
    }
}
