pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: h
    property var prefs: ({mode:"desktop", palette:0, light:false, glass:0.78, favorites:[], recent:[], wallpaper:0, wallpaperPath:"", wallpaperFit:"crop", wallpaperDim:.15, desktopWidgets:true, dynamicColors:false, dynamicPalette:{}, colorScheme:"scheme-tonal-spot"})
    property var status: ({workspace:1, workspaces:[], windows:[], title:"Your desktop", volume:0, muted:false, network:"Connecting…", wifi:false, bluetooth:false, track:"", artist:"", art:"", playing:false, battery:-1, charging:false, brightness:-1, cpu:0, memory:0, uptime:"", profile:"", hypr:false})
    property var connectivity: ({wifi:{items:[],busy:false,error:"",powered:false},bluetooth:{items:[],busy:false,error:"",powered:false}})
    property string controlDetail: ""
    function connection(kind,verb,extra) { command(Object.assign({action:"connectivity",kind:kind,verb:verb},extra||{})); }
    property bool audioOpen:false
    property var audioScreen:null
    onAudioScreenChanged:if(!audioScreen)audioOpen=false
    function openAudio(screen) {audioScreen=screen||chooseScreen();controlDetail="";page="";audioOpen=true;}
    function closeAudio() {audioOpen=false;}
    function toggleAudio(screen) {if(audioOpen)closeAudio();else openAudio(screen);}
    function audioScroll(steps,screen) {openAudio(screen);volume(Math.max(0,Math.min(100,status.volume+steps*2)));}
    property string page: ""
    onPageChanged:if(page!=="")closeAudio()
    property string category: "All apps"
    property string query: ""
    property string calculation: ""
    readonly property bool dnd: Notifier.dnd
    property bool keepAwake: false
    property bool themeBusy: false
    property var wallpaperLibrary: []
    property var wallpaperFolders: []
    property string wallpaperFolder:""
    property string wallpaperParent:""
    function browseWallpaperFolder(folder) {
        wallpaperRequest++;wallpaperLibraryBusy=true;wallpaperLibraryError="";
        command({action:"wallpaper-list",folder:folder||"",browse:true,request:wallpaperRequest});
    }
    property bool wallpaperLibraryBusy: false
    property string wallpaperLibraryError: ""
    property int wallpaperRequest: 0
    function browseWallpapers(folder) {
        wallpaperRequest++;wallpaperLibraryBusy=true;wallpaperLibraryError="";
        command({action:"wallpaper-list",folder:folder||"",request:wallpaperRequest});
    }
    property bool gameSession: false
    property date gameStarted: new Date()
    readonly property int gameMinutes: gameSession ? Math.max(0,Math.floor((now-gameStarted)/60000)) : 0
    function toggleGameSession() {
        if(!gameSession)gameStarted=new Date();
        gameSession=!gameSession;
        message(gameSession ? "Play session on · popups quiet, idle inhibited, shelf hidden" : "Play session ended · your settings are unchanged");
    }
    property bool controller: false
    property string controllerName: ""
    property bool systemOskAvailable:false
    property bool systemOskRunning:false
    property bool systemOskVisible:false
    property string systemOskDetail:""
    readonly property bool systemOskReady:systemOskAvailable&&systemOskRunning
    property var clipboardItems: []
    property bool clipboardPaused: false
    property bool clipboardAvailable: false
    property string clipboardDetail: "Starting clipboard service"
    property string clipboardPendingId: ""
    property bool clipboardCloseAfterCopy: true
    property var gameArt: ({})
    function artFor(app) {
        if(!app)return {}

        const match=((app.execString||"")+" "+app.id).match(/(?:rungameid\/|run\/|steam_app_)(\d+)/);
        return match ? gameArt[match[1]]||{} : {}

    }
    property string toast: ""
    property string osd: ""
    property int focusSeconds: 25*60
    property bool focusRunning: false
    property bool preferencesLoaded: false
    // Normalize desktop entries once; search, taskbar, and window cards all use
    // these indexes instead of scanning the complete application list.
    property var apps: DesktopEntries.applications.values.filter(a => !a.noDisplay).sort((a,b) => a.name.localeCompare(b.name))
    readonly property var appIndex: {
        const index=Object.create(null);
        const add=(value,app) => {
            const key=String(value||"").toLowerCase().replace(/\.desktop$/i,"").trim();
            if(key && !index[key]) index[key]=app;
        };
        apps.forEach(a => {
            add(a.id,a); add(a.startupClass,a);
        });
        // Exact identifiers win over the legacy basename fallback.
        apps.forEach(a => {
            add(String(a.id||"").split(".").pop(),a);
        });
        return index;
    }
    readonly property var appSearchIndex: apps.map(a => ({
        app:a,
        name:String(a.name||"").toLowerCase(),
        hay:(String(a.name||"")+" "+String(a.genericName||"")+" "+(a.keywords||[]).join(" ")).toLowerCase(),
        categories:(a.categories||[]).join(" ").toLowerCase()
    }))
    property var favoriteApps: {
        let ids = prefs.favorites;
        if (prefs.pinsConfigured || ids.length) return ids.map(id => appIndex[String(id).toLowerCase()]).filter(Boolean);
        const choices = ["firefox", "google-chrome", "chromium", "kitty", "org.kde.dolphin", "org.gnome.Nautilus", "steam", "code", "org.kde.kate"];
        return choices.map(id => appIndex[id.toLowerCase()]).filter(Boolean).slice(0,6);
    }
    property var dockScreen: null
    property bool dockNotice: false
    property bool displaysReady: false
    property var knownDisplays: []
    property var resolvedDisplays: Quickshell.screens.map(s=>({name:s.name,mode:layoutFor(s.width,s.height,s.name)}))
    property string displayLayoutState:JSON.stringify({mode:prefs.mode,displays:resolvedDisplays})
    onDisplayLayoutStateChanged:if(preferencesLoaded)layoutSync.restart()
    onPreferencesLoadedChanged:if(preferencesLoaded)layoutSync.restart()
    Timer {id:layoutSync;interval:200;onTriggered:if(h.preferencesLoaded&&["auto","desktop","phone","console"].indexOf(h.prefs.mode)>=0&&h.resolvedDisplays.every(d=>d.name!==""))h.command({action:"display-layouts",mode:h.prefs.mode,displays:h.resolvedDisplays})}
    property var displayTopology: Quickshell.screens.map(s=>s.name)
    onDisplayTopologyChanged: updateDisplays(Quickshell.screens)
    function updateDisplays(screens) {
        if(!displaysReady)return;
        const names=screens.map(s=>s.name);
        const added=screens.filter(s=>knownDisplays.indexOf(s.name)<0);
        knownDisplays=names;
        if(dockScreen&&names.indexOf(dockScreen.name)<0) {dockNotice=false;dockScreen=null;}
        if(added.length) {dockScreen=added[added.length-1];dockNotice=true;dockTimer.restart();}
    }
    Timer {interval:3000;running:true;onTriggered:{h.knownDisplays=h.displayTopology.slice();h.displaysReady=true;}}
    Timer {id:dockTimer;interval:30000;onTriggered:h.dockNotice=false}
    function pauseDockNotice(){if(dockNotice)dockTimer.stop();}
    function resumeDockNotice(){if(dockNotice)dockTimer.restart();}
    function useDockedWorkspace(phoneScreen) {
        if(!dockScreen)return;
        const overrides=Object.assign({},prefs.displayModes||{});
        if(phoneScreen)overrides[phoneScreen.name]="phone";
        overrides[dockScreen.name]="desktop";
        set("displayModes",overrides);
        targetScreen=dockScreen;dockNotice=false;
        mode("auto");openSection("apps");
    }
    property var targetScreen: null
    function chooseScreen() {
        return Quickshell.screens.find(s=>s.name===status.activeMonitor) ||
            (ToplevelManager.activeToplevel && ToplevelManager.activeToplevel.screens.length ? ToplevelManager.activeToplevel.screens[0] : null) || Quickshell.screens[0];
    }
    property string launcherSection: "apps"
    property string mobileTab: "home"
    // Resource telemetry changes frequently; compositor topology does not. Keep
    // the latter on its own properties so every CPU tick does not rebuild the
    // taskbar's complete window grouping model.
    property bool compositorActive: false
    property var compositorWindows: []
    property var windows: compositorActive ? compositorWindows : ToplevelManager.toplevels.values.map(w => ({title:w.title,className:w.appId,handle:w,workspace:0,address:""}))
    property var taskGroups: {
        let groups=[];
        const byKey=Object.create(null);
        const addGroup=(key,app,name,icon) => {
            key=key||"unknown";
            let group=byKey[key];
            if(!group) {group={app:app,key:key,name:name,icon:icon,windows:[]};byKey[key]=group;groups.push(group);}
            return group;
        };
        favoriteApps.forEach(app => addGroup(app.id,app,app.name,app.icon));
        windows.forEach(w => {
            const app=appForWindow(w);
            const key=app ? app.id : w.className;
            const group=addGroup(key,app,app ? app.name : w.className||w.title,app ? app.icon : "application-x-executable");
            group.windows.push(w);
        });
        const order=prefs.taskbarOrder||[];
        return groups.sort((a,b)=>{const ai=order.indexOf(a.key),bi=order.indexOf(b.key);return (ai<0 ? order.length : ai)-(bi<0 ? order.length : bi);});
    }
    function reorderTask(key,index) {
        let order=taskGroups.map(g=>g.key);const from=order.indexOf(key);
        if(from<0||index<0||index>=order.length)return;
        order.splice(from,1);order.splice(index,0,key);
        set("taskbarOrder",order.concat((prefs.taskbarOrder||[]).filter(k=>order.indexOf(k)<0)).slice(0,128));
    }
    property var recentApps: prefs.recent.map(id => appIndex[String(id).toLowerCase()]).filter(Boolean).slice(0,6)
    readonly property var inbox: Notifier.inbox
    readonly property int unread: Notifier.unread
    property date now: clock.date
    signal navigate(string key)
    function command(data) { bridge.write(JSON.stringify(data)+"\n"); }
    function systemOsk(verb) { command({action:"system-osk",verb:verb||"toggle"}); }
    function set(key,value) { let p = Object.assign({},prefs); p[key]=value; prefs=p; command({action:"preference",key:key,value:value}); }
    function toggle(p) { page = page === p ? "" : p; if(page === "launcher") query = ""; }
    function mode(m) { if(m==="phone") {const screen=targetScreen||chooseScreen();if(screen)set("phoneDisplay",screen.name);} set("mode",m); page=""; query=""; mobileTab="home"; launcherSection="apps"; category=m==="console" ? "Games" : "All apps"; }
    function close() { page="";closeAudio(); }
    function launch(app) {
        if(!app)return;
        const running=windows.filter(w=>appForWindow(w)===app);
        if(running.length){command({action:"recent",id:app.id});activateGroup({app:app,windows:running});}
        else launchNew(app);
    }
    function launchNew(app) {if(!app)return;command({action:"recent",id:app.id});app.execute();page="";}
    function pinned(app) { return prefs.favorites.indexOf(app.id)>=0; }
    function pin(app) { command({action:"pin",id:app.id,initial:favoriteApps.map(a=>a.id)}); }
    function settings(which) { if(which==="network"||which==="bluetooth") {controlDetail=which==="network" ? "wifi" : which;page="controls";return;} page=""; command({action:"settings",which:which}); }
    function volume(value) { command({action:"volume",value:value}); let s=Object.assign({},status); s.volume=Math.round(value); status=s; }
    function workspace(n) { if(status.hypr)command({action:"workspace",number:Number(n)}); }
    property var pendingFocus:null
    function focusWindow(w) {
        // Release layer-shell keyboard exclusivity before transferring app focus.
        pendingFocus=w;close();focusTransfer.restart();
    }
    Timer {id:focusTransfer;interval:100;onTriggered:{
        const w=h.pendingFocus;h.pendingFocus=null;if(!w)return;
        if(h.status.hypr&&w.address)h.command({action:"focus-window",address:w.address});
        else if(w.handle)w.handle.activate();
    }}
    function closeWindow(w) {
        if(w.handle) w.handle.close();
        else if(status.hypr) Quickshell.execDetached(["hyprctl","dispatch","closewindow","address:"+w.address]);
    }
    function displayMode(name,mode) {
        const overrides=Object.assign({},prefs.displayModes||{});
        if(mode==="auto")delete overrides[name];else overrides[name]=mode;
        set("displayModes",overrides);
    }
    function layoutFor(width,height,name) {
        if(prefs.mode==="phone"&&name) {
            const phoneName=prefs.phoneDisplay||(Quickshell.screens[0] ? Quickshell.screens[0].name : "");
            return name===phoneName ? "phone" : "desktop";
        }
        if(prefs.mode!=="auto") return prefs.mode;
        const override=(prefs.displayModes||{})[name];
        if(override)return override;
        return width<680 || (height>width && width<1000) ? "phone" : "desktop";
    }
    function openSection(section) { launcherSection=section;if(section==="windows")mobileTab="recent";page=section==="windows"&&prefs.mode==="console" ? "windows" : "launcher"; }
    function appForWindow(w) {
        const key=String(w.className||"").toLowerCase().replace(/\.desktop$/i,"").trim();
        return appIndex[key]||null;
    }
    function active(w) { return w.handle ? w.handle.activated : w.address===status.activeAddress; }
    function activateGroup(g) {
        if(!g.windows.length) { if(g.app)launch(g.app);return; }
        let index=g.windows.findIndex(w=>active(w));
        focusWindow(g.windows[(index+1)%g.windows.length]);
    }
    function appMenu(app) {
        if(!app)return [];
        const matching=windows.filter(w=>appForWindow(w)===app);
        let entries=[{text:"Open new instance",icon:"add",run:()=>launchNew(app)},
                     {text:pinned(app) ? "Unpin from taskbar" : "Pin to taskbar",icon:"pin",run:()=>pin(app)}];
        (app.actions||[]).forEach(a=>entries.push({text:a.name,icon:"next",run:()=>{a.execute();close();}}));
        matching.forEach(w=>entries.push({text:"Switch to "+w.title,icon:"desktop",run:()=>focusWindow(w)}));
        if(matching.length) entries.push({text:"Close "+matching.length+" window"+(matching.length===1 ? "" : "s"),icon:"close",run:()=>matching.forEach(w=>closeWindow(w))});
        return entries;
    }
    function windowMenu(w) {
        let entries=[{text:"Switch to window",icon:"desktop",run:()=>focusWindow(w)}];
        if(w.handle) {
            entries.push({text:w.handle.maximized ? "Restore size" : "Maximize",icon:"expand",run:()=>w.handle.maximized=!w.handle.maximized});
            entries.push({text:"Minimize",icon:"sleep",run:()=>w.handle.minimized=true});
        }
        if(status.hypr) status.workspaces.filter(n=>n!==w.workspace).forEach(n=>entries.push({text:"Move to workspace "+n,icon:"next",run:()=>Quickshell.execDetached(["hyprctl","dispatch","movetoworkspacesilent",n+",address:"+w.address])}));
        entries.push({text:"Close window",icon:"close",run:()=>closeWindow(w)});
        return entries;
    }
    function taskbarMenu() {
        return [{text:"All applications",icon:"apps",run:()=>openSection("apps")},
                {text:"Running windows",icon:"desktop",run:()=>openSection("windows")},
                {text:prefs.taskbarAutoHide ? "Keep taskbar visible" : "Auto-hide taskbar",icon:"expand",run:()=>set("taskbarAutoHide",!prefs.taskbarAutoHide)},
                {text:prefs.taskbarLabels===false ? "Show app names" : "Icons only",icon:"list",run:()=>set("taskbarLabels",prefs.taskbarLabels===false)},
                {text:"Convergence",icon:"expand",run:()=>page="convergence"},
                {text:"Personalize",icon:"palette",run:()=>page="appearance"}];
    }
    function message(s) { toast=s; toastTimer.restart(); }
    function screenShot() { close(); command({action:"screenshot"}); }
    function media(verb) { command({action:"media",verb:verb}); }
    function refreshClipboard() { command({action:"clipboard-list"}); }
    function toggleClipboard() { page=page==="clipboard" ? "" : "clipboard";if(page==="clipboard")refreshClipboard(); }
    function copyClipboard(id,closeAfter) {
        clipboardPendingId=id;clipboardCloseAfterCopy=closeAfter!==false;
        command({action:"clipboard-copy",id:id});
    }
    function deleteClipboard(id) { command({action:"clipboard-delete",id:id}); }
    function clearClipboard() { command({action:"clipboard-clear"}); }
    function pauseClipboard() { command({action:"clipboard-pause",paused:!clipboardPaused}); }
    function timerToggle() { if(focusSeconds<=0) focusSeconds=25*60; focusRunning=!focusRunning; }
    function searchApps(text,cat) {
        const q=text.toLowerCase().trim();
        const categories = {Games:["game"], Create:["graphics","audiovideo","audio","video"], Work:["office","development","education"], System:["system","settings","utility"], Internet:["network"]};

        const source = cat === "Pinned" ? favoriteApps.map(a => ({app:a,name:String(a.name||"").toLowerCase(),hay:(String(a.name||"")+" "+String(a.genericName||"")+" "+(a.keywords||[]).join(" ")).toLowerCase(),categories:(a.categories||[]).join(" ").toLowerCase()})) : appSearchIndex;
        const category=categories[cat];
        return source.map(record => {
            const a=record.app;
            const name=record.name;
            if(category && !category.some(token => record.categories.indexOf(token)>=0)) return null;
            let score=0;
            if(q) {
                if(name===q) score=1000;
                else if(name.startsWith(q)) score=800;
                else if(name.indexOf(q)>=0) score=600;
                else if(record.hay.indexOf(q)>=0) score=400;
                else { let j=0; for(let i=0;i<name.length && j<q.length;i++) if(name[i]===q[j]) j++; if(j===q.length) score=100-name.length; else return null; }
            }
            return {app:a,score:score}

        }).filter(Boolean).sort((a,b)=>b.score-a.score||a.app.name.localeCompare(b.app.name)).map(x=>x.app);
    }
    SystemClock { id: clock; precision: SystemClock.Seconds }
    Process {
        id: bridge
        command: ["/usr/local/bin/aurora-opal-bridge"]
        running: true
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                try {
                    const e=JSON.parse(line);
                    if(e.event === "status") {
                        if (h.preferencesLoaded && (e.data.volume !== h.status.volume || e.data.muted !== h.status.muted)) { h.osd=e.data.muted ? "Volume muted" : "Volume  " + e.data.volume + "%"; osdTimer.restart(); }
                        h.status=Object.assign({},h.status,e.data);
                    } else if(e.event === "compositor") {
                        if (e.data.hypr !== undefined) h.compositorActive=!!e.data.hypr;
                        if (e.data.windows !== undefined) h.compositorWindows=e.data.windows;
                        h.status=Object.assign({},h.status,e.data);
                    } else if(e.event === "preferences") {
                        h.prefs=e.data;
                        // Startup/reload must NEVER open a keyboard-exclusive overlay.
                        // Only an explicit user action may open the drawer.
                        h.preferencesLoaded=true;
                    } else if(e.event === "wallpapers" && e.request===h.wallpaperRequest) {
                        h.wallpaperLibrary=e.items;h.wallpaperLibraryError=e.error;h.wallpaperLibraryBusy=false;
                        if(!e.error){h.wallpaperFolders=e.folders||[];h.wallpaperFolder=e.folder||"";h.wallpaperParent=e.parent||"";}
                    } else if(e.event === "connectivity") {
                        let data=Object.assign({},h.connectivity);
                        data[e.kind]=Object.assign({},data[e.kind],e);h.connectivity=data;
                    } else if(e.event === "themeBusy") h.themeBusy=e.busy;
                    else if(e.event === "message") h.message(e.text);
                    else if(e.event === "controller") { h.controller=e.connected;h.controllerName=e.name||""; }
                    else if(e.event === "systemOsk") {h.systemOskAvailable=!!e.available;h.systemOskRunning=!!e.running;h.systemOskVisible=!!e.visible;h.systemOskDetail=e.detail||"";}
                    else if(e.event === "libraryArt") h.gameArt=e.data;
                    else if(e.event === "navigation" && h.prefs.mode === "console") { if(e.key==="home") h.toggle("launcher"); else if(h.page!=="") h.navigate(e.key); }
                    else if(e.event === "calculation" && e.query===h.query.slice(1).trim()) h.calculation=e.result;
                    else if(e.event === "clipboard") {
                        h.clipboardItems=e.items||[];h.clipboardPaused=!!e.paused;
                        h.clipboardAvailable=!!e.available;h.clipboardDetail=e.detail||"";
                    } else if(e.event === "clipboardCopied") {
                        if(e.id===h.clipboardPendingId) {
                            if(e.success&&h.clipboardCloseAfterCopy)h.close();
                            h.clipboardPendingId="";
                        }
                        h.message(e.success ? "Copied. Ctrl+V to paste." : "Couldn’t copy this entry.");
                    }
                } catch(error) { console.warn("Opal bridge:",error); }
            }
        }
        onExited: (code,status) => { h.message("System bridge stopped. Restart Opal to reconnect."); }
    }
    Timer { id: toastTimer; interval: 4500; onTriggered: h.toast="" }
    Timer { id: osdTimer; interval: 1800; onTriggered: h.osd="" }
    Timer { interval:1000; running:h.focusRunning; repeat:true; onTriggered: { h.focusSeconds--; if(h.focusSeconds<=0) { h.focusRunning=false; h.message("Focus complete. Time to take a breath."); Quickshell.execDetached(["notify-send","-a","Opal","Focus complete","Time to take a break."]); } } }
}
