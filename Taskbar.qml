import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root
    property var desktopHiddenWindows: []
    property var pendingWindowActionTarget: null
    property string pendingWindowAction: ""
    property int pendingWindowActionAttempts: 0

    function allMatchingToplevels(appIds, label) {
        const targets = (Array.isArray(appIds) ? appIds : (appIds ? [appIds] : [])).concat(label || "");
        if (targets.length === 0) return [];
        const windows = ToplevelManager.toplevels.values;
        let matches = [];
        for (let i = 0; i < windows.length; i++) {
            const w = windows[i];
            if (PinnedApps.matchesApp([w.appId, w.title], targets)) matches.push(w);
        }
        return matches;
    }

    function primaryToplevel(matches) {
        if (matches.length === 0) return null;
        for (let i = 0; i < matches.length; i++) {
            if (matches[i].activated) return matches[i];
        }
        return matches[0];
    }

    function handleAppClick(appIds, launchCmd, label) {
        const matchIds = (appIds || []).concat(label || "");
        const matches = allMatchingToplevels(matchIds);
        if (matches.length === 0) {
            if (launchCmd && launchCmd.length > 0) Quickshell.execDetached(launchCmd);
            return;
        }

        if (matches.length === 1) {
            const win = matches[0];
            if (win.activated) win.minimized = true;
            else {
                if (win.minimized) win.minimized = false;
                win.activate();
            }
            return;
        }

        let activeIdx = -1;
        for (let i = 0; i < matches.length; i++) {
            if (matches[i].activated) {
                activeIdx = i;
                break;
            }
        }

        const nextIdx = (activeIdx + 1) % matches.length;
        const nextWin = matches[nextIdx];
        if (nextWin.minimized) nextWin.minimized = false;
        nextWin.activate();
    }

    readonly property var unpinnedAppGroups: PinnedApps.unpinnedAppGroups

    function queueWindowAction(target, actionName, appId, launchCommand) {
        if (!target) return;

        if (actionName === "kill") {
            try { target.close(); } catch(e) {}

            const candidates = [];
            const addCandidate = (val) => {
                if (!val || typeof val !== "string") return;
                const s = val.trim().toLowerCase();
                if (!s || s.length < 2) return;
                if (!candidates.includes(s)) candidates.push(s);
            };

            const rawId = (appId || target.appId || "").trim();
            if (rawId) {
                addCandidate(rawId);
                if (rawId.includes(".")) {
                    const parts = rawId.split(".");
                    addCandidate(parts[parts.length - 1]);
                }
                if (rawId.endsWith("-browser")) {
                    addCandidate(rawId.replace(/-browser$/, ""));
                }
                if (rawId.endsWith("-desktop")) {
                    addCandidate(rawId.replace(/-desktop$/, ""));
                }
                if (rawId.endsWith(".desktop")) {
                    addCandidate(rawId.replace(/\.desktop$/, ""));
                }
            }

            if (launchCommand && launchCommand.length > 0 && typeof launchCommand[0] === "string") {
                const cmdBin = launchCommand[0].split("/").pop().trim();
                addCandidate(cmdBin);
            }

            try {
                const entry = DesktopEntries.byId(rawId) || DesktopEntries.heuristicLookup(rawId);
                if (entry && entry.command && entry.command.length > 0 && typeof entry.command[0] === "string") {
                    addCandidate(entry.command[0].split("/").pop().trim());
                }
            } catch(e) {}

            if (candidates.some(c => c.includes("discord"))) {
                ["discord", "discordcanary", "discordptb", "discorddevelopment"].forEach(addCandidate);
            }
            if (candidates.some(c => c.includes("pcmanfm"))) {
                ["pcmanfm-qt", "pcmanfm"].forEach(addCandidate);
            }
            if (candidates.some(c => c.includes("thorium"))) {
                ["thorium-browser", "thorium"].forEach(addCandidate);
            }

            const blacklist = [
                "sh", "bash", "zsh", "systemd", "qs", "quickshell", "labwc",
                "xwayland", "dbus-daemon", "systemd-run", "pipewire", "wireplumber",
                "init", "rtk", "python", "python3", "node", "wtype", "grep", "sleep", "pkill", "pgrep"
            ];

            const safeTargets = candidates.filter(c => !blacklist.includes(c) && c.length >= 2);
            if (safeTargets.length > 0) {
                const checks = safeTargets.map(t => "pkill -15 -x '" + t + "'").join("; ");
                const hardKills = safeTargets.map(t => "pkill -9 -x '" + t + "'").join("; ");
                const killCmd = "sleep 0.15; " + checks + "; sleep 0.25; " + hardKills;
                Quickshell.execDetached(["sh", "-c", killCmd]);
            }
            return;
        }

        pendingWindowActionTarget = target;
        pendingWindowAction = actionName;
        pendingWindowActionAttempts = 0;
        if (target.minimized) target.minimized = false;
        target.activate();
        labwcActionTimer.restart();
    }

    function formatTime12(hours, minutes) {
        if (hours === undefined || minutes === undefined) return "--:-- --";
        if (SettingsService.clock24Hour)
            return String(hours).padStart(2, '0') + ":" + String(minutes).padStart(2, '0');
        const h = hours % 12 || 12;
        const m = String(minutes).padStart(2, '0');
        const ampm = hours >= 12 ? "PM" : "AM";
        return h + ":" + m + " " + ampm;
    }

    implicitHeight: Theme.taskbarHeight
    color: "transparent"
    surfaceFormat.opaque: false
    anchors { left: true; right: true; bottom: true }
    exclusiveZone: Theme.taskbarHeight
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "weylume-taskbar"

    function toggleAppAudioMute(appIds, label) {
        const nodes = AudioService.nodesForApp(appIds, label);
        if (nodes.length === 0) return;
        const anyUnmuted = nodes.some(n => !n.audio || !n.audio.muted);
        const targetMute = anyUnmuted;

        for (let i = 0; i < nodes.length; i++) {
            const n = nodes[i];
            if (n.audio) n.audio.muted = targetMute;
            else if (n.id) {
                Quickshell.execDetached(["wpctl", "set-mute", String(n.id), targetMute ? "1" : "0"]);
            }
        }
    }

    function ownsPopup() {
        return !ShellState.popupScreenName || ShellState.popupScreenName === root.screen.name;
    }

    function toggleShowDesktop() {
        if (root.desktopHiddenWindows.length > 0) {
            const previous = root.desktopHiddenWindows.slice();
            root.desktopHiddenWindows = [];
            for (let i = 0; i < previous.length; ++i) {
                const window = previous[i];
                if (window) window.minimized = false;
            }
            return;
        }
        const windows = ToplevelManager.toplevels.values;
        const hidden = [];
        for (let i = 0; i < windows.length; ++i) {
            const window = windows[i];
            if (!window.minimized) {
                hidden.push(window);
                window.minimized = true;
            }
        }
        root.desktopHiddenWindows = hidden;
    }

    property var currentHoveredButton: null

    Timer {
        id: hoverPreviewTimer
        interval: 220
        repeat: false
        property var targetButton: null
        property var targetWindows: []
        property string targetLabel: ""
        property string targetIcon: ""
        onTriggered: {
            if (targetButton && targetWindows.length > 0) {
                taskPreviewLoader.active = true;
                if (taskPreviewLoader.item) {
                    taskPreviewLoader.item.openFor(targetButton, targetWindows, targetLabel, targetIcon);
                } else {
                    Qt.callLater(() => {
                        if (taskPreviewLoader.item && targetButton) {
                            taskPreviewLoader.item.openFor(targetButton, targetWindows, targetLabel, targetIcon);
                        }
                    });
                }
            }
        }
    }

    function handleButtonHover(button, windows, label, icon) {
        if (!windows || windows.length === 0) {
            handleButtonUnhover(button);
            return;
        }
        currentHoveredButton = button;
        if (taskPreviewLoader.item?.previewVisible) {
            hoverPreviewTimer.stop();
            if (taskPreviewLoader.item.anchorItem !== button) {
                taskPreviewLoader.item.dismiss();
            }
            taskPreviewLoader.item.openFor(button, windows, label, icon);
        } else {
            hoverPreviewTimer.targetButton = button;
            hoverPreviewTimer.targetWindows = windows;
            hoverPreviewTimer.targetLabel = label;
            hoverPreviewTimer.targetIcon = icon;
            hoverPreviewTimer.restart();
        }
    }

    function handleButtonUnhover(button) {
        if (currentHoveredButton === button) {
            currentHoveredButton = null;
        }
        hoverPreviewTimer.stop();
        if (taskPreviewLoader.item) taskPreviewLoader.item.scheduleHide(350);
    }

    Timer {
        id: labwcActionTimer
        interval: 50
        repeat: true
        onTriggered: {
            root.pendingWindowActionAttempts++;
            if (!root.pendingWindowActionTarget) {
                stop();
                return;
            }
            if (!root.pendingWindowActionTarget.activated) {
                if (root.pendingWindowActionAttempts < 12) return;
                stop();
                root.pendingWindowActionTarget = null;
                root.pendingWindowAction = "";
                return;
            }
            let key = "";
            if (root.pendingWindowAction === "top") key = "t";
            else if (root.pendingWindowAction === "sticky") key = "o";
            if (key)
                Quickshell.execDetached(["wtype", "-M", "logo", "-M", "alt", "-M", "ctrl", "-k", key, "-m", "ctrl", "-m", "alt", "-m", "logo"]);
            stop();
            root.pendingWindowActionTarget = null;
            root.pendingWindowAction = "";
        }
    }

    // Left System Taskbar
    RowLayout {
        id: leftCluster
        anchors.left: parent.left
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12

        ColumnLayout {
            spacing: 1
            Text {
                text: "CPU " + SystemData.cpuTemperature
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 9
                font.weight: Font.DemiBold
            }
            Text {
                text: "GPU " + SystemData.gpuTemperature
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 9
                font.weight: Font.DemiBold
            }
        }

        ColumnLayout {
            spacing: 1
            Text {
                text: "▲ " + SystemData.networkSend
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 9
                font.weight: Font.DemiBold
            }
            Text {
                text: "▼ " + SystemData.networkReceive
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 9
                font.weight: Font.DemiBold
            }
        }
    }

    // Center Taskbar Area - strictly centered on screen and symmetric-bounded to prevent cluster overlaps
    Item {
        id: centerContainer
        readonly property real sideLimit: Math.max(leftCluster.implicitWidth || leftCluster.width, rightCluster.implicitWidth || rightCluster.width)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(centerCluster.implicitWidth, Math.max(0, parent.width - 2 * sideLimit - 24))
        implicitHeight: parent.height
        height: parent.height
        clip: true

        RowLayout {
            id: centerCluster
            x: Math.max(0, (parent.width - implicitWidth) / 2)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3

        WinButton {
            id: startButton
            accessibleName: "Start menu"
            implicitWidth: 36
            implicitHeight: 36
            active: ShellState.startOpen
            onClicked: ShellState.toggleStart(root.screen.name)

            Item {
                anchors.centerIn: parent
                width: 18
                height: 18
                Grid {
                    anchors.fill: parent
                    columns: 2
                    spacing: 2
                    Repeater {
                        model: 4
                        Rectangle { width: 8; height: 8; color: Theme.text; radius: 1 }
                    }
                }
            }
        }

        Repeater {
            model: PinnedApps.items
            WinButton {
                id: pinnedButton
                accessibleName: modelData.label || "Pinned application"
                required property var modelData
                required property int index
                readonly property var matches: root.allMatchingToplevels(modelData.appIds || (modelData.appId ? [modelData.appId] : [modelData.label]), modelData.label)
                readonly property var runningWindow: root.primaryToplevel(matches)
                readonly property var audioNodes: AudioService.nodesForApp(modelData.appIds || (modelData.appId ? [modelData.appId] : [modelData.label]), modelData.label)
                implicitWidth: 36
                implicitHeight: 36
                iconSize: 22
                icon: (modelData.label === "Settings" || modelData.icon === "weylume-settings" || modelData.icon === "preferences-system") ? Theme.settingsIcon : (modelData.icon || "application-x-executable")
                fallback: modelData.fallback || (modelData.label ? modelData.label.charAt(0).toUpperCase() : "□")
                showIndicator: true
                isRunning: matches.length > 0
                active: matches.some(w => w.activated)
                draggable: true
                dragIndex: index
                maxDragIndex: PinnedApps.items.length - 1
                slotSpacing: centerCluster.spacing
                hasAudio: audioNodes.length > 0
                audioMuted: audioNodes.length > 0 && audioNodes.every(node => node.audio?.muted)
                onAudioMuteToggled: root.toggleAppAudioMute(modelData.appIds || (modelData.appId ? [modelData.appId] : [modelData.label]), modelData.label)
                onDragReordered: (from, to) => PinnedApps.move(from, to)
                onContainsMouseChanged: {
                    if (containsMouse) {
                        root.handleButtonHover(pinnedButton, matches, modelData.label, (modelData.label === "Settings" || modelData.icon === "weylume-settings" || modelData.icon === "preferences-system") ? Theme.settingsIcon : modelData.icon);
                    } else {
                        root.handleButtonUnhover(pinnedButton);
                    }
                }
                onClicked: {
                    ShellState.closeFlyouts(false);
                    if (taskPreviewLoader.item) taskPreviewLoader.item.dismiss();
                    if (modelData.label === "Settings" || (modelData.appIds && modelData.appIds.includes("weylume-settings"))) {
                        ShellState.toggleSettings();
                    } else {
                        root.handleAppClick(modelData.appIds || (modelData.appId ? [modelData.appId] : [modelData.label]), modelData.command, modelData.label);
                    }
                }
                onRightClicked: (x, y) => {
                    if (taskPreviewLoader.item) taskPreviewLoader.item.dismiss();
                    taskContextMenu.openFor(
                        pinnedButton,
                        runningWindow,
                        modelData.label,
                        modelData.command,
                        modelData.icon,
                        modelData.appIds?.[0] || modelData.appId || ""
                    );
                }

                DropArea {
                    anchors.fill: parent
                    onEntered: {
                        if (pinnedButton.matches && pinnedButton.matches.length > 0) {
                            const win = pinnedButton.runningWindow || pinnedButton.matches[0];
                            if (win) {
                                if (win.minimized) win.minimized = false;
                                win.activate();
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            implicitWidth: 1
            implicitHeight: 22
            color: Theme.border
            Layout.leftMargin: 2
            Layout.rightMargin: 2
            visible: root.unpinnedAppGroups.length > 0
        }

        Repeater {
            model: ScriptModel {
                values: root.unpinnedAppGroups
            }
            WinButton {
                id: runningButton
                accessibleName: {
                    const lowId = String(modelData.appId || "").toLowerCase();
                    const lowTitle = String(modelData.title || "").toLowerCase();
                    if (lowId === "weylume-settings" || lowTitle === "settings" || (lowId === "org.quickshell" && lowTitle === "settings")) {
                        return "Settings";
                    }
                    return desktopEntry?.name || modelData.title || modelData.appId;
                }
                required property var modelData
                property var desktopEntry: {
                    const lowId = String(modelData.appId || "").toLowerCase();
                    const lowTitle = String(modelData.title || "").toLowerCase();
                    if (lowId === "weylume-settings" || lowTitle === "settings" || (lowId === "org.quickshell" && lowTitle === "settings")) {
                        return DesktopEntries.heuristicLookup("weylume-settings") || DesktopEntries.heuristicLookup("preferences-system");
                    }
                    return DesktopEntries.heuristicLookup(modelData.appId) || DesktopEntries.heuristicLookup(modelData.title);
                }
                readonly property var audioNodes: AudioService.nodesForApp([modelData.appId, modelData.title], desktopEntry?.name || modelData.title)
                implicitWidth: 36
                implicitHeight: 36
                iconSize: 22
                icon: {
                    const lowId = String(modelData.appId || "").toLowerCase();
                    const lowTitle = String(modelData.title || "").toLowerCase();
                    if (lowId === "weylume-settings" || lowTitle === "settings" || (lowId === "org.quickshell" && lowTitle === "settings")) {
                        return Theme.settingsIcon;
                    }
                    if (desktopEntry && desktopEntry.icon && desktopEntry.icon !== "org.quickshell") return desktopEntry.icon;
                    const low = lowId + " " + lowTitle;
                    if (low.includes("abdownloadmanager") || low.includes("ab-download-manager") || low.includes("ab download manager")) {
                        return "file:///opt/ABDownloadManager/lib/ABDownloadManager.png";
                    }
                    if (low.includes("walkietalkie") || low.includes("walkie talkie") || low.includes("io.walkietalkie")) {
                        return "file:///home/pc/.local/share/waydroid/data/icons/io.walkietalkie.png";
                    }
                    return modelData.appId || "application-x-executable";
                }
                fallback: (runningButton.accessibleName || "S").charAt(0).toUpperCase()
                showIndicator: true
                isRunning: true
                active: modelData.windows.some(w => w.activated)
                hasAudio: audioNodes.length > 0
                audioMuted: audioNodes.length > 0 && audioNodes.every(node => node.audio?.muted)
                onAudioMuteToggled: root.toggleAppAudioMute([modelData.appId, modelData.title], desktopEntry?.name || modelData.title)
                onContainsMouseChanged: {
                    if (containsMouse) {
                        root.handleButtonHover(runningButton, modelData.windows, runningButton.accessibleName, runningButton.icon);
                    } else {
                        root.handleButtonUnhover(runningButton);
                    }
                }
                onClicked: {
                    ShellState.closeFlyouts(false);
                    if (taskPreviewLoader.item) taskPreviewLoader.item.dismiss();
                    if (runningButton.accessibleName === "Settings" || String(modelData.appId || "").toLowerCase() === "weylume-settings") {
                        ShellState.toggleSettings();
                    } else {
                        root.handleAppClick([modelData.appId, modelData.title], [modelData.appId]);
                    }
                }
                onRightClicked: (x, y) => {
                    if (taskPreviewLoader.item) taskPreviewLoader.item.dismiss();
                    taskContextMenu.openFor(
                        runningButton,
                        modelData.primaryWindow,
                        runningButton.accessibleName,
                        (runningButton.accessibleName === "Settings") ? ["qs", "-c", "weylume", "ipc", "call", "shell", "toggleSettings"] : [modelData.appId],
                        runningButton.icon,
                        modelData.appId
                    );
                }

                DropArea {
                    anchors.fill: parent
                    onEntered: {
                        if (runningButton.modelData?.windows && runningButton.modelData.windows.length > 0) {
                            const win = runningButton.modelData.primaryWindow || runningButton.modelData.windows[0];
                            if (win) {
                                if (win.minimized) win.minimized = false;
                                win.activate();
                            }
                        }
                    }
                }
            }
        }
    }
    }

    // Show Desktop button (anchored directly to bottom-right corner of display)
    Rectangle {
        id: showDesktopBtn
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 8
        anchors.bottom: parent.bottom
        width: 5
        radius: 2
        color: showDesktopMouse.containsMouse ? (Theme.isDark ? "#40ffffff" : "#30000000") : "transparent"

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: 4
            anchors.bottomMargin: 4
            width: 1
            color: Theme.isDark ? "#28ffffff" : "#18000000"
        }

        MouseArea {
            id: showDesktopMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleShowDesktop()
        }
    }

    // Right System Taskbar
    RowLayout {
        id: rightCluster
        anchors.right: showDesktopBtn.left
        anchors.rightMargin: 2
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        // Tray overflow arrow
        WinButton {
            id: trayArrow
            accessibleName: "Tray overflow"
            implicitWidth: 22
            implicitHeight: 32
            icon: Quickshell.shellPath("assets/chevron-up.svg")
            fallback: "˄"
            iconSize: 15
            iconRotation: ShellState.trayOpen ? 180 : 0
            active: ShellState.trayOpen
            onClicked: ShellState.toggleTray(root.screen.name)
        }

        // System status pill (Network, Bluetooth, Brightness, Audio, Tray)
        Rectangle {
            id: statusPill
            implicitHeight: 32
            implicitWidth: statusIconsRow.implicitWidth + 10
            radius: 6
            color: ShellState.quickOpen ? Theme.cardHover : "transparent"

            RowLayout {
                id: statusIconsRow
                anchors.centerIn: parent
                spacing: 3

                Repeater {
                    model: TrayConfig.pinnedItems

                    Item {
                        id: trayItemContainer
                        required property var modelData
                        required property int index

                        property real pressStartX: 0
                        property real pressStartY: 0
                        property real dragOffsetX: 0
                        property real dragOffsetY: 0
                        property bool isDragging: false
                        property bool hasPress: false

                        onIndexChanged: {
                            if (!isDragging) {
                                pressStartX = 0;
                                pressStartY = 0;
                                dragOffsetX = 0;
                                dragOffsetY = 0;
                            }
                        }

                        onModelDataChanged: {
                            if (!isDragging) {
                                pressStartX = 0;
                                pressStartY = 0;
                                dragOffsetX = 0;
                                dragOffsetY = 0;
                            }
                        }

                        implicitWidth: (!trayIconImg.visible && fallbackText.implicitWidth > 16) ? Math.max(24, Math.ceil(fallbackText.implicitWidth + 8)) : 24
                        implicitHeight: 26
                        z: isDragging ? 1000 : 1

                        Rectangle {
                            anchors.fill: parent
                            radius: 4
                            color: itemMouseArea.containsMouse ? "#20ffffff" : "transparent"
                            opacity: trayItemContainer.isDragging ? 0.75 : 1.0
                            scale: trayItemContainer.isDragging ? 1.2 : 1.0

                            Behavior on scale { NumberAnimation { duration: SettingsService.reducedMotion ? 0 : 90; easing.type: Easing.OutQuad } }
                            Behavior on opacity { NumberAnimation { duration: SettingsService.reducedMotion ? 0 : 90 } }

                            transform: Translate {
                                x: trayItemContainer.dragOffsetX
                                y: trayItemContainer.dragOffsetY
                            }

                            Image {
                                id: trayIconImg
                                anchors.centerIn: parent
                                width: 16
                                height: 16
                                sourceSize: Qt.size(32, 32)
                                source: {
                                    const ic = trayItemContainer.modelData.icon;
                                    if (!ic) return "";
                                    const lower = ic.toLowerCase();
                                    if (lower === "steam" || lower.includes("steam")) return Quickshell.shellPath("assets/steam.svg");
                                    return (ic.startsWith("/") || ic.startsWith("image://")) ? ic : Quickshell.iconPath(ic, "application-x-executable");
                                }
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                mipmap: true
                                visible: status === Image.Ready
                            }

                            Text {
                                id: fallbackText
                                anchors.centerIn: parent
                                text: trayItemContainer.modelData.fallback || "•"
                                visible: !trayIconImg.visible
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }
                        }

                        MouseArea {
                            id: itemMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

                            onWheel: event => {
                                const dir = event.angleDelta.y > 0 ? 1 : -1;
                                if (trayItemContainer.modelData.wheel) {
                                    trayItemContainer.modelData.wheel(dir);
                                } else if (trayItemContainer.modelData.id === "sys-brightness") {
                                    ShellState.adjustBrightness(dir * 0.05);
                                } else if (trayItemContainer.modelData.id === "sys-audio") {
                                    ShellState.adjustVolume(dir * 0.02);
                                }
                            }

                            onPressed: event => {
                                if (event.button === Qt.RightButton) {
                                    ShellState.trayOpen = false;
                                    ShellState.taskMenusCloseRequested();
                                }
                                const keepTray = ShellState.trayOpen;
                                if (ShellState.quickOpen || ShellState.startOpen || ShellState.notifOpen || ShellState.audioMixerOpen || ShellState.settingsOpen || ShellState.clipboardOpen) {
                                    ShellState.closeFlyouts(false);
                                    if (keepTray) ShellState.trayOpen = true;
                                }
                                if (event.button === Qt.LeftButton) {
                                    const pos = itemMouseArea.mapToItem(statusIconsRow, event.x, event.y);
                                    trayItemContainer.hasPress = true;
                                    trayItemContainer.pressStartX = pos.x;
                                    trayItemContainer.pressStartY = pos.y;
                                    trayItemContainer.isDragging = false;
                                    trayItemContainer.dragOffsetX = 0;
                                    trayItemContainer.dragOffsetY = 0;
                                }
                            }

                            onPositionChanged: event => {
                                if (pressed && trayItemContainer.hasPress && (pressedButtons & Qt.LeftButton)) {
                                    const pos = itemMouseArea.mapToItem(statusIconsRow, event.x, event.y);
                                    const dx = pos.x - trayItemContainer.pressStartX;
                                    const dy = pos.y - trayItemContainer.pressStartY;
                                    if (!trayItemContainer.isDragging && (Math.abs(dx) >= 6 || Math.abs(dy) >= 6)) {
                                        trayItemContainer.isDragging = true;
                                    }
                                    if (trayItemContainer.isDragging) {
                                        const slotWidth = (trayItemContainer.width > 0 ? trayItemContainer.width : 24) + statusIconsRow.spacing;
                                        const minOffset = -trayItemContainer.index * slotWidth;
                                        const maxOffset = (TrayConfig.pinnedItems.length - 1 - trayItemContainer.index) * slotWidth;
                                        if (!trayItemContainer.modelData?.isSystem && (ShellState.trayOpen || dy < -10)) {
                                            trayItemContainer.dragOffsetX = Math.min(maxOffset + 30, dx);
                                        } else {
                                            trayItemContainer.dragOffsetX = Math.max(minOffset - 25, Math.min(maxOffset + 25, dx));
                                        }
                                        trayItemContainer.dragOffsetY = dy;
                                    }
                                }
                            }

                            onCanceled: {
                                trayItemContainer.hasPress = false;
                                trayItemContainer.pressStartX = 0;
                                trayItemContainer.pressStartY = 0;
                                trayItemContainer.dragOffsetX = 0;
                                trayItemContainer.dragOffsetY = 0;
                                trayItemContainer.isDragging = false;
                            }

                            onReleased: event => {
                                if (event.button === Qt.MiddleButton) {
                                    if (trayItemContainer.modelData.secondaryActivate) {
                                        trayItemContainer.modelData.secondaryActivate();
                                    } else if (trayItemContainer.modelData.id === "sys-audio") {
                                        ShellState.toggleMute();
                                    }
                                    return;
                                }
                                if (event.button === Qt.RightButton) {
                                    ShellState.trayOpen = false;
                                    trayItemMenu.openFor(trayItemContainer, trayItemContainer.modelData);
                                    return;
                                }
                                if (trayItemContainer.isDragging) {
                                    const curIdx = trayItemContainer.index;
                                    const curOffsetY = trayItemContainer.dragOffsetY;
                                    const curOffsetX = trayItemContainer.dragOffsetX;
                                    const isSystemIcon = !!trayItemContainer.modelData?.isSystem;
                                    const slotWidth = (trayItemContainer.width > 0 ? trayItemContainer.width : 24) + statusIconsRow.spacing;
                                    const minOffset = -curIdx * slotWidth;
                                    const maxOffset = (TrayConfig.pinnedItems.length - 1 - curIdx) * slotWidth;

                                    trayItemContainer.hasPress = false;
                                    trayItemContainer.pressStartX = 0;
                                    trayItemContainer.pressStartY = 0;
                                    trayItemContainer.dragOffsetX = 0;
                                    trayItemContainer.dragOffsetY = 0;
                                    trayItemContainer.isDragging = false;

                                    // 1. App icon dropped towards hidden tray (to the left onto chevron or up towards popup)
                                    if (!isSystemIcon && (curOffsetX < minOffset - 15 || (ShellState.trayOpen && (curOffsetY < -20 || curOffsetX < minOffset - 10)))) {
                                        TrayConfig.unpin(trayItemContainer.modelData);
                                        return;
                                    }

                                    // 2. System icon dragged past left edge towards tray: cancel and snap back
                                    if (isSystemIcon && curOffsetX < minOffset - 15) {
                                        return;
                                    }

                                    // 3. Reorder slot on taskbar
                                    const offsetSlots = Math.round(curOffsetX / slotWidth);
                                    if (offsetSlots !== 0) {
                                        const targetIndex = Math.max(0, Math.min(TrayConfig.pinnedItems.length - 1, curIdx + offsetSlots));
                                        if (targetIndex !== curIdx) {
                                            TrayConfig.movePinned(curIdx, targetIndex);
                                        }
                                    }
                                } else {
                                    trayItemContainer.hasPress = false;
                                    trayItemContainer.pressStartX = 0;
                                    trayItemContainer.pressStartY = 0;
                                    if (trayItemContainer.modelData.id === "sys-audio") {
                                        ShellState.toggleMixer(root.screen.name);
                                    } else if (trayItemContainer.modelData.id === "sys-notifications") {
                                        ShellState.toggleNotif(root.screen.name, "notifications");
                                    } else if (trayItemContainer.modelData.activate) {
                                        ShellState.useScreen(root.screen.name);
                                        trayItemContainer.modelData.activate();
                                    } else if (trayItemContainer.modelData.isSystem) {
                                        ShellState.toggleQuick(root.screen.name);
                                    }
                                }
                            }
                        }
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                z: -1
                hoverEnabled: true
                onClicked: ShellState.toggleQuick(root.screen.name)
            }
        }

        // Clock & Date button
        Rectangle {
            id: clockBtn
            implicitWidth: 62
            implicitHeight: 32
            radius: 6
            color: (clockMouse.containsMouse || ShellState.notifOpen) ? Theme.cardHover : "transparent"

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 0
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.formatTime12(ShellState.currentHour, ShellState.currentMinute)
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Qt.formatDate(ShellState.currentDate, "dd.MM.yyyy")
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                }
            }

            MouseArea {
                id: clockMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: ShellState.toggleNotif(root.screen.name, "calendar")
            }
        }
    }

    LazyLoader {
        property bool loaded: false
        active: (ShellState.startOpen && root.ownsPopup()) || (!SettingsService.unloadClosedFlyouts && loaded)
        onActiveChanged: if (ShellState.startOpen && root.ownsPopup()) loaded = true
        StartMenu { anchorItem: startButton }
    }

    LazyLoader {
        property bool loaded: false
        active: (ShellState.notifOpen && root.ownsPopup()) || (!SettingsService.unloadClosedFlyouts && loaded)
        onActiveChanged: if (ShellState.notifOpen && root.ownsPopup()) loaded = true
        NotificationCenter { anchorItem: clockBtn }
    }

    LazyLoader {
        property bool loaded: false
        active: (ShellState.quickOpen && root.ownsPopup()) || (!SettingsService.unloadClosedFlyouts && loaded)
        onActiveChanged: if (ShellState.quickOpen && root.ownsPopup()) loaded = true
        QuickSettings { anchorItem: statusPill }
    }

    LazyLoader {
        property bool loaded: false
        active: (ShellState.audioMixerOpen && root.ownsPopup()) || (!SettingsService.unloadClosedFlyouts && loaded)
        onActiveChanged: if (ShellState.audioMixerOpen && root.ownsPopup()) loaded = true
        AudioMixer { anchorItem: statusPill }
    }

    LazyLoader {
        active: ShellState.trayOpen && root.ownsPopup()
        TrayOverflow { anchorItem: trayArrow }
    }
    LazyLoader {
        active: ShellState.clipboardOpen && root.ownsPopup()
        ClipboardPanel { anchorItem: statusPill }
    }
    LazyLoader {
        active: ShellState.emojiOpen && root.ownsPopup()
        EmojiPicker { anchorItem: statusPill }
    }
    TrayItemMenu {
        id: trayItemMenu
    }
    LazyLoader {
        id: taskPreviewLoader
        TaskPreview {
            onPreviewVisibleChanged: if (!previewVisible) Qt.callLater(() => {
                if (!previewVisible) taskPreviewLoader.active = false;
            })
        }
    }
    TaskContextMenu {
        id: taskContextMenu
        onWindowActionRequested: (target, actionName, appId, launchCommand) => root.queueWindowAction(target, actionName, appId, launchCommand)
    }
}
