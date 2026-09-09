import QtQuick
import QtQuick.Controls
import QtQml.Models

Menu {
    id:menu
    property var entries:[]
    popupType:Popup.Window
    implicitWidth:280
    margins:8
    padding:8
    dim:false
    closePolicy:Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background:Rectangle {radius:22;color:Theme.surface;border.width:1;border.color:Theme.outline}
    Instantiator {
        model:menu.entries
        delegate:MenuItem {
            id:row
            required property var modelData
            text:modelData.text
            enabled:modelData.enabled!==false
            implicitHeight:46
            leftPadding:42;rightPadding:14
            contentItem:MText {text:row.text;font.pixelSize:13;color:row.enabled ? Theme.text : Theme.muted;verticalAlignment:Text.AlignVCenter}
            background:Rectangle {radius:14;color:row.highlighted ? Theme.primaryContainer : "transparent"
                Glyph {x:10;anchors.verticalCenter:parent.verticalCenter;name:row.modelData.icon||"next";font.pixelSize:20;color:Theme.primary}
            }
            onTriggered:if(modelData.run)modelData.run()
        }
        onObjectAdded:(index,object)=>menu.insertItem(index,object)
        onObjectRemoved:(index,object)=>menu.removeItem(object)
    }
}
