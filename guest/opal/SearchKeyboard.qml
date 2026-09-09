import QtQuick
import QtQuick.Layouts

Rectangle {
    id:k
    property bool controllerMode:false
    property bool shift:false
    property bool numbers:false
    property int selection:0
    readonly property var rows:numbers ? ["1234567890".split(""),["+","-","*","/","=","(",")","%","?",">"],[".",",",":",";","!","@","#","_","'",'"'],["ABC","SPACE","⌫","DONE","CLOSE"]] : ["qwertyuiop".split(""),"asdfghjkl".split(""),"zxcvbnm".split(""),["123","SHIFT","SPACE","⌫","DONE","CLOSE"]]
    readonly property var keys:rows.reduce((all,row,r)=>all.concat(row.map((key,c)=>({key:key,row:r,col:c}))),[])
    signal insert(string text)
    signal erase()
    signal accept()
    signal dismiss()
    implicitHeight:controllerMode ? 320 : 244
    radius:24;color:Theme.surface
    function press(value) {
        if(value==="CLOSE")dismiss();
        else if(value==="DONE")accept();
        else if(value==="⌫")erase();
        else if(value==="SHIFT")shift=!shift;
        else if(value==="123"||value==="ABC") {numbers=!numbers;selection=0;}
        else if(value==="SPACE")insert(" ");
        else {insert(shift ? value.toUpperCase() : value);shift=false;}
    }
    function navigation(direction) {
        const key=keys[Math.min(selection,keys.length-1)];
        if(direction==="accept") {press(key.key);return;}
        if(direction==="back") {dismiss();return;}
        if(direction==="left")selection=Math.max(0,selection-1);
        if(direction==="right")selection=Math.min(keys.length-1,selection+1);
        if(direction==="up"||direction==="down") {
            const row=Math.max(0,Math.min(rows.length-1,key.row+(direction==="up" ? -1 : 1)));
            const col=Math.min(rows[row].length-1,Math.floor((key.col+.5)*rows[row].length/rows[key.row].length));
            selection=rows.slice(0,row).reduce((n,r)=>n+r.length,0)+col;
        }
    }
    ColumnLayout {
        anchors {fill:parent;margins:10}
spacing:5
        MText {text:k.controllerMode ? "D-pad to choose · A to type · B to close" : "Search keyboard";font.pixelSize:11;color:Theme.subtext;Layout.leftMargin:6;Layout.bottomMargin:4}
        Repeater {
            model:k.rows
            RowLayout {
                id:keyRow
                required property var modelData
                required property int index
                Layout.fillWidth:true;Layout.fillHeight:true;spacing:4
                Repeater {
                    model:keyRow.modelData
                    MButton {
                        required property string modelData
                        required property int index
                        property int keyIndex:k.rows.slice(0,keyRow.index).reduce((n,r)=>n+r.length,0)+index
                        Layout.fillWidth:true;Layout.fillHeight:true;Layout.minimumWidth:0
                        text:modelData==="SPACE" ? "␣" : modelData==="SHIFT" ? "⇧" : modelData==="CLOSE" ? "×" : modelData==="DONE" ? "↵" : k.shift&&modelData.length===1 ? modelData.toUpperCase() : modelData
                        compact:true
                        filled:(k.controllerMode&&k.selection===keyIndex)||modelData==="DONE"
                        tonal:!filled
                        tooltip:modelData
                        onClicked:k.press(modelData)
                    }
                }
            }
        }
    }
}
