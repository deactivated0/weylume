import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import qs

PopupWindow {
    id: root
    Shortcut { sequence: "Escape"; enabled: root.visible; onActivated: root.dismiss() }

    property var anchorItem: null
    property var currentItem: null
    property bool menuVisible: false

    readonly property bool isAudioItem: root.currentItem?.id === "sys-audio"

    QsMenuOpener {
        id: dbusMenuOpener
        menu: root.currentItem?.rawItem?.menu ?? null
    }

    readonly property var rawDbusEntries: (dbusMenuOpener.children?.values ?? []).filter(entry => entry)
    readonly property var dbusEntries: sanitizeEntries(rawDbusEntries)
    readonly property bool hasDbusMenu: dbusEntries.length > 0
    readonly property var audioSinks: AudioService.sinks

    function isSinkDefault(node) {
        return AudioService.isSinkDefault(node);
    }

    function switchDefaultAudio(node) {
        if (!node) return;
        AudioService.setDefaultSink(node);
        root.dismiss();
    }

    function formatText(raw) {
        if (!raw) return "";
        let s = raw.replace(/&|_/g, "");
        if (s.includes("\t")) {
            s = s.split("\t")[0];
        }
        return s.trim();
    }

    function formatShortcut(raw) {
        if (!raw || !raw.includes("\t")) return "";
        let sc = raw.split("\t")[1].trim();
        return sc.replace(/Control/gi, "Ctrl");
    }

    function sanitizeEntries(rawList) {
        if (!rawList || rawList.length === 0) return [];
        let visibleItems = [];
        for (let i = 0; i < rawList.length; i++) {
            let e = rawList[i];
            if (!e) continue;
            let isSep = e.isSeparator ?? false;
            let txt = formatText(e.text ?? "");
            if (isSep || txt.length > 0) {
                visibleItems.push(e);
            }
        }

        let result = [];
        let prevWasSep = true;
        for (let i = 0; i < visibleItems.length; i++) {
            let e = visibleItems[i];
            let isSep = e.isSeparator ?? false;
            if (isSep) {
                if (!prevWasSep) {
                    result.push(e);
                    prevWasSep = true;
                }
            } else {
                result.push(e);
                prevWasSep = false;
            }
        }
        if (result.length > 0 && (result[result.length - 1].isSeparator ?? false)) {
            result.pop();
        }
        return result;
    }

    function getCleanAppTitle() {
        if (root.isAudioItem) return "Audio Output";
        let t = (root.currentItem?.title || "").trim();
        if (t.length > 0 && t !== "Tray App" && t !== "Application" && t !== "System Tray") {
            return t;
        }
        let tip = (root.currentItem?.tooltip || "").trim();
        if (tip.length > 0 && tip !== "Tray App") {
            return tip;
        }
        const id = (root.currentItem?.id || "").toLowerCase();
        const icon = (root.currentItem?.icon || "").toLowerCase();
        const combined = id + " " + icon;
        if (combined.includes("discord-development") || combined.includes("discorddevelopment")) return "Discord Development";
        if (combined.includes("discord-canary") || combined.includes("discordcanary")) return "Discord Canary";
        if (combined.includes("discord-ptb") || combined.includes("discordptb")) return "Discord PTB";
        if (combined.includes("discord")) return "Discord";
        if (combined.includes("vesktop")) return "Vesktop";
        if (combined.includes("steam")) return "Steam";
        if (combined.includes("easyeffects")) return "Easy Effects";

        for (let i = 0; i < dbusEntries.length; i++) {
            let txt = root.formatText(dbusEntries[i]?.text || "");
            if (txt.startsWith("Open ") && txt.length > 5) {
                return txt.substring(5).trim();
            }
        }
        for (let i = dbusEntries.length - 1; i >= 0; i--) {
            let txt = root.formatText(dbusEntries[i]?.text || "");
            if (txt.startsWith("Quit ") && txt.length > 5) {
                return txt.substring(5).trim();
            }
        }
        if (root.currentItem?.id) {
            let base = root.currentItem.id.split("_status_icon")[0].split("_snix_")[0].replace(/[-_]/g, " ").trim();
            if (base.length > 0 && !base.startsWith("app tray")) {
                return base.split(" ").map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(" ");
            }
        }
        return "Application";
    }

    function getHeaderIcon() {
        if (root.isAudioItem) return "assets/volume.svg";
        const ic = root.currentItem?.icon || "";
        const lower = ic.toLowerCase();
        const id = (root.currentItem?.id || "").toLowerCase();

        if (lower.includes("steam") || id.includes("steam")) return Quickshell.shellPath("assets/steam.svg");

        if (lower.includes("discord-development") || id.includes("discord-development") || id.includes("discorddevelopment")) {
            return Quickshell.iconPath("discord-development", Quickshell.iconPath("discord", "application-x-executable"));
        }
        if (lower.includes("discord-canary") || id.includes("discord-canary") || id.includes("discordcanary")) {
            return Quickshell.iconPath("discord-canary", Quickshell.iconPath("discord", "application-x-executable"));
        }
        if (lower.includes("discord-ptb") || id.includes("discord-ptb") || id.includes("discordptb")) {
            return Quickshell.iconPath("discord-ptb", Quickshell.iconPath("discord", "application-x-executable"));
        }
        if (lower.includes("discord") || id.includes("discord")) {
            return Quickshell.iconPath("discord", "application-x-executable");
        }

        if (ic.startsWith("/") || ic.startsWith("image://") || ic.startsWith("file://")) return ic;
        return Quickshell.iconPath(ic, "application-x-executable");
    }

    Timer {
        id: openTimer
        interval: 100
        repeat: false
        onTriggered: {
            if (root.currentItem && !root.menuVisible) {
                root.menuVisible = true;
            }
        }
    }

    onDbusEntriesChanged: {
        if (openTimer.running && dbusEntries.length > 0) {
            openTimer.stop();
            root.menuVisible = true;
        }
    }

    function openFor(item, trayData) {
        if (!item || !trayData) return;
        ShellState.taskMenusCloseRequested();
        openTimer.stop();
        menuVisible = false;
        currentItem = null;
        anchorItem = null;

        Qt.callLater(() => {
            anchorItem = item;
            currentItem = trayData;
            if (trayData.id === "sys-audio") {
                menuVisible = true;
            } else if (trayData.rawItem?.menu) {
                if (dbusEntries.length > 0) {
                    menuVisible = true;
                } else {
                    openTimer.start();
                }
            } else {
                menuVisible = true;
            }
        });
    }

    function dismiss() {
        openTimer.stop();
        menuVisible = false;
        currentItem = null;
        anchorItem = null;
    }

    Connections {
        target: ShellState
        function onTaskMenusCloseRequested() {
            if (root.menuVisible) {
                root.dismiss();
            }
        }
    }

    visible: menuVisible
    implicitWidth: root.isAudioItem ? 280 : 260
    implicitHeight: Math.min(520, mainCol.implicitHeight + 24)

    color: "transparent"
    grabFocus: true
    surfaceFormat.opaque: false
    anchor.item: anchorItem
    anchor.edges: Edges.Top | Edges.Right
    anchor.gravity: Edges.Top | Edges.Left

    onVisibleChanged: if (!visible) dismiss()

    Rectangle {
        id: shellBox
        anchors.fill: parent
        anchors.margins: 4
        radius: 12
        color: Theme.background
        border.width: 1
        border.color: Theme.border
        clip: true

        ColumnLayout {
            id: mainCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8
            spacing: 4

            // Header (Icon + Title)
            RowLayout {
                id: headerRow
                Layout.fillWidth: true
                Layout.margins: 4
                spacing: 8

                Rectangle {
                    width: 22; height: 22; radius: 5
                    color: "#080808"
                    border.width: 1
                    border.color: "#181818"

                    Image {
                        id: headerIconImg
                        anchors.centerIn: parent
                        width: 13; height: 13
                        sourceSize: Qt.size(28, 28)
                        source: root.getHeaderIcon()
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                        visible: status === Image.Ready
                    }

                    Text {
                        anchors.centerIn: parent
                        text: root.getCleanAppTitle().charAt(0).toUpperCase()
                        visible: !headerIconImg.visible
                        color: "#ffffff"
                        font.pixelSize: 10
                        font.weight: Font.Bold
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        text: root.getCleanAppTitle()
                        color: "#ffffff"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        text: root.isAudioItem ? (Math.round((Pipewire.defaultAudioSink?.audio?.volume ?? 0) * 100) + "% volume") : (root.currentItem?.isSystem ? "System Shortcut" : "Application")
                        color: "#777777"
                        font.family: Theme.fontFamily
                        font.pixelSize: 8
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: "#141414"
                Layout.topMargin: 1
                Layout.bottomMargin: 2
            }

            // Scrollable Items Section
            ScrollView {
                id: scrollItemsView
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(380, scrollContentCol.implicitHeight)
                Layout.maximumHeight: 380
                clip: true
                contentWidth: availableWidth
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                ColumnLayout {
                    id: scrollContentCol
                    width: scrollItemsView.availableWidth
                    spacing: 2

                    // 1. Audio Sinks List (When Right-Clicked Speaker)
                    Repeater {
                        model: root.isAudioItem ? root.audioSinks : []

                        Rectangle {
                            id: sinkItem
                            required property var modelData
                            required property int index
                            readonly property bool isDefault: root.isSinkDefault(sinkItem.modelData)

                            Layout.fillWidth: true
                            implicitHeight: 32
                            radius: 6
                            color: isDefault ? "#141414" : (sinkMouse.containsMouse ? "#101010" : "transparent")
                            border.width: 1
                            border.color: isDefault ? "#ffffff" : (sinkMouse.containsMouse ? "#242424" : "transparent")

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 8

                                Text {
                                    text: sinkItem.isDefault ? "✓" : " "
                                    color: "#ffffff"
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    Layout.preferredWidth: 12
                                }

                                Text {
                                    text: sinkItem.modelData.properties?.["node.description"] || sinkItem.modelData.properties?.["node.nick"] || sinkItem.modelData.name || "Audio Device"
                                    color: sinkItem.isDefault ? "#ffffff" : "#c0c0c0"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.weight: sinkItem.isDefault ? Font.DemiBold : Font.Normal
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                Text {
                                    text: Math.round((sinkItem.modelData.audio?.volume ?? 1.0) * 100) + "%"
                                    color: "#727272"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                }
                            }

                            MouseArea {
                                id: sinkMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.switchDefaultAudio(sinkItem.modelData)
                            }
                        }
                    }

                    // 2. DBus Menu Items (Discord, Steam, Easy Effects, etc.)
                    Repeater {
                        model: (root.currentItem && !root.isAudioItem) ? root.dbusEntries : []

                        ColumnLayout {
                            id: dbusEntryWrapper
                            required property var modelData
                            required property int index

                            property bool isExpanded: false

                            readonly property bool isSep: dbusEntryWrapper.modelData?.isSeparator ?? false
                            readonly property string rawText: dbusEntryWrapper.modelData?.text ?? ""
                            readonly property string itemText: root.formatText(rawText)
                            readonly property string shortcutText: root.formatShortcut(rawText)
                            readonly property bool hasChildren: dbusEntryWrapper.modelData?.hasChildren ?? false

                            visible: isSep || itemText.length > 0
                            Layout.fillWidth: true
                            spacing: 2

                            // Separator
                            Rectangle {
                                visible: dbusEntryWrapper.isSep
                                Layout.fillWidth: true
                                Layout.leftMargin: 4
                                Layout.rightMargin: 4
                                implicitHeight: 1
                                color: "#141414"
                                Layout.topMargin: 2
                                Layout.bottomMargin: 2
                            }

                            // Menu Entry Item
                            Rectangle {
                                visible: !dbusEntryWrapper.isSep
                                Layout.fillWidth: true
                                implicitHeight: 28
                                radius: 6
                                color: (dbusEntryWrapper.modelData?.enabled && (menuEntryMouse.containsMouse || dbusEntryWrapper.isExpanded)) ? "#121212" : "transparent"
                                border.width: 1
                                border.color: (dbusEntryWrapper.modelData?.enabled && (menuEntryMouse.containsMouse || dbusEntryWrapper.isExpanded)) ? "#202020" : "transparent"
                                opacity: (dbusEntryWrapper.modelData?.enabled ?? true) ? 1.0 : 0.4

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 6

                                    Text {
                                        visible: (dbusEntryWrapper.modelData?.checkState === Qt.Checked || dbusEntryWrapper.modelData?.checked === true)
                                        Layout.preferredWidth: 12
                                        horizontalAlignment: Text.AlignHCenter
                                        text: "✓"
                                        color: "#ffffff"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                    }

                                    Image {
                                        id: dbusIcon
                                        visible: (dbusEntryWrapper.modelData?.icon?.length > 0) && status === Image.Ready
                                        Layout.preferredWidth: 13
                                        Layout.preferredHeight: 13
                                        sourceSize: Qt.size(26, 26)
                                        source: {
                                            const ic = dbusEntryWrapper.modelData?.icon;
                                            if (!ic) return "";
                                            return (ic.startsWith("/") || ic.startsWith("image://") || ic.startsWith("file://")) ? ic : Quickshell.iconPath(ic, "");
                                        }
                                        fillMode: Image.PreserveAspectFit
                                        smooth: true
                                        mipmap: true
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: dbusEntryWrapper.itemText
                                        color: (menuEntryMouse.containsMouse || dbusEntryWrapper.isExpanded) ? "#ffffff" : "#e4e4e4"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        font.weight: (menuEntryMouse.containsMouse || dbusEntryWrapper.isExpanded) ? Font.DemiBold : Font.Normal
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        visible: dbusEntryWrapper.shortcutText.length > 0
                                        text: dbusEntryWrapper.shortcutText
                                        color: menuEntryMouse.containsMouse ? "#cccccc" : "#727272"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 9
                                    }

                                    Text {
                                        visible: dbusEntryWrapper.hasChildren
                                        text: dbusEntryWrapper.isExpanded ? "▾" : "›"
                                        color: (menuEntryMouse.containsMouse || dbusEntryWrapper.isExpanded) ? "#ffffff" : "#727272"
                                        font.pixelSize: dbusEntryWrapper.isExpanded ? 11 : 13
                                        Layout.preferredWidth: 10
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                }

                                MouseArea {
                                    id: menuEntryMouse
                                    anchors.fill: parent
                                    enabled: (dbusEntryWrapper.modelData?.enabled ?? true) && !dbusEntryWrapper.isSep
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (dbusEntryWrapper.hasChildren) {
                                            dbusEntryWrapper.isExpanded = !dbusEntryWrapper.isExpanded;
                                        } else {
                                            const entry = dbusEntryWrapper.modelData;
                                            root.dismiss();
                                            if (entry) {
                                                try { entry.triggered(); } catch (e) {
                                                    try { entry.sendTriggered(); } catch (e2) {}
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Submenu Opener & Nested Container
                            QsMenuOpener {
                                id: subMenuOpener
                                menu: (dbusEntryWrapper.hasChildren && dbusEntryWrapper.isExpanded) ? dbusEntryWrapper.modelData : null
                            }

                            readonly property var rawSubEntries: (subMenuOpener.children?.values ?? []).filter(sub => sub)
                            readonly property var subEntries: root.sanitizeEntries(rawSubEntries)

                            ColumnLayout {
                                id: subMenuCol
                                visible: dbusEntryWrapper.hasChildren && dbusEntryWrapper.isExpanded && dbusEntryWrapper.subEntries.length > 0
                                Layout.fillWidth: true
                                Layout.leftMargin: 10
                                spacing: 2

                                Repeater {
                                    model: subMenuCol.visible ? dbusEntryWrapper.subEntries : []

                                    Item {
                                        id: subItemWrapper
                                        required property var modelData
                                        required property int index

                                        readonly property bool subIsSep: subItemWrapper.modelData?.isSeparator ?? false
                                        readonly property string subRawText: subItemWrapper.modelData?.text ?? ""
                                        readonly property string subItemText: root.formatText(subRawText)
                                        readonly property string subShortcut: root.formatShortcut(subRawText)

                                        visible: subIsSep || subItemText.length > 0
                                        Layout.fillWidth: true
                                        implicitHeight: visible ? (subIsSep ? 6 : 26) : 0

                                        Rectangle {
                                            visible: subItemWrapper.subIsSep
                                            anchors.centerIn: parent
                                            width: parent.width - 6
                                            height: 1
                                            color: "#181818"
                                        }

                                        Rectangle {
                                            visible: !subItemWrapper.subIsSep
                                            anchors.fill: parent
                                            radius: 5
                                            color: (subItemWrapper.modelData?.enabled && subMouse.containsMouse) ? "#161616" : "transparent"
                                            border.width: 1
                                            border.color: (subItemWrapper.modelData?.enabled && subMouse.containsMouse) ? "#242424" : "transparent"
                                            opacity: (subItemWrapper.modelData?.enabled ?? true) ? 1.0 : 0.4

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 6
                                                anchors.rightMargin: 6
                                                spacing: 6

                                                Text {
                                                    visible: (subItemWrapper.modelData?.checkState === Qt.Checked || subItemWrapper.modelData?.checked === true)
                                                    Layout.preferredWidth: 10
                                                    horizontalAlignment: Text.AlignHCenter
                                                    text: "✓"
                                                    color: "#ffffff"
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 9
                                                    font.weight: Font.Bold
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: subItemWrapper.subItemText
                                                    color: subMouse.containsMouse ? "#ffffff" : "#d0d0d0"
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 9
                                                    font.weight: subMouse.containsMouse ? Font.DemiBold : Font.Normal
                                                    elide: Text.ElideRight
                                                }

                                                Text {
                                                    visible: subItemWrapper.subShortcut.length > 0
                                                    text: subItemWrapper.subShortcut
                                                    color: subMouse.containsMouse ? "#cccccc" : "#686868"
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 8
                                                }
                                            }

                                            MouseArea {
                                                id: subMouse
                                                anchors.fill: parent
                                                enabled: (subItemWrapper.modelData?.enabled ?? true) && !subItemWrapper.subIsSep
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    const subEntry = subItemWrapper.modelData;
                                                    root.dismiss();
                                                    if (subEntry) {
                                                        try { subEntry.triggered(); } catch (e) {
                                                            try { subEntry.sendTriggered(); } catch (e2) {}
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // 3. Fallback Open Action (For Apps Without DBus Menu)
                    Rectangle {
                        visible: !root.hasDbusMenu && !root.isAudioItem
                        Layout.fillWidth: true
                        implicitHeight: 28
                        radius: 6
                        color: openMouse.containsMouse ? "#121212" : "transparent"
                        border.width: 1
                        border.color: openMouse.containsMouse ? "#202020" : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            Text {
                                Layout.fillWidth: true
                                text: "Open " + root.getCleanAppTitle()
                                color: "#ffffff"
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: openMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const it = root.currentItem;
                                root.dismiss();
                                if (it) {
                                    if (it.activate) it.activate();
                                    else if (it.secondaryActivate) it.secondaryActivate();
                                }
                            }
                        }
                    }

                    // 4. EarTrumpet Flyout Trigger (When Right-Clicked Speaker)
                    Rectangle {
                        visible: root.isAudioItem
                        Layout.fillWidth: true
                        implicitHeight: 28
                        radius: 6
                        color: openMixerMouse.containsMouse ? "#121212" : "transparent"
                        border.width: 1
                        border.color: openMixerMouse.containsMouse ? "#202020" : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            Text {
                                Layout.fillWidth: true
                                text: "Open Volume Mixer"
                                color: "#ffffff"
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                            }

                            Text {
                                text: "›"
                                color: "#727272"
                                font.pixelSize: 12
                            }
                        }

                        MouseArea {
                            id: openMixerMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.dismiss();
                                ShellState.toggleMixer();
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: "#141414"
                Layout.topMargin: 2
                Layout.bottomMargin: 2
            }

            // Pin / Unpin Action Row
            Rectangle {
                id: pinToggleRow
                readonly property bool isPinned: root.currentItem ? TrayConfig.isPinned(root.currentItem) : false
                Layout.fillWidth: true
                implicitHeight: 28
                radius: 6
                color: pinToggleMouse.containsMouse ? "#121212" : "transparent"
                border.width: 1
                border.color: pinToggleMouse.containsMouse ? "#202020" : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        text: pinToggleRow.isPinned ? "Hide from taskbar" : "Pin to taskbar"
                        color: "#c0c0c0"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                    }
                }

                MouseArea {
                    id: pinToggleMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const it = root.currentItem;
                        root.dismiss();
                        if (it) TrayConfig.toggle(it);
                    }
                }
            }
        }
    }
}
