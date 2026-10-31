pragma Singleton
import QtQuick
import QtQml.Models
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs

Scope {
    id: root
    property var currentNotification: null
    property var history: []
    property var liveNotifications: ({})
    property bool loaded: false

    function appKey(notification) {
        return String(notification.desktopEntry || notification.appName || notification.appIcon || "unknown").trim().toLowerCase();
    }

    function isMuted(notification) {
        const raw = SettingsService.mutedNotificationApps;
        if (!raw || raw.trim().length === 0) return false;
        const key = appKey(notification);
        const parts = raw.split(",");
        for (let i = 0; i < parts.length; ++i) {
            if (parts[i].trim().toLowerCase() === key) return true;
        }
        return false;
    }

    function safeHint(hints, key, fallback) {
        const value = hints && hints[key] !== undefined ? hints[key] : fallback;
        return typeof value === "string" || typeof value === "number" || typeof value === "boolean" ? value : fallback;
    }

    function serialize(notification) {
        const timestamp = Date.now();
        const existing = root.history.find(item => root.liveNotifications[item.key] === notification
            || (notification.lastGeneration && item.id === String(notification.id ?? "")
                && appKey(item) === appKey(notification)));
        const key = existing?.key || appKey(notification) + ":" + String(notification.id ?? "") + ":" + timestamp;
        const actionItems = [];
        const actions = notification.actions || [];
        for (let index = 0; index < actions.length; ++index) {
            actionItems.push({
                index: index,
                identifier: String(actions[index].identifier || ""),
                text: String(actions[index].text || "Open")
            });
        }
        const hints = notification.hints || ({});
        return {
            key: key,
            id: String(notification.id ?? ""),
            timestamp: notification.lastGeneration && existing ? existing.timestamp : timestamp,
            summary: String(notification.summary || "Notification").slice(0, 1024),
            body: String(notification.body || "").slice(0, 16384),
            appName: String(notification.appName || ""),
            appIcon: String(notification.appIcon || "dialog-information"),
            desktopEntry: String(notification.desktopEntry || ""),
            image: String(notification.image || ""),
            urgency: Number(notification.urgency ?? 1),
            category: String(safeHint(hints, "category", "")),
            progress: Number(safeHint(hints, "value", -1)),
            resident: Boolean(notification.resident),
            transient: Boolean(notification.transient),
            expireTimeout: Number(notification.expireTimeout ?? -1),
            hasInlineReply: Boolean(notification.hasInlineReply),
            inlineReplyPlaceholder: String(notification.inlineReplyPlaceholder || ""),
            actions: actionItems
        };
    }

    function releaseIfUnowned(notification) {
        if (!notification || notification === root.currentNotification) return;
        for (const k in root.liveNotifications) {
            if (root.liveNotifications[k] === notification) return;
        }
        try { notification.expire(); } catch (error) {}
    }

    function trimHistory(items) {
        const trimmed = items.slice(0, Math.max(10, SettingsService.notificationHistoryLimit));
        const previous = root.liveNotifications;
        const retained = ({});
        for (let index = 0; index < trimmed.length; ++index) {
            const key = trimmed[index].key;
            if (previous[key]) retained[key] = previous[key];
        }
        root.liveNotifications = retained;
        for (const key of Object.keys(previous))
            if (!retained[key]) releaseIfUnowned(previous[key]);
        return trimmed;
    }

    function handleNotification(notification) {
        if (!notification) return;
        if (isMuted(notification)) {
            notification.expire();
            return;
        }
        notification.tracked = true;
        const item = serialize(notification);
        if (!item.transient) {
            const live = Object.assign({}, root.liveNotifications);
            live[item.key] = notification;
            root.liveNotifications = live;
            root.history = trimHistory([item].concat(root.history.filter(previous => previous.key !== item.key)));
            saveTimer.restart();
        }

        if (!SettingsService.dndEnabled && !(SettingsService.gamingMode && SettingsService.gamingDnd)) {
            const previous = root.currentNotification;
            root.currentNotification = notification;
            root.releaseIfUnowned(previous);
            root.currentNotificationKey = item.key;
            expiry.interval = Math.max(1500, notification.expireTimeout > 0
                ? notification.expireTimeout * 1000 : SettingsService.notificationTimeout);
            expiry.restart();
            if (SettingsService.notificationSounds && SystemService.has("canberra-gtk-play"))
                SystemService.enqueue(["notification-sound"], "notification", "notification-sound", true);
        } else if (item.transient) {
            // Transient notifications have no history owner and would otherwise
            // remain tracked indefinitely while DND is active.
            notification.expire();
        }
    }

    function refreshNotification(notification) {
        if (!notification) return;
        const item = serialize(notification);
        const index = root.history.findIndex(previous => previous.key === item.key);
        if (index < 0) return;
        const next = root.history.slice();
        item.timestamp = next[index].timestamp;
        next[index] = item;
        root.history = next;
        saveTimer.restart();
    }

    function closedNotification(notification) {
        const next = Object.assign({}, root.liveNotifications);
        const keys = Object.keys(next).filter(key => next[key] === notification);
        for (const key of keys) delete next[key];
        root.liveNotifications = next;
        root.history = root.history.map(item => keys.includes(item.key)
            ? Object.assign({}, item, { actions: [], hasInlineReply: false, closed: true }) : item);
        if (root.currentNotification === notification) {
            root.currentNotification = null;
            root.currentNotificationKey = "";
            expiry.stop();
        }
        if (keys.length) saveTimer.restart();
    }

    Instantiator {
        model: {
            const items = Object.values(root.liveNotifications);
            if (root.currentNotification && !items.includes(root.currentNotification)) items.push(root.currentNotification);
            return items;
        }
        delegate: Connections {
            required property var modelData
            target: modelData
            function onClosed(reason) { root.closedNotification(modelData); }
            function onSummaryChanged() { root.refreshNotification(modelData); }
            function onBodyChanged() { root.refreshNotification(modelData); }
            function onActionsChanged() { root.refreshNotification(modelData); }
            function onHintsChanged() { root.refreshNotification(modelData); }
        }
    }

    function clearAll() {
        const notifications = Object.values(root.liveNotifications);
        if (root.currentNotification && !notifications.includes(root.currentNotification))
            notifications.push(root.currentNotification);
        root.history = [];
        root.liveNotifications = ({});
        root.currentNotification = null;
        root.currentNotificationKey = "";
        expiry.stop();
        for (const notification of notifications) {
            try { notification.dismiss(); } catch (error) {}
        }
        saveTimer.restart();
    }

    function removeAt(idx) {
        const key = root.history[idx]?.key || "";
        const live = root.liveNotifications[key];
        const nextLive = Object.assign({}, root.liveNotifications);
        delete nextLive[key];
        root.liveNotifications = nextLive;
        if (key && key === root.currentNotificationKey) {
            root.currentNotification = null;
            root.currentNotificationKey = "";
            expiry.stop();
        }
        root.history = root.history.filter((_, i) => i !== idx);
        if (live) {
            try { live.dismiss(); } catch (error) {}
        }
        saveTimer.restart();
    }

    function invokeAction(item, actionIndex) {
        const notification = root.liveNotifications[item?.key || ""];
        if (!notification) return false;
        const actions = notification.actions || [];
        const index = Number(actionIndex);
        if (index < 0 || index >= actions.length) return false;
        try {
            actions[index].invoke();
            return true;
        } catch (error) {
            return false;
        }
    }

    function dismissCurrent() {
        const key = root.currentNotificationKey;
        const notification = root.currentNotification;
        root.currentNotification = null;
        root.currentNotificationKey = "";
        expiry.stop();
        if (notification) {
            try { notification.dismiss(); } catch (error) {}
        }
        if (key) {
            const nextLive = Object.assign({}, root.liveNotifications);
            delete nextLive[key];
            root.liveNotifications = nextLive;
        }
    }

    function activateNotification(item) {
        if (!item) return;
        if (!item.key && item.actions?.length > 0) {
            try {
                item.actions[0].invoke();
                return;
            } catch (error) {}
        }
        if (item.actions?.length > 0 && invokeAction(item, item.actions[0].index)) return;

        // 2. Extract and open URLs if present in text
        const fullText = (item.summary || "") + " " + (item.body || "");
        const urlMatch = fullText.match(new RegExp("https?://[^\\s)>\\]'\\\"]+", "i"));
        if (urlMatch) {
            Quickshell.execDetached(["xdg-open", urlMatch[0]]);
            return;
        }

        // 3. Launch associated application
        const application = item.desktopEntry || item.appName || item.appIcon || "";
        if (application) {
            const entry = DesktopEntries.heuristicLookup(application);
            if (entry) entry.execute();
            else {
                const binary = application.trim().toLowerCase();
                if (new RegExp("^[a-z0-9._+-]+$").test(binary)) Quickshell.execDetached([binary]);
            }
        }
    }

    property string currentNotificationKey: ""

    function mergeHistory(items) {
        const current = root.history;
        const keys = new Set(current.map(item => item.key));
        const carried = new Set();
        const identity = item => JSON.stringify([appKey(item), item.id]);
        const restoredById = new Map(items.filter(item => item && typeof item.summary === "string")
            .map(item => [identity(item), item]));
        const retained = current.map(item => {
            if (!root.liveNotifications[item.key]?.lastGeneration) return item;
            const id = identity(item);
            carried.add(id);
            const previous = restoredById.get(id);
            return previous ? Object.assign({}, item, {timestamp: previous.timestamp}) : item;
        });
        const restored = SettingsService.persistentNotificationHistory
            ? items.filter(item => item && typeof item.summary === "string"
                && !keys.has(item.key) && !carried.has(identity(item)))
                .map(item => Object.assign({}, item, {actions: [], hasInlineReply: false, closed: true})) : [];
        root.history = root.trimHistory(retained.concat(restored));
    }

    FileView {
        id: historyStore
        path: StateStore.ready && SettingsService.initialized ? Quickshell.shellPath("notification_history.json") : ""
        onLoaded: {
            const firstLoad = !root.loaded;
            try {
                const parsed = JSON.parse(text() || "{}");
                const items = Array.isArray(parsed.history) ? parsed.history : [];
                root.mergeHistory(items);
            } catch (error) { console.warn("Notification history load failed", error); }
            root.loaded = true;
            if (firstLoad && Object.keys(root.liveNotifications).length) saveTimer.restart();
        }
    }

    Timer {
        id: saveTimer
        interval: 300
        onTriggered: {
            if (!root.loaded || !SettingsService.persistentNotificationHistory) return;
            historyStore.setText(JSON.stringify({ version: 1, history: root.history }, null, 2) + "\n");
        }
    }

    Timer {
        id: expiry
        interval: SettingsService.notificationTimeout
        onTriggered: {
            const notification = root.currentNotification;
            // Retain non-transient objects so Notification Center actions stay
            // valid; transient objects are released immediately.
            root.currentNotification = null;
            root.currentNotificationKey = "";
            root.releaseIfUnowned(notification);
        }
    }

    // Build the toast only while a notification is on screen.
    LazyLoader {
        active: root.currentNotification !== null

        PanelWindow {
            id: toastWindow
            visible: root.currentNotification !== null
            implicitWidth: 420
            implicitHeight: Math.max(96, toastCardLayout.implicitHeight + 28)
            color: "transparent"
            anchors { top: true; right: true }
            margins { top: 20; right: 20 }
            exclusiveZone: 0
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "weylume-notification"

            Rectangle {
                id: toastCard
                anchors.fill: parent
                radius: 24
                color: "#000000"
                border.width: 1
                border.color: cardMouse.containsMouse ? "#303030" : "#202020"
                clip: true

                ColumnLayout {
                    id: toastCardLayout
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10

                    // Main Row: [Icon] [Meta + Title + Subtitle] [Time + View Pill]
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 14

                        // 1. App Icon Squircle Box
                        Rectangle {
                            Layout.preferredWidth: 54
                            Layout.preferredHeight: 54
                            Layout.alignment: Qt.AlignVCenter
                            radius: 18
                            color: "#0a0a0a"
                            border.width: 1
                            border.color: "#202020"

                            Image {
                                anchors.centerIn: parent
                                width: 34
                                height: 34
                                sourceSize: Qt.size(68, 68)
                                source: {
                                    const notif = root.currentNotification;
                                    if (notif?.image) return notif.image;
                                    const icon = notif?.appIcon || "dialog-information";
                                    const lower = icon.toLowerCase();
                                    if (lower === "steam" || lower.includes("steam")) return Quickshell.shellPath("assets/steam.svg");
                                    if (lower === "discord" || lower.includes("discord")) return Quickshell.iconPath("discord", "dialog-information");
                                    return (icon.startsWith("/") || icon.startsWith("image://") || icon.startsWith("file://")) ? icon : Quickshell.iconPath(icon, "dialog-information");
                                }
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                mipmap: true
                                visible: status === Image.Ready
                            }
                        }

                        // 2. Metadata, Title & Body
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 2

                            // App Name Meta
                            Text {
                                text: (root.currentNotification?.appName || "SYSTEM").toUpperCase()
                                color: "#a7a7ad"
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                                font.letterSpacing: 0.5
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            // Notification Summary / Title
                            Text {
                                text: root.currentNotification?.summary || "Notification"
                                color: "#f7f7f7"
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.weight: Font.Bold
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            // Notification Body / Subtitle
                            Text {
                                visible: (root.currentNotification?.body || "").length > 0
                                text: root.currentNotification?.body || ""
                                color: "#a7a7ad"
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.Normal
                                textFormat: Text.PlainText
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        // 3. Action Stack: Timestamp + Action Pill / Close
                        ColumnLayout {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 8

                            // Time + Close
                            RowLayout {
                                Layout.alignment: Qt.AlignRight
                                spacing: 6

                                Text {
                                    text: "Just now"
                                    color: "#a7a7ad"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    font.weight: Font.Medium
                                }

                                Rectangle {
                                    width: 18
                                    height: 18
                                    radius: 9
                                    color: closeToastMouse.containsMouse ? "#222222" : "#101010"
                                    border.width: 1
                                    border.color: closeToastMouse.containsMouse ? "#333333" : "#202020"
                                    z: 10

                                    Text {
                                        anchors.centerIn: parent
                                        text: "✕"
                                        color: closeToastMouse.containsMouse ? "#ffffff" : "#888888"
                                        font.pixelSize: 8
                                        font.weight: Font.Bold
                                    }

                                    MouseArea {
                                        id: closeToastMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.dismissCurrent()
                                    }
                                }
                            }

                            // Action Pill Button ("View" or primary action)
                            Rectangle {
                                id: actionPill
                                Layout.alignment: Qt.AlignRight
                                implicitWidth: Math.max(76, actionPillText.implicitWidth + 24)
                                implicitHeight: 30
                                radius: 15
                                color: actPillMouse.containsMouse ? "#202020" : "#111111"
                                border.width: 1
                                border.color: actPillMouse.containsMouse ? "#3a3a3a" : "#222222"
                                z: 10

                                Text {
                                    id: actionPillText
                                    anchors.centerIn: parent
                                    text: {
                                        const actions = root.currentNotification?.actions;
                                        if (actions && actions.length > 0) return actions[0].text || "View";
                                        return "View";
                                    }
                                    color: "#ffffff"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                }

                                MouseArea {
                                    id: actPillMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        const notif = root.currentNotification;
                                        const actions = notif?.actions;
                                        if (actions && actions.length > 0 && typeof actions[0].invoke === "function") {
                                             actions[0].invoke();
                                        } else {
                                            const key = root.currentNotificationKey;
                                            const item = root.history.find(entry => entry.key === key) || notif;
                                            root.activateNotification(item);
                                        }
                                        if (notif?.resident) {
                                            root.currentNotification = null;
                                            root.currentNotificationKey = "";
                                        } else {
                                            root.dismissCurrent();
                                        }
                                        ShellState.openNotifications();
                                    }
                                }
                            }
                        }
                    }

                    // Extra Action Buttons Row (if notification has multiple actions)
                    RowLayout {
                        visible: root.currentNotification?.actions !== undefined && root.currentNotification?.actions.length > 1
                        Layout.fillWidth: true
                        spacing: 8

                        Repeater {
                            model: (root.currentNotification?.actions || []).slice(1)

                            Rectangle {
                                required property var modelData
                                required property int index

                                Layout.fillWidth: true
                                implicitHeight: 28
                                radius: 14
                                color: extraActMouse.containsMouse ? "#202020" : "#111111"
                                border.width: 1
                                border.color: extraActMouse.containsMouse ? "#3a3a3a" : "#222222"
                                z: 10

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.text || "Action"
                                    color: "#f0f0f0"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                }

                                MouseArea {
                                    id: extraActMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (typeof modelData.invoke === "function") {
                                            modelData.invoke();
                                        }
                                        if (root.currentNotification?.resident) {
                                            root.currentNotification = null;
                                            root.currentNotificationKey = "";
                                        } else {
                                            root.dismissCurrent();
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Click entire background to activate notification
                MouseArea {
                    id: cardMouse
                    anchors.fill: parent
                    z: -1
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: expiry.stop()
                    onExited: expiry.restart()
                    onClicked: {
                        const key = root.currentNotificationKey;
                        const item = root.history.find(entry => entry.key === key) || root.currentNotification;
                        const resident = Boolean(root.currentNotification?.resident);
                        root.activateNotification(item);
                        if (resident) {
                            root.currentNotification = null;
                            root.currentNotificationKey = "";
                        } else {
                            root.dismissCurrent();
                        }
                        ShellState.openNotifications();
                    }
                }
            }
        }
    }
}
