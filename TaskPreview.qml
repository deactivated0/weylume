import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs

PopupWindow {
    id: root

    property var anchorItem: null
    property var windows: []
    property string appLabel: ""
    property string appIcon: ""
    property bool previewVisible: false
    property real previewTimestamp: 0
    property bool captureQueued: false

    property var manifest: []
    function previewPath(appId, title) {
        const matches = root.manifest.filter(w => w.app === appId && w.title === title);
        // The Quickshell toplevel API has no ext-list identifier. Never attach
        // an arbitrary thumbnail to two indistinguishable native windows.
        return matches.length === 1 && matches[0].path
            ? "file://" + matches[0].path + "?t=" + root.previewTimestamp : "";
    }
    function capture() {
        previewCapture.stdinEnabled = true;
        previewCapture.running = true;
    }

    function openFor(item, windowList, label, icon) {
        hideTimer.stop();
        if (!windowList || windowList.length === 0) {
            dismiss();
            return;
        }
        if (anchorItem !== item) {
            previewVisible = false;
        }
        anchorItem = item;
        windows = windowList;
        appLabel = label || "";
        appIcon = icon || "";
        if (previewCapture.running) captureQueued = true;
        else capture();
        previewVisible = true;
    }

    function dismiss() {
        previewVisible = false;
        captureQueued = false;
        if (previewCapture.running) previewCapture.running = false;
        anchorItem = null;
        windows = [];
        hideTimer.stop();
    }

    function scheduleHide(ms) {
        hideTimer.interval = ms || 350;
        hideTimer.restart();
    }

    function cancelHide() {
        hideTimer.stop();
    }

    Timer {
        id: hideTimer
        interval: 350
        repeat: false
        onTriggered: {
            const mouseOnPreview = frameHover.hovered;
            const mouseOnAnchor = Boolean(root.anchorItem && root.anchorItem.containsMouse);
            if (!mouseOnPreview && !mouseOnAnchor) {
                root.dismiss();
            }
        }
    }

    Process {
        id: previewCapture
        command: [Quickshell.shellPath("weylume-native"), "previews"]
        property var received: []
        onStarted: {
            received = [];
            write(JSON.stringify(root.windows.map(w => ({ app: String(w.appId || ""), title: String(w.title || "") }))));
            stdinEnabled = false;
        }
        stdout: SplitParser {
            onRead: line => { try { previewCapture.received.push(JSON.parse(line)); } catch (error) {} }
        }
        onExited: {
            root.manifest = received;
            root.previewTimestamp = Date.now();
            if (root.captureQueued && root.previewVisible) {
                root.captureQueued = false;
                root.capture();
            }
        }
    }

    visible: previewVisible && (windows.length > 0) && anchorItem !== null
    implicitWidth: mainFrame.implicitWidth + 16
    implicitHeight: mainFrame.implicitHeight + 16
    color: "transparent"
    surfaceFormat.opaque: false
    anchor.item: anchorItem
    anchor.edges: Edges.Top
    anchor.gravity: Edges.Top

    onVisibleChanged: {
        if (!visible) previewVisible = false;
    }

    Rectangle {
        id: mainFrame
        anchors.centerIn: parent
        implicitWidth: cardRow.implicitWidth + 16
        implicitHeight: cardRow.implicitHeight + 16
        radius: 10
        color: "#f4080808"
        border.width: 1
        border.color: "#282828"

        HoverHandler {
            id: frameHover
            onHoveredChanged: {
                if (hovered) {
                    hideTimer.stop();
                } else {
                    root.scheduleHide(350);
                }
            }
        }

        RowLayout {
            id: cardRow
            anchors.centerIn: parent
            spacing: 8

            Repeater {
                model: root.windows

                Rectangle {
                    id: winCard
                    required property var modelData
                    required property int index

                    readonly property bool isActive: Boolean(winCard.modelData?.activated)
                    readonly property bool isMinimized: Boolean(winCard.modelData?.minimized)
                    readonly property string winTitle: winCard.modelData?.title || root.appLabel || "Window"

                    Layout.preferredWidth: 230
                    Layout.preferredHeight: 155
                    radius: 8
                    color: cardMouseArea.containsMouse ? "#1c1c1c" : "#111111"
                    border.width: 1
                    border.color: winCard.isActive ? "#ffffff" : (cardMouseArea.containsMouse ? "#484848" : "#202020")

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 7
                        spacing: 5

                        // 1. Card Header: App Icon + Title + Close Button
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Image {
                                Layout.preferredWidth: 15
                                Layout.preferredHeight: 15
                                sourceSize: Qt.size(30, 30)
                                source: {
                                    const ic = root.appIcon;
                                    if (!ic) return "";
                                    const lower = ic.toLowerCase();
                                    if (lower === "steam" || lower.includes("steam")) return Quickshell.shellPath("assets/steam.svg");
                                    if (lower === "weylume-settings" || lower === "preferences-system" || (root.appLabel && root.appLabel.toLowerCase() === "settings") || lower.includes("weylume-gear") || (winCard.winTitle && winCard.winTitle.toLowerCase() === "settings")) return Theme.settingsIcon;
                                    return (ic.startsWith("/") || ic.startsWith("image://") || ic.startsWith("file://")) ? ic : Quickshell.iconPath(ic, "application-x-executable");
                                }
                                fillMode: Image.PreserveAspectFit
                                visible: status === Image.Ready
                            }

                            Text {
                                Layout.fillWidth: true
                                text: winCard.winTitle
                                color: "#ffffff"
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            // Close Button (✕)
                            Rectangle {
                                width: 16
                                height: 16
                                radius: 4
                                color: closeBtnMouse.containsMouse ? "#2a2a2a" : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: "✕"
                                    color: closeBtnMouse.containsMouse ? "#ffffff" : "#888888"
                                    font.pixelSize: 8
                                    font.weight: Font.Bold
                                }

                                MouseArea {
                                    id: closeBtnMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (winCard.modelData) {
                                             try { winCard.modelData.close(); } catch (e) {}
                                        }
                                        if (root.windows.length <= 1) {
                                            root.dismiss();
                                        }
                                    }
                                }
                            }
                        }

                        // 2. Window Viewport: Actual Window Screenshot Preview
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 5
                            color: "#050505"
                            border.width: 1
                            border.color: "#161616"
                            clip: true

                            // Actual Window Image Preview
                            Image {
                                id: winScreenshot
                                anchors.fill: parent
                                anchors.margins: 1
                                fillMode: Image.PreserveAspectFit
                                source: root.previewPath(winCard.modelData?.appId, winCard.modelData?.title)
                                smooth: true
                                mipmap: true
                                cache: false
                                asynchronous: true
                                opacity: winCard.isMinimized ? 0.7 : 1.0
                                visible: status === Image.Ready
                            }

                            // Fallback icon placeholder if screenshot not ready yet
                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 4
                                visible: !winScreenshot.visible

                                Image {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.preferredWidth: 36
                                    Layout.preferredHeight: 36
                                    sourceSize: Qt.size(72, 72)
                                    source: {
                                        const ic = root.appIcon;
                                        if (!ic) return "";
                                        const lower = ic.toLowerCase();
                                        if (lower === "steam" || lower.includes("steam")) return Quickshell.shellPath("assets/steam.svg");
                                        if (lower === "weylume-settings" || lower === "preferences-system" || (root.appLabel && root.appLabel.toLowerCase() === "settings") || lower.includes("weylume-gear") || (winCard.winTitle && winCard.winTitle.toLowerCase() === "settings")) return Theme.settingsIcon;
                                        return (ic.startsWith("/") || ic.startsWith("image://") || ic.startsWith("file://")) ? ic : Quickshell.iconPath(ic, "application-x-executable");
                                    }
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    mipmap: true
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: cardMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const win = winCard.modelData;
                            root.dismiss();
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
