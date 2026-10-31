import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs

Item {
    id: root
    clip: true

    readonly property bool isDark: SettingsService.darkMode !== false
    readonly property color colBg: isDark ? "#0A0A0C" : "#F2F2F7"
    readonly property color colSurface: isDark ? "#121216" : "#FFFFFF"
    readonly property color colSurfaceAlt: isDark ? "#18181E" : "#F7F7F8"
    readonly property color colCardHover: isDark ? "#1E1E26" : "#EFEFF4"
    readonly property color colBorder: isDark ? "#24242C" : "#E5E5EA"
    readonly property color colBorderSubtle: isDark ? "#1A1A20" : "#EBEBEF"
    readonly property color colTextPrimary: isDark ? "#F5F5F7" : "#000000"
    readonly property color colTextSecondary: isDark ? "#8E8E93" : "#6E6E73"
    readonly property color colTextMuted: isDark ? "#545458" : "#A2A2A8"
    readonly property color colAccent: isDark ? "#2A82E4" : "#007AFF"
    readonly property color colSwitchOn: isDark ? "#FFFFFF" : "#000000"
    readonly property color colSwitchOff: isDark ? "#282830" : "#D1D1D6"
    readonly property color colSuccess: isDark ? "#30D158" : "#34C759"
    readonly property color colWarning: isDark ? "#FFD60A" : "#FF9500"
    readonly property color colDanger: isDark ? "#FF453A" : "#FF3B30"
    readonly property color colPurple: isDark ? "#BF5AF2" : "#AF52DE"

    property string searchQuery: ""
    property string activeFilter: "all" // all, enabled, disabled, running, user, system, labwc
    property bool showAddModal: false
    property bool showEditModal: false
    property bool showScriptEditor: false
    property var editingItem: null

    // Add modal state
    property int addTab: 0 // 0 = installed, 1 = custom
    property string addSearchQuery: ""
    property string newName: ""
    property string newExec: ""
    property string newIcon: "application-x-executable"
    property string newComment: ""
    property int newDelay: 0
    property bool newTerminal: false

    // Script editor state
    property string labwcScriptEdit: ""

    Component.onCompleted: {
        AutostartService.refresh();
    }

    readonly property var filteredEntries: {
        const list = AutostartService.entries || [];
        const q = searchQuery.toLowerCase().trim();
        return list.filter(item => {
            // Search query match
            if (q.length > 0) {
                const name = (item.name || "").toLowerCase();
                const exec = (item.exec || "").toLowerCase();
                const comm = (item.comment || "").toLowerCase();
                const id = (item.id || "").toLowerCase();
                if (!name.includes(q) && !exec.includes(q) && !comm.includes(q) && !id.includes(q)) {
                    return false;
                }
            }
            // Category filter
            if (activeFilter === "enabled") return item.enabled;
            if (activeFilter === "disabled") return !item.enabled;
            if (activeFilter === "running") return item.running;
            if (activeFilter === "user") return item.source === "user";
            if (activeFilter === "system") return item.source === "system";
            if (activeFilter === "labwc") return item.source === "labwc";
            return true;
        });
    }

    ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true
        contentWidth: availableWidth
        contentHeight: mainCol.implicitHeight + 60
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical: ScrollBar {
            id: vBar
            policy: ScrollBar.AsNeeded
            width: 6
            contentItem: Rectangle {
                implicitWidth: 6
                radius: 3
                color: root.isDark ? (vBar.pressed ? "#505060" : (vBar.hovered ? "#404050" : "#2A2A36")) : (vBar.pressed ? "#9999A0" : (vBar.hovered ? "#B0B0B8" : "#C7C7CC"))
            }
            background: Item {}
        }

        WheelHandler {
            target: null
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                if (scroll.contentHeight <= scroll.height) return;
                const ady = event.angleDelta.y;
                const pdy = event.pixelDelta.y;
                let delta = 0;
                if (pdy !== 0) {
                    delta = -pdy;
                } else if (ady !== 0) {
                    delta = (ady > 0 ? -70 : 70);
                }
                if (delta !== 0) {
                    const maxScroll = Math.max(0, scroll.contentHeight - scroll.height);
                    scroll.contentItem.contentY = Math.max(0, Math.min(maxScroll, scroll.contentItem.contentY + delta));
                }
            }
        }

        Item {
            width: scroll.availableWidth
            implicitHeight: mainCol.implicitHeight + 60
            height: implicitHeight

        ColumnLayout {
            id: mainCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 24
            anchors.rightMargin: 24
            anchors.topMargin: 18
            spacing: 16

            // Metrics Summary Row
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                MetricCard {
                    Layout.fillWidth: true
                    title: "TOTAL APPS"
                    value: String(AutostartService.totalCount)
                    caption: "Configured startup programs"
                    accentColor: root.colAccent
                    iconName: "application-x-executable"
                }

                MetricCard {
                    Layout.fillWidth: true
                    title: "ENABLED"
                    value: String(AutostartService.enabledCount)
                    caption: "Will run on system boot"
                    accentColor: root.colSuccess
                    iconName: "dialog-ok"
                }

                MetricCard {
                    Layout.fillWidth: true
                    title: "ACTIVE NOW"
                    value: String(AutostartService.runningCount)
                    caption: "Processes currently alive"
                    accentColor: root.colSuccess
                    isPulse: true
                    iconName: "system-run"
                }

                MetricCard {
                    Layout.fillWidth: true
                    title: "DELAYED"
                    value: String(AutostartService.delayedCount)
                    caption: "Deferred startup delay"
                    accentColor: root.colWarning
                    iconName: "appointment-soon"
                }
            }

            // Action & Search Toolbar
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                // Search input
                Rectangle {
                    Layout.fillWidth: true
                    height: 36
                    radius: 8
                    color: root.colSurface
                    border.width: 1
                    border.color: searchInput.activeFocus ? root.colAccent : root.colBorder

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        Image {
                            width: 14; height: 14
                            sourceSize: Qt.size(28, 28)
                            source: "assets/search.svg"
                            opacity: 0.5
                        }

                        TextInput {
                            id: searchInput
                            Layout.fillWidth: true
                            text: root.searchQuery
                            onTextChanged: root.searchQuery = text
                            color: root.colTextPrimary
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            clip: true

                            Text {
                                anchors.fill: parent
                                text: "Search autostart apps by name, command, or description..."
                                color: root.colTextMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                visible: !searchInput.text && !searchInput.activeFocus
                            }
                        }

                        Text {
                            visible: root.searchQuery.length > 0
                            text: "✕"
                            color: root.colTextSecondary
                            font.pixelSize: 11
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { searchInput.text = ""; root.searchQuery = ""; }
                            }
                        }
                    }
                }

                // Add Application Button
                Rectangle {
                    width: 130; height: 36
                    radius: 8
                    color: addBtnMouse.containsMouse ? (root.isDark ? "#3590F3" : "#0069D9") : root.colAccent

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 6
                        Text { text: "+"; color: "#FFFFFF"; font.pixelSize: 14; font.weight: Font.Bold }
                        Text { text: "Add Startup App"; color: "#FFFFFF"; font.family: Theme.fontFamily; font.pixelSize: 11; font.weight: Font.DemiBold }
                    }

                    MouseArea {
                        id: addBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.newName = "";
                            root.newExec = "";
                            root.newIcon = "application-x-executable";
                            root.newComment = "";
                            root.newDelay = 0;
                            root.newTerminal = false;
                            root.addSearchQuery = "";
                            root.showAddModal = true;
                        }
                    }
                }

                // Script Editor Toggle Button
                Rectangle {
                    width: 115; height: 36
                    radius: 8
                    color: scriptBtnMouse.containsMouse ? root.colCardHover : root.colSurface
                    border.width: 1
                    border.color: root.showScriptEditor ? root.colAccent : root.colBorder

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 6
                        Image { width: 13; height: 13; sourceSize: Qt.size(26, 26); source: "assets/edit.svg"; opacity: 0.8 }
                        Text { text: "Labwc Script"; color: root.showScriptEditor ? root.colAccent : root.colTextPrimary; font.family: Theme.fontFamily; font.pixelSize: 11; font.weight: Font.Medium }
                    }

                    MouseArea {
                        id: scriptBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.showScriptEditor = !root.showScriptEditor;
                            if (root.showScriptEditor) {
                                AutostartService.loadLabwcScript();
                                root.labwcScriptEdit = AutostartService.labwcScript;
                            }
                        }
                    }
                }

                // Open Autostart Folder Button
                Rectangle {
                    width: 36; height: 36
                    radius: 8
                    color: folderBtnMouse.containsMouse ? root.colCardHover : root.colSurface
                    border.width: 1
                    border.color: root.colBorder

                    Image {
                        anchors.centerIn: parent
                        width: 14; height: 14
                        sourceSize: Qt.size(28, 28)
                        source: "assets/book.svg"
                        opacity: 0.8
                    }

                    MouseArea {
                        id: folderBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: AutostartService.openFolder()
                    }
                }

                // Refresh Button
                Rectangle {
                    width: 36; height: 36
                    radius: 8
                    color: refreshBtnMouse.containsMouse ? root.colCardHover : root.colSurface
                    border.width: 1
                    border.color: root.colBorder

                    Text {
                        anchors.centerIn: parent
                        text: "↻"
                        font.pixelSize: 15
                        color: root.colTextPrimary
                    }

                    MouseArea {
                        id: refreshBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: AutostartService.refresh()
                    }
                }
            }

            // Filter Tabs Bar
            Rectangle {
                Layout.fillWidth: true
                height: 32
                radius: 7
                color: root.isDark ? "#121216" : "#EAEAEA"
                border.width: 1
                border.color: root.colBorder

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 2
                    spacing: 2

                    Repeater {
                        model: [
                            { id: "all", label: "All Items (" + AutostartService.totalCount + ")" },
                            { id: "enabled", label: "Enabled (" + AutostartService.enabledCount + ")" },
                            { id: "disabled", label: "Disabled (" + (AutostartService.totalCount - AutostartService.enabledCount) + ")" },
                            { id: "running", label: "Running Now (" + AutostartService.runningCount + ")" },
                            { id: "user", label: "User Apps" },
                            { id: "system", label: "System (/etc)" },
                            { id: "labwc", label: "Labwc Script" }
                        ]

                        Rectangle {
                            id: fTab
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 5
                            color: root.activeFilter === fTab.modelData.id ? (root.isDark ? "#24242C" : "#FFFFFF") : (fTabMouse.containsMouse ? (root.isDark ? "#18181E" : "#ECECED") : "transparent")
                            border.width: root.activeFilter === fTab.modelData.id ? 1 : 0
                            border.color: root.isDark ? "#383844" : "#D0D0D6"

                            Text {
                                anchors.centerIn: parent
                                text: fTab.modelData.label
                                color: root.activeFilter === fTab.modelData.id ? root.colTextPrimary : root.colTextSecondary
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.weight: root.activeFilter === fTab.modelData.id ? Font.DemiBold : Font.Normal
                            }

                            MouseArea {
                                id: fTabMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.activeFilter = fTab.modelData.id
                            }
                        }
                    }
                }
            }

            // Labwc Script Inline Editor Drawer (if opened)
            Rectangle {
                visible: root.showScriptEditor
                Layout.fillWidth: true
                implicitHeight: scriptCol.implicitHeight + 24
                radius: 10
                color: root.colSurface
                border.width: 1
                border.color: root.colBorder

                ColumnLayout {
                    id: scriptCol
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "Labwc Session Autostart Script (~/.config/labwc/autostart)"
                            color: root.colTextPrimary
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: "Automatic .bak created on save"
                            color: root.colTextMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 180
                        radius: 6
                        color: root.isDark ? "#0A0A0C" : "#F7F7F9"
                        border.width: 1
                        border.color: root.colBorder

                        ScrollView {
                            anchors.fill: parent
                            anchors.margins: 8
                            clip: true

                            TextArea {
                                id: labwcTextArea
                                text: root.labwcScriptEdit.length > 0 ? root.labwcScriptEdit : AutostartService.labwcScript
                                onTextChanged: root.labwcScriptEdit = text
                                color: root.colTextPrimary
                                font.family: "Monospace"
                                font.pixelSize: 11
                                wrapMode: TextEdit.NoWrap
                                background: null
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Item { Layout.fillWidth: true }

                        Rectangle {
                            width: 80; height: 28; radius: 5
                            color: resetBtnM.containsMouse ? root.colCardHover : root.colSurfaceAlt
                            border.width: 1; border.color: root.colBorder
                            Text { anchors.centerIn: parent; text: "Reset"; color: root.colTextSecondary; font.pixelSize: 11 }
                            MouseArea {
                                id: resetBtnM; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    AutostartService.loadLabwcScript();
                                    labwcTextArea.text = AutostartService.labwcScript;
                                    root.labwcScriptEdit = AutostartService.labwcScript;
                                }
                            }
                        }

                        Rectangle {
                            width: 110; height: 28; radius: 5
                            color: saveScriptBtnM.containsMouse ? (root.isDark ? "#3590F3" : "#0069D9") : root.colAccent
                            Text { anchors.centerIn: parent; text: "Save & Apply"; color: "#FFFFFF"; font.pixelSize: 11; font.weight: Font.DemiBold }
                            MouseArea {
                                id: saveScriptBtnM; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    AutostartService.saveLabwcScript(labwcTextArea.text);
                                }
                            }
                        }
                    }
                }
            }

            // Autostart Items List
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                // Empty state notice
                Rectangle {
                    visible: root.filteredEntries.length === 0
                    Layout.fillWidth: true
                    height: 120
                    radius: 10
                    color: root.colSurface
                    border.width: 1
                    border.color: root.colBorder

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "No startup applications found"
                            color: root.colTextPrimary
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.searchQuery ? "No entries match your search query." : "Click '+ Add Startup App' above to add any program to boot startup."
                            color: root.colTextSecondary
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                    }
                }

                Repeater {
                    model: root.filteredEntries

                    Rectangle {
                        id: appCard
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: cardRow.implicitHeight + 20
                        radius: 10
                        color: root.colSurface
                        border.width: 1
                        border.color: appCard.modelData.running ? (root.isDark ? "#283C28" : "#D4EDDA") : root.colBorder

                        RowLayout {
                            id: cardRow
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            anchors.topMargin: 10
                            anchors.bottomMargin: 10
                            spacing: 14

                            // App Icon
                            Rectangle {
                                width: 38; height: 38
                                radius: 8
                                color: root.isDark ? "#1A1A22" : "#EAEAEE"
                                border.width: 1
                                border.color: root.colBorderSubtle

                                Image {
                                    id: appIcon
                                    anchors.centerIn: parent
                                    width: 24; height: 24
                                    sourceSize: Qt.size(48, 48)
                                    source: appCard.modelData.icon ? (appCard.modelData.icon.startsWith("/") ? ("file://" + appCard.modelData.icon) : Quickshell.iconPath(appCard.modelData.icon)) : ""
                                    visible: status === Image.Ready
                                    fillMode: Image.PreserveAspectFit
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: !appIcon.visible
                                    text: (appCard.modelData.name || "A").substring(0, 1).toUpperCase()
                                    color: root.colAccent
                                    font.pixelSize: 14
                                    font.weight: Font.Bold
                                }
                            }

                            // Details
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Text {
                                        text: appCard.modelData.name || appCard.modelData.id
                                        color: appCard.modelData.enabled ? root.colTextPrimary : root.colTextSecondary
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }

                                    // Source Tag
                                    Rectangle {
                                        height: 16
                                        width: srcTxt.implicitWidth + 10
                                        radius: 4
                                        color: appCard.modelData.source === "user" ? (root.isDark ? "#17283C" : "#E1EFFF") : (appCard.modelData.source === "system" ? (root.isDark ? "#2E1A3C" : "#F5E8FF") : (root.isDark ? "#382C10" : "#FFF7D6"))
                                        Text {
                                            id: srcTxt
                                            anchors.centerIn: parent
                                            text: appCard.modelData.source === "user" ? "User Autostart" : (appCard.modelData.source === "system" ? "System Service" : "Labwc Session")
                                            color: appCard.modelData.source === "user" ? root.colAccent : (appCard.modelData.source === "system" ? root.colPurple : root.colWarning)
                                            font.pixelSize: 9
                                            font.weight: Font.Medium
                                        }
                                    }

                                    // Running Status Badge
                                    Rectangle {
                                        height: 16
                                        width: runTxt.implicitWidth + 16
                                        radius: 4
                                        color: appCard.modelData.running ? (root.isDark ? "#16331C" : "#D4EDDA") : (root.isDark ? "#1E1E24" : "#EAEAEE")

                                        RowLayout {
                                            anchors.centerIn: parent
                                            spacing: 4
                                            Rectangle {
                                                width: 5; height: 5; radius: 3
                                                color: appCard.modelData.running ? root.colSuccess : root.colTextMuted
                                            }
                                            Text {
                                                id: runTxt
                                                text: appCard.modelData.running ? ("Running" + (appCard.modelData.pid ? (" • PID " + appCard.modelData.pid) : "")) : "Inactive"
                                                color: appCard.modelData.running ? root.colSuccess : root.colTextMuted
                                                font.pixelSize: 9
                                                font.weight: Font.Medium
                                            }
                                        }
                                    }

                                    // Delay Badge (if > 0)
                                    Rectangle {
                                        visible: appCard.modelData.delay > 0
                                        height: 16
                                        width: delayTxt.implicitWidth + 10
                                        radius: 4
                                        color: root.isDark ? "#2A2412" : "#FFF8E1"
                                        Text {
                                            id: delayTxt
                                            anchors.centerIn: parent
                                            text: appCard.modelData.delay + "s delay"
                                            color: root.colWarning
                                            font.pixelSize: 9
                                            font.weight: Font.Medium
                                        }
                                    }

                                    // Terminal Badge
                                    Rectangle {
                                        visible: appCard.modelData.terminal
                                        height: 16
                                        width: termTxt.implicitWidth + 8
                                        radius: 4
                                        color: root.isDark ? "#202028" : "#E8E8EE"
                                        Text {
                                            id: termTxt
                                            anchors.centerIn: parent
                                            text: "Terminal"
                                            color: root.colTextSecondary
                                            font.pixelSize: 9
                                        }
                                    }
                                }

                                // Comment / Description
                                Text {
                                    visible: (appCard.modelData.comment || "").length > 0
                                    Layout.fillWidth: true
                                    text: appCard.modelData.comment || ""
                                    color: root.colTextSecondary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }

                                // Exec command pill
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 20
                                    radius: 4
                                    color: root.isDark ? "#0D0D11" : "#F0F0F4"
                                    border.width: 1
                                    border.color: root.colBorderSubtle

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 6
                                        anchors.rightMargin: 6
                                        spacing: 6

                                        Text {
                                            Layout.fillWidth: true
                                            text: appCard.modelData.exec || ""
                                            color: root.colTextMuted
                                            font.family: "Monospace"
                                            font.pixelSize: 9
                                            elide: Text.ElideMiddle
                                        }

                                        Text {
                                            text: "copy"
                                            color: root.colAccent
                                            font.pixelSize: 8
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: ClipboardService.add(appCard.modelData.exec)
                                            }
                                        }
                                    }
                                }
                            }

                            // Actions Row
                            RowLayout {
                                spacing: 8

                                // Run Now button
                                Rectangle {
                                    width: 28; height: 28; radius: 6
                                    color: runBtnM.containsMouse ? root.colCardHover : root.colSurfaceAlt
                                    border.width: 1; border.color: root.colBorder

                                    Image {
                                        anchors.centerIn: parent
                                        width: 10; height: 10
                                        sourceSize: Qt.size(20, 20)
                                        source: "assets/play.svg"
                                        opacity: 0.85
                                    }

                                    MouseArea {
                                        id: runBtnM; anchors.fill: parent
                                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: AutostartService.launch(appCard.modelData.exec, appCard.modelData.name)
                                    }
                                }

                                // Edit button
                                Rectangle {
                                    width: 28; height: 28; radius: 6
                                    color: editBtnM.containsMouse ? root.colCardHover : root.colSurfaceAlt
                                    border.width: 1; border.color: root.colBorder

                                    Image {
                                        anchors.centerIn: parent
                                        width: 10; height: 10
                                        sourceSize: Qt.size(20, 20)
                                        source: "assets/edit.svg"
                                        opacity: 0.85
                                    }

                                    MouseArea {
                                        id: editBtnM; anchors.fill: parent
                                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.editingItem = appCard.modelData;
                                            root.newName = appCard.modelData.name || "";
                                            root.newExec = appCard.modelData.exec || "";
                                            root.newIcon = appCard.modelData.icon || "application-x-executable";
                                            root.newComment = appCard.modelData.comment || "";
                                            root.newDelay = appCard.modelData.delay || 0;
                                            root.newTerminal = Boolean(appCard.modelData.terminal);
                                            root.showEditModal = true;
                                        }
                                    }
                                }

                                // Delete button
                                Rectangle {
                                    width: 28; height: 28; radius: 6
                                    color: delBtnM.containsMouse ? (root.isDark ? "#3A1616" : "#FFE5E5") : root.colSurfaceAlt
                                    border.width: 1; border.color: delBtnM.containsMouse ? root.colDanger : root.colBorder

                                    Text {
                                        anchors.centerIn: parent
                                        text: "✕"
                                        font.pixelSize: 11
                                        color: delBtnM.containsMouse ? root.colDanger : root.colTextSecondary
                                    }

                                    MouseArea {
                                        id: delBtnM; anchors.fill: parent
                                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: AutostartService.deleteEntry(appCard.modelData.id, appCard.modelData.name)
                                    }
                                }

                                // Separator
                                Rectangle { width: 1; height: 20; color: root.colBorder }

                                // Main Toggle Switch
                                Rectangle {
                                    width: 36; height: 20; radius: 10
                                    color: appCard.modelData.enabled ? root.colSwitchOn : root.colSwitchOff

                                    Behavior on color { ColorAnimation { duration: SettingsService.reducedMotion ? 0 : 80 } }

                                    Rectangle {
                                        width: 16; height: 16; radius: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: appCard.modelData.enabled ? parent.width - width - 2 : 2
                                        color: appCard.modelData.enabled ? (root.isDark ? "#000000" : "#FFFFFF") : (root.isDark ? "#8E8E93" : "#FFFFFF")
                                        Behavior on color { ColorAnimation { duration: SettingsService.reducedMotion ? 0 : 80 } }
                                        Behavior on x { NumberAnimation { duration: SettingsService.reducedMotion ? 0 : 80 } }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: AutostartService.toggle(appCard.modelData.id, !appCard.modelData.enabled)
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

    // Modal Background Dimmer
    Rectangle {
        anchors.fill: parent
        visible: root.showAddModal || root.showEditModal
        color: root.isDark ? "#B0000000" : "#70000000"
        z: 99

        MouseArea {
            anchors.fill: parent
            onClicked: { root.showAddModal = false; root.showEditModal = false; }
        }
    }

    // Add Application Modal Dialog
    Rectangle {
        visible: root.showAddModal
        anchors.centerIn: parent
        width: 520; height: 500
        radius: 12
        color: root.colSurface
        border.width: 1
        border.color: root.colBorder
        z: 100

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                Text { text: "Add Startup Application"; color: root.colTextPrimary; font.family: Theme.fontFamily; font.pixelSize: 15; font.weight: Font.Bold }
                Item { Layout.fillWidth: true }
                Text {
                    text: "✕"; color: root.colTextSecondary; font.pixelSize: 14
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.showAddModal = false }
                }
            }

            // Tab Switcher: Installed vs Custom
            Rectangle {
                Layout.fillWidth: true; height: 32; radius: 6
                color: root.isDark ? "#0E0E12" : "#ECECEC"

                RowLayout {
                    anchors.fill: parent; anchors.margins: 2; spacing: 2

                    Rectangle {
                        Layout.fillWidth: true; Layout.fillHeight: true; radius: 5
                        color: root.addTab === 0 ? (root.isDark ? "#24242C" : "#FFFFFF") : "transparent"
                        Text { anchors.centerIn: parent; text: "Choose from Installed Apps"; color: root.addTab === 0 ? root.colTextPrimary : root.colTextSecondary; font.pixelSize: 11; font.weight: root.addTab === 0 ? Font.DemiBold : Font.Normal }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.addTab = 0 }
                    }

                    Rectangle {
                        Layout.fillWidth: true; Layout.fillHeight: true; radius: 5
                        color: root.addTab === 1 ? (root.isDark ? "#24242C" : "#FFFFFF") : "transparent"
                        Text { anchors.centerIn: parent; text: "Custom Command / Script"; color: root.addTab === 1 ? root.colTextPrimary : root.colTextSecondary; font.pixelSize: 11; font.weight: root.addTab === 1 ? Font.DemiBold : Font.Normal }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.addTab = 1 }
                    }
                }
            }

            // Tab 0: Installed Apps Picker
            ColumnLayout {
                visible: root.addTab === 0
                Layout.fillWidth: true; Layout.fillHeight: true
                spacing: 10

                // Search box for installed apps
                Rectangle {
                    Layout.fillWidth: true; height: 32; radius: 6
                    color: root.isDark ? "#0A0A0E" : "#F5F5F7"
                    border.width: 1; border.color: root.colBorder

                    TextInput {
                        id: addAppSearch
                        anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8
                        verticalAlignment: TextInput.AlignVCenter
                        text: root.addSearchQuery
                        onTextChanged: root.addSearchQuery = text
                        color: root.colTextPrimary; font.pixelSize: 11

                        Text {
                            anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                            text: "Search installed programs..."; color: root.colTextMuted; font.pixelSize: 11
                            visible: !addAppSearch.text && !addAppSearch.activeFocus
                        }
                    }
                }

                // List of installed applications
                Rectangle {
                    Layout.fillWidth: true; Layout.fillHeight: true; radius: 8
                    color: root.isDark ? "#0E0E12" : "#F7F7F9"
                    border.width: 1; border.color: root.colBorder

                    ScrollView {
                        anchors.fill: parent; anchors.margins: 4; clip: true

                        ListView {
                            id: appsListView
                            model: {
                                const q = root.addSearchQuery.toLowerCase().trim();
                                const all = DesktopEntries.applications.values || [];
                                return all.filter(app => {
                                    if (!app.name && !app.id) return false;
                                    if (!q) return true;
                                    return (app.name || "").toLowerCase().includes(q)
                                        || (app.id || "").toLowerCase().includes(q)
                                        || (app.comment || "").toLowerCase().includes(q);
                                }).slice(0, 40);
                            }

                            delegate: Rectangle {
                                required property var modelData
                                width: appsListView.width; height: 40; radius: 6
                                color: appRowM.containsMouse ? root.colCardHover : "transparent"

                                RowLayout {
                                    anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; spacing: 10

                                    Image {
                                        width: 22; height: 22
                                        sourceSize: Qt.size(44, 44)
                                        source: modelData.icon ? Quickshell.iconPath(modelData.icon) : ""
                                        fillMode: Image.PreserveAspectFit
                                        visible: status === Image.Ready
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 1
                                        Text { text: modelData.name || modelData.id; color: root.colTextPrimary; font.pixelSize: 11; font.weight: Font.DemiBold; elide: Text.ElideRight }
                                        Text { text: modelData.execString || modelData.comment || ""; color: root.colTextSecondary; font.pixelSize: 9; elide: Text.ElideRight }
                                    }

                                    Rectangle {
                                        width: 50; height: 22; radius: 4; color: root.colAccent
                                        Text { anchors.centerIn: parent; text: "Select"; color: "#FFFFFF"; font.pixelSize: 10 }
                                    }
                                }

                                MouseArea {
                                    id: appRowM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.newName = modelData.name || modelData.id;
                                        root.newExec = modelData.execString || (modelData.command ? modelData.command.join(" ") : modelData.id);
                                        root.newIcon = modelData.icon || "application-x-executable";
                                        root.newComment = modelData.comment || "";
                                        root.addTab = 1; // Switch to review & customize delay/flags
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Tab 1: Custom Form / Review
            ColumnLayout {
                visible: root.addTab === 1
                Layout.fillWidth: true; Layout.fillHeight: true
                spacing: 10

                Text { text: "Application Name"; color: root.colTextSecondary; font.pixelSize: 10; font.weight: Font.DemiBold }
                Rectangle {
                    Layout.fillWidth: true; height: 32; radius: 6; color: root.colSurfaceAlt; border.width: 1; border.color: root.colBorder
                    TextInput {
                        anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; verticalAlignment: TextInput.AlignVCenter
                        text: root.newName; onTextChanged: root.newName = text; color: root.colTextPrimary; font.pixelSize: 11
                    }
                }

                Text { text: "Executable Command Line"; color: root.colTextSecondary; font.pixelSize: 10; font.weight: Font.DemiBold }
                Rectangle {
                    Layout.fillWidth: true; height: 32; radius: 6; color: root.colSurfaceAlt; border.width: 1; border.color: root.colBorder
                    TextInput {
                        anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; verticalAlignment: TextInput.AlignVCenter
                        text: root.newExec; onTextChanged: root.newExec = text; color: root.colTextPrimary; font.pixelSize: 11
                    }
                }

                RowLayout {
                    Layout.fillWidth: true; spacing: 12

                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 4
                        Text { text: "Startup Delay"; color: root.colTextSecondary; font.pixelSize: 10; font.weight: Font.DemiBold }
                        RowLayout {
                            spacing: 6
                            Repeater {
                                model: [0, 2, 3, 5, 10]
                                Rectangle {
                                    required property int modelData
                                    width: 42; height: 26; radius: 5
                                    color: root.newDelay === modelData ? root.colAccent : (dM.containsMouse ? root.colCardHover : root.colSurfaceAlt)
                                    border.width: 1; border.color: root.colBorder
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData === 0 ? "0s" : (modelData + "s")
                                        color: root.newDelay === modelData ? "#FFFFFF" : root.colTextPrimary
                                        font.pixelSize: 10
                                    }
                                    MouseArea { id: dM; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.newDelay = modelData }
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        spacing: 4
                        Text { text: "Terminal Mode"; color: root.colTextSecondary; font.pixelSize: 10; font.weight: Font.DemiBold }
                        RowLayout {
                            spacing: 6
                            Rectangle {
                                width: 70; height: 26; radius: 5
                                color: root.newTerminal ? root.colAccent : root.colSurfaceAlt
                                border.width: 1; border.color: root.colBorder
                                Text { anchors.centerIn: parent; text: root.newTerminal ? "Terminal" : "GUI / Detached"; color: root.newTerminal ? "#FFFFFF" : root.colTextSecondary; font.pixelSize: 9 }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.newTerminal = !root.newTerminal }
                            }
                        }
                    }
                }

                Text { text: "Description / Notes (Optional)"; color: root.colTextSecondary; font.pixelSize: 10; font.weight: Font.DemiBold }
                Rectangle {
                    Layout.fillWidth: true; height: 32; radius: 6; color: root.colSurfaceAlt; border.width: 1; border.color: root.colBorder
                    TextInput {
                        anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; verticalAlignment: TextInput.AlignVCenter
                        text: root.newComment; onTextChanged: root.newComment = text; color: root.colTextPrimary; font.pixelSize: 11
                    }
                }
            }

            // Modal Footer Buttons
            RowLayout {
                Layout.fillWidth: true; spacing: 8
                Item { Layout.fillWidth: true }

                Rectangle {
                    width: 70; height: 32; radius: 6; color: root.colSurfaceAlt; border.width: 1; border.color: root.colBorder
                    Text { anchors.centerIn: parent; text: "Cancel"; color: root.colTextSecondary; font.pixelSize: 11 }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.showAddModal = false }
                }

                Rectangle {
                    width: 140; height: 32; radius: 6
                    color: root.newExec.trim().length > 0 ? root.colAccent : root.colBorder
                    enabled: root.newExec.trim().length > 0
                    Text { anchors.centerIn: parent; text: "Add to Autostart"; color: "#FFFFFF"; font.pixelSize: 11; font.weight: Font.DemiBold }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!root.newExec.trim()) return;
                            AutostartService.saveEntry({
                                id: "",
                                name: root.newName.trim() || "Startup App",
                                exec: root.newExec.trim(),
                                icon: root.newIcon || "application-x-executable",
                                comment: root.newComment.trim(),
                                delay: root.newDelay,
                                terminal: root.newTerminal,
                                enabled: true
                            });
                            root.showAddModal = false;
                        }
                    }
                }
            }
        }
    }

    // Edit Application Modal Dialog
    Rectangle {
        visible: root.showEditModal
        anchors.centerIn: parent
        width: 480; height: 380
        radius: 12
        color: root.colSurface
        border.width: 1
        border.color: root.colBorder
        z: 100

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                Text { text: "Edit Autostart Entry"; color: root.colTextPrimary; font.family: Theme.fontFamily; font.pixelSize: 14; font.weight: Font.Bold }
                Item { Layout.fillWidth: true }
                Text {
                    text: "✕"; color: root.colTextSecondary; font.pixelSize: 14
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.showEditModal = false }
                }
            }

            Text { text: "Display Name"; color: root.colTextSecondary; font.pixelSize: 10; font.weight: Font.DemiBold }
            Rectangle {
                Layout.fillWidth: true; height: 32; radius: 6; color: root.colSurfaceAlt; border.width: 1; border.color: root.colBorder
                TextInput {
                    anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; verticalAlignment: TextInput.AlignVCenter
                    text: root.newName; onTextChanged: root.newName = text; color: root.colTextPrimary; font.pixelSize: 11
                }
            }

            Text { text: "Command / Executable"; color: root.colTextSecondary; font.pixelSize: 10; font.weight: Font.DemiBold }
            Rectangle {
                Layout.fillWidth: true; height: 32; radius: 6; color: root.colSurfaceAlt; border.width: 1; border.color: root.colBorder
                TextInput {
                    anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; verticalAlignment: TextInput.AlignVCenter
                    text: root.newExec; onTextChanged: root.newExec = text; color: root.colTextPrimary; font.pixelSize: 11
                }
            }

            RowLayout {
                Layout.fillWidth: true; spacing: 12

                ColumnLayout {
                    Layout.fillWidth: true; spacing: 4
                    Text { text: "Startup Delay"; color: root.colTextSecondary; font.pixelSize: 10; font.weight: Font.DemiBold }
                    RowLayout {
                        spacing: 6
                        Repeater {
                            model: [0, 2, 3, 5, 10]
                            Rectangle {
                                required property int modelData
                                width: 42; height: 26; radius: 5
                                color: root.newDelay === modelData ? root.colAccent : (eDM.containsMouse ? root.colCardHover : root.colSurfaceAlt)
                                border.width: 1; border.color: root.colBorder
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData === 0 ? "0s" : (modelData + "s")
                                    color: root.newDelay === modelData ? "#FFFFFF" : root.colTextPrimary
                                    font.pixelSize: 10
                                }
                                MouseArea { id: eDM; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.newDelay = modelData }
                            }
                        }
                    }
                }

                ColumnLayout {
                    spacing: 4
                    Text { text: "Terminal Mode"; color: root.colTextSecondary; font.pixelSize: 10; font.weight: Font.DemiBold }
                    Rectangle {
                        width: 70; height: 26; radius: 5
                        color: root.newTerminal ? root.colAccent : root.colSurfaceAlt
                        border.width: 1; border.color: root.colBorder
                        Text { anchors.centerIn: parent; text: root.newTerminal ? "Terminal" : "GUI / Detached"; color: root.newTerminal ? "#FFFFFF" : root.colTextSecondary; font.pixelSize: 9 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.newTerminal = !root.newTerminal }
                    }
                }
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true; spacing: 8
                Item { Layout.fillWidth: true }

                Rectangle {
                    width: 70; height: 32; radius: 6; color: root.colSurfaceAlt; border.width: 1; border.color: root.colBorder
                    Text { anchors.centerIn: parent; text: "Cancel"; color: root.colTextSecondary; font.pixelSize: 11 }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.showEditModal = false }
                }

                Rectangle {
                    width: 110; height: 32; radius: 6; color: root.colAccent
                    Text { anchors.centerIn: parent; text: "Save Changes"; color: "#FFFFFF"; font.pixelSize: 11; font.weight: Font.DemiBold }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!root.editingItem) return;
                            AutostartService.saveEntry({
                                id: root.editingItem.id,
                                name: root.newName.trim() || root.editingItem.name,
                                exec: root.newExec.trim() || root.editingItem.exec,
                                icon: root.editingItem.icon || "application-x-executable",
                                comment: root.editingItem.comment || "",
                                delay: root.newDelay,
                                terminal: root.newTerminal,
                                enabled: root.editingItem.enabled
                            });
                            root.showEditModal = false;
                        }
                    }
                }
            }
        }
    }

    // Component for Top Metric Cards
    component MetricCard: Rectangle {
        property string title: ""
        property string value: "0"
        property string caption: ""
        property color accentColor: root.colAccent
        property bool isPulse: false
        property string iconName: ""

        implicitHeight: 74
        radius: 10
        color: root.colSurface
        border.width: 1
        border.color: root.colBorder

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Rectangle {
                    visible: isPulse
                    width: 6; height: 6; radius: 3; color: accentColor
                }
                Text {
                    text: title
                    color: root.colTextSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    font.weight: Font.Bold
                }
            }

            Text {
                text: value
                color: root.colTextPrimary
                font.family: Theme.fontFamily
                font.pixelSize: 20
                font.weight: Font.Bold
            }

            Text {
                text: caption
                color: root.colTextMuted
                font.family: Theme.fontFamily
                font.pixelSize: 9
                elide: Text.ElideRight
            }
        }
    }
}
