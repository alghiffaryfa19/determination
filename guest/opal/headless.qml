import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtTest
import Quickshell
import "." as Opal

// Isolated renderer. The runner removes DISPLAY/WAYLAND_DISPLAY and supplies
// an offscreen platform, disposable HOME, and a nonexistent session bus.
ShellRoot {
    Component.onCompleted:Quickshell.watchFiles=false
    Window {
        id:fixture
        width:960;height:650;visible:true;color:Opal.Theme.base
        property int step:0
        property real musicVolume:40
        property var cases:[
            {name:"expressive-controls",ui:"shapes",w:600,h:310},
            {name:"audio-drawer-dark",ui:"audio",w:444,h:354,music:true,wheel:true},
            {name:"audio-drawer-light",ui:"audio",w:360,h:354,music:true,light:true},
            {name:"shade-reference",ui:"shade",w:360,h:768,music:true},
            {name:"wallpaper-browser",ui:"wallpaper",w:800,h:860,browse:true},
            {name:"wallpaper-studio",ui:"wallpaper",w:800,h:860},
            {name:"wallpaper-studio-light",ui:"wallpaper",w:800,h:860,light:true},
            {name:"wallpaper-studio-images",ui:"wallpaper",w:800,h:860,photo:true},
            {name:"wallpaper-studio-phone",ui:"wallpaper",w:360,h:740},
            {name:"touch-apps-monitor",ui:"phone",w:1920,h:1080,drawer:true},
            {name:"dock-welcome",ui:"dock",w:580,h:290},
            {name:"dock-welcome-phone",ui:"dock",w:366,h:374,phone:true},
            {name:"dock-welcome-phone-light",ui:"dock",w:336,h:374,phone:true,light:true},
            {name:"phone-switcher-monitor",ui:"switcher",w:1080,h:880,recent:true,phone:true},
            {name:"glass",ui:"glass",w:960,h:740},
            {name:"convergence-dark",ui:"convergence",w:800,h:820},
            {name:"convergence-light",ui:"convergence",w:800,h:820,light:true},
            {name:"convergence-phone",ui:"convergence",w:360,h:740},
            {name:"tablet-home",ui:"phone",w:1000,h:740},
            {name:"desktop",ui:"desktop",w:960,h:650},
            {name:"desktop-light",ui:"desktop",w:960,h:740,light:true},
            {name:"wifi-phone",ui:"shade",w:360,h:640,detail:"wifi"},
            {name:"bluetooth-light",ui:"shade",w:490,h:740,detail:"bluetooth",light:true},
            {name:"workspace-dark",ui:"workspace",w:1440,h:900},
            {name:"workspace-light",ui:"workspace",w:1440,h:900,light:true},
            {name:"shade-dark",ui:"shade",w:490,h:860},
            {name:"shade-light",ui:"shade",w:490,h:860,light:true},
            {name:"shade-phone",ui:"shade",w:360,h:640},
            {name:"appearance-dark",ui:"appearance",w:620,h:800},
            {name:"appearance-light",ui:"appearance",w:620,h:800,light:true},
            {name:"appearance-phone",ui:"appearance",w:328,h:740},
            {name:"shade-scrolled",ui:"shade",w:490,h:700,scroll:true},
            {name:"appearance-scrolled",ui:"appearance",w:620,h:800,scroll:true},
            {name:"phone-home",ui:"phone",w:390,h:844},
            {name:"phone-home-light",ui:"phone",w:390,h:844,light:true},
            {name:"phone-switcher",ui:"phone",w:390,h:844,recent:true},
            {name:"desktop-switcher",ui:"switcher",w:900,h:650,recent:true},
            {name:"console-switcher",ui:"switcher",w:1100,h:750,recent:true,game:true},
            {name:"phone-apps",ui:"phone",w:390,h:844,apps:true},
            {name:"small-phone",ui:"phone",w:360,h:740,apps:true},
            {name:"phone-landscape",ui:"phone",w:800,h:480},
            {name:"console",ui:"console",w:1280,h:800},
            {name:"console-search",ui:"console",w:1280,h:800,search:true},
            {name:"console-actions",ui:"console",w:1280,h:800,menu:true},
            {name:"console-session",ui:"console",w:960,h:600,menu:true,section:1},
            {name:"console-setup-light",ui:"console",w:960,h:600,menu:true,section:3,light:true,nintendo:true},
            {name:"phone-bars",ui:"phonebars",w:390,h:844},
            {name:"phone-bars-light",ui:"phonebars",w:360,h:740,light:true,buttons:true},
            {name:"handheld",ui:"console",w:960,h:600},
            {name:"clipboard-empty",ui:"clipboard",w:470,h:650,empty:true},
            {name:"clipboard-text",ui:"clipboard",w:470,h:650},
            {name:"clipboard-phone",ui:"clipboard",w:390,h:844,phone:true},
            {name:"clipboard-widget",ui:"dashboard",w:840,h:700},
            {name:"taskbar-drag",ui:"taskbar",w:700,h:64,drag:true}
        ]
        Rectangle {anchors.fill:parent;color:Opal.Theme.base}
        Loader {id:view;anchors.fill:parent}
        TestCase {id:input;name:"TaskbarDrag";when:false}
        Component {id:taskbarView;Opal.TaskStrip {labels:false}}
        Component {id:audioView;Opal.AudioPanel {}}
        Component {id:shapeView;Item {
            property alias slider:shapeSlider
            property alias enabledTile:onStateTile
            property alias disabledTile:offStateTile
            ColumnLayout {anchors.fill:parent;anchors.margins:24;spacing:16
                Opal.MText {text:"Split tracks · expressive states";font.pixelSize:20}
                Opal.ExpressiveSlider {id:shapeSlider;Layout.fillWidth:true;icon:"sun";value:58}
                RowLayout {Layout.fillWidth:true;spacing:12
                    Opal.ShadeTile {id:offStateTile;Layout.fillWidth:true;icon:"coffee";title:"Keep awake";subtitle:"Off";active:false}
                    Opal.ShadeTile {id:onStateTile;Layout.fillWidth:true;icon:"quiet";title:"Do not disturb";subtitle:"On";active:true}
                }
                RowLayout {Layout.alignment:Qt.AlignHCenter;spacing:14
                    Opal.MButton {icon:"moon";morph:true;checked:false;tonal:true}
                    Opal.MButton {icon:"moon";morph:true;checked:true;filled:true}
                }
            }
        }}
        Timer {interval:100;repeat:true;running:fixture.step<fixture.cases.length&&!!fixture.cases[fixture.step].music
            onTriggered:Opal.Hub.status=Object.assign({},Opal.Hub.status,{track:"A little evening music",artist:"Local player",art:"file://"+Quickshell.env("HOME")+"/Pictures/Wallpapers/Fixture-1.png",playing:true,volume:fixture.musicVolume,audioOutput:"Headphones"})
        }
        Component {id:switcherView;Opal.WindowSwitcher {}}
        Component {id:wallpaperStudio;Opal.WallpaperPicker {}}
        Component {id:dockView;Opal.DockWelcome {displayName:"USB-C · External monitor"}}
        Component {id:glassView;Item {Opal.Wallpaper {anchors.fill:parent;showWidgets:false} Opal.Surface {anchors.fill:parent;anchors.margins:24;translucency:.55;Opal.Convergence {anchors.fill:parent}}}}
        Component {id:convergenceView;Opal.Convergence {}}
        Component {id:desktop;Opal.Launcher {}}
        Component {id:phone;Opal.MobileHome {}}
        Component {id:phoneBars;Item {
            property alias navigation:phoneNav
            Opal.PhoneStatus {anchors.top:parent.top;width:parent.width;height:48}
            Opal.MobileHome {anchors.fill:parent;anchors.topMargin:48;anchors.bottomMargin:phoneNav.height}
            Opal.PhoneNavigation {id:phoneNav;anchors.bottom:parent.bottom;width:parent.width;height:implicitHeight}
        }}
        Component {id:gaming;Opal.ConsoleHome {}}
        Component {id:clipboardView;Opal.ClipboardPanel {}}
        Component {id:dashboardView;Opal.Dashboard {}}
        Component {id:shadeView;Opal.QuickSettings {}}
        Component {id:appearanceView;Opal.Appearance {}}
        Component {id:workspaceView;Item {
            Opal.Wallpaper {anchors.fill:parent}
        }}
        function scrollEnd(item) {
            if(item.contentHeight!==undefined&&item.contentHeight>item.height)item.contentY=item.contentHeight-item.height;
            for(let child of item.children||[])scrollEnd(child);
        }
        function next() {
            if(step>=cases.length) {console.log("OFFSCREEN_TESTS_COMPLETE");Qt.quit();return;}
            const test=cases[step];
            view.sourceComponent=null;
            width=test.w;height=test.h;musicVolume=40;
            Opal.Hub.prefs=Object.assign({},Opal.Hub.prefs,{mode:test.ui==="convergence"||test.ui==="glass"||test.ui==="dock" ? "auto" : test.ui,light:!!test.light,phoneButtons:!!test.buttons,controllerLayout:test.nintendo ? "nintendo" : "standard"});
            Opal.Hub.mobileTab=test.recent ? "recent" : test.apps||test.drawer ? "apps" : "home";
            if(test.recent) {
                const fixtureWindows=[{title:"Project notes",className:"org.kde.kate",workspace:1,address:"fixture-1"},{title:"A good playlist",className:"firefox",workspace:2,address:"fixture-2"}];
                Opal.Hub.status=Object.assign({},Opal.Hub.status,{hypr:true,windows:fixtureWindows});
                Opal.Hub.compositorActive=true;Opal.Hub.compositorWindows=fixtureWindows;
            } else {
                Opal.Hub.status=Object.assign({},Opal.Hub.status,{hypr:false});
                Opal.Hub.compositorActive=false;Opal.Hub.compositorWindows=[];
            }
            Opal.Hub.controlDetail=test.detail||"";
            if(test.ui==="clipboard"||test.ui==="dashboard") {
                const samples=["A little thought worth keeping.","https://m3.material.io/","const idea = {\n  color: 'expressive',\n  mood: 'quiet'\n};","Meet at 16:30. Bring the good playlist."];
                Opal.Hub.clipboardAvailable=true;
                Opal.Hub.clipboardItems=test.empty ? [] : samples.map((t,i)=>({id:"fixture-"+i,text:t,chars:t.length,lines:t.split(String.fromCharCode(10)).length,kind:i===1 ? "Link" : i===2 ? "Snippet" : "Text",captured:0}));
            }
            if(test.ui==="dock") {
                Opal.Hub.prefs=Object.assign({},Opal.Hub.prefs,{displayModes:{"phone-fixture":"phone"}});
                if(Opal.Hub.layoutFor(1920,1080,"monitor-fixture")!=="desktop"||Opal.Hub.layoutFor(1080,1920,"phone-fixture")!=="phone"||Opal.Hub.layoutFor(390,844,"small-fixture")!=="phone")console.error("ASSERTION_FAILED: per-display convergence");
                if(Opal.Hub.dockNotice)console.error("ASSERTION_FAILED: docking welcome opened at startup");
                const ready=Opal.Hub.displaysReady;
                const known=Opal.Hub.knownDisplays;
                const page=Opal.Hub.page;
                Opal.Hub.displaysReady=true;Opal.Hub.knownDisplays=["internal-fixture"];
                Opal.Hub.updateDisplays([{name:"internal-fixture"},{name:"external-fixture"}]);
                if(!Opal.Hub.dockNotice||Opal.Hub.dockScreen.name!=="external-fixture"||Opal.Hub.page!==page)console.error("ASSERTION_FAILED: nonexclusive hotplug welcome");
                Opal.Hub.updateDisplays([{name:"internal-fixture"}]);
                if(Opal.Hub.dockNotice||Opal.Hub.dockScreen!==null)console.error("ASSERTION_FAILED: unplug cleanup");
                Opal.Hub.knownDisplays=known;Opal.Hub.displaysReady=ready;
            }
            if(test.drag) {
                Opal.Hub.prefs=Object.assign({},Opal.Hub.prefs,{favorites:[],pinsConfigured:true,taskbarOrder:[]});
                const fixtureWindows=[0,1,2,3].map(i=>({className:"Fixture-"+i,title:"Fixture "+i,address:"fixture-"+i,workspace:1}));
                Opal.Hub.status=Object.assign({},Opal.Hub.status,{hypr:true,windows:fixtureWindows});
                Opal.Hub.compositorActive=true;Opal.Hub.compositorWindows=fixtureWindows;
            }
            if(test.ui==="phonebars")Opal.Hub.status=Object.assign({},Opal.Hub.status,{battery:73,charging:true,wifi:true,network:"Home Wi-Fi"});
            if(test.music)Opal.Hub.status=Object.assign({},Opal.Hub.status,{track:"A little evening music",artist:"Local player",art:"file://"+Quickshell.env("HOME")+"/Pictures/Wallpapers/Fixture-1.png",playing:true,volume:40,audioOutput:"Headphones"});
            view.sourceComponent=test.ui==="phonebars" ? phoneBars : test.ui==="shapes" ? shapeView : test.ui==="audio" ? audioView : test.ui==="taskbar" ? taskbarView : test.ui==="switcher" ? switcherView : test.ui==="wallpaper" ? wallpaperStudio : test.ui==="dock" ? dockView : test.ui==="glass" ? glassView : test.ui==="convergence" ? convergenceView : test.ui==="desktop" ? desktop : test.ui==="phone" ? phone : test.ui==="clipboard" ? clipboardView : test.ui==="dashboard" ? dashboardView : test.ui==="workspace" ? workspaceView : test.ui==="shade" ? shadeView : test.ui==="appearance" ? appearanceView : gaming;
            if(test.ui==="phonebars") {
                view.item.navigation.go("recent");
                if(Opal.Hub.mobileTab!=="recent")console.error("ASSERTION_FAILED: phone recents");
                view.item.navigation.back();
                if(Opal.Hub.mobileTab!=="home"||Opal.Hub.page!=="launcher")console.error("ASSERTION_FAILED: phone contextual back");
                view.item.navigation.back();
                if(Opal.Hub.page!=="")console.error("ASSERTION_FAILED: phone dismiss");
            }
            if(test.ui==="switcher") {
                view.item.layoutMode=test.phone ? "phone" : test.game ? "console" : "desktop";
                if(test.phone)Qt.callLater(()=>{if(view.item.touchCarousel)console.error("ASSERTION_FAILED: wide phone switcher uses carousel");});
                view.item.navigate("right");
                if(view.item.selection!==1)console.error("ASSERTION_FAILED: switcher navigation");
                view.item.query="Project";
                if(view.item.windows.length!==1)console.error("ASSERTION_FAILED: switcher filtering");
                view.item.query="";
            }
            if(test.ui==="dock")view.item.phone=!!test.phone;
            if(test.ui==="wallpaper") {
                const original=JSON.stringify(Opal.Hub.prefs);
                view.item.draftArt=2;view.item.draftPath="";
                if(test.browse){view.item.tab="images";Opal.Hub.browseWallpaperFolder(Quickshell.env("HOME")+"/Pictures");}
                if(test.photo){view.item.draftPath="file://"+Quickshell.env("HOME")+"/Pictures/Wallpapers/Fixture-1.png";view.item.tab="images";Opal.Hub.browseWallpapers(Quickshell.env("HOME")+"/Pictures/Wallpapers");}
                if(JSON.stringify(Opal.Hub.prefs)!==original)console.error("ASSERTION_FAILED: preview mutated preferences");
            }
            if(test.drawer&&view.item.columns>7)console.error("ASSERTION_FAILED: unbounded touch grid");
            if(test.phone&&test.ui==="clipboard")view.item.touchMode=true;
            if(test.scroll)Qt.callLater(()=>scrollEnd(view.item));
            if(test.apps)view.item.keyboardOpen=true;
            if(test.search) {
                view.item.navigate("search");
                view.item.navigate("accept");
                view.item.navigate("right");
                view.item.navigate("accept");
                if(view.item.query!=="qw")console.error("ASSERTION_FAILED: controller keyboard",view.item.query);
            }
            if(test.menu) {
                view.item.navigate("menu");
                view.item.navigate("nextTab");
                if(view.item.menuTab!==1||view.item.menuIndex!==0)console.error("ASSERTION_FAILED: play hub category");
                view.item.navigate("down");
                if(view.item.menuIndex!==1)console.error("ASSERTION_FAILED: play hub selection");
                view.item.navigate("back");
                if(view.item.menuOpen)console.error("ASSERTION_FAILED: play hub back");
                view.item.navigate("menu");view.item.menuTab=test.section||0;view.item.menuIndex=0;
                if(test.nintendo&&view.item.acceptButton!=="B")console.error("ASSERTION_FAILED: swapped button hints");
            }
            if(test.ui==="console"&&!test.search&&!test.menu) {
                view.item.navigate("right");
                if(view.item.library.length>1&&view.item.selection!==1)console.error("ASSERTION_FAILED: controller grid");
                view.item.navigate("left");
            }
            if(test.ui==="shapes")Qt.callLater(()=>{
                if(view.item.enabledTile.radius>=view.item.disabledTile.radius)console.error("ASSERTION_FAILED: on/off shape morph");
                if(view.item.slider.handle.height<=view.item.slider.background.height)console.error("ASSERTION_FAILED: tall slider handle");
            });
            if(test.wheel)Qt.callLater(()=>{
                Opal.Hub.status=Object.assign({},Opal.Hub.status,{volume:40});
                input.mouseWheel(view.item,220,150,0,120);
                if(Opal.Hub.status.volume!==42)console.error("ASSERTION_FAILED: audio wheel volume");
                input.mouseWheel(view.item,220,277,0,120);
                if(Opal.Hub.status.volume!==44)console.error("ASSERTION_FAILED: audio slider wheel double handled");
                fixture.musicVolume=Opal.Hub.status.volume;
            });
            if(test.drag)Qt.callLater(()=>{
                input.mousePress(view.item,22,32,Qt.LeftButton);
                input.mouseMove(view.item,58,32,40);
                input.mouseMove(view.item,130,32,40);
                if(!view.item.dragging)console.error("ASSERTION_FAILED: taskbar mouse drag did not begin");
            });
            console.log("THEME",test.name,Opal.Theme.primary,Opal.Theme.onPrimary);
            capture.restart();
        }
        Timer {
            id:capture;interval:600
            onTriggered:{
                fixture.contentItem.grabToImage(result=>{
                    result.saveToFile(Quickshell.env("OPAL_TEST_OUTPUT")+"/"+fixture.cases[fixture.step].name+".png");
                    console.log("RENDERED",fixture.cases[fixture.step].name,view.item.width,view.item.height);
                    if(fixture.cases[fixture.step].drag){
                        input.mouseRelease(view.item,130,32,Qt.LeftButton);
                        if(view.item.dragging||(Opal.Hub.prefs.taskbarOrder||[]).indexOf("Fixture-0")<1)console.error("ASSERTION_FAILED: taskbar drop order");
                        if(Opal.Hub.pendingFocus!==null)console.error("ASSERTION_FAILED: taskbar drag activated window");
                    }
                    fixture.step++;Qt.callLater(fixture.next);
                });
            }
        }
        Component.onCompleted:Qt.callLater(next)
    }
}
