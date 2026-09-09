import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id:c
    property string selected:["auto","desktop","phone","console"].indexOf(Hub.prefs.mode)>=0 ? Hub.prefs.mode : "auto"
    readonly property bool narrow:width<620
    readonly property var modes:[
        {id:"auto",title:"Flow",icon:"expand",tag:"ADAPTIVE",description:"A touch home on small and portrait displays. A workspace on larger screens. Each output finds its own fit."},
        {id:"desktop",title:"Workspace",icon:"desktop",tag:"DESKTOP",description:"Windows up front. A running-app shelf, quick search and a compact command center."},
        {id:"phone",title:"Touch",icon:"phone",tag:"PHONE + TABLET",description:"Edge-to-edge home, reachable controls and app switching. Rotate into a wider, two-column home."},
        {id:"console",title:"Play",icon:"game",tag:"CONTROLLER",description:"A game-first library with large artwork, D-pad navigation and a session that keeps interruptions out."}
    ]
    readonly property var choice:modes.find(m=>m.id===selected)||modes[0]
    ColumnLayout {
        anchors.fill:parent;anchors.margins:c.narrow ? 18 : 28;spacing:18
        RowLayout {Layout.fillWidth:true
            ColumnLayout {Layout.fillWidth:true;spacing:4
                MText {text:"ONE SHELL · EVERY SHAPE";font.pixelSize:10;font.letterSpacing:2;color:Theme.primary}
                MText {text:"Convergence";font.pixelSize:c.narrow ? 28 : 36;font.weight:Font.DemiBold}
            }
            Item {Layout.fillWidth:true}
            MButton {icon:"close";tooltip:"Close convergence";onClicked:Hub.close()}
        }
        Flickable {
            Layout.fillWidth:true;Layout.fillHeight:true;clip:true;contentHeight:body.implicitHeight;boundsBehavior:Flickable.StopAtBounds
            ScrollBar.vertical:ScrollBar {}
            ColumnLayout {id:body;width:parent.width;spacing:18
                Rectangle {
                    Layout.fillWidth:true;Layout.preferredHeight:c.narrow ? 232 : 270;radius:28;clip:true;color:Theme.alpha(Theme.primaryContainer,.40);border.width:1;border.color:Theme.outline
                    Flower {width:180;height:180;x:parent.width-195;y:15;fill:Theme.alpha(Theme.primary,.09);lobes:8;rotation:c.selected==="phone" ? 45 : 0;Behavior on rotation {NumberAnimation {duration:Theme.motion(450)}}}
                    Item {
                        id:preview;anchors.horizontalCenter:parent.horizontalCenter;y:20
                        width:c.selected==="phone" ? 100 : Math.min(parent.width-64,340);height:c.selected==="phone" ? 158 : 142
                        Behavior on width {NumberAnimation {duration:Theme.motion(420);easing.type:Easing.OutCubic}}
                        Behavior on height {NumberAnimation {duration:Theme.motion(420);easing.type:Easing.OutCubic}}
                        Rectangle {anchors.fill:parent;radius:16;color:Theme.alpha(Theme.base,.65);border.width:2;border.color:Theme.alpha(Theme.primary,.65)
                            Rectangle {x:9;y:9;width:parent.width-18;height:8;radius:4;color:Theme.alpha(Theme.primary,.30)}
                            Row {x:14;y:29;spacing:8
                                Repeater {model:c.selected==="console" ? 3 : c.selected==="phone" ? 1 : 2
                                    Rectangle {required property int index;width:(preview.width-36)/(c.selected==="console" ? 3 : c.selected==="phone" ? 1 : 2);height:c.selected==="console" ? 80 : 66;radius:10;color:Theme.alpha(index===0 ? Theme.primary : Theme.secondary,.20)
                                        Glyph {anchors.centerIn:parent;name:c.selected==="console" ? "game" : index===0 ? "apps" : "desktop";font.pixelSize:28;color:Theme.primary}
                                    }
                                }
                            }
                            Rectangle {anchors.bottom:parent.bottom;anchors.bottomMargin:10;anchors.horizontalCenter:parent.horizontalCenter;width:parent.width*.54;height:12;radius:6;color:Theme.alpha(Theme.primary,.55)}
                        }
                        Rectangle {opacity:c.selected==="auto" ? 1 : 0;scale:c.selected==="auto" ? 1 : .8;Behavior on opacity {NumberAnimation {duration:Theme.motion(220)}} Behavior on scale {NumberAnimation {duration:Theme.motion(360);easing.type:Easing.OutBack}} width:65;height:105;radius:12;x:parent.width-36;y:58;color:Theme.alpha(Theme.base,.95);border.width:2;border.color:Theme.secondary
                            Glyph {anchors.centerIn:parent;name:"phone";font.pixelSize:28;color:Theme.secondary}
                            Rectangle {width:24;height:3;radius:2;anchors.bottom:parent.bottom;anchors.bottomMargin:9;anchors.horizontalCenter:parent.horizontalCenter;color:Theme.secondary}
                        }
                    }
                    MText {anchors.bottom:parent.bottom;anchors.bottomMargin:22;anchors.horizontalCenter:parent.horizontalCenter;text:c.choice.title+" / "+c.choice.tag;font.pixelSize:13;font.letterSpacing:1;color:Theme.primary}
                }
                GridLayout {Layout.fillWidth:true;columns:c.narrow ? 2 : 4;columnSpacing:8;rowSpacing:8
                    Repeater {model:c.modes
                        MButton {required property var modelData;Layout.fillWidth:true;implicitHeight:54;text:modelData.title;icon:modelData.icon;filled:c.selected===modelData.id;tonal:false;onClicked:c.selected=modelData.id}
                    }
                }
                MText {Layout.fillWidth:true;text:c.choice.description;wrapMode:Text.Wrap;font.pixelSize:14;color:Theme.subtext}
                MText {text:"DOCK & DISPLAYS";font.pixelSize:10;font.letterSpacing:2;color:Theme.primary}
                Repeater {model:Quickshell.screens
                    Rectangle {required property var modelData;Layout.fillWidth:true;implicitHeight:72;radius:20;color:Theme.alpha(Theme.surfaceHigh,.45)
                        RowLayout {anchors.fill:parent;anchors.margins:14;spacing:12
                            Glyph {name:modelData.height>modelData.width ? "phone" : "desktop";color:Theme.primary}
                            ColumnLayout {Layout.fillWidth:true;spacing:4
                                MText {Layout.fillWidth:true;text:modelData.name||"Display";font.weight:Font.DemiBold}
                                MText {Layout.fillWidth:true;text:modelData.width+" × "+modelData.height+" · "+Hub.layoutFor(modelData.width,modelData.height,modelData.name)+" now";font.pixelSize:11;color:Theme.subtext}
                            }
                            MButton {text:(Hub.prefs.displayModes||{})[modelData.name]||"Auto";icon:"expand";compact:true;tonal:true;tooltip:"Layout on this display (used in Flow)";onClicked:displayMenu.popup()}
                            OpalMenu {id:displayMenu;entries:[
                                {text:"Automatic fit",icon:"expand",run:()=>Hub.displayMode(modelData.name,"auto")},
                                {text:"Desktop workspace",icon:"desktop",run:()=>Hub.displayMode(modelData.name,"desktop")},
                                {text:"Touch home",icon:"phone",run:()=>Hub.displayMode(modelData.name,"phone")}
                            ]}
                        }
                    }
                }
                MButton {Layout.fillWidth:true;icon:"spark";tonal:true;text:Theme.reduceMotion ? "Motion: reduced" : "Motion: expressive";onClicked:Hub.set("reduceMotion",!Theme.reduceMotion)}
                MText {text:"MAKE IT FEEL RIGHT";font.pixelSize:10;font.letterSpacing:2;color:Theme.primary}
                GridLayout {Layout.fillWidth:true;columns:c.narrow ? 1 : 2;columnSpacing:8;rowSpacing:8
                    MButton {Layout.fillWidth:true;text:Hub.prefs.phoneButtons ? "Touch: navigation buttons" : "Touch: gesture strip";icon:"phone";tonal:true;onClicked:Hub.set("phoneButtons",!Hub.prefs.phoneButtons)}
                    MButton {Layout.fillWidth:true;text:Hub.prefs.taskbarAutoHide ? "Shelf: auto-hide" : "Shelf: always visible";icon:"desktop";tonal:true;onClicked:Hub.set("taskbarAutoHide",!Hub.prefs.taskbarAutoHide)}
                }
                RowLayout {Layout.fillWidth:true
                    MText {Layout.fillWidth:true;text:"Glass density";color:Theme.subtext}
                    MText {text:Math.round(Hub.prefs.glass*100)+"%";color:Theme.primary}
                }
                ExpressiveSlider {Layout.fillWidth:true;from:45;to:100;value:Hub.prefs.glass*100;icon:"sun";onMoved:Hub.set("glass",Math.round(value)/100)}
                MText {Layout.fillWidth:true;text:"Plug in a display for a docking welcome. In Flow, each screen adapts independently; the menu above remembers your choice for that output. Display positioning, mirroring and resolution remain compositor-managed. USB-C display-out requires compatible hardware.";wrapMode:Text.Wrap;font.pixelSize:11;color:Theme.subtext}
            }
        }
        MButton {Layout.fillWidth:true;filled:true;implicitHeight:54;icon:c.selected===Hub.prefs.mode ? "check" : "expand";text:c.selected===Hub.prefs.mode ? c.choice.title+" is active" : "Use "+c.choice.title;onClicked:Hub.mode(c.selected)}
    }
}
