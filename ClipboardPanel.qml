import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs

PopupWindow {
    id: root
    required property var anchorItem
    Shortcut { sequence: "Escape"; onActivated: ShellState.closeFlyouts() }
    property string query: ""
    visible: ShellState.clipboardOpen
    implicitWidth: Math.min(380, Math.max(280, (ShellState.popupScreen?.width || 1920) - 8))
    implicitHeight: Math.min(520, Math.max(200, (ShellState.popupScreen?.height || 1080) - Theme.taskbarHeight - 12))
    color: "transparent"
    grabFocus: true
    surfaceFormat.opaque: false
    anchor.item: anchorItem
    anchor.edges: Edges.Top | Edges.Right
    anchor.gravity: Edges.Top | Edges.Left

    onVisibleChanged: {
        if (visible) Qt.callLater(() => search.forceActiveFocus());
        else if (ShellState.clipboardOpen) ShellState.clipboardOpen = false;
    }

    readonly property var filtered: ClipboardService.history.filter(item => {
        if (!item) return false;
        if (root.query.trim() === "") return true;
        const q = root.query.trim().toLowerCase();
        if (item.type === "image") return "image".includes(q) || "screenshot".includes(q);
        return (item.text || "").toLowerCase().includes(q);
    })

    function findActualIndex(item) {
        if (!item) return -1;
        return ClipboardService.history.findIndex(entry => {
            if (!entry) return false;
            if (item.type === "image" && entry.type === "image") {
                return (item.hash && entry.hash && item.hash === entry.hash) || (item.path && entry.path && item.path === entry.path);
            }
            return entry.type !== "image" && entry.text === item.text;
        });
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 4
        radius: 14
        color: Theme.background
        border.width: 1
        border.color: Theme.border
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            // Header Row
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "Clipboard history"
                    color: "#ffffff"
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }

                Rectangle {
                    radius: 8
                    color: "#121212"
                    border.width: 1
                    border.color: "#222222"
                    implicitWidth: countText.implicitWidth + 10
                    implicitHeight: 18

                    Text {
                        id: countText
                        anchors.centerIn: parent
                        text: ClipboardService.history.length + " items"
                        color: "#888888"
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                    }
                }

                Item { Layout.fillWidth: true }

                // Clear All Button (removes unpinned items)
                Rectangle {
                    width: 26; height: 26; radius: 6
                    color: clearMouse.containsMouse ? "#222222" : "#121212"
                    border.width: 1
                    border.color: clearMouse.containsMouse ? "#333333" : "#1c1c1c"
                    visible: ClipboardService.history.some(it => !it.pinned)

                    Text {
                        anchors.centerIn: parent
                        text: "⌫"
                        color: clearMouse.containsMouse ? "#ffffff" : "#999999"
                        font.pixelSize: 11
                    }

                    MouseArea {
                        id: clearMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ClipboardService.clear()
                    }
                }

                // Close Button
                Rectangle {
                    width: 26; height: 26; radius: 6
                    color: closeMouse.containsMouse ? "#222222" : "#121212"
                    border.width: 1
                    border.color: closeMouse.containsMouse ? "#333333" : "#1c1c1c"

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: closeMouse.containsMouse ? "#ffffff" : "#999999"
                        font.pixelSize: 9
                    }

                    MouseArea {
                        id: closeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ShellState.closeFlyouts()
                    }
                }
            }

            // Search Bar
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 34
                radius: 8
                color: "#0c0c0c"
                border.width: 1
                border.color: search.activeFocus ? "#ffffff" : "#202020"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 8
                    spacing: 8

                    Image {
                        source: "assets/search.svg"
                        Layout.preferredWidth: 13
                        Layout.preferredHeight: 13
                        sourceSize: Qt.size(26, 26)
                        fillMode: Image.PreserveAspectFit
                        opacity: search.activeFocus ? 0.9 : 0.5
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        TextInput {
                            id: search
                            anchors.fill: parent
                            verticalAlignment: TextInput.AlignVCenter
                            color: "#ffffff"
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            text: root.query
                            Accessible.name: "Search clipboard history"
                            onTextChanged: { root.query = text; historyList.currentIndex = root.filtered.length ? 0 : -1; }
                            Keys.onDownPressed: historyList.currentIndex = Math.min(root.filtered.length - 1, historyList.currentIndex + 1)
                            Keys.onUpPressed: historyList.currentIndex = Math.max(root.filtered.length ? 0 : -1, historyList.currentIndex - 1)
                            Keys.onReturnPressed: {
                                if (historyList.currentIndex >= 0 && historyList.currentIndex < root.filtered.length) {
                                    ClipboardService.copyItem(root.filtered[historyList.currentIndex]);
                                    ShellState.closeFlyouts();
                                }
                            }
                            Keys.onEscapePressed: ShellState.closeFlyouts()
                        }

                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            visible: search.text.length === 0
                            text: "Search copied text or images..."
                            color: "#505050"
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                    }

                    // Clear search button
                    Rectangle {
                        visible: search.text.length > 0
                        width: 18; height: 18; radius: 9
                        color: clearSearchMouse.containsMouse ? "#282828" : "#181818"

                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            color: "#aaaaaa"
                            font.pixelSize: 8
                        }

                        MouseArea {
                            id: clearSearchMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { search.text = ""; root.query = ""; }
                        }
                    }
                }
            }

            // Empty State
            Item {
                visible: root.filtered.length === 0
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "📋"
                        font.pixelSize: 28
                        opacity: 0.4
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: ClipboardService.history.length === 0 ? "Copied items will appear here" : "No matching clipboard items"
                        color: "#666666"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                }
            }

            // Clipboard History List
            ListView {
                id: historyList
                reuseItems: true
                onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
                visible: root.filtered.length > 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8
                clip: true
                model: root.filtered

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index

                    readonly property bool isImage: row.modelData.type === "image"
                    readonly property bool isPinned: Boolean(row.modelData.pinned)
                    property bool justCopied: false

                    Timer {
                        id: copiedTimer
                        interval: 1200
                        repeat: false
                        onTriggered: row.justCopied = false
                    }

                    width: ListView.view.width
                    height: isImage ? 152 : 78
                    radius: 10
                    color: rowMouse.containsMouse ? "#151515" : "#0c0c0c"
                    border.width: 1
                    border.color: isPinned ? "#3b82f6" : (rowMouse.containsMouse ? "#282828" : "#181818")

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6

                        // Body: Image preview OR Text content
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            // 1. Picture Preview (for image clipboard items)
                            Rectangle {
                                visible: row.isImage
                                anchors.fill: parent
                                radius: 6
                                color: "#060606"
                                border.width: 1
                                border.color: "#181818"
                                clip: true

                                Image {
                                    id: imgPreview
                                    anchors.centerIn: parent
                                    width: parent.width - 6
                                    height: parent.height - 6
                                    sourceSize: Qt.size(80, 80)
                                    source: row.modelData.path ? ("file://" + row.modelData.path) : ""
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    mipmap: true
                                    asynchronous: true
                                    cache: true
                                }
                            }

                            // 2. Text Snippet (for text clipboard items)
                            Text {
                                visible: !row.isImage
                                anchors.fill: parent
                                text: (row.modelData.text || "").replace(/\s+/g, " ")
                                color: rowMouse.containsMouse ? "#ffffff" : "#e0e0e0"
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                wrapMode: Text.Wrap
                            }
                        }

                        // Footer: Timestamp on left, Action Buttons (Pin, Copy, Delete) on right
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                Layout.fillWidth: true
                                text: (row.isImage ? "Image • " : "") + Qt.formatDateTime(new Date(Number(row.modelData.timestamp)), "MMM d, HH:mm")
                                color: "#666666"
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                elide: Text.ElideRight
                            }

                            // Action 1: Pin Button
                            Rectangle {
                                width: 26; height: 26; radius: 6
                                color: row.isPinned ? "#1e3a5f" : (pinMouse.containsMouse ? "#242424" : "transparent")
                                border.width: 1
                                border.color: row.isPinned ? "#3b82f6" : (pinMouse.containsMouse ? "#333333" : "transparent")

                                Image {
                                    anchors.centerIn: parent
                                    width: 13; height: 13
                                    source: row.isPinned ? "assets/pin-filled.svg" : "assets/pin.svg"
                                    sourceSize: Qt.size(26, 26)
                                    fillMode: Image.PreserveAspectFit
                                    opacity: row.isPinned ? 1.0 : (pinMouse.containsMouse ? 0.9 : 0.6)
                                }

                                MouseArea {
                                    id: pinMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        const actual = root.findActualIndex(row.modelData);
                                        if (actual >= 0) ClipboardService.togglePin(actual);
                                    }
                                }
                            }

                            // Action 2: Copy Button (Next to Delete Button)
                            Rectangle {
                                width: 26; height: 26; radius: 6
                                color: row.justCopied ? "#143a1e" : (copyBtnMouse.containsMouse ? "#242424" : "transparent")
                                border.width: 1
                                border.color: row.justCopied ? "#22c55e" : (copyBtnMouse.containsMouse ? "#333333" : "transparent")

                                Image {
                                    anchors.centerIn: parent
                                    width: 13; height: 13
                                    source: row.justCopied ? "assets/check.svg" : "assets/copy.svg"
                                    sourceSize: Qt.size(26, 26)
                                    fillMode: Image.PreserveAspectFit
                                    opacity: row.justCopied ? 1.0 : (copyBtnMouse.containsMouse ? 0.9 : 0.6)
                                }

                                MouseArea {
                                    id: copyBtnMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        ClipboardService.copyItem(row.modelData);
                                        row.justCopied = true;
                                        copiedTimer.restart();
                                    }
                                }
                            }

                            // Action 3: Delete Button (✕)
                            Rectangle {
                                width: 26; height: 26; radius: 6
                                color: removeMouse.containsMouse ? "#331515" : "transparent"
                                border.width: 1
                                border.color: removeMouse.containsMouse ? "#ef4444" : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: "✕"
                                    color: removeMouse.containsMouse ? "#ef4444" : "#888888"
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                }

                                MouseArea {
                                    id: removeMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        const actual = root.findActualIndex(row.modelData);
                                        if (actual >= 0) ClipboardService.removeAt(actual);
                                    }
                                }
                            }
                        }
                    }

                    // Card Primary Click (Click anywhere on card to copy and paste/close)
                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        anchors.rightMargin: 84
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            ClipboardService.copyItem(row.modelData);
                            ShellState.closeFlyouts();
                        }
                    }
                }
            }
        }
    }
}
