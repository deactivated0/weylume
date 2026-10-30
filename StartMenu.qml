import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

PopupWindow {
    id: root
    required property var anchorItem
    property bool allProgramsView: false
    property bool commandMode: false

    visible: ShellState.startOpen
    implicitWidth: Math.min(SettingsService.startMenuWidth, Math.max(160, (ShellState.popupScreen?.width || 1920) - 8))
    implicitHeight: Math.min((SettingsService.startMenuHeight), Math.max(120, (ShellState.popupScreen?.height || 1080) - Theme.taskbarHeight - 12))
    color: "transparent"
    grabFocus: true
    surfaceFormat.opaque: false
    anchor.item: anchorItem
    anchor.edges: Edges.Top | Edges.Left
    anchor.gravity: Edges.Top | Edges.Right

    property bool powerMenuOpen: false

    Timer {
        id: powerCloseTimer
        interval: 500
        onTriggered: root.powerMenuOpen = false
    }

    property string navZone: "left" // "left", "right", "allPrograms"
    property int navIndex: 0
    property bool navActive: false
    property var expandedCategories: ({})

    function isCategoryExpanded(catId) {
        if (search.text.trim() !== "") return true;
        return Boolean(expandedCategories[catId]);
    }

    function toggleCategory(catId, explicitState) {
        const current = isCategoryExpanded(catId);
        const next = explicitState !== undefined ? Boolean(explicitState) : !current;
        const copy = Object.assign({}, expandedCategories);
        copy[catId] = next;
        expandedCategories = copy;
    }

    readonly property var categorizedApps: (root.allProgramsView || search.text.trim() !== "") ? getCategorizedApps() : []

    readonly property var visibleLeftNodes: {
        if (!root.allProgramsView && search.text.trim() === "") {
            const favs = StartFavorites.items || [];
            const list = [];
            for (let i = 0; i < favs.length; i++) {
                list.push({
                    type: "favorite",
                    index: i,
                    data: favs[i],
                    id: "fav:" + i
                });
            }
            return list;
        } else if (search.text.trim() !== "") {
            const cats = categorizedApps;
            const nodes = [];
            for (let c = 0; c < cats.length; c++) {
                const cat = cats[c];
                for (let a = 0; a < cat.apps.length; a++) {
                    const app = cat.apps[a];
                    nodes.push({
                        type: "app",
                        catId: cat.id,
                        appIndex: a,
                        data: app,
                        id: "app:" + (app.id || app.name)
                    });
                }
            }
            return nodes;
        } else {
            const cats = categorizedApps;
            const nodes = [];
            for (let c = 0; c < cats.length; c++) {
                const cat = cats[c];
                const expanded = isCategoryExpanded(cat.id);
                nodes.push({
                    type: "category",
                    catId: cat.id,
                    catIndex: c,
                    data: cat,
                    expanded: expanded,
                    id: "cat:" + cat.id
                });
                if (expanded) {
                    for (let a = 0; a < cat.apps.length; a++) {
                        const app = cat.apps[a];
                        nodes.push({
                            type: "app",
                            catId: cat.id,
                            appIndex: a,
                            data: app,
                            id: "app:" + (app.id || app.name)
                        });
                    }
                }
            }
            return nodes;
        }
    }

    function openDirectory(targetPath) {
        if (!targetPath) return;
        let resolved = targetPath;
        if (resolved.startsWith("~")) {
            resolved = (Quickshell.env("HOME") || "") + resolved.slice(1);
        }
        if (SystemService.has("pcmanfm-qt")) {
            Quickshell.execDetached(["pcmanfm-qt", resolved]);
        } else {
            Quickshell.execDetached(["xdg-open", resolved]);
        }
    }

    readonly property var visibleRightItems: {
        const list = [];
        if (SettingsService.startShowUserFolder) {
            list.push({ id: "user", label: Quickshell.env("USER") || "User Home", icon: "user-home", path: SettingsService.startPathUserFolder || Quickshell.env("HOME") });
        }
        if (SettingsService.startShowDocuments) {
            list.push({ id: "docs", label: "Documents", icon: "folder-documents", path: SettingsService.startPathDocuments || (Quickshell.env("HOME") + "/Documents") });
        }
        if (SettingsService.startShowPictures) {
            list.push({ id: "pics", label: "Pictures", icon: "folder-pictures", path: SettingsService.startPathPictures || (Quickshell.env("HOME") + "/Pictures") });
        }
        if (SettingsService.startShowMusic) {
            list.push({ id: "music", label: "Music", icon: "folder-music", path: SettingsService.startPathMusic || (Quickshell.env("HOME") + "/Music") });
        }
        if (SettingsService.startShowDownloads) {
            list.push({ id: "down", label: "Downloads", icon: "folder-download", path: SettingsService.startPathDownloads || (Quickshell.env("HOME") + "/Downloads") });
        }
        if (SettingsService.startCustomFolder1Path && SettingsService.startCustomFolder1Path.trim()) {
            list.push({ id: "custom1", label: SettingsService.startCustomFolder1Name.trim() || "Folder 1", icon: "folder", path: SettingsService.startCustomFolder1Path.trim() });
        }
        if (SettingsService.startCustomFolder2Path && SettingsService.startCustomFolder2Path.trim()) {
            list.push({ id: "custom2", label: SettingsService.startCustomFolder2Name.trim() || "Folder 2", icon: "folder", path: SettingsService.startCustomFolder2Path.trim() });
        }
        if (SettingsService.startShowThisPC) {
            list.push({ id: "thispc", label: "This PC", icon: "computer", path: SettingsService.startPathThisPC || "/mnt" });
        }
        if (SettingsService.startShowSettings) {
            list.push({ id: "settings", label: "Settings", icon: "preferences-desktop", action: "settings" });
        }
        if (SettingsService.startShowTerminal) {
            list.push({ id: "terminal", label: "Terminal", icon: "utilities-terminal", action: "terminal" });
        }
        return list;
    }

    readonly property string currentSelectedId: {
        if (!navActive || navZone !== "left") return "";
        const nodes = visibleLeftNodes;
        if (navIndex >= 0 && navIndex < nodes.length) return nodes[navIndex].id || "";
        return "";
    }

    function handleNavDown(event) {
        const nodes = visibleLeftNodes;
        if (!navActive) {
            if (nodes.length > 0) {
                event.accepted = true;
                navActive = true;
                navZone = "left";
                navIndex = 0;
            }
            return;
        }
        event.accepted = true;
        if (navZone === "left") {
            const maxIdx = nodes.length - 1;
            if (navIndex < maxIdx) {
                navIndex++;
            } else if (!root.allProgramsView && search.text.trim() === "") {
                navZone = "allPrograms";
            } else {
                navIndex = 0;
            }
        } else if (navZone === "allPrograms") {
            navZone = "left";
            navIndex = 0;
        } else if (navZone === "right") {
            const count = visibleRightItems.length;
            if (count > 0) {
                navIndex = (navIndex + 1) % count;
            } else {
                navIndex = 0;
            }
        }
    }

    function handleNavUp(event) {
        const nodes = visibleLeftNodes;
        if (!navActive) {
            if (nodes.length > 0) {
                event.accepted = true;
                navActive = true;
                navZone = "left";
                navIndex = search.text.trim() !== "" ? 0 : Math.max(0, nodes.length - 1);
            }
            return;
        }
        event.accepted = true;
        if (navZone === "allPrograms") {
            navZone = "left";
            navIndex = Math.max(0, nodes.length - 1);
        } else if (navZone === "left") {
            if (navIndex > 0) {
                navIndex--;
            } else if (!root.allProgramsView && search.text.trim() === "") {
                navZone = "allPrograms";
            } else {
                navIndex = Math.max(0, nodes.length - 1);
            }
        } else if (navZone === "right") {
            const count = visibleRightItems.length;
            if (count > 0) {
                navIndex = (navIndex - 1 + count) % count;
            } else {
                navIndex = 0;
            }
        }
    }

    function handleNavRight(event) {
        if (!navActive) {
            event.accepted = true;
            navActive = true;
            navZone = "right";
            navIndex = 0;
            return;
        }
        event.accepted = true;
        if (navZone === "left") {
            const nodes = visibleLeftNodes;
            const node = (navIndex >= 0 && navIndex < nodes.length) ? nodes[navIndex] : null;
            if (node && node.type === "category" && !node.expanded) {
                toggleCategory(node.catId, true);
                return;
            }
            navZone = "right";
            const rightCount = visibleRightItems.length;
            navIndex = rightCount > 0 ? Math.min(rightCount - 1, Math.max(0, navIndex)) : 0;
        } else if (navZone === "allPrograms") {
            navZone = "right";
            const rightCount = visibleRightItems.length;
            navIndex = rightCount > 0 ? Math.min(rightCount - 1, Math.max(0, navIndex)) : 0;
        } else if (navZone === "right") {
            navZone = "left";
            const nodes = visibleLeftNodes;
            navIndex = Math.min(Math.max(0, nodes.length - 1), Math.max(0, navIndex));
        }
    }

    function handleNavLeft(event) {
        if (!navActive) {
            event.accepted = true;
            navActive = true;
            navZone = "left";
            navIndex = 0;
            return;
        }
        event.accepted = true;
        if (navZone === "right") {
            navZone = "left";
            const nodes = visibleLeftNodes;
            navIndex = Math.min(Math.max(0, nodes.length - 1), Math.max(0, navIndex));
        } else if (navZone === "left") {
            const nodes = visibleLeftNodes;
            const node = (navIndex >= 0 && navIndex < nodes.length) ? nodes[navIndex] : null;
            if (node && node.type === "app") {
                for (let i = navIndex - 1; i >= 0; i--) {
                    if (nodes[i].type === "category" && nodes[i].catId === node.catId) {
                        navIndex = i;
                        break;
                    }
                }
                return;
            } else if (node && node.type === "category" && node.expanded) {
                toggleCategory(node.catId, false);
                return;
            }
            navZone = "right";
            navIndex = Math.min(9, Math.max(0, navIndex));
        } else if (navZone === "allPrograms") {
            navZone = "right";
            navIndex = Math.min(9, Math.max(0, navIndex));
        }
    }

    function handleNavReturn(event) {
        event.accepted = true;
        if (root.commandMode && search.text.trim()) {
            Quickshell.execDetached(["sh", "-lc", search.text.trim()]);
            ShellState.closeFlyouts();
            return;
        }
        if (!navActive) {
            if (search.text.trim() !== "" && appModel.values.length > 0) {
                appModel.values[0].execute();
                ShellState.closeFlyouts();
            } else {
                const nodes = visibleLeftNodes;
                if (nodes.length > 0) {
                    launchLeftNode(nodes[0]);
                }
            }
            return;
        }
        if (navZone === "left") {
            const nodes = visibleLeftNodes;
            const node = (navIndex >= 0 && navIndex < nodes.length) ? nodes[navIndex] : null;
            if (node) launchLeftNode(node);
        } else if (navZone === "right") {
            launchRightItem(navIndex);
        } else if (navZone === "allPrograms") {
            root.allProgramsView = !root.allProgramsView;
            navZone = "left";
            navIndex = 0;
        }
    }

    function launchLeftNode(node) {
        if (!node) return;
        if (node.type === "category") {
            toggleCategory(node.catId);
        } else if (node.type === "app") {
            if (node.data && typeof node.data.execute === "function") {
                node.data.execute();
                ShellState.closeFlyouts();
            }
        } else if (node.type === "favorite") {
            const item = node.data;
            if (!item) return;
            if ((item.label || "").toLowerCase() === "settings") {
                ShellState.toggleSettings();
                return;
            } else if (item.command && item.command.length) {
                Quickshell.execDetached(item.command);
            } else if (item.execute) {
                item.execute();
            } else if (item.appIds?.[0]) {
                Quickshell.execDetached([item.appIds[0]]);
            } else if (item.label) {
                Quickshell.execDetached([item.label.toLowerCase()]);
            }
            ShellState.closeFlyouts();
        }
    }

    function launchRightItem(idx) {
        const items = visibleRightItems;
        if (idx < 0 || idx >= items.length) return;
        const item = items[idx];
        if (item.action === "settings") {
            ShellState.toggleSettings();
            return;
        } else if (item.action === "terminal") {
            Quickshell.execDetached(["kitty"]);
        } else if (item.path) {
            openDirectory(item.path);
        }
        ShellState.closeFlyouts();
    }

    function ensureVisibleInCatView(item) {
        if (!item || !catScrollView.visible) return;
        const flickable = catScrollView.contentItem;
        if (!flickable) return;
        const pos = item.mapToItem(catColumn, 0, 0);
        const targetY = pos.y;
        const itemH = item.height || 34;
        const viewH = catScrollView.height;
        const currentY = flickable.contentY;

        if (targetY < currentY) {
            flickable.contentY = Math.max(0, targetY - 6);
        } else if (targetY + itemH > currentY + viewH) {
            flickable.contentY = Math.min(Math.max(0, flickable.contentHeight - viewH), targetY + itemH - viewH + 6);
        }
    }

    function ensureVisibleInFavView(item) {
        if (!item || !favScrollView.visible) return;
        const flickable = favScrollView.contentItem;
        if (!flickable) return;
        const pos = item.mapToItem(leftCol, 0, 0);
        const targetY = pos.y;
        const itemH = item.height || 38;
        const viewH = favScrollView.height;
        const currentY = flickable.contentY;

        if (targetY < currentY) {
            flickable.contentY = Math.max(0, targetY - 6);
        } else if (targetY + itemH > currentY + viewH) {
            flickable.contentY = Math.min(Math.max(0, flickable.contentHeight - viewH), targetY + itemH - viewH + 6);
        }
    }

    Timer {
        id: focusTimer
        interval: 30
        onTriggered: search.forceActiveFocus()
    }

    onVisibleChanged: {
        if (visible) {
            allProgramsView = Boolean(SettingsService.startDefaultAllPrograms);
            if (commandMode) commandMode = false;
            if (search.text !== "") search.text = "";
            if (startContextMenu.visible) startContextMenu.dismiss();
            if (Object.keys(expandedCategories).length > 0) expandedCategories = ({});
            if (navZone !== "left") navZone = "left";
            if (navIndex !== 0) navIndex = 0;
            if (navActive) navActive = false;
            focusTimer.restart();
        } else {
            root.powerMenuOpen = false;
            if (ShellState.startOpen) {
                ShellState.startOpen = false;
            }
        }
    }

    readonly property var rawApplications: DesktopEntries.applications.values
    readonly property var _internalCache: ({ deduplicated: null, categorized: null })

    onRawApplicationsChanged: {
        _internalCache.deduplicated = null;
        _internalCache.categorized = null;
    }

    Timer {
        interval: 1200
        running: true
        repeat: false
        onTriggered: root.getBaseCategorizedApps()
    }

    function getDeduplicatedApps() {
        if (_internalCache.deduplicated) return _internalCache.deduplicated;
        const raw = DesktopEntries.applications.values;
        const seenNames = new Set();
        const seenIds = new Set();
        const unique = [];

        for (let i = 0; i < raw.length; i++) {
            const app = raw[i];
            if (!app || !app.name || !app.name.trim()) continue;

            const nameKey = app.name.trim().toLowerCase();
            const idKey = (app.id || "").trim().toLowerCase();

            if (seenNames.has(nameKey) || (idKey && seenIds.has(idKey))) {
                continue;
            }

            seenNames.add(nameKey);
            if (idKey) seenIds.add(idKey);
            unique.push(app);
        }
        _internalCache.deduplicated = unique;
        return unique;
    }

    readonly property var deduplicatedApps: (root.allProgramsView || search.text.trim() !== "") ? getDeduplicatedApps() : []

    QtObject {
        id: appModel
        readonly property var values: {
            const query = search.text.trim().toLowerCase();
            if (!query) return [];
            let apps = root.deduplicatedApps.filter(entry => {
                if (!entry || !entry.name) return false;
                return commandMode || entry.name.toLowerCase().includes(query);
            });
            apps.sort((a, b) => a.name.localeCompare(b.name));
            return apps;
        }
    }

    function getBaseCategorizedApps() {
        if (_internalCache.categorized) return _internalCache.categorized;
        const apps = getDeduplicatedApps();
        const catDefs = [
            { id: "waydroid", name: "Waydroid (Android)", icon: "applications-other", apps: [] },
            { id: "internet", name: "Internet & Network", icon: "applications-internet", apps: [] },
            { id: "games", name: "Games", icon: "applications-games", apps: [] },
            { id: "media", name: "Media & Entertainment", icon: "applications-multimedia", apps: [] },
            { id: "graphics", name: "Graphics & Design", icon: "applications-graphics", apps: [] },
            { id: "dev", name: "Development & Coding", icon: "applications-development", apps: [] },
            { id: "system", name: "System & Admin", icon: "applications-system", apps: [] },
            { id: "accessories", name: "Accessories & Utilities", icon: "applications-accessories", apps: [] },
            { id: "other", name: "Other Applications", icon: "applications-other", apps: [] }
        ];

        for (let i = 0; i < apps.length; i++) {
            const app = apps[i];
            const cats = (app.categories || []).map(c => c.toLowerCase());
            const name = (app.name || "").toLowerCase();
            const id = (app.id || "").toLowerCase();
            const exec = (app.exec || app.command?.[0] || "").toLowerCase();

            if (id.includes("waydroid") || exec.includes("waydroid") || cats.some(c => c.includes("waydroid")) || name.startsWith("waydroid")) {
                catDefs[0].apps.push(app);
            } else if (cats.some(c => c.includes("game")) || name.includes("steam") || name.includes("cemu") || name.includes("game") || name.includes("strike")) {
                catDefs[2].apps.push(app);
            } else if (cats.some(c => c.includes("network") || c.includes("web") || c.includes("chat") || c.includes("browser")) || name.includes("firefox") || name.includes("discord") || name.includes("browser") || name.includes("chat")) {
                catDefs[1].apps.push(app);
            } else if (cats.some(c => c.includes("audio") || c.includes("video") || c.includes("player")) || name.includes("mpv") || name.includes("spotify") || name.includes("vlc") || name.includes("media") || name.includes("music")) {
                catDefs[3].apps.push(app);
            } else if (cats.some(c => c.includes("graphics") || c.includes("photo") || c.includes("drawing") || c.includes("paint")) || name.includes("gimp") || name.includes("inkscape") || name.includes("paint") || name.includes("draw")) {
                catDefs[4].apps.push(app);
            } else if (cats.some(c => c.includes("development") || c.includes("ide") || c.includes("programming") || c.includes("editor") || c.includes("texteditor")) || name.includes("code") || name.includes("kate") || name.includes("featherpad") || name.includes("rust") || name.includes("edit")) {
                catDefs[5].apps.push(app);
            } else if (cats.some(c => c.includes("filemanager") || c.includes("filetools") || c.includes("utility") || c.includes("accessories") || c.includes("calc") || c.includes("archiv") || c.includes("compress")) || name.includes("file") || name.includes("thunar") || id.includes("thunar") || exec.includes("thunar") || name.includes("calc") || name.includes("archive") || name.includes("manager") || id.includes("org.kde.ark") || name.toLowerCase() === "ark") {
                catDefs[7].apps.push(app);
            } else if (cats.some(c => c.includes("system") || c.includes("settings") || c.includes("monitor") || c.includes("admin")) || name.includes("terminal") || name.includes("kitty") || name.includes("monitor") || name.includes("settings") || name.includes("tweak")) {
                catDefs[6].apps.push(app);
            } else {
                catDefs[8].apps.push(app);
            }
        }

        catDefs.forEach(c => c.apps.sort((a, b) => a.name.localeCompare(b.name)));
        _internalCache.categorized = catDefs.filter(c => c.apps.length > 0);
        return _internalCache.categorized;
    }

    function getCategorizedApps() {
        const base = getBaseCategorizedApps();
        const query = search.text.trim().toLowerCase();
        if (!query || commandMode) {
            return base;
        }

        const filtered = [];
        for (let i = 0; i < base.length; i++) {
            const cat = base[i];
            const matching = [];
            for (let j = 0; j < cat.apps.length; j++) {
                const app = cat.apps[j];
                const name = app._lcName || (app._lcName = (app.name || "").toLowerCase());
                const comment = app._lcComment || (app._lcComment = (app.comment || "").toLowerCase());
                if (name.includes(query) || (comment && comment.includes(query))) {
                    matching.push(app);
                }
            }
            if (matching.length > 0) {
                filtered.push({
                    id: cat.id,
                    name: cat.name,
                    icon: cat.icon,
                    apps: matching
                });
            }
        }
        return filtered;
    }

    Item {
        anchors.fill: parent

        // Main Card
        Rectangle {
            id: startCard
            anchors.fill: parent
            radius: 10
            border.width: 1
            border.color: Theme.border
            color: Theme.background
            clip: true

            // Background click dismisses context menu
            MouseArea {
                anchors.fill: parent
                z: 50
                enabled: startContextMenu.visible
                onClicked: startContextMenu.dismiss()
            }

            // Top highlight line
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 1
                color: Theme.isDark ? "#0effffff" : "#0e000000"
            }

            // Main Content Area (2 Columns)
            Item {
                id: mainArea
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                anchors.topMargin: 10
                anchors.bottomMargin: 86

                TapHandler {
                    onTapped: {
                        root.navActive = true;
                        search.forceActiveFocus();
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    spacing: 10

                    // Left Column Area (Toggles between Favorites and Categorized All Programs)
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: SettingsService.startCompactMode ? mainArea.width : (mainArea.width - 10) / 2

                        // View 1: Draggable Favorite Apps
                        ScrollView {
                            id: favScrollView
                            anchors.fill: parent
                            visible: !root.allProgramsView && search.text.trim() === ""
                            clip: true
                            contentWidth: availableWidth
                            contentHeight: leftCol.implicitHeight

                            ColumnLayout {
                                id: leftCol
                                width: parent.width
                                spacing: 2

                                Repeater {
                                    model: StartFavorites.items

                                    Rectangle {
                                        id: favRow
                                        required property var modelData
                                        required property int index
                                        readonly property bool isNavSelected: root.currentSelectedId === ("fav:" + favRow.index)
                                        onIsNavSelectedChanged: {
                                            if (isNavSelected) root.ensureVisibleInFavView(favRow);
                                        }
                                        Layout.fillWidth: true
                                        implicitHeight: 38
                                        radius: 6
                                        color: (favMouse.containsMouse || isNavSelected) ? Theme.cardHover : "transparent"
                                        border.width: isNavSelected ? 1 : 0
                                        border.color: isNavSelected ? Theme.accent : "transparent"

                                        Behavior on color { ColorAnimation { duration: SettingsService.reducedMotion ? 0 : 50 } }
                                        Behavior on border.color { ColorAnimation { duration: SettingsService.reducedMotion ? 0 : 50 } }
                                        focus: favMouse.containsMouse
                                        Keys.onDeletePressed: StartFavorites.removeByIndex(favRow.index)
                                        z: favMouse.drag.active ? 100 : 1
                                        opacity: favMouse.drag.active ? 0.85 : 1.0
                                        scale: favMouse.drag.active ? 1.03 : 1.0

                                        Behavior on scale { NumberAnimation { duration: SettingsService.reducedMotion ? 0 : 60 } }

                                        transform: Translate {
                                            y: dragHandle.y
                                        }

                                        Item {
                                            id: dragHandle
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 6
                                            anchors.rightMargin: 8
                                            spacing: 9

                                            Rectangle {
                                                Layout.preferredWidth: 28
                                                Layout.preferredHeight: 28
                                                radius: 6
                                                color: "transparent"
                                                border.width: 0

                                                Image {
                                                    id: favIcon
                                                    anchors.centerIn: parent
                                                    width: 22
                                                    height: 22
                                                    sourceSize: Qt.size(44, 44)
                                                    source: {
                                                        const ico = favRow.modelData.icon || "application-x-executable";
                                                        if (ico === "preferences-system" || ico === "weylume-settings" || favRow.modelData.label === "Settings") {
                                                            return Theme.settingsIcon;
                                                        }
                                                        return Quickshell.iconPath(ico);
                                                    }
                                                    fillMode: Image.PreserveAspectFit
                                                    smooth: true
                                                    mipmap: true
                                                    visible: status === Image.Ready
                                                }

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (favRow.modelData.label || favRow.modelData.name || "A").charAt(0).toUpperCase()
                                                    visible: favIcon.status !== Image.Ready
                                                    color: Theme.text
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 12
                                                    font.weight: Font.Bold
                                                }
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text: favRow.modelData.label || favRow.modelData.name || "App"
                                                color: Theme.text
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 12
                                                elide: Text.ElideRight
                                            }
                                        }

                                        MouseArea {
                                            id: favMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                                            drag.target: dragHandle
                                            drag.axis: Drag.YAxis
                                            drag.threshold: 2

                                            onClicked: event => {
                                                if (event.button === Qt.RightButton) {
                                                    startContextMenu.openFor(favRow, favRow.modelData);
                                                } else {
                                                    if ((favRow.modelData.label || "").toLowerCase() === "settings") {
                                                        ShellState.toggleSettings();
                                                        return;
                                                    } else if (favRow.modelData.command && favRow.modelData.command.length) {
                                                        Quickshell.execDetached(favRow.modelData.command);
                                                    } else if (favRow.modelData.execute) {
                                                        favRow.modelData.execute();
                                                    } else {
                                                        Quickshell.execDetached([favRow.modelData.appIds?.[0] || favRow.modelData.label.toLowerCase()]);
                                                    }
                                                    ShellState.closeFlyouts();
                                                }
                                            }

                                            onReleased: {
                                                if (dragHandle.y !== 0) {
                                                    const rowHeight = favRow.height + leftCol.spacing;
                                                    const offset = Math.round(dragHandle.y / rowHeight);
                                                    if (offset !== 0) {
                                                        const targetIdx = Math.max(0, Math.min(StartFavorites.items.length - 1, favRow.index + offset));
                                                        if (targetIdx !== favRow.index) {
                                                            StartFavorites.move(favRow.index, targetIdx);
                                                        }
                                                    }
                                                    dragHandle.y = 0;
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // View 2: Categorized All Programs (Stays within Left Column)
                        ScrollView {
                            id: catScrollView
                            anchors.fill: parent
                            visible: root.allProgramsView || search.text.trim() !== ""
                            clip: true
                            contentWidth: availableWidth
                            contentHeight: catColumn.implicitHeight

                            ColumnLayout {
                                id: catColumn
                                width: parent.width
                                spacing: 4

                                Repeater {
                                    model: root.categorizedApps

                                    ColumnLayout {
                                        id: catGroup
                                        required property var modelData
                                        property bool expanded: root.isCategoryExpanded(catGroup.modelData.id)

                                        Layout.fillWidth: true
                                        spacing: 2

                                        // Category Header Folder (Collapsed by Default)
                                        Rectangle {
                                            id: catHeader
                                            readonly property bool isNavSelected: root.currentSelectedId === ("cat:" + catGroup.modelData.id)
                                            onIsNavSelectedChanged: {
                                                if (isNavSelected) root.ensureVisibleInCatView(catHeader);
                                            }
                                            Layout.fillWidth: true
                                            implicitHeight: 34
                                            radius: 6
                                            color: (catMouse.containsMouse || isNavSelected) ? Theme.cardHover : "transparent"
                                            border.width: isNavSelected ? 1 : 0
                                            border.color: isNavSelected ? Theme.accent : "transparent"

                                            Behavior on color { ColorAnimation { duration: SettingsService.reducedMotion ? 0 : 50 } }
                                            Behavior on border.color { ColorAnimation { duration: SettingsService.reducedMotion ? 0 : 50 } }

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 8
                                                anchors.rightMargin: 10
                                                spacing: 9

                                                Image {
                                                    Layout.preferredWidth: 18
                                                    Layout.preferredHeight: 18
                                                    sourceSize: Qt.size(36, 36)
                                                    source: Quickshell.iconPath(catGroup.modelData.icon, "folder")
                                                    fillMode: Image.PreserveAspectFit
                                                    smooth: true
                                                    mipmap: true
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: catGroup.modelData.name + " (" + catGroup.modelData.apps.length + ")"
                                                    color: Theme.text
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 12
                                                    font.weight: Font.DemiBold
                                                    elide: Text.ElideRight
                                                }

                                                Text {
                                                    text: catGroup.expanded ? "▾" : "▸"
                                                    color: Theme.muted
                                                    font.pixelSize: 14
                                                }
                                            }

                                            MouseArea {
                                                id: catMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                onClicked: root.toggleCategory(catGroup.modelData.id)
                                            }
                                        }

                                        // Category App Items
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.leftMargin: 14
                                            spacing: 1
                                            visible: catGroup.expanded

                                            Repeater {
                                                model: catGroup.expanded ? catGroup.modelData.apps : []

                                                Rectangle {
                                                    id: appItemRow
                                                    required property var modelData
                                                    readonly property bool isNavSelected: root.currentSelectedId === ("app:" + (appItemRow.modelData.id || appItemRow.modelData.name))
                                                    onIsNavSelectedChanged: {
                                                        if (isNavSelected) root.ensureVisibleInCatView(appItemRow);
                                                    }
                                                    Layout.fillWidth: true
                                                    implicitHeight: 32
                                                    radius: 5
                                                    color: (appItemMouse.containsMouse || isNavSelected) ? Theme.cardHover : "transparent"
                                                    border.width: isNavSelected ? 1 : 0
                                                    border.color: isNavSelected ? Theme.accent : "transparent"

                                                    Behavior on color { ColorAnimation { duration: SettingsService.reducedMotion ? 0 : 50 } }
                                                    Behavior on border.color { ColorAnimation { duration: SettingsService.reducedMotion ? 0 : 50 } }

                                                    RowLayout {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 6
                                                        anchors.rightMargin: 8
                                                        spacing: 9

                                                        Image {
                                                            Layout.preferredWidth: 20
                                                            Layout.preferredHeight: 20
                                                            sourceSize: Qt.size(40, 40)
                                                            source: (appItemRow.modelData.name === "Settings" || appItemRow.modelData.id === "weylume-settings" || appItemRow.modelData.icon === "weylume-settings" || appItemRow.modelData.icon === "preferences-system")
                                                                ? Theme.settingsIcon
                                                                : Quickshell.iconPath(appItemRow.modelData.icon, "application-x-executable")
                                                            fillMode: Image.PreserveAspectFit
                                                            smooth: true
                                                            mipmap: true
                                                        }

                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: appItemRow.modelData.name
                                                            color: Theme.text
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 12
                                                            elide: Text.ElideRight
                                                        }
                                                    }

                                                    MouseArea {
                                                        id: appItemMouse
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                                        onClicked: event => {
                                                            if (event.button === Qt.RightButton) {
                                                                startContextMenu.openFor(appItemRow, appItemRow.modelData);
                                                            } else {
                                                                appItemRow.modelData.execute();
                                                                ShellState.closeFlyouts();
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
                    }

                    // Right Column (System Shortcuts)
                    ScrollView {
                        visible: !SettingsService.startCompactMode
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: SettingsService.startCompactMode ? 0 : (mainArea.width - 10) / 2
                        clip: true
                        contentWidth: availableWidth
                        contentHeight: rightCol.implicitHeight

                        ColumnLayout {
                            id: rightCol
                            width: parent.width
                            spacing: 1

                            RightSystemRow {
                                visible: SettingsService.startShowUserFolder
                                rowId: "user"
                                label: Quickshell.env("USER") || "User Home"
                                iconName: "user-home"
                                targetPath: SettingsService.startPathUserFolder || Quickshell.env("HOME")
                            }
                            RightSystemRow {
                                visible: SettingsService.startShowDocuments
                                rowId: "docs"
                                label: "Documents"
                                iconName: "folder-documents"
                                targetPath: SettingsService.startPathDocuments || (Quickshell.env("HOME") + "/Documents")
                            }
                            RightSystemRow {
                                visible: SettingsService.startShowPictures
                                rowId: "pics"
                                label: "Pictures"
                                iconName: "folder-pictures"
                                targetPath: SettingsService.startPathPictures || (Quickshell.env("HOME") + "/Pictures")
                            }
                            RightSystemRow {
                                visible: SettingsService.startShowMusic
                                rowId: "music"
                                label: "Music"
                                iconName: "folder-music"
                                targetPath: SettingsService.startPathMusic || (Quickshell.env("HOME") + "/Music")
                            }
                            RightSystemRow {
                                visible: SettingsService.startShowDownloads
                                rowId: "down"
                                label: "Downloads"
                                iconName: "folder-download"
                                targetPath: SettingsService.startPathDownloads || (Quickshell.env("HOME") + "/Downloads")
                            }
                            RightSystemRow {
                                visible: Boolean(SettingsService.startCustomFolder1Path && SettingsService.startCustomFolder1Path.trim())
                                rowId: "custom1"
                                label: SettingsService.startCustomFolder1Name.trim() || "Folder 1"
                                iconName: "folder"
                                targetPath: SettingsService.startCustomFolder1Path.trim()
                            }
                            RightSystemRow {
                                visible: Boolean(SettingsService.startCustomFolder2Path && SettingsService.startCustomFolder2Path.trim())
                                rowId: "custom2"
                                label: SettingsService.startCustomFolder2Name.trim() || "Folder 2"
                                iconName: "folder"
                                targetPath: SettingsService.startCustomFolder2Path.trim()
                            }

                            Rectangle {
                                visible: SettingsService.startShowThisPC && (SettingsService.startShowUserFolder || SettingsService.startShowDocuments || SettingsService.startShowPictures || SettingsService.startShowMusic || SettingsService.startShowDownloads || (SettingsService.startCustomFolder1Path && SettingsService.startCustomFolder1Path.trim().length > 0) || (SettingsService.startCustomFolder2Path && SettingsService.startCustomFolder2Path.trim().length > 0))
                                Layout.fillWidth: true
                                implicitHeight: 1
                                color: Theme.border
                                Layout.topMargin: 3
                                Layout.bottomMargin: 3
                                Layout.leftMargin: 4
                                Layout.rightMargin: 4
                            }

                            RightSystemRow {
                                visible: SettingsService.startShowThisPC
                                rowId: "thispc"
                                label: "This PC"
                                iconName: "computer"
                                targetPath: SettingsService.startPathThisPC || "/mnt"
                            }

                            Rectangle {
                                visible: SettingsService.startShowThisPC && (SettingsService.startShowSettings || SettingsService.startShowTerminal)
                                Layout.fillWidth: true
                                implicitHeight: 1
                                color: Theme.border
                                Layout.topMargin: 3
                                Layout.bottomMargin: 3
                                Layout.leftMargin: 4
                                Layout.rightMargin: 4
                            }

                            RightSystemRow {
                                visible: SettingsService.startShowSettings
                                rowId: "settings"
                                label: "Settings"
                                iconName: "preferences-desktop"
                                hasChev: false
                                onTriggered: ShellState.toggleSettings()
                            }
                            RightSystemRow {
                                visible: SettingsService.startShowTerminal
                                rowId: "terminal"
                                label: "Terminal"
                                iconName: "utilities-terminal"
                                command: ["kitty"]
                            }
                        }
                    }
                }
            }

            // "All Programs" Bar (Left side column only)
            Rectangle {
                id: allProgramsBar
                readonly property bool isNavSelected: root.navActive && root.navZone === "allPrograms"
                anchors.left: parent.left
                anchors.leftMargin: 10
                width: SettingsService.startCompactMode ? (startCard.width - 20) : (startCard.width - 30) / 2
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 48
                height: 38
                radius: 5
                color: (allMouse.containsMouse || isNavSelected) ? Theme.cardHover : "transparent"
                border.width: isNavSelected ? 1 : 0
                border.color: isNavSelected ? Theme.accent : "transparent"

                Behavior on color { ColorAnimation { duration: SettingsService.reducedMotion ? 0 : 50 } }
                Behavior on border.color { ColorAnimation { duration: SettingsService.reducedMotion ? 0 : 50 } }

                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: Theme.border
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    spacing: 9

                    Text {
                        text: root.allProgramsView ? "‹" : "›"
                        color: Theme.muted
                        font.pixelSize: 18
                        font.weight: Font.Bold
                    }

                    Text {
                        text: root.allProgramsView ? "Back to Pinned Favorites" : "All Programs"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }
                }

                MouseArea {
                    id: allMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        startContextMenu.dismiss();
                        root.allProgramsView = !root.allProgramsView;
                        root.navActive = true;
                        search.forceActiveFocus();
                    }
                }
            }

            // Power Flyout Menu (Shown on Sleep button hover)
            Rectangle {
                id: powerFlyout
                z: 110
                width: 140
                height: powerMenuCol.implicitHeight + 12
                radius: 7
                color: Theme.card
                border.width: 1
                border.color: Theme.border
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.bottom: bottomBar.top
                anchors.bottomMargin: 0
                visible: root.powerMenuOpen

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: powerCloseTimer.stop()
                    onExited: powerCloseTimer.restart()
                }

                ColumnLayout {
                    id: powerMenuCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 5
                    spacing: 2

                    ContextMenuItem {
                        label: "Shut down"
                        onTriggered: {
                            ShellState.requestSessionAction("shutdown");
                        }
                    }

                    ContextMenuItem {
                        label: "Restart"
                        onTriggered: {
                            ShellState.requestSessionAction("reboot");
                        }
                    }

                    ContextMenuItem {
                        label: "Lock PC"
                        onTriggered: {
                            ShellState.requestSessionAction("lock");
                        }
                    }
                }
            }

            // Bottom Bar
            Rectangle {
                id: bottomBar
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 48
                color: Theme.card
                radius: 10

                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: Theme.border
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10

                    // Search input (Shorter, compact width)
                    Rectangle {
                        Layout.preferredWidth: 210
                        implicitHeight: 28
                        radius: 6
                        color: Theme.background
                        border.width: 1
                        border.color: search.activeFocus ? Theme.accent : Theme.border

                        MouseArea {
                            anchors.fill: parent
                            z: -1
                            onClicked: {
                                root.navActive = false;
                                search.forceActiveFocus();
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 7

                            TextInput {
                                id: search
                                Layout.fillWidth: true
                                verticalAlignment: TextInput.AlignVCenter
                                color: Theme.text
                                selectionColor: Theme.isDark ? "#40ffffff" : "#40000000"
                                selectedTextColor: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                clip: true
                                selectByMouse: true

                                onActiveFocusChanged: {
                                    if (activeFocus) {
                                        root.navActive = false;
                                    }
                                }

                                onCursorPositionChanged: {
                                    root.navActive = false;
                                }

                                onTextChanged: {
                                    startContextMenu.dismiss();
                                    root.navZone = "left";
                                    root.navIndex = 0;
                                    root.navActive = false;
                                }

                                Text {
                                    anchors.fill: parent
                                    verticalAlignment: Text.AlignVCenter
                                    visible: !search.text
                                    text: root.commandMode ? "Type command..." : "Search programs..."
                                    color: Theme.muted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                }

                                Keys.onEscapePressed: {
                                    if (search.text !== "") {
                                        search.text = "";
                                        root.navActive = false;
                                    } else {
                                        ShellState.closeFlyouts();
                                    }
                                }

                                Keys.onLeftPressed: event => {
                                    if (search.text !== "") {
                                        root.navActive = false;
                                        event.accepted = false;
                                    } else {
                                        root.handleNavLeft(event);
                                    }
                                }

                                Keys.onRightPressed: event => {
                                    if (search.text !== "") {
                                        root.navActive = false;
                                        event.accepted = false;
                                    } else {
                                        root.handleNavRight(event);
                                    }
                                }

                                Keys.onDownPressed: event => root.handleNavDown(event)

                                Keys.onUpPressed: event => root.handleNavUp(event)

                                Keys.onReturnPressed: event => root.handleNavReturn(event)
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    // Sleep Power Button (Transparent on idle)
                    Rectangle {
                        implicitWidth: 98
                        implicitHeight: 28
                        radius: 5
                        color: (powerMouse.containsMouse || powerFlyout.visible) ? "#1affffff" : "transparent"
                        border.width: 0

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 6

                            Text {
                                text: "⏾"
                                color: "#f5f5f5"
                                font.pixelSize: 11
                            }

                            Text {
                                text: "Sleep"
                                color: "#f5f5f5"
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.Medium
                            }

                            Item {
                                Layout.fillWidth: true
                            }

                            Rectangle {
                                Layout.preferredWidth: 1
                                Layout.preferredHeight: 14
                                color: "#24ffffff"
                            }

                            Text {
                                text: "▾"
                                color: "#bbbbbb"
                                font.pixelSize: 9
                            }
                        }

                        MouseArea {
                            id: powerMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: {
                                powerCloseTimer.stop();
                                root.powerMenuOpen = true;
                            }
                            onExited: powerCloseTimer.restart()
                            onClicked: {
                                ShellState.requestSessionAction("suspend");
                            }
                        }
                    }
                }
            }

            // Right-Click Context Menu for Apps (Clean text, No emojis)
            Rectangle {
                id: startContextMenu
                visible: false
                z: 100
                width: 175
                height: menuCol.implicitHeight + 14
                radius: 7
                color: "#f8121212"
                border.width: 1
                border.color: Theme.border

                property var currentApp: null

                function openFor(item, app) {
                    currentApp = app;
                    const pt = item.mapToItem(startCard, 0, item.height);
                    let targetX = pt.x + 20;
                    let targetY = pt.y;
                    if (targetX + width > startCard.width - 10) targetX = startCard.width - width - 10;
                    if (targetY + height > startCard.height - 50) targetY = pt.y - height - 5;
                    x = Math.max(10, targetX);
                    y = Math.max(10, targetY);
                    visible = true;
                }

                function dismiss() {
                    visible = false;
                    currentApp = null;
                }

                ColumnLayout {
                    id: menuCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 6
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        Layout.margins: 4
                        text: startContextMenu.currentApp ? (startContextMenu.currentApp.label || startContextMenu.currentApp.name || "Application") : ""
                        color: "#ffffff"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 1
                        color: "#1affffff"
                    }

                    ContextMenuItem {
                        label: "Open"
                        onTriggered: {
                            const app = startContextMenu.currentApp;
                            startContextMenu.dismiss();
                            if (app) {
                                if (app.command && app.command.length) Quickshell.execDetached(app.command);
                                else if (app.execute) app.execute();
                                else Quickshell.execDetached([app.appIds?.[0] || app.id || app.name.toLowerCase()]);
                            }
                            ShellState.closeFlyouts();
                        }
                    }

                    ContextMenuItem {
                        readonly property bool isFav: startContextMenu.currentApp ? StartFavorites.isFavorite(startContextMenu.currentApp.id || startContextMenu.currentApp.appId, startContextMenu.currentApp.name || startContextMenu.currentApp.label) : false
                        label: isFav ? "Unpin from Start" : "Pin to Start"
                        onTriggered: {
                            const app = startContextMenu.currentApp;
                            startContextMenu.dismiss();
                            if (app) StartFavorites.toggleFavorite(app);
                        }
                    }

                    ContextMenuItem {
                        readonly property bool isTaskPinned: startContextMenu.currentApp ? PinnedApps.isPinned(startContextMenu.currentApp.id || startContextMenu.currentApp.appId, startContextMenu.currentApp.name || startContextMenu.currentApp.label) : false
                        label: isTaskPinned ? "Unpin from Taskbar" : "Pin to Taskbar"
                        onTriggered: {
                            const app = startContextMenu.currentApp;
                            startContextMenu.dismiss();
                            if (app) {
                                if (isTaskPinned) {
                                    PinnedApps.unpin(app.id || app.appId, app.name || app.label);
                                } else {
                                    PinnedApps.pin({
                                        appId: app.id || app.appId,
                                        label: app.name || app.label,
                                        icon: app.icon,
                                        command: app.command
                                    });
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Context Menu Item Component (No Emojis)
    component ContextMenuItem: Rectangle {
        id: itemRoot
        required property string label
        signal triggered()

        Layout.fillWidth: true
        implicitHeight: 28
        radius: 5
        color: itemMouse.containsMouse ? "#24ffffff" : "transparent"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: itemRoot.label
                color: "#f5f5f5"
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }
        }

        MouseArea {
            id: itemMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: itemRoot.triggered()
        }
    }

    // Right System Row Component
    component RightSystemRow: Rectangle {
        id: rightRow
        required property string label
        property string rowId: ""
        property int rowIndex: root.visibleRightItems.findIndex(it => it.id === rightRow.rowId)
        property string iconName: ""
        property bool hasChev: false
        property var command: []
        property string targetPath: ""
        signal triggered()

        readonly property bool isNavSelected: root.navActive && root.navZone === "right" && root.navIndex === rightRow.rowIndex

        Layout.fillWidth: true
        implicitHeight: 38
        radius: 6
        color: (rightMouse.containsMouse || isNavSelected) ? Theme.cardHover : "transparent"
        border.width: isNavSelected ? 1 : 0
        border.color: isNavSelected ? Theme.accent : "transparent"

        Behavior on color { ColorAnimation { duration: SettingsService.reducedMotion ? 0 : 50 } }
        Behavior on border.color { ColorAnimation { duration: SettingsService.reducedMotion ? 0 : 50 } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 10

            Image {
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
                sourceSize: Qt.size(40, 40)
                source: (rightRow.rowId === "settings" || rightRow.iconName === "preferences-desktop" || rightRow.iconName === "preferences-system" || rightRow.label === "Settings")
                    ? Theme.settingsIcon
                    : Quickshell.iconPath(rightRow.iconName, "application-x-executable")
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
            }

            Text {
                Layout.fillWidth: true
                text: rightRow.label
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 12
                elide: Text.ElideRight
            }

            Text {
                visible: rightRow.hasChev
                text: "›"
                color: Theme.muted
                font.pixelSize: 18
            }
        }

        MouseArea {
            id: rightMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                startContextMenu.dismiss();
                rightRow.triggered();
                if (rightRow.targetPath) {
                    root.openDirectory(rightRow.targetPath);
                    ShellState.closeFlyouts();
                } else if (rightRow.command && rightRow.command.length) {
                    Quickshell.execDetached(rightRow.command);
                    ShellState.closeFlyouts();
                }
            }
        }
    }
}
