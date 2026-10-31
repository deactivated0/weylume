import QtQuick
import QtQuick.Layouts
import Quickshell

PopupWindow {
    id: root
    Shortcut { sequence: "Escape"; enabled: root.visible; onActivated: root.dismiss() }

    property var anchorItem: null
    property var targetWindow: null
    property var launchCommand: []
    property string appLabel: "Application"
    property string iconName: "application-x-executable"
    property string appId: ""
    property bool menuVisible: false
    property bool forceCloseConfirmation: false

    signal windowActionRequested(var targetWindow, string actionName, string appId, var launchCommand)

    function openFor(item, target, label, command, icon, appId) {
        ShellState.closeFlyouts();
        anchorItem = item;
        targetWindow = target;
        appLabel = label || "Application";
        launchCommand = command || [];
        iconName = icon || "application-x-executable";
        root.appId = appId || (target?.appId ?? "");
        forceCloseConfirmation = false;
        menuVisible = true;
    }

    function dismiss() {
        menuVisible = false;
        forceCloseConfirmation = false;
    }

    readonly property var desktopEntry: {
        if (!root.menuVisible) return null;
        let entry = null;
        if (root.appId) {
            entry = DesktopEntries.byId(root.appId) || DesktopEntries.heuristicLookup(root.appId);
        }
        if (!entry && root.appLabel) {
            entry = DesktopEntries.heuristicLookup(root.appLabel);
        }
        if (!entry && root.launchCommand && root.launchCommand.length > 0) {
            const bin = root.launchCommand[0].split("/").pop();
            entry = DesktopEntries.byId(bin) || DesktopEntries.heuristicLookup(bin);
        }
        return entry;
    }

    readonly property bool isBrowser: {
        const id = (root.appId || "").toLowerCase();
        const lbl = (root.appLabel || "").toLowerCase();
        const cmd = (root.launchCommand.join(" ") || "").toLowerCase();
        return id.includes("helium") || lbl.includes("helium") || cmd.includes("helium")
            || id.includes("chrome") || id.includes("chromium") || id.includes("brave") || id.includes("edge")
            || id.includes("firefox") || id.includes("zen") || id.includes("librewolf");
    }

    readonly property var incognitoCommand: {
        const id = (root.appId || "").toLowerCase();
        const lbl = (root.appLabel || "").toLowerCase();
        const cmd = (root.launchCommand.join(" ") || "").toLowerCase();
        if (id.includes("firefox") || id.includes("zen") || id.includes("librewolf") || lbl.includes("firefox") || cmd.includes("firefox")) {
            return (root.launchCommand.length > 0 ? [root.launchCommand[0]] : ["firefox"]).concat(["--private-window"]);
        }
        if (id.includes("helium") || lbl.includes("helium") || cmd.includes("helium")) {
            return ["helium", "--incognito"];
        }
        if (root.launchCommand.length > 0) {
            return [root.launchCommand[0], "--incognito"];
        }
        return ["helium", "--incognito"];
    }

    visible: menuVisible
    implicitWidth: 220
    implicitHeight: menuColumn.implicitHeight + 16
    color: "transparent"
    grabFocus: true
    surfaceFormat.opaque: false
    anchor.item: anchorItem
    anchor.edges: Edges.Top | Edges.Left
    anchor.gravity: Edges.Top | Edges.Right

    onVisibleChanged: if (!visible) menuVisible = false

    Connections {
        target: ShellState
        function onTaskMenusCloseRequested() {
            root.menuVisible = false;
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 4
        radius: 12
        color: Theme.background
        border.width: 1
        border.color: Theme.border
        clip: true

        ColumnLayout {
            id: menuColumn
            anchors.fill: parent
            anchors.margins: 8
            spacing: 3

            // App Header
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 4
                spacing: 8

                Rectangle {
                    width: 22; height: 22; radius: 5
                    color: Theme.card
                    border.width: 1
                    border.color: Theme.border

                    Image {
                        id: appHeaderIcon
                        anchors.centerIn: parent
                        width: 13; height: 13
                        sourceSize: Qt.size(28, 28)
                        source: {
                            const ic = root.iconName;
                            if (!ic) return "";
                            const lower = ic.toLowerCase();
                            if (lower === "steam" || lower.includes("steam")) return Quickshell.shellPath("assets/steam.svg");
                            if (lower === "weylume-settings" || lower === "preferences-system" || (root.appLabel && root.appLabel.toLowerCase() === "settings") || lower.includes("weylume-gear")) return Theme.settingsIcon;
                            return (ic.startsWith("/") || ic.startsWith("image://") || ic.startsWith("file://")) ? ic : Quickshell.iconPath(ic, "application-x-executable");
                        }
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                        visible: status === Image.Ready
                    }

                    Text {
                        anchors.centerIn: parent
                        text: (root.desktopEntry?.name || root.appLabel || "A").charAt(0).toUpperCase()
                        visible: !appHeaderIcon.visible
                        color: Theme.text
                        font.pixelSize: 10
                        font.weight: Font.Bold
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        Layout.fillWidth: true
                        text: root.desktopEntry?.name || root.appLabel
                        color: Theme.text
                        elide: Text.ElideRight
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.targetWindow ? (root.targetWindow.title || "Running Window") : "Application"
                        color: Theme.muted
                        elide: Text.ElideRight
                        font.family: Theme.fontFamily
                        font.pixelSize: 8
                    }
                }
            }

            Rectangle {
                visible: root.targetWindow !== null
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.border
                Layout.topMargin: 1
                Layout.bottomMargin: 1
            }

            // Window Management Section (Top, if window is running)
            MenuAction {
                visible: root.targetWindow !== null
                label: "Always on top"
                onTriggered: {
                    const target = root.targetWindow;
                    root.dismiss();
                    if (target) root.windowActionRequested(target, "top");
                }
            }

            MenuAction {
                visible: root.targetWindow !== null
                label: (root.targetWindow?.maximized) ? "Restore" : "Maximize"
                onTriggered: {
                    const target = root.targetWindow;
                    root.dismiss();
                    if (target) target.maximized = !target.maximized;
                }
            }

            MenuAction {
                visible: root.targetWindow !== null
                label: "Minimize"
                onTriggered: {
                    const target = root.targetWindow;
                    root.dismiss();
                    if (target) target.minimized = true;
                }
            }

            MenuAction {
                visible: root.targetWindow !== null
                label: "Close window"
                onTriggered: {
                    const target = root.targetWindow;
                    root.dismiss();
                    if (target) target.close();
                }
            }

            MenuAction {
                visible: root.targetWindow !== null
                label: root.forceCloseConfirmation ? "Confirm force close" : "Force close"
                danger: true
                onTriggered: {
                    if (!root.forceCloseConfirmation) {
                        root.forceCloseConfirmation = true;
                        return;
                    }
                    const target = root.targetWindow;
                    root.dismiss();
                    if (target) {
                        const aId = root.appId || (target?.appId ?? "");
                        const cmd = root.launchCommand || [];
                        root.windowActionRequested(target, "kill", aId, cmd);
                    }
                }
            }

            // Separator before Application Options
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.border
                Layout.topMargin: 1
                Layout.bottomMargin: 1
            }

            // Application Options (Bottom)
            // Native Desktop Actions (from .desktop file)
            Repeater {
                model: root.desktopEntry?.actions ?? []

                MenuAction {
                    required property var modelData
                    label: modelData.name || modelData.id
                    iconSource: modelData.icon ? Quickshell.iconPath(modelData.icon) : ""
                    onTriggered: {
                        const act = modelData;
                        root.dismiss();
                        try {
                            act.execute();
                        } catch (e) {
                            if (act.command && act.command.length > 0) {
                                Quickshell.execDetached(act.command);
                            }
                        }
                    }
                }
            }

            // Default Open / New Window action
            MenuAction {
                visible: root.launchCommand.length > 0 || (root.desktopEntry !== null)
                label: root.targetWindow ? "Open new window" : "Open"
                onTriggered: {
                    const command = root.launchCommand;
                    const entry = root.desktopEntry;
                    root.dismiss();
                    if (command && command.length > 0) {
                        Quickshell.execDetached(command);
                    } else if (entry) {
                        try { entry.execute(); } catch (e) {}
                    }
                }
            }

            // Incognito Window (for browsers)
            MenuAction {
                visible: root.isBrowser && !(root.desktopEntry?.actions?.some(a => (a.name || "").toLowerCase().includes("incognito") || (a.name || "").toLowerCase().includes("private")))
                label: "New Incognito Window"
                onTriggered: {
                    const cmd = root.incognitoCommand;
                    root.dismiss();
                    Quickshell.execDetached(cmd);
                }
            }

            // Pin / Unpin Action
            MenuAction {
                readonly property bool isAppPinned: PinnedApps.isPinned(root.appId, root.appLabel)
                label: isAppPinned ? "Unpin from taskbar" : "Pin to taskbar"
                onTriggered: {
                    const pinned = isAppPinned;
                    if (pinned) {
                        PinnedApps.unpin(root.appId, root.appLabel);
                    } else {
                        PinnedApps.pin({
                            appId: root.appId,
                            label: root.appLabel,
                            icon: root.iconName,
                            command: root.launchCommand
                        });
                    }
                    root.dismiss();
                }
            }
        }
    }

    component MenuAction: Rectangle {
        id: actionRoot

        required property string label
        property string iconSource: ""
        property bool danger: false
        signal triggered()

        Layout.fillWidth: true
        implicitHeight: 28
        radius: 6
        color: actionRoot.enabled && actionMouse.containsMouse
            ? (danger ? (Theme.isDark ? "#2c1216" : "#ffebee") : Theme.cardHover)
            : "transparent"
        border.width: 1
        border.color: actionRoot.enabled && actionMouse.containsMouse
            ? (danger ? (Theme.isDark ? "#4a181c" : "#ffcdd2") : Theme.border)
            : "transparent"
        opacity: actionRoot.enabled ? 1 : 0.38

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 8

            Image {
                visible: actionRoot.iconSource !== "" && status === Image.Ready
                Layout.preferredWidth: 13
                Layout.preferredHeight: 13
                sourceSize: Qt.size(26, 26)
                source: actionRoot.iconSource
                fillMode: Image.PreserveAspectFit
            }

            Text {
                Layout.fillWidth: true
                text: actionRoot.label
                color: actionRoot.danger ? Theme.danger : Theme.text
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Normal
            }
        }

        MouseArea {
            id: actionMouse
            anchors.fill: parent
            enabled: actionRoot.enabled
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: actionRoot.triggered()
        }
    }
}
