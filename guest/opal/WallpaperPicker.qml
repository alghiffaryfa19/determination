import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id:w
    property string draftPath:Hub.prefs.wallpaperPath||""
    property int draftArt:Hub.prefs.wallpaper||0
    property string draftFit:Hub.prefs.wallpaperFit||"crop"
    property real draftDim:Hub.prefs.wallpaperDim||0
    property string tab:Hub.prefs.wallpaperPath ? "images" : "art"
    property bool pathEditor:false
    readonly property bool small:width<450||height<720
    readonly property var names:["Bloom","Orbit","Play","Quiet"]
    readonly property bool changed:draftPath!==(Hub.prefs.wallpaperPath||"")||draftArt!==(Hub.prefs.wallpaper||0)||draftFit!==(Hub.prefs.wallpaperFit||"crop")||Math.abs(draftDim-(Hub.prefs.wallpaperDim||0))>.001
    Component.onCompleted:Hub.browseWallpapers("")
    ColumnLayout {
        anchors.fill:parent;anchors.margins:w.small ? 16 : 24;spacing:w.small ? 8 : 12
        RowLayout {Layout.fillWidth:true
            ColumnLayout {Layout.fillWidth:true;spacing:2
                MText {text:"WALLPAPER STUDIO";font.pixelSize:10;font.letterSpacing:2;color:Theme.primary}
                MText {text:"Find your backdrop";font.pixelSize:w.small ? 23 : 30;font.weight:Font.DemiBold}
            }
            Item {Layout.fillWidth:true}
            MButton {icon:"close";tooltip:"Leave without applying preview";onClicked:Hub.page="appearance"}
        }
        Rectangle {Layout.fillWidth:true;Layout.preferredHeight:w.small ? 144 : 220;radius:24;color:Theme.base;clip:true
            Wallpaper {id:wallpaperPreview;anchors.fill:parent;showWidgets:false;imagePath:w.draftPath;composition:w.draftArt;fit:w.draftFit;dim:w.draftDim}
            Surface {anchors.left:parent.left;anchors.top:parent.top;anchors.margins:12;width:previewLabel.implicitWidth+24;height:30;radius:15;translucency:.65
                MText {id:previewLabel;anchors.centerIn:parent;text:w.changed ? "Preview · not applied" : "Current wallpaper";font.pixelSize:11}
            }
            Surface {anchors.horizontalCenter:parent.horizontalCenter;anchors.bottom:parent.bottom;anchors.bottomMargin:12;width:180;height:42;radius:21;translucency:Hub.prefs.glass
                Row {anchors.centerIn:parent;spacing:16
                    Glyph {name:"apps";color:Theme.primary}
                    Glyph {name:"folder";color:Theme.secondary}
                    Glyph {name:"web";color:Theme.tertiary}
                    Glyph {name:"settings";color:Theme.text}
                }
            }
        }
        RowLayout {Layout.fillWidth:true;spacing:8
            MButton {Layout.fillWidth:true;compact:true;icon:"folder";text:"Browse files";tonal:true;enabled:!Hub.wallpaperLibraryBusy;onClicked:{w.tab="images";Hub.browseWallpaperFolder("");}}
            MButton {Layout.fillWidth:true;compact:true;icon:"terminal";text:"Folder path";tonal:true;onClicked:{w.tab="images";w.pathEditor=!w.pathEditor;if(w.pathEditor)folderPath.forceActiveFocus();}}
        }
        RowLayout {visible:w.pathEditor;Layout.fillWidth:true;spacing:6
            TextField {id:folderPath;Layout.fillWidth:true;implicitHeight:44;placeholderText:"~/Pictures/Wallpapers";text:Hub.wallpaperFolder ? decodeURIComponent(Hub.wallpaperFolder.replace("file://","")) : "";font.family:Theme.font;color:Theme.text;placeholderTextColor:Theme.subtext;selectByMouse:true;leftPadding:14;background:Rectangle {radius:22;color:Theme.surfaceHigh} onAccepted:Hub.browseWallpaperFolder(text)}
            MButton {icon:"next";compact:true;enabled:!Hub.wallpaperLibraryBusy;tooltip:"Open folder here";onClicked:Hub.browseWallpaperFolder(folderPath.text)}
        }
        RowLayout {Layout.fillWidth:true;spacing:6
            MButton {text:"Fill";compact:true;enabled:!!w.draftPath;filled:w.draftFit==="crop";onClicked:w.draftFit="crop"}
            MButton {text:"Fit";compact:true;enabled:!!w.draftPath;filled:w.draftFit==="fit";onClicked:w.draftFit="fit"}
            MText {text:"Dim";font.pixelSize:11;color:Theme.subtext}
            ExpressiveSlider {Layout.fillWidth:true;enabled:!!w.draftPath;opacity:enabled ? 1 : .4;from:0;to:80;value:w.draftDim*100;icon:"moon";onMoved:w.draftDim=Math.round(value)/100}
        }
        RowLayout {Layout.fillWidth:true;spacing:8
            MButton {Layout.fillWidth:true;text:"Opal collection";compact:true;filled:w.tab==="art";onClicked:w.tab="art"}
            MButton {Layout.fillWidth:true;text:"Your images";compact:true;filled:w.tab==="images";onClicked:w.tab="images"}
            MButton {visible:w.tab==="images";icon:"restart";compact:true;tooltip:"Refresh folder";enabled:!Hub.wallpaperLibraryBusy;onClicked:{if(Hub.wallpaperFolder)Hub.browseWallpaperFolder(Hub.wallpaperFolder);else Hub.browseWallpapers("");}}
        }
        RowLayout {visible:w.tab==="images";Layout.fillWidth:true;spacing:6
            MButton {icon:"back";compact:true;implicitWidth:38;implicitHeight:34;enabled:!!Hub.wallpaperParent&&!Hub.wallpaperLibraryBusy;tooltip:"Parent folder";onClicked:Hub.browseWallpaperFolder(Hub.wallpaperParent)}
            MText {Layout.fillWidth:true;text:Hub.wallpaperFolder ? decodeURIComponent(Hub.wallpaperFolder.replace("file://","")) : "Your local collection";elide:Text.ElideMiddle;font.pixelSize:11;color:Theme.subtext}
            MButton {icon:"grid";compact:true;implicitWidth:38;implicitHeight:34;tooltip:"Local collection";enabled:!Hub.wallpaperLibraryBusy;onClicked:Hub.browseWallpapers("")}
        }
        MText {visible:w.tab==="images"&&Hub.wallpaperLibraryError!=="";text:Hub.wallpaperLibraryError;Layout.fillWidth:true;wrapMode:Text.Wrap;font.pixelSize:11;color:Theme.tertiary}
        GridView {
            id:gallery;Layout.fillWidth:true;Layout.fillHeight:true;clip:true;cacheBuffer:0
            cellWidth:width/(w.width<500 ? 2 : 3);cellHeight:w.small ? 116 : 148
            model:w.tab==="art" ? [0,1,2,3] : Hub.wallpaperFolders.concat(Hub.wallpaperLibrary)
            enabled:w.tab==="art"||!Hub.wallpaperLibraryBusy
            onModelChanged:contentY=0
            boundsBehavior:Flickable.StopAtBounds
            ScrollBar.vertical:ScrollBar {}
            delegate:Item {
                id:tile
                required property var modelData
                required property int index
                readonly property bool art:w.tab==="art"
                readonly property bool directory:!art&&!!modelData.directory
                readonly property bool chosen:art ? !w.draftPath&&w.draftArt===index : !directory&&w.draftPath===modelData.path
                function choose(){if(art){w.draftPath="";w.draftArt=index;}else if(directory)Hub.browseWallpaperFolder(modelData.path);else w.draftPath=modelData.path;}
                width:gallery.cellWidth;height:gallery.cellHeight
                Rectangle {id:frame;anchors.fill:parent;anchors.margins:5;radius:18;color:Theme.alpha(Theme.surfaceHigh,.5);border.width:tile.chosen ? 2 : 1;border.color:tile.chosen ? Theme.primary : Theme.outline
                    Item {anchors.fill:parent;anchors.margins:7;anchors.bottomMargin:32;clip:true
                        Loader {anchors.fill:parent;active:tile.art;sourceComponent:Component {Wallpaper {showWidgets:false;imagePath:"";composition:tile.index}}}
                        Image {id:thumbnail;anchors.fill:parent;visible:!tile.art&&!tile.directory;source:tile.art||tile.directory ? "" : tile.modelData.path;fillMode:Image.PreserveAspectCrop;sourceSize.width:240;sourceSize.height:150;asynchronous:true;autoTransform:true}
                        Glyph {anchors.centerIn:parent;visible:tile.directory||!tile.art&&thumbnail.status!==Image.Ready;name:tile.directory ? "folder" : thumbnail.status===Image.Error ? "close" : "palette";font.pixelSize:tile.directory ? 36 : 22;color:Theme.subtext}
                    }
                    MText {anchors.left:parent.left;anchors.right:parent.right;anchors.bottom:parent.bottom;anchors.margins:10;text:tile.art ? w.names[tile.index] : tile.modelData.name;font.pixelSize:11;color:tile.chosen ? Theme.primary : Theme.text}
                    scale:pick.pressed ? .97 : 1
                    Behavior on scale {NumberAnimation {duration:Theme.motion(160)}}
                    MouseArea {id:pick;anchors.fill:parent;onClicked:tile.choose()}
                    Accessible.role:Accessible.Button
                    Accessible.name:tile.art ? w.names[tile.index] : tile.modelData.name
                    activeFocusOnTab:true
                    Keys.onReturnPressed:tile.choose()
                    Keys.onSpacePressed:tile.choose()
                    Accessible.onPressAction:tile.choose()
                }
            }
            MText {anchors.centerIn:parent;width:parent.width-24;horizontalAlignment:Text.AlignHCenter;wrapMode:Text.Wrap;visible:w.tab==="images"&&(Hub.wallpaperLibraryBusy||Hub.wallpaperLibrary.length+Hub.wallpaperFolders.length===0);text:Hub.wallpaperLibraryBusy ? "Finding local images…" : Hub.wallpaperLibraryError||"No images here yet.\nBrowse a folder to find your wallpaper.";color:Theme.subtext;font.pixelSize:13}
        }
        MText {visible:w.tab==="images";Layout.fillWidth:true;text:Hub.wallpaperLibrary.length+" images · local only · up to 120 per scan";font.pixelSize:10;color:Theme.muted}
        RowLayout {Layout.fillWidth:true;spacing:8
            MButton {text:"Reset";tonal:true;enabled:w.changed;onClicked:{w.draftPath=Hub.prefs.wallpaperPath||"";w.draftArt=Hub.prefs.wallpaper||0;w.draftFit=Hub.prefs.wallpaperFit||"crop";w.draftDim=Hub.prefs.wallpaperDim||0;}}
            MButton {Layout.fillWidth:true;icon:"check";text:w.changed ? "Apply wallpaper" : "Applied";filled:true;enabled:w.changed&&wallpaperPreview.imageReady;onClicked:Hub.command({action:"wallpaper",path:w.draftPath,wallpaper:w.draftArt,wallpaperFit:w.draftFit,wallpaperDim:w.draftDim})}
        }
    }
}
