import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PopupWindow {
    id: root
    Shortcut { sequence: "Escape"; enabled: root.visible; onActivated: root.dismiss() }

    property var anchorItem: null
    property var itemData: null
    readonly property bool isDesktopBg: itemData === null
    property bool menuVisible: false
    property bool openWithVisible: false
    property real openTime: 0

    readonly property Timer openTimer: openSubmenuTimer
    readonly property Timer closeTimer: closeSubmenuTimer

    Timer {
        id: openSubmenuTimer
        interval: 140
        repeat: false
        onTriggered: {
            closeSubmenuTimer.stop();
            root.openWithVisible = true;
        }
    }

    Timer {
        id: closeSubmenuTimer
        interval: 250
        repeat: false
        onTriggered: {
            openSubmenuTimer.stop();
            root.openWithVisible = false;
        }
    }

    Connections {
        target: ToplevelManager
        function onActiveToplevelChanged() {
            if (root.menuVisible && ToplevelManager.activeToplevel && (Date.now() - root.openTime > 300)) {
                root.dismiss();
            }
        }
    }

    signal renameRequested(var itemData)
    signal deleteRequested(var itemData)
    signal autoArrangeRequested()
    signal sortByNameRequested()
    signal sortByDateRequested()
    signal createFolderRequested()

    readonly property bool isStartPinned: checkItemPinnedToStart(root.itemData)
    readonly property bool isTaskPinned: checkItemPinnedToTaskbar(root.itemData)

    function openFor(item, data) {
        root.openTime = Date.now();
        ShellState.closeFlyouts(false);
        openSubmenuTimer.stop();
        closeSubmenuTimer.stop();
        openWithVisible = false;
        anchorItem = item;
        itemData = data;
        menuVisible = true;
        Quickshell.execDetached(["wtype", "-M", "logo", "-k", "F24", "-m", "logo"]);
    }

    function dismiss() {
        openSubmenuTimer.stop();
        closeSubmenuTimer.stop();
        openWithVisible = false;
        menuVisible = false;
    }

    function isArchive(name) {
        if (!name) return false;
        const n = name.toLowerCase();
        return n.endsWith(".zip") || n.endsWith(".tar.gz") || n.endsWith(".tgz")
            || n.endsWith(".tar.xz") || n.endsWith(".tar") || n.endsWith(".7z")
            || n.endsWith(".rar");
    }

    function getParentDir(p, isDir) {
        if (!p) return "/home/pc";
        if (isDir) return p;
        const lastSlash = p.lastIndexOf("/");
        return lastSlash > 0 ? p.substring(0, lastSlash) : "/home/pc";
    }

    function getItemPath(data) {
        return (data && data.path) ? String(data.path) : "";
    }

    function getItemStem(data) {
        if (!data || !data.path || !data.isDesktop) return "";
        const p = String(data.path);
        const lastSlash = p.lastIndexOf("/");
        const fn = lastSlash >= 0 ? p.substring(lastSlash + 1) : p;
        return fn.toLowerCase().endsWith(".desktop")
            ? fn.substring(0, fn.length - 8).toLowerCase()
            : fn.toLowerCase();
    }

    function checkItemPinnedToTaskbar(data) {
        if (!data || root.isDesktopBg || data.isSpecial) return false;
        const p = root.getItemPath(data);
        const stem = root.getItemStem(data);
        const items = PinnedApps.items || [];
        for (let i = 0; i < items.length; i++) {
            const pin = items[i];
            if (!pin) continue;
            const cmd = pin.command;
            if (cmd && Array.isArray(cmd)) {
                for (let c = 0; c < cmd.length; c++) {
                    if (String(cmd[c]) === p) return true;
                }
            }
            if (stem.length > 0) {
                const appIds = pin.appIds;
                if (Array.isArray(appIds)) {
                    for (let a = 0; a < appIds.length; a++) {
                        if (String(appIds[a]).toLowerCase() === stem) return true;
                    }
                }
                if (pin.appId && String(pin.appId).toLowerCase() === stem) return true;
                if (cmd && cmd.length > 0 && String(cmd[0]).toLowerCase() === stem) return true;
            }
        }
        return false;
    }

    function checkItemPinnedToStart(data) {
        if (!data || root.isDesktopBg || data.isSpecial) return false;
        const p = root.getItemPath(data);
        const stem = root.getItemStem(data);
        const items = StartFavorites.items || [];
        for (let i = 0; i < items.length; i++) {
            const fav = items[i];
            if (!fav) continue;
            const cmd = fav.command;
            if (cmd && Array.isArray(cmd)) {
                for (let c = 0; c < cmd.length; c++) {
                    if (String(cmd[c]) === p) return true;
                }
            }
            if (stem.length > 0) {
                const appIds = fav.appIds;
                if (Array.isArray(appIds)) {
                    for (let a = 0; a < appIds.length; a++) {
                        if (String(appIds[a]).toLowerCase() === stem) return true;
                    }
                }
                if (fav.appId && String(fav.appId).toLowerCase() === stem) return true;
                if (cmd && cmd.length > 0 && String(cmd[0]).toLowerCase() === stem) return true;
            }
        }
        return false;
    }

    function pinItemToTaskbar(data) {
        if (!data) return;
        const p = root.getItemPath(data);
        const stem = root.getItemStem(data);
        const cmd = (data.exec && data.exec.length > 0) ? data.exec : (p ? ["xdg-open", p] : [data.name]);
        PinnedApps.pin({
            appId: stem.length > 0 ? stem : p,
            label: data.name || stem || "Application",
            icon: data.icon || "application-x-executable",
            command: cmd,
            appIds: stem.length > 0 ? [stem] : [p]
        });
    }

    function unpinItemFromTaskbar(data) {
        if (!data) return;
        const p = root.getItemPath(data);
        const stem = root.getItemStem(data);
        const current = (PinnedApps.items || []).filter(pin => {
            if (!pin) return false;
            const cmd = pin.command;
            if (cmd && Array.isArray(cmd)) {
                for (let c = 0; c < cmd.length; c++) {
                    if (String(cmd[c]) === p) return false;
                }
            }
            if (stem.length > 0) {
                const appIds = pin.appIds;
                if (Array.isArray(appIds)) {
                    for (let a = 0; a < appIds.length; a++) {
                        if (String(appIds[a]).toLowerCase() === stem) return false;
                    }
                }
                if (pin.appId && String(pin.appId).toLowerCase() === stem) return false;
                if (cmd && cmd.length > 0 && String(cmd[0]).toLowerCase() === stem) return false;
            }
            return true;
        });
        PinnedApps.save(current);
    }

    function pinItemToStart(data) {
        if (!data) return;
        const p = root.getItemPath(data);
        const stem = root.getItemStem(data);
        const cmd = (data.exec && data.exec.length > 0) ? data.exec : (p ? ["xdg-open", p] : [data.name]);
        StartFavorites.addFavorite({
            label: data.name || stem || "Application",
            icon: data.icon || "application-x-executable",
            command: cmd,
            appIds: stem.length > 0 ? [stem] : [p]
        });
    }

    function unpinItemFromStart(data) {
        if (!data) return;
        const p = root.getItemPath(data);
        const stem = root.getItemStem(data);
        const current = (StartFavorites.items || []).filter(fav => {
            if (!fav) return false;
            const cmd = fav.command;
            if (cmd && Array.isArray(cmd)) {
                for (let c = 0; c < cmd.length; c++) {
                    if (String(cmd[c]) === p) return false;
                }
            }
            if (stem.length > 0) {
                const appIds = fav.appIds;
                if (Array.isArray(appIds)) {
                    for (let a = 0; a < appIds.length; a++) {
                        if (String(appIds[a]).toLowerCase() === stem) return false;
                    }
                }
                if (fav.appId && String(fav.appId).toLowerCase() === stem) return false;
                if (cmd && cmd.length > 0 && String(cmd[0]).toLowerCase() === stem) return false;
            }
            return true;
        });
        StartFavorites.save(current);
    }

    component MenuAction: Rectangle {
        id: actionRoot
        required property string label
        property bool disabled: false
        property bool danger: false
        property bool hasArrow: false
        property bool active: false
        property bool isSubmenuItem: false
        property string shortcutText: ""
        signal triggered()
        signal hovered()

        Layout.fillWidth: true
        Layout.leftMargin: 4
        Layout.rightMargin: 4
        implicitHeight: 22
        radius: 4
        color: !actionRoot.disabled && (actionMouse.containsMouse || actionRoot.active)
            ? (Theme.isDark ? "#ffffff" : "#000000")
            : "transparent"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 6

            Text {
                Layout.fillWidth: true
                text: actionRoot.label
                color: actionRoot.disabled
                    ? (Theme.isDark ? "#45ffffff" : "#45000000")
                    : ((actionMouse.containsMouse || actionRoot.active)
                        ? (actionRoot.danger ? "#d00000" : (Theme.isDark ? "#000000" : "#ffffff"))
                        : (actionRoot.danger ? Theme.danger : Theme.text))
                elide: Text.ElideRight
                font.family: '-apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display", "Helvetica Neue", Arial, sans-serif'
                font.pixelSize: 12
                font.letterSpacing: -0.1
            }

            Text {
                visible: actionRoot.hasArrow
                text: "›"
                color: (actionMouse.containsMouse || actionRoot.active) && !actionRoot.disabled
                    ? (Theme.isDark ? "#000000" : "#ffffff")
                    : Theme.muted
                font.pixelSize: 13
                lineHeight: 1.0
                font.family: '-apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display", "Helvetica Neue", Arial, sans-serif'
            }

            Text {
                visible: !actionRoot.hasArrow && actionRoot.shortcutText.length > 0
                text: actionRoot.shortcutText
                color: (actionMouse.containsMouse || actionRoot.active) && !actionRoot.disabled
                    ? (Theme.isDark ? "#000000" : "#ffffff")
                    : Theme.muted
                font.pixelSize: 10
                font.family: '-apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display", "Helvetica Neue", Arial, sans-serif'
            }
        }

        MouseArea {
            id: actionMouse
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            hoverEnabled: !actionRoot.disabled
            cursorShape: actionRoot.disabled ? Qt.ArrowCursor : Qt.PointingHandCursor
            onEntered: {
                if (!actionRoot.disabled) {
                    actionRoot.hovered();
                    if (actionRoot.isSubmenuItem) {
                        root.closeTimer.stop();
                        root.openTimer.stop();
                    } else if (!actionRoot.hasArrow && root.openWithVisible) {
                        root.closeTimer.restart();
                    }
                }
            }
            onClicked: mouse => {
                if (!actionRoot.disabled && mouse.button === Qt.LeftButton) actionRoot.triggered();
            }
        }
    }

    visible: menuVisible
    implicitWidth: 212
    implicitHeight: menuColumn.implicitHeight + 10
    color: "transparent"
    grabFocus: false
    surfaceFormat.opaque: false
    anchor.item: anchorItem
    anchor.edges: Edges.Top | Edges.Left
    anchor.gravity: Edges.Bottom | Edges.Right

    onVisibleChanged: if (!visible) root.dismiss()

    Connections {
        target: ShellState
        function onTaskMenusCloseRequested() {
            root.dismiss();
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: 8
        color: Theme.background
        border.width: 1
        border.color: Theme.border
        clip: true

        // Subtle top inset highlight line
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 1
            height: 1
            radius: 8
            color: Theme.isDark ? "#12ffffff" : "#12000000"
        }

        ColumnLayout {
            id: menuColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: 4
            anchors.bottomMargin: 4
            spacing: 1

            // ==========================================
            // DESKTOP BACKGROUND CONTEXT MENU (itemData === null)
            // ==========================================
            MenuAction {
                visible: root.isDesktopBg
                label: "New Folder"
                onTriggered: {
                    root.dismiss();
                    root.createFolderRequested();
                }
            }

            MenuAction {
                visible: root.isDesktopBg
                label: "New Text File"
                onTriggered: {
                    root.dismiss();
                    Quickshell.execDetached([Quickshell.shellPath("weylume-native"), "desktop", "create", "document", "New Document.txt"]);
                }
            }

            Item {
                visible: root.isDesktopBg
                Layout.fillWidth: true
                implicitHeight: 7
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 11
                    anchors.rightMargin: 11
                    y: 3
                    height: 1
                    color: Theme.border
                }
            }

            MenuAction {
                visible: root.isDesktopBg
                label: "Open Terminal"
                onTriggered: {
                    root.dismiss();
                    Quickshell.execDetached(["kitty", "--directory", "/home/pc/Desktop"]);
                }
            }

            MenuAction {
                visible: root.isDesktopBg
                label: "Open Terminal (as Administrator)"
                onTriggered: {
                    root.dismiss();
                    Quickshell.execDetached(["kitty", "--directory", "/home/pc/Desktop", "-e", "sudo", "-i"]);
                }
            }

            Item {
                visible: root.isDesktopBg
                Layout.fillWidth: true
                implicitHeight: 7
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 11
                    anchors.rightMargin: 11
                    y: 3
                    height: 1
                    color: Theme.border
                }
            }

            MenuAction {
                visible: root.isDesktopBg
                label: "Sort by Name"
                onTriggered: {
                    root.dismiss();
                    root.sortByNameRequested();
                }
            }

            MenuAction {
                visible: root.isDesktopBg
                label: "Sort by Date"
                onTriggered: {
                    root.dismiss();
                    root.sortByDateRequested();
                }
            }

            MenuAction {
                visible: root.isDesktopBg
                label: "Clean Up By Grid"
                onTriggered: {
                    root.dismiss();
                    root.autoArrangeRequested();
                }
            }

            Item {
                visible: root.isDesktopBg
                Layout.fillWidth: true
                implicitHeight: 7
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 11
                    anchors.rightMargin: 11
                    y: 3
                    height: 1
                    color: Theme.border
                }
            }

            MenuAction {
                visible: root.isDesktopBg
                label: "Change Wallpaper..."
                onTriggered: {
                    root.dismiss();
                    ShellState.toggleSettings(Quickshell.screens && Quickshell.screens[0] ? Quickshell.screens[0].name : "");
                    SettingsService.activeTab = "wallpaper";
                }
            }

            MenuAction {
                visible: root.isDesktopBg
                label: "Display Settings..."
                onTriggered: {
                    root.dismiss();
                    ShellState.toggleSettings(Quickshell.screens && Quickshell.screens[0] ? Quickshell.screens[0].name : "");
                    SettingsService.activeTab = "display";
                }
            }

            // ==========================================
            // FILE / FOLDER CONTEXT MENU (itemData !== null)
            // ==========================================
            MenuAction {
                visible: !root.isDesktopBg
                label: "Open"
                onTriggered: {
                    const data = root.itemData;
                    root.dismiss();
                    if (data?.exec && data.exec.length > 0) {
                        Quickshell.execDetached(data.exec);
                    } else if (data?.path) {
                        Quickshell.execDetached(["xdg-open", data.path]);
                    }
                }
            }

            MenuAction {
                id: openWithAction
                visible: Boolean(!root.isDesktopBg && root.itemData?.path && !root.itemData?.isSpecial)
                label: "Open With"
                hasArrow: true
                active: root.openWithVisible
                onHovered: {
                    closeSubmenuTimer.stop();
                    openSubmenuTimer.restart();
                }
                onTriggered: {
                    openSubmenuTimer.stop();
                    closeSubmenuTimer.stop();
                    root.openWithVisible = !root.openWithVisible;
                }
            }

            MenuAction {
                visible: Boolean(!root.isDesktopBg && root.itemData?.path && !root.itemData?.isSpecial)
                label: "Open with VS Code"
                onTriggered: {
                    const data = root.itemData;
                    root.dismiss();
                    if (data?.path) {
                        Quickshell.execDetached(["code-insiders", data.path]);
                    }
                }
            }

            MenuAction {
                visible: Boolean(!root.isDesktopBg && root.itemData?.path && !root.itemData?.isSpecial)
                label: root.itemData?.isDir ? "Open Terminal Here" : "Open Terminal"
                onTriggered: {
                    const data = root.itemData;
                    root.dismiss();
                    if (data?.path) {
                        const dir = root.getParentDir(data.path, data.isDir);
                        Quickshell.execDetached(["kitty", "--directory", dir]);
                    }
                }
            }

            MenuAction {
                visible: Boolean(!root.isDesktopBg && root.itemData?.path && !root.itemData?.isSpecial)
                label: "Open Terminal (as Administrator)"
                onTriggered: {
                    const data = root.itemData;
                    root.dismiss();
                    if (data?.path) {
                        const dir = root.getParentDir(data.path, data.isDir);
                        Quickshell.execDetached(["kitty", "--directory", dir, "-e", "sudo", "-i"]);
                    }
                }
            }

            Item {
                visible: Boolean(!root.isDesktopBg && root.itemData && !root.itemData.isSpecial)
                Layout.fillWidth: true
                implicitHeight: 7
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 11
                    anchors.rightMargin: 11
                    y: 3
                    height: 1
                    color: Theme.border
                }
            }

            MenuAction {
                visible: Boolean(!root.isDesktopBg && root.itemData?.path && !root.itemData?.isSpecial)
                label: "Duplicate"
                onTriggered: {
                    const data = root.itemData;
                    root.dismiss();
                    if (data?.path) {
                        Quickshell.execDetached([Quickshell.shellPath("weylume-native"), "desktop", "duplicate", data.path]);
                    }
                }
            }

            MenuAction {
                visible: Boolean(!root.isDesktopBg && root.itemData?.path && !root.itemData?.isSpecial)
                label: "Rename"
                onTriggered: {
                    const data = root.itemData;
                    root.dismiss();
                    root.renameRequested(data);
                }
            }

            MenuAction {
                visible: Boolean(!root.isDesktopBg && root.itemData?.path && !root.itemData?.isSpecial && !root.isArchive(root.itemData.name))
                label: "Add to Zip"
                onTriggered: {
                    const data = root.itemData;
                    root.dismiss();
                    if (data?.path) {
                        Quickshell.execDetached([Quickshell.shellPath("weylume-native"), "desktop", "compress", data.path]);
                    }
                }
            }

            MenuAction {
                visible: Boolean(!root.isDesktopBg && root.itemData?.path && !root.itemData?.isSpecial && root.isArchive(root.itemData.name))
                label: "Extract Zip"
                onTriggered: {
                    const data = root.itemData;
                    root.dismiss();
                    if (data?.path) {
                        Quickshell.execDetached([Quickshell.shellPath("weylume-native"), "desktop", "extract", data.path]);
                    }
                }
            }

            MenuAction {
                visible: Boolean(!root.isDesktopBg && root.itemData?.path && !root.itemData?.isSpecial && root.isArchive(root.itemData.name))
                label: "Extract to..."
                onTriggered: {
                    const data = root.itemData;
                    root.dismiss();
                    if (data?.path) {
                        Quickshell.execDetached(["sh", "-c",
                            'DEST=$(zenity --file-selection --directory --title="Choose Extraction Directory" 2>/dev/null); if [ -n "$DEST" ]; then "$1" desktop extract-to "$2" "$DEST"; fi',
                            "sh", Quickshell.shellPath("weylume-native"), data.path]);
                    }
                }
            }

            Item {
                visible: Boolean(!root.isDesktopBg && root.itemData && !root.itemData.isSpecial)
                Layout.fillWidth: true
                implicitHeight: 7
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 11
                    anchors.rightMargin: 11
                    y: 3
                    height: 1
                    color: Theme.border
                }
            }

            MenuAction {
                visible: Boolean(!root.isDesktopBg && root.itemData?.path && !root.itemData?.isSpecial)
                label: "Move To Folder..."
                onTriggered: {
                    const data = root.itemData;
                    root.dismiss();
                    if (data?.path) {
                        Quickshell.execDetached(["sh", "-c",
                            'DEST=$(zenity --file-selection --directory --title="Move To Folder" 2>/dev/null); if [ -n "$DEST" ]; then "$1" desktop move "$2" "$DEST"; fi',
                            "sh", Quickshell.shellPath("weylume-native"), data.path]);
                    }
                }
            }

            MenuAction {
                visible: Boolean(!root.isDesktopBg && root.itemData?.path && !root.itemData?.isSpecial)
                label: "Copy To Folder..."
                onTriggered: {
                    const data = root.itemData;
                    root.dismiss();
                    if (data?.path) {
                        Quickshell.execDetached(["sh", "-c",
                            'DEST=$(zenity --file-selection --directory --title="Copy To Folder" 2>/dev/null); if [ -n "$DEST" ]; then "$1" desktop copy "$2" "$DEST"; fi',
                            "sh", Quickshell.shellPath("weylume-native"), data.path]);
                    }
                }
            }

            Item {
                visible: Boolean(!root.isDesktopBg && root.itemData && !root.itemData.isSpecial)
                Layout.fillWidth: true
                implicitHeight: 7
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 11
                    anchors.rightMargin: 11
                    y: 3
                    height: 1
                    color: Theme.border
                }
            }

            MenuAction {
                visible: Boolean(!root.isDesktopBg && root.itemData?.path && !root.itemData?.isSpecial && !root.itemData.isDir)
                label: "Copy File Contents"
                onTriggered: {
                    const data = root.itemData;
                    root.dismiss();
                    if (data?.path) {
                        Quickshell.execDetached([Quickshell.shellPath("weylume-native"), "desktop", "copy-content", data.path]);
                    }
                }
            }

            MenuAction {
                visible: Boolean(!root.isDesktopBg && root.itemData?.path && !root.itemData?.isSpecial)
                label: "Copy File Path"
                onTriggered: {
                    const data = root.itemData;
                    root.dismiss();
                    if (data?.path) {
                        Quickshell.execDetached(["wl-copy", "--", data.path]);
                    }
                }
            }

            MenuAction {
                visible: Boolean(!root.isDesktopBg && root.itemData?.path && !root.itemData?.isSpecial && (root.itemData.name.endsWith(".png") || root.itemData.name.endsWith(".jpg") || root.itemData.name.endsWith(".jpeg") || root.itemData.name.endsWith(".webp") || root.itemData.name.endsWith(".PNG") || root.itemData.name.endsWith(".JPG")))
                label: "Set as Wallpaper"
                onTriggered: {
                    const data = root.itemData;
                    root.dismiss();
                    if (data?.path) {
                        Quickshell.execDetached([Quickshell.shellPath("weylume-native"), "desktop", "wallpaper", data.path]);
                    }
                }
            }

            MenuAction {
                visible: Boolean(!root.isDesktopBg && root.itemData && !root.itemData.isSpecial)
                label: root.isStartPinned ? "Unpin from Start Menu" : "Pin to Start Menu"
                onTriggered: {
                    const data = root.itemData;
                    root.dismiss();
                    if (root.isStartPinned) root.unpinItemFromStart(data);
                    else root.pinItemToStart(data);
                }
            }

            MenuAction {
                visible: Boolean(!root.isDesktopBg && root.itemData && !root.itemData.isSpecial)
                label: root.isTaskPinned ? "Unpin from Taskbar" : "Pin to Taskbar"
                onTriggered: {
                    const data = root.itemData;
                    root.dismiss();
                    if (root.isTaskPinned) root.unpinItemFromTaskbar(data);
                    else root.pinItemToTaskbar(data);
                }
            }

            Item {
                visible: Boolean(!root.isDesktopBg && root.itemData && !root.itemData.isSpecial)
                Layout.fillWidth: true
                implicitHeight: 7
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 11
                    anchors.rightMargin: 11
                    y: 3
                    height: 1
                    color: Theme.border
                }
            }

            MenuAction {
                visible: Boolean(!root.isDesktopBg && root.itemData && !root.itemData.isSpecial)
                label: "Move to Trash"
                danger: true
                onTriggered: {
                    const data = root.itemData;
                    root.dismiss();
                    root.deleteRequested(data);
                }
            }

            MenuAction {
                visible: Boolean(!root.isDesktopBg && root.itemData && !root.itemData.isSpecial)
                label: "Permanent Delete"
                danger: true
                onTriggered: {
                    const data = root.itemData;
                    root.dismiss();
                    if (data?.path) {
                        Quickshell.execDetached([Quickshell.shellPath("weylume-native"), "desktop", "delete", data.path]);
                    }
                }
            }
        }
    }

    PopupWindow {
        id: openWithSubmenu
        Shortcut { sequence: "Escape"; enabled: openWithSubmenu.visible; onActivated: root.dismiss() }
        visible: root.menuVisible && root.openWithVisible
        anchor.item: openWithAction
        anchor.edges: Edges.Top | Edges.Right
        anchor.gravity: Edges.Bottom | Edges.Right
        implicitWidth: 196
        implicitHeight: subMenuColumn.implicitHeight + 10
        color: "transparent"
        grabFocus: false
        surfaceFormat.opaque: false

        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: 8
            color: Theme.background
            border.width: 1
            border.color: Theme.border
            clip: true

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 1
                height: 1
                radius: 8
                color: Theme.isDark ? "#12ffffff" : "#12000000"
            }

            ColumnLayout {
                id: subMenuColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: 4
                anchors.bottomMargin: 4
                spacing: 1

                MenuAction {
                    isSubmenuItem: true
                    label: "Visual Studio Code"
                    onHovered: root.closeTimer.stop()
                    onTriggered: {
                        const data = root.itemData;
                        root.dismiss();
                        if (data?.path) Quickshell.execDetached(["code-insiders", data.path]);
                    }
                }

                MenuAction {
                    isSubmenuItem: true
                    label: "Text Editor (FeatherPad)"
                    onHovered: root.closeTimer.stop()
                    onTriggered: {
                        const data = root.itemData;
                        root.dismiss();
                        if (data?.path) Quickshell.execDetached(["featherpad", data.path]);
                    }
                }

                MenuAction {
                    isSubmenuItem: true
                    label: "Files (PCManFM-Qt)"
                    onHovered: root.closeTimer.stop()
                    onTriggered: {
                        const data = root.itemData;
                        root.dismiss();
                        if (data?.path) {
                            Quickshell.execDetached(data.isDir
                                ? ["pcmanfm-qt", data.path]
                                : ["pcmanfm-qt", "--show-item", data.path]);
                        }
                    }
                }
            }
        }

        HoverHandler {
            onHoveredChanged: {
                if (hovered) {
                    root.closeTimer.stop();
                    root.openTimer.stop();
                } else {
                    root.closeTimer.restart();
                }
            }
        }
    }
}
