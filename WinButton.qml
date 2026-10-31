import QtQuick
import Quickshell
import qs

Item {
    id: root
    property string icon: ""
    property string accessibleName: fallback || icon
    activeFocusOnTab: enabled
    Accessible.role: Accessible.Button
    Accessible.name: accessibleName
    Accessible.onPressAction: if (enabled) clicked()
    Keys.onReturnPressed: clicked()
    Keys.onSpacePressed: clicked()
    Keys.onMenuPressed: rightClicked(width / 2, height / 2)
    property string fallback: ""
    property int iconSize: 22
    property bool active: false
    property real iconRotation: 0
    property bool isRunning: false
    property bool showIndicator: false
    property bool draggable: false
    property int dragIndex: -1
    property int maxDragIndex: -1
    property real slotSpacing: 3
    property bool hasAudio: false
    property bool audioMuted: false
    readonly property bool containsMouse: mouse.containsMouse
    signal clicked()
    signal rightClicked(real x, real y)
    signal dragReordered(int fromIndex, int toIndex)
    signal audioMuteToggled()

    property real pressStartX: 0
    property real dragOffsetX: 0
    property bool isDragging: false

    onDragIndexChanged: {
        root.pressStartX = 0;
        root.dragOffsetX = 0;
        root.isDragging = false;
    }

    implicitWidth: 38
    implicitHeight: 38
    z: root.isDragging ? 1000 : 1

    function getResolvedSource() {
        if (!root.icon) return "";
        if (root.icon.startsWith("/") || root.icon.startsWith("file://") || root.icon.startsWith("image://")) {
            return root.icon;
        }
        const lower = root.icon.toLowerCase();
        if (lower === "steam" || lower === "com.valvesoftware.steam" || lower.includes("steam")) {
            return Quickshell.shellPath("assets/steam.svg");
        }
        if (lower.includes("abdownloadmanager") || lower.includes("ab-download-manager") || lower.includes("ab download manager")) {
            return "file:///opt/ABDownloadManager/lib/ABDownloadManager.png";
        }
        if (lower === "weylume-settings" || lower === "preferences-system" || lower === "org.quickshell" || (root.accessibleName || "").toLowerCase() === "settings" || lower.includes("weylume-gear")) {
            return Theme.settingsIcon;
        }
        const p = Quickshell.iconPath(root.icon);
        if (p && p.toString() !== "") return p;
        return "";
    }

    // Moving Visual Body (translates smoothly during drag without moving the MouseArea)
    Rectangle {
        anchors.fill: parent
        radius: 6
        color: mouse.containsMouse ? (Theme.isDark ? "#14ffffff" : "#14000000") : "transparent"
        border.width: 0
        opacity: root.isDragging ? 0.85 : 1.0
        scale: root.isDragging ? 1.15 : 1.0

        Behavior on color { ColorAnimation { duration: SettingsService.reducedMotion ? 0 : 120 } }
        Behavior on scale { NumberAnimation { duration: SettingsService.reducedMotion ? 0 : 90; easing.type: Easing.OutQuad } }

        transform: Translate {
            x: root.dragOffsetX
        }

        Image {
            id: iconImage
            anchors.centerIn: parent
            anchors.verticalCenterOffset: (root.showIndicator && (root.isRunning || root.active)) ? -2 : 0
            width: root.iconSize
            height: root.iconSize
            sourceSize: Qt.size(root.iconSize * 3, root.iconSize * 3)
            source: root.getResolvedSource()
            fillMode: Image.PreserveAspectFit
            visible: status === Image.Ready
            smooth: true
            mipmap: true
            rotation: root.iconRotation
            Behavior on rotation { NumberAnimation { duration: SettingsService.reducedMotion ? 0 : 120; easing.type: Easing.OutQuad } }
        }

        Text {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: (root.showIndicator && (root.isRunning || root.active)) ? -2 : 0
            text: root.fallback
            visible: iconImage.status !== Image.Ready
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: root.iconSize
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            rotation: root.iconRotation
            Behavior on rotation { NumberAnimation { duration: SettingsService.reducedMotion ? 0 : 120; easing.type: Easing.OutQuad } }
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 2
            width: 4
            height: 4
            radius: 2
            visible: root.showIndicator && (root.isRunning || root.active)
            color: root.active ? Theme.accent : "transparent"
            border.width: root.active ? 0 : 1
            border.color: Theme.accent
            smooth: true
            antialiasing: true
        }

        // Small speaker badge on top right
        Rectangle {
            visible: root.hasAudio
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 2
            anchors.rightMargin: 2
            width: 14
            height: 14
            radius: 7
            color: Theme.card
            border.width: 1
            border.color: root.audioMuted ? "#ff4444" : Theme.border
            z: 50

            Image {
                anchors.centerIn: parent
                width: 9
                height: 9
                sourceSize: Qt.size(18, 18)
                source: root.audioMuted ? "assets/speaker-muted-mono.svg" : "assets/volume.svg"
                fillMode: Image.PreserveAspectFit
                opacity: 0.95
                smooth: true
                mipmap: true
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: root.audioMuteToggled()
            }
        }
    }

    // Stationary MouseArea - Captures mouse and tracks cursor smoothly
    MouseArea {
        id: mouse
        onPressAndHold: event => { if (!root.isDragging) root.rightClicked(event.x, event.y); }
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onPressed: event => {
            if (root.draggable && (ShellState.startOpen || ShellState.quickOpen || ShellState.notifOpen || ShellState.trayOpen || ShellState.audioMixerOpen || ShellState.settingsOpen || ShellState.clipboardOpen)) {
                ShellState.closeFlyouts(false);
            }
            if (root.hasAudio && event.x >= (root.width - 16) && event.y <= 16) {
                root.audioMuteToggled();
                return;
            }
            if (event.button === Qt.LeftButton && root.draggable) {
                const global = mouse.mapToItem(null, event.x, event.y);
                root.pressStartX = global.x;
                root.isDragging = false;
                root.dragOffsetX = 0;
            }
        }

        onPositionChanged: event => {
            if (pressed && (pressedButtons & Qt.LeftButton) && root.draggable && root.pressStartX !== 0) {
                const global = mouse.mapToItem(null, event.x, event.y);
                const dx = global.x - root.pressStartX;
                if (!root.isDragging && Math.abs(dx) >= 12) {
                    root.isDragging = true;
                }
                if (root.isDragging) {
                    const slotWidth = root.width + root.slotSpacing;
                    const minOffset = -root.dragIndex * slotWidth;
                    const maxOffset = (root.maxDragIndex >= 0 ? (root.maxDragIndex - root.dragIndex) : 0) * slotWidth;
                    root.dragOffsetX = Math.max(minOffset, Math.min(maxOffset, dx));
                }
            }
        }

        onCanceled: {
            root.pressStartX = 0;
            root.dragOffsetX = 0;
            root.isDragging = false;
        }

        onReleased: event => {
            if (root.hasAudio && event.x >= (root.width - 16) && event.y <= 16) {
                return;
            }
            if (event.button === Qt.RightButton) {
                root.rightClicked(event.x, event.y);
                return;
            }
            if (root.isDragging) {
                const slotWidth = root.width + root.slotSpacing;
                const offsetSlots = Math.round(root.dragOffsetX / slotWidth);
                const from = root.dragIndex;
                root.pressStartX = 0;
                root.dragOffsetX = 0;
                root.isDragging = false;

                if (offsetSlots !== 0 && from >= 0) {
                    const maxIdx = root.maxDragIndex >= 0 ? root.maxDragIndex : (PinnedApps?.items ? (PinnedApps.items.length - 1) : (from + offsetSlots));
                    const targetIndex = Math.max(0, Math.min(maxIdx, from + offsetSlots));
                    if (!isNaN(targetIndex) && targetIndex !== from) {
                        root.dragReordered(from, targetIndex);
                    }
                }
            } else {
                root.pressStartX = 0;
                root.clicked();
            }
        }
    }
}
