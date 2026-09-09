import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: center
    property bool unreadOnly: false
    property bool confirmClear: false
    readonly property var filtered: {
        const revision = Notifier.revision;
        const query = search.text.trim().toLowerCase();
        return Notifier.inbox.filter(e => (!unreadOnly || !e.read) &&
            (!query || (e.notification.appName + " " + e.notification.summary + " " + e.notification.body).toLowerCase().includes(query)));
    }
    Component.onCompleted: Notifier.centerOpen = true
    Component.onDestruction: Notifier.centerOpen = false
    ColumnLayout {
        anchors.fill: parent; spacing: 12
        RowLayout {
            Layout.fillWidth: true
            ColumnLayout {
                Layout.fillWidth: true; spacing: 3
                MText { text: "Notifications"; font.pixelSize: 23; font.weight: Font.DemiBold }
                MText { text: Notifier.inbox.length + " in your inbox"; font.pixelSize: 12; color: Theme.subtext }
            }
            MButton { icon: Hub.dnd ? "quiet" : "bell"; tonal: Hub.dnd; compact: true; tooltip: Hub.dnd ? "Turn off Do not disturb" : "Turn on Do not disturb"; onClicked: Hub.set("dnd", !Hub.dnd) }
        }
        Rectangle {
            visible: Hub.dnd; Layout.fillWidth: true; implicitHeight: quietText.implicitHeight+22
            radius: 12; color: Theme.alpha(Theme.primary,.1)
            MText { id: quietText; anchors {fill:parent;margins:11} text: "Do not disturb is on. New notifications stay here silently."; wrapMode: Text.Wrap; font.pixelSize: 12; color: Theme.subtext }
        }
        TextField {
            id: search; Layout.fillWidth: true; implicitHeight: 42
            placeholderText: "Search notifications"; color: Theme.text; placeholderTextColor: Theme.muted
            font.family: Theme.font; font.pixelSize: 13; leftPadding: 12; selectByMouse: true
            background: Rectangle { radius: 12; color: Theme.alpha(Theme.surfaceHigh,.4); border.width: search.activeFocus ? 2 : 1; border.color: search.activeFocus ? Theme.primary : Theme.outline }
            Accessible.name: "Search notifications"
        }
        RowLayout {
            Layout.fillWidth: true; spacing: 4
            MButton { text: "All"; compact: true; filled: !center.unreadOnly; onClicked: center.unreadOnly=false }
            MButton { text: "Unread"; compact: true; filled: center.unreadOnly; onClicked: center.unreadOnly=true }
            Item { Layout.fillWidth: true }
            MButton { text: "Clear all"; compact: true; enabled: Notifier.inbox.length>0; onClicked: center.confirmClear=!center.confirmClear }
        }
        RowLayout {
            visible: center.confirmClear; Layout.fillWidth: true
            MText { text: "Dismiss every notification?"; wrapMode: Text.Wrap; Layout.fillWidth: true; font.pixelSize: 12 }
            MButton { text: "Cancel"; compact: true; onClicked: center.confirmClear=false }
            MButton { text: "Clear"; compact: true; filled: true; onClicked: {Notifier.clear();center.confirmClear=false;} }
        }
        ListView {
            id: list; Layout.fillWidth: true; Layout.fillHeight: true
            model: center.filtered; clip: true; spacing: 8; boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            delegate: NotificationCard { required property var modelData; entry: modelData; width: list.width; }
            ColumnLayout {
                anchors.centerIn: parent; width: Math.max(0,parent.width-32); visible: list.count===0; spacing: 10
                Glyph { Layout.alignment: Qt.AlignHCenter; name: search.text || center.unreadOnly ? "search" : "bell"; color: Theme.muted; font.pixelSize: 32 }
                MText { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: search.text ? "No matching notifications" : center.unreadOnly ? "No unread notifications" : "No notifications"; font.pixelSize: 16; font.weight: Font.DemiBold; wrapMode: Text.Wrap }
                MText { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: search.text ? "Try another app name or keyword." : "New notifications will appear here."; color: Theme.subtext; font.pixelSize: 12; wrapMode: Text.Wrap }
            }
        }
        MButton { visible: Notifier.unread>0; text: "Mark all as read"; compact: true; Layout.alignment: Qt.AlignRight; onClicked: Notifier.markAllRead() }
    }
}
