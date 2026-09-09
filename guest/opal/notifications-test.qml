import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import "." as Opal

ShellRoot {
    Window {
        id: fixture; width: 420; height: 760; visible: true; color: Opal.Theme.base
        Opal.Surface { anchors.fill:parent }
        Loader { id: center; anchors {fill:parent;margins:20} active:false; sourceComponent: Component {Opal.NotificationCenter {}} }
        Column {
            anchors {left:parent.left;right:parent.right;top:parent.top;margins:12} spacing:10; visible:!center.active
            Repeater {model:Opal.Notifier.popups;Opal.NotificationCard {required property var modelData;entry:modelData;popup:true;width:parent.width}}
        }
    }
    IpcHandler {
        target: "test"
        function inspect(): string {
            return JSON.stringify({unread:Opal.Notifier.unread, count:Opal.Notifier.inbox.length,
                popups:Opal.Notifier.popups.length, entries:Opal.Notifier.entries.map(e=>({id:e.notification.id,summary:e.notification.summary,popup:e.popup,read:e.read,remaining:e.remaining}))});
        }
        function dnd(value: bool): void { Opal.Hub.prefs=Object.assign({},Opal.Hub.prefs,{dnd:value}); }
        function hover(value: bool): void { Opal.Notifier.popups.forEach(e=>e.hovered=value); }
        function centerOpen(value: bool): void { center.active=value; }
        function clear(): void { Opal.Notifier.clear(); }
        function theme(light: bool): void { Opal.Hub.prefs=Object.assign({},Opal.Hub.prefs,{light:light}); }
        function capture(path: string): void {fixture.contentItem.grabToImage(image=>image.saveToFile(path));}
        function quit(): void {Qt.quit();}
    }
}
