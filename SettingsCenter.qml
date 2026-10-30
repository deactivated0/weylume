import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import qs

FloatingWindow {
    id: root
    visible: ShellState.settingsOpen
    title: "Settings"
    implicitWidth: 980
    implicitHeight: 700
    minimumSize: Qt.size(720, 500)
    color: root.colBgWindow

    property string page: "quickshell"
    property string startMenuTab: "layout"
    property string searchQuery: ""

    readonly property bool isDark: SettingsService.darkMode !== false
    readonly property color colBgWindow: isDark ? "#000000" : "#FFFFFF"
    readonly property color colBgSidebar: isDark ? "#050505" : "#F5F5F7"
    readonly property color colSurface: isDark ? "#0C0C0E" : "#FBFBFD"
    readonly property color colBorder: isDark ? "#1F1F22" : "#E5E5EA"
    readonly property color colTextPrimary: isDark ? "#FFFFFF" : "#000000"
    readonly property color colTextSecondary: isDark ? "#8E8E93" : "#6E6E73"
    readonly property color colAccent: isDark ? "#FFFFFF" : "#000000"

    Shortcut { sequence: "Escape"; onActivated: ShellState.settingsOpen = false }
    Shortcut { sequence: "Ctrl+W"; onActivated: ShellState.settingsOpen = false }
    Shortcut { sequence: "Ctrl+F"; onActivated: searchInput.forceActiveFocus() }

    onVisibleChanged: {
        if (visible) {
            SystemService.refreshLabwc();
            SystemService.refreshSystem();
            OutputService.refresh();
        }
    }

    function pageTitle() {
        if (root.page === "startmenu") return "Start Menu";
        if (root.page === "sound") return "Sound";
        if (root.page === "lockscreen") return "Lock Screen & Security";
        if (root.page === "autostart") return "Autostart Applications";
        if (root.page === "integrations") return "Integrations";
        if (root.page === "labwc") return "Window Manager";
        if (root.page === "system") return "Arch System";
        return "General & Display";
    }

    function pageDescription() {
        if (root.page === "startmenu") return "Customize layout, dimensions, sidebar quick access, custom folders, and search runner";
        if (root.page === "sound") return "Configure output devices, input microphones, per-application audio stream mixer, and test sounds";
        if (root.page === "lockscreen") return "macOS-inspired AMOLED lock screen, PIN/password authentication, direct auto-unlock, and startup lock";
        if (root.page === "autostart") return "Startup programs, service delays, process execution states, and session initialization";
        if (root.page === "integrations") return "Per-game rule overrides, Bluetooth devices, and system service integrations";
        if (root.page === "labwc") return "Labwc Wayland compositor, window tiling, input behavior, and display presentation";
        if (root.page === "system") return "Kernel, power profiles, audio stack recovery, pacman updates, and installed diagnostic tools";
        return "Display scaling (100% to 200%), desktop interface, notification history, screenshot capture, and telemetry";
    }

    function cycleScreenshotMode() {
        const modes = ["region", "window", "screen"];
        SettingsService.screenshotMode = modes[(modes.indexOf(SettingsService.screenshotMode) + 1) % modes.length];
    }

    function cycleRecordingSource() {
        SettingsService.recordingSource = SettingsService.recordingSource === "portal" ? "screen" : "portal";
    }

    // Main Solid Window Canvas (No margins, zero transparent slots)
    Rectangle {
        anchors.fill: parent
        color: root.colBgWindow
        border.width: 1
        border.color: root.colBorder
        clip: true

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // Left Sidebar: 240px NavigationSplitView Style (Monochrome)
            Rectangle {
                Layout.preferredWidth: 240
                Layout.fillHeight: true
                color: root.colBgSidebar

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    // Clean Solid Titlebar Header
                    Rectangle {
                        Layout.fillWidth: true
                        height: 48
                        color: root.colBgSidebar

                        MouseArea {
                            anchors.fill: parent
                            onPressed: root.startSystemMove()
                            onDoubleClicked: root.maximized = !root.maximized
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            spacing: 8

                            Image {
                                width: 14; height: 14
                                source: "assets/settings.svg"
                                opacity: 0.9
                            }

                            Text {
                                text: "Settings"
                                color: root.colTextPrimary
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                            }

                            Item { Layout.fillWidth: true }
                        }
                    }

                    // Compact Search Input Box
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.leftMargin: 12
                        Layout.rightMargin: 12
                        Layout.bottomMargin: 10
                        height: 28
                        radius: 6
                        color: root.isDark ? "#121216" : "#EAEAEA"
                        border.width: 1
                        border.color: searchInput.activeFocus ? root.colAccent : (root.isDark ? "#222228" : "#DCDCDF")

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 6
                            spacing: 6

                            Image {
                                width: 12; height: 12
                                source: "assets/search.svg"
                                opacity: 0.55
                            }

                            TextInput {
                                id: searchInput
                                Layout.fillWidth: true
                                color: root.colTextPrimary
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                selectByMouse: true
                                onTextChanged: root.searchQuery = text.trim().toLowerCase()

                                Text {
                                    anchors.fill: parent
                                    visible: searchInput.text.length === 0
                                    text: "Search"
                                    color: root.colTextSecondary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                }
                            }

                            Rectangle {
                                visible: searchInput.text.length > 0
                                width: 14; height: 14; radius: 7
                                color: clearSearchMouse.containsMouse ? (root.isDark ? "#3A3A42" : "#C7C7CC") : (root.isDark ? "#24242C" : "#D1D1D6")
                                Text { anchors.centerIn: parent; text: "×"; color: root.isDark ? "#AEAEB2" : "#3C3C43"; font.pixelSize: 9 }
                                MouseArea {
                                    id: clearSearchMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { searchInput.text = ""; root.searchQuery = ""; }
                                }
                            }
                        }
                    }

                    // Categorized Sidebar Navigation Items (Strictly Monochrome)
                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                        ScrollBar.vertical.policy: ScrollBar.AlwaysOff

                        ColumnLayout {
                            width: 240 - 24
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 2

                            Repeater {
                                id: navRepeater
                                model: [
                                    { id: "quickshell", label: "General & Display", detail: "Shell, capture, clipboard", icon: "assets/settings.svg" },
                                    { id: "sound", label: "Sound", detail: "Volume, outputs, mixer", icon: "assets/volume.svg" },
                                    { id: "lockscreen", label: "Lock Screen", detail: "PIN, password, auto-lock", icon: "assets/shield.svg" },
                                    { id: "startmenu", label: "Start Menu", detail: "Layout, sidebar, custom folders", icon: "assets/plus.svg" },
                                    { id: "autostart", label: "Autostart Apps", detail: "Startup apps, delays, services", icon: "assets/play.svg" },
                                    { id: "labwc", label: "Window Manager", detail: "Compositor, inputs, display", icon: "assets/edit.svg" },
                                    { id: "system", label: "Arch System", detail: "Power, tools, updates", icon: "assets/cpu.svg" },
                                    { id: "integrations", label: "Integrations", detail: "Games, rules, hardware", icon: "assets/flask.svg" }
                                ]
                                Rectangle {
                                    id: navRow
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true
                                    implicitHeight: 44
                                    radius: 7
                                    color: root.page === navRow.modelData.id ? (root.isDark ? "#1C1C22" : "#E5E5EA") : (navMouse.containsMouse ? (root.isDark ? "#121217" : "#ECECEE") : "transparent")
                                    border.width: root.page === navRow.modelData.id ? 1 : 0
                                    border.color: root.isDark ? "#282832" : "#DCDCDF"

                                    Behavior on color { ColorAnimation { duration: SettingsService.reducedMotion ? 0 : 70 } }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10

                                        Rectangle {
                                            width: 24; height: 24; radius: 6
                                            color: root.isDark ? (root.page === navRow.modelData.id ? "#282832" : "#141418") : (root.page === navRow.modelData.id ? "#D8D8DF" : "#EAEAEA")
                                            border.width: 1
                                            border.color: root.colBorder
                                            Image {
                                                anchors.centerIn: parent
                                                width: 13; height: 13
                                                source: navRow.modelData.icon
                                                opacity: root.page === navRow.modelData.id ? 1.0 : 0.6
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1
                                            Text {
                                                text: navRow.modelData.label
                                                color: root.page === navRow.modelData.id ? root.colTextPrimary : (navMouse.containsMouse ? root.colTextPrimary : root.colTextSecondary)
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 13
                                                font.weight: root.page === navRow.modelData.id ? Font.DemiBold : Font.Normal
                                            }
                                            Text {
                                                text: navRow.modelData.detail
                                                color: root.colTextSecondary
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 10
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: navMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.page = navRow.modelData.id
                                    }
                                }
                            }
                        }
                    }

                    // System Telemetry Footer Card (Monochrome)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.leftMargin: 12
                        Layout.rightMargin: 12
                        Layout.bottomMargin: 12
                        implicitHeight: 64
                        radius: 8
                        color: root.isDark ? "#0A0A0D" : "#ECECED"
                        border.width: 1
                        border.color: root.colBorder

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 9
                            spacing: 3

                            RowLayout {
                                spacing: 6
                                Rectangle { width: 6; height: 6; radius: 3; color: root.isDark ? "#FFFFFF" : "#000000" }
                                Text {
                                    text: "Arch Linux • Labwc Wayland"
                                    color: root.colTextPrimary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                }
                            }

                            Text {
                                text: (SystemService.networkAvailable ? "Network Active" : "Offline") + " • " + (AudioService.sinks.length > 0 ? "PipeWire Active" : "Audio Idle")
                                color: root.colTextSecondary
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            // Hairline 1px Divider
            Rectangle {
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                color: root.colBorder
            }

            // Right Pane: Unified Toolbar + Scrollable Detail View
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: root.colBgWindow

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    // Unified Title-Toolbar Header (Solid 48px height, seamless edge)
                    Rectangle {
                        Layout.fillWidth: true
                        height: 48
                        color: root.colBgWindow

                        MouseArea {
                            anchors.fill: parent
                            onPressed: root.startSystemMove()
                            onDoubleClicked: root.maximized = !root.maximized
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 24
                            anchors.rightMargin: 16
                            spacing: 12

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Text {
                                    text: root.pageTitle()
                                    color: root.colTextPrimary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 16
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    text: root.pageDescription()
                                    color: root.colTextSecondary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                            }

                            // Appearance Toggle (Dark AMOLED vs Light Pure White)
                            Rectangle {
                                width: 130
                                height: 28
                                radius: 6
                                color: root.isDark ? "#121216" : "#EAEAEA"
                                border.width: 1
                                border.color: root.colBorder

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    spacing: 2

                                    // Dark Mode option
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        radius: 5
                                        color: root.isDark ? (root.isDark ? "#24242C" : "#FFFFFF") : "transparent"
                                        Text {
                                            anchors.centerIn: parent
                                            text: "Dark"
                                            color: root.isDark ? "#FFFFFF" : root.colTextSecondary
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                            font.weight: root.isDark ? Font.DemiBold : Font.Normal
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: SettingsService.darkMode = true
                                        }
                                    }

                                    // Light Mode option
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        radius: 5
                                        color: !root.isDark ? (root.isDark ? "#24242C" : "#FFFFFF") : "transparent"
                                        Text {
                                            anchors.centerIn: parent
                                            text: "Light"
                                            color: !root.isDark ? "#000000" : root.colTextSecondary
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                            font.weight: !root.isDark ? Font.DemiBold : Font.Normal
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: SettingsService.darkMode = false
                                        }
                                    }
                                }
                            }

                            // Primary Contextual Action Button
                            Rectangle {
                                implicitWidth: bannerActionLabel.implicitWidth + 24
                                height: 28
                                radius: 6
                                color: bannerActionMouse.containsMouse ? (root.isDark ? "#242430" : "#E0E0E5") : (root.isDark ? "#16161D" : "#ECECED")
                                border.width: 1
                                border.color: root.colBorder

                                Text {
                                    id: bannerActionLabel
                                    anchors.centerIn: parent
                                    text: root.page === "startmenu" ? "Test Start Menu" : (root.page === "autostart" ? "Add Startup App" : (root.page === "labwc" ? "Reload Labwc" : (root.page === "system" ? "Check Updates" : "Take Screenshot")))
                                    color: root.colTextPrimary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                }
                                MouseArea {
                                    id: bannerActionMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.page === "startmenu") ShellState.toggleStart();
                                        else if (root.page === "autostart") { if (settingsPageLoader.item) settingsPageLoader.item.showAddModal = true; }
                                        else if (root.page === "labwc") Quickshell.execDetached(["labwc", "--reconfigure"]);
                                        else if (root.page === "system") SystemService.checkUpdates();
                                        else SystemService.captureScreenshot();
                                    }
                                }
                            }

                            // Minimal Monochrome Window Close Button
                            Rectangle {
                                width: 28; height: 28; radius: 5
                                color: winCloseMouse.containsMouse ? (root.isDark ? "#282832" : "#E5E5EA") : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: "×"
                                    color: winCloseMouse.containsMouse ? root.colTextPrimary : root.colTextSecondary
                                    font.pixelSize: 16
                                }
                                MouseArea {
                                    id: winCloseMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: ShellState.settingsOpen = false
                                }
                            }
                        }
                    }

                    // Hairline 1px Divider below toolbar
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: root.colBorder
                    }

                    // Dynamic Page Loader
                    Loader {
                        id: settingsPageLoader
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        sourceComponent: root.page === "startmenu" ? startMenuPage : root.page === "sound" ? soundPage : root.page === "lockscreen" ? lockscreenPage : root.page === "autostart" ? autostartPage : root.page === "integrations" ? integrationsPage : root.page === "labwc" ? labwcPage : root.page === "system" ? systemPage : quickshellPage
                    }
                }
            }
        }
    }

    Component { id: autostartPage; AutostartPage {} }
    Component { id: integrationsPage; IntegrationsPage {} }
    Component { id: soundPage; SoundPage {} }
    Component { id: lockscreenPage; LockscreenPage {} }

    // PAGE 1: START MENU ADVANCED CONFIGURATION
    Component {
        id: startMenuPage
        ScrollView {
            id: smScroll
            clip: true
            contentWidth: availableWidth
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: ScrollBar.AlwaysOff

            Item {
                width: smScroll.availableWidth
                implicitHeight: smCol.implicitHeight + 40

                ColumnLayout {
                    id: smCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: 24
                    anchors.rightMargin: 24
                    anchors.topMargin: 18
                    spacing: 16

                    // Segmented Control Tab Bar
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
                                    { id: "layout", label: "Layout & Sizing" },
                                    { id: "shortcuts", label: "Sidebar Shortcuts" },
                                    { id: "custom", label: "Custom Folders" },
                                    { id: "advanced", label: "Search & Actions" }
                                ]
                                Rectangle {
                                    id: tabBtn
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: 5
                                    color: root.startMenuTab === tabBtn.modelData.id ? (root.isDark ? "#24242C" : "#FFFFFF") : (tabMouse.containsMouse ? (root.isDark ? "#18181E" : "#ECECED") : "transparent")
                                    border.width: root.startMenuTab === tabBtn.modelData.id ? 1 : 0
                                    border.color: root.isDark ? "#383844" : "#D0D0D6"

                                    Behavior on color { ColorAnimation { duration: SettingsService.reducedMotion ? 0 : 80 } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: tabBtn.modelData.label
                                        color: root.startMenuTab === tabBtn.modelData.id ? root.colTextPrimary : root.colTextSecondary
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.weight: root.startMenuTab === tabBtn.modelData.id ? Font.DemiBold : Font.Normal
                                    }

                                    MouseArea {
                                        id: tabMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.startMenuTab = tabBtn.modelData.id
                                    }
                                }
                            }
                        }
                    }

                    // TAB 1: LAYOUT & SIZING
                    ColumnLayout {
                        visible: root.startMenuTab === "layout"
                        Layout.fillWidth: true
                        spacing: 16

                        SettingsGroup {
                            title: "GEOMETRY PREVIEW"
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 88
                                color: "transparent"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 14
                                    spacing: 16

                                    Rectangle {
                                        width: 68
                                        height: 64
                                        radius: 6
                                        color: root.isDark ? "#000000" : "#EAEAEA"
                                        border.width: 1
                                        border.color: root.colBorder
                                        clip: true

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 3
                                            spacing: 2

                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                radius: 3
                                                color: root.isDark ? "#17171D" : "#FFFFFF"
                                                Column {
                                                    anchors.fill: parent
                                                    anchors.margins: 4
                                                    spacing: 3
                                                    Repeater {
                                                        model: 5
                                                        Rectangle { width: parent.width - 2; height: 3; radius: 1; color: root.isDark ? "#363642" : "#D0D0D6" }
                                                    }
                                                }
                                            }

                                            Rectangle {
                                                visible: !SettingsService.startCompactMode
                                                width: 22
                                                Layout.fillHeight: true
                                                radius: 3
                                                color: root.isDark ? "#101014" : "#F4F4F6"
                                                Column {
                                                    anchors.fill: parent
                                                    anchors.margins: 4
                                                    spacing: 3
                                                    Repeater {
                                                        model: 4
                                                        Rectangle { width: 14; height: 3; radius: 1; color: root.isDark ? "#282834" : "#D8D8DE" }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 3
                                        Text {
                                            text: SettingsService.startCompactMode ? "Single-Column Compact Launcher" : "Two-Column Classic Start Menu"
                                            color: root.colTextPrimary
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 13
                                            font.weight: Font.DemiBold
                                        }
                                        Text {
                                            text: "Width: " + SettingsService.startMenuWidth + " px • Height: " + SettingsService.startMenuHeight + " px • App icons: " + SettingsService.startAppIconSize + " px"
                                            color: root.colTextSecondary
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                        }
                                        Text {
                                            text: "Default: " + (SettingsService.startDefaultAllPrograms ? "Categorized All Programs view" : "Pinned Favorites view")
                                            color: root.colTextSecondary
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                        }
                                    }
                                }
                            }
                        }

                        SettingsGroup {
                            title: "DIMENSIONS & SCALING"
                            SettingsButton {
                                label: "Menu width"
                                description: "Cycle widths: 400 (compact) • 450 (standard) • 500 (spacious) • 550 (wide) • 600 px"
                                buttonText: SettingsService.startMenuWidth + " px"
                                onClicked: {
                                    const widths = [400, 450, 500, 550, 600];
                                    const idx = widths.indexOf(SettingsService.startMenuWidth);
                                    SettingsService.startMenuWidth = widths[(idx + 1) % widths.length];
                                }
                            }
                            SettingsButton {
                                label: "Menu height"
                                description: "Cycle heights: 480 (compact) • 520 • 575 (standard) • 620 • 680 px"
                                buttonText: SettingsService.startMenuHeight + " px"
                                onClicked: {
                                    const heights = [480, 520, 575, 620, 680];
                                    const idx = heights.indexOf(SettingsService.startMenuHeight);
                                    SettingsService.startMenuHeight = heights[(idx + 1) % heights.length];
                                }
                            }
                            SettingsButton {
                                label: "App icon size"
                                description: "Size of icons in left favorites and application tree: 20 • 24 • 28 • 32 • 40 px"
                                buttonText: SettingsService.startAppIconSize + " px"
                                onClicked: {
                                    const sizes = [20, 24, 28, 32, 40];
                                    const idx = sizes.indexOf(SettingsService.startAppIconSize);
                                    SettingsService.startAppIconSize = sizes[(idx + 1) % sizes.length];
                                }
                            }
                        }

                        SettingsGroup {
                            title: "LAYOUT MODES"
                            SettingsToggle {
                                label: "Compact single-column launcher"
                                description: "Hides the right sidebar entirely for an ultra-minimalist application search launcher"
                                checked: SettingsService.startCompactMode
                                onToggled: value => SettingsService.startCompactMode = value
                            }
                            SettingsToggle {
                                label: "Default directly to All Programs"
                                description: "Opens directly into the full categorized application tree instead of pinned favorites"
                                checked: SettingsService.startDefaultAllPrograms
                                onToggled: value => SettingsService.startDefaultAllPrograms = value
                            }
                        }
                    }

                    // TAB 2: SIDEBAR SHORTCUTS & TARGET PATHS
                    ColumnLayout {
                        visible: root.startMenuTab === "shortcuts"
                        Layout.fillWidth: true
                        spacing: 16

                        SettingsGroup {
                            title: "DEFAULT DIRECTORIES & PATH OVERRIDES"
                            caption: "Leaving target path blank uses standard system location"
                            SettingsToggle {
                                label: "User folder (" + (Quickshell.env("USER") || "User") + ")"
                                description: "Show personal user home directory shortcut"
                                checked: SettingsService.startShowUserFolder
                                onToggled: value => SettingsService.startShowUserFolder = value
                            }
                            SettingsField {
                                label: "User folder target path"
                                description: "Target directory when clicked (empty = default ~)"
                                text: SettingsService.startPathUserFolder; placeholder: Quickshell.env("HOME") || "~"
                                onAccepted: value => SettingsService.startPathUserFolder = value.trim()
                            }
                            SettingsToggle {
                                label: "Documents folder"
                                description: "Show Documents shortcut in right sidebar"
                                checked: SettingsService.startShowDocuments
                                onToggled: value => SettingsService.startShowDocuments = value
                            }
                            SettingsField {
                                label: "Documents target path"
                                description: "Target directory when clicked (empty = ~/Documents)"
                                text: SettingsService.startPathDocuments; placeholder: (Quickshell.env("HOME") || "~") + "/Documents"
                                onAccepted: value => SettingsService.startPathDocuments = value.trim()
                            }
                            SettingsToggle {
                                label: "Pictures folder"
                                description: "Show Pictures shortcut in right sidebar"
                                checked: SettingsService.startShowPictures
                                onToggled: value => SettingsService.startShowPictures = value
                            }
                            SettingsField {
                                label: "Pictures target path"
                                description: "Target directory when clicked (empty = ~/Pictures)"
                                text: SettingsService.startPathPictures; placeholder: (Quickshell.env("HOME") || "~") + "/Pictures"
                                onAccepted: value => SettingsService.startPathPictures = value.trim()
                            }
                            SettingsToggle {
                                label: "Music folder"
                                description: "Show Music shortcut in right sidebar"
                                checked: SettingsService.startShowMusic
                                onToggled: value => SettingsService.startShowMusic = value
                            }
                            SettingsField {
                                label: "Music target path"
                                description: "Target directory when clicked (empty = ~/Music)"
                                text: SettingsService.startPathMusic; placeholder: (Quickshell.env("HOME") || "~") + "/Music"
                                onAccepted: value => SettingsService.startPathMusic = value.trim()
                            }
                            SettingsToggle {
                                label: "Downloads folder"
                                description: "Show Downloads shortcut in right sidebar"
                                checked: SettingsService.startShowDownloads
                                onToggled: value => SettingsService.startShowDownloads = value
                            }
                            SettingsField {
                                label: "Downloads target path"
                                description: "Target directory when clicked (empty = ~/Downloads)"
                                text: SettingsService.startPathDownloads; placeholder: (Quickshell.env("HOME") || "~") + "/Downloads"
                                onAccepted: value => SettingsService.startPathDownloads = value.trim()
                            }
                            SettingsToggle {
                                label: "This PC (Devices & Drives)"
                                description: "Show root device explorer shortcut (/mnt)"
                                checked: SettingsService.startShowThisPC
                                onToggled: value => SettingsService.startShowThisPC = value
                            }
                            SettingsField {
                                label: "This PC target path"
                                description: "Target directory when clicked (empty = /mnt)"
                                text: SettingsService.startPathThisPC; placeholder: "/mnt"
                                onAccepted: value => SettingsService.startPathThisPC = value.trim()
                            }
                        }

                        SettingsGroup {
                            title: "SYSTEM UTILITIES & RESET"
                            SettingsToggle {
                                label: "Settings"
                                description: "Show shortcut to open Weylume Settings Control Center"
                                checked: SettingsService.startShowSettings
                                onToggled: value => SettingsService.startShowSettings = value
                            }
                            SettingsToggle {
                                label: "Terminal"
                                description: "Show shortcut to launch terminal (Kitty)"
                                checked: SettingsService.startShowTerminal
                                onToggled: value => SettingsService.startShowTerminal = value
                            }
                            SettingsButton {
                                label: "Restore default directory paths"
                                description: "Clear all custom directory path overrides back to default OS locations"
                                buttonText: "Reset Paths"
                                onClicked: {
                                    SettingsService.startPathUserFolder = "";
                                    SettingsService.startPathDocuments = "";
                                    SettingsService.startPathPictures = "";
                                    SettingsService.startPathMusic = "";
                                    SettingsService.startPathDownloads = "";
                                    SettingsService.startPathThisPC = "";
                                }
                            }
                        }
                    }

                    // TAB 3: CUSTOM FOLDERS
                    ColumnLayout {
                        visible: root.startMenuTab === "custom"
                        Layout.fillWidth: true
                        spacing: 16

                        SettingsGroup {
                            title: "CUSTOM FOLDER 1"
                            caption: SettingsService.startCustomFolder1Path ? "Active target: " + SettingsService.startCustomFolder1Path : "Not configured"
                            SettingsField {
                                label: "Folder display label"; description: "Text shown in the Start Menu right sidebar"
                                text: SettingsService.startCustomFolder1Name; placeholder: "e.g. Projects"
                                onAccepted: value => SettingsService.startCustomFolder1Name = value.trim()
                            }
                            SettingsField {
                                label: "Folder target directory"; description: "Absolute path or ~ path to open"
                                text: SettingsService.startCustomFolder1Path; placeholder: "/home/pc/Projects"
                                onAccepted: value => SettingsService.startCustomFolder1Path = value.trim()
                            }
                            SettingsButton {
                                label: "Quick preset: Projects"
                                description: "Set display label to Projects and target to ~/Projects"
                                buttonText: "Apply"
                                onClicked: {
                                    SettingsService.startCustomFolder1Name = "Projects";
                                    SettingsService.startCustomFolder1Path = (Quickshell.env("HOME") || "") + "/Projects";
                                }
                            }
                            SettingsButton {
                                label: "Quick preset: Games"
                                description: "Set display label to Games and target to /mnt/Games"
                                buttonText: "Apply"
                                onClicked: {
                                    SettingsService.startCustomFolder1Name = "Games";
                                    SettingsService.startCustomFolder1Path = "/mnt/Games";
                                }
                            }
                            SettingsButton {
                                visible: SettingsService.startCustomFolder1Path.length > 0
                                label: "Test open target folder"
                                description: "Open configured path in pcmanfm-qt file manager"
                                buttonText: "Open"
                                onClicked: {
                                    let p = SettingsService.startCustomFolder1Path;
                                    if (p.startsWith("~")) p = (Quickshell.env("HOME") || "") + p.slice(1);
                                    Quickshell.execDetached(["pcmanfm-qt", p]);
                                }
                            }
                            SettingsButton {
                                visible: SettingsService.startCustomFolder1Path.length > 0 || SettingsService.startCustomFolder1Name.length > 0
                                label: "Clear custom folder 1"
                                description: "Remove label and path for Custom Folder 1"
                                buttonText: "Clear"; danger: true
                                onClicked: {
                                    SettingsService.startCustomFolder1Name = "";
                                    SettingsService.startCustomFolder1Path = "";
                                }
                            }
                        }

                        SettingsGroup {
                            title: "CUSTOM FOLDER 2"
                            caption: SettingsService.startCustomFolder2Path ? "Active target: " + SettingsService.startCustomFolder2Path : "Not configured"
                            SettingsField {
                                label: "Folder display label"; description: "Text shown in the Start Menu right sidebar"
                                text: SettingsService.startCustomFolder2Name; placeholder: "e.g. Storage"
                                onAccepted: value => SettingsService.startCustomFolder2Name = value.trim()
                            }
                            SettingsField {
                                label: "Folder target directory"; description: "Absolute path or ~ path to open"
                                text: SettingsService.startCustomFolder2Path; placeholder: "/mnt/Storage"
                                onAccepted: value => SettingsService.startCustomFolder2Path = value.trim()
                            }
                            SettingsButton {
                                label: "Quick preset: Desktop"
                                description: "Set display label to Desktop and target to ~/Desktop"
                                buttonText: "Apply"
                                onClicked: {
                                    SettingsService.startCustomFolder2Name = "Desktop";
                                    SettingsService.startCustomFolder2Path = (Quickshell.env("HOME") || "") + "/Desktop";
                                }
                            }
                            SettingsButton {
                                label: "Quick preset: Storage"
                                description: "Set display label to Storage and target to /mnt/Storage"
                                buttonText: "Apply"
                                onClicked: {
                                    SettingsService.startCustomFolder2Name = "Storage";
                                    SettingsService.startCustomFolder2Path = "/mnt/Storage";
                                }
                            }
                            SettingsButton {
                                visible: SettingsService.startCustomFolder2Path.length > 0
                                label: "Test open target folder"
                                description: "Open configured path in pcmanfm-qt file manager"
                                buttonText: "Open"
                                onClicked: {
                                    let p = SettingsService.startCustomFolder2Path;
                                    if (p.startsWith("~")) p = (Quickshell.env("HOME") || "") + p.slice(1);
                                    Quickshell.execDetached(["pcmanfm-qt", p]);
                                }
                            }
                            SettingsButton {
                                visible: SettingsService.startCustomFolder2Path.length > 0 || SettingsService.startCustomFolder2Name.length > 0
                                label: "Clear custom folder 2"
                                description: "Remove label and path for Custom Folder 2"
                                buttonText: "Clear"; danger: true
                                onClicked: {
                                    SettingsService.startCustomFolder2Name = "";
                                    SettingsService.startCustomFolder2Path = "";
                                }
                            }
                        }
                    }

                    // TAB 4: SEARCH & ADVANCED ACTIONS
                    ColumnLayout {
                        visible: root.startMenuTab === "advanced"
                        Layout.fillWidth: true
                        spacing: 16

                        SettingsGroup {
                            title: "SEARCH BAR FEATURES"
                            SettingsToggle {
                                label: "Terminal command runner"
                                description: "Prefix search queries with '>' to immediately run direct shell commands in Kitty"
                                checked: SettingsService.startEnableCommandRunner
                                onToggled: value => SettingsService.startEnableCommandRunner = value
                            }
                        }

                        SettingsGroup {
                            title: "LIVE PREVIEW & TESTING"
                            SettingsButton {
                                label: "Test Start Menu"
                                description: "Open the Start Menu live to test and preview your geometry and shortcut changes"
                                buttonText: "Open Menu"
                                onClicked: ShellState.toggleStart()
                            }
                        }

                        SettingsGroup {
                            title: "DANGER ZONE"
                            SettingsButton {
                                label: "Reset all Start Menu settings"
                                description: "Restore all defaults: geometry, layout, sidebar shortcuts, custom directory paths, and folders"
                                buttonText: "Reset Defaults"; danger: true
                                onClicked: {
                                    SettingsService.startMenuWidth = 450;
                                    SettingsService.startMenuHeight = 575;
                                    SettingsService.startDefaultAllPrograms = false;
                                    SettingsService.startCompactMode = false;
                                    SettingsService.startAppIconSize = 32;
                                    SettingsService.startShowUserFolder = true;
                                    SettingsService.startShowDocuments = true;
                                    SettingsService.startShowPictures = true;
                                    SettingsService.startShowMusic = true;
                                    SettingsService.startShowDownloads = true;
                                    SettingsService.startShowThisPC = true;
                                    SettingsService.startShowSettings = true;
                                    SettingsService.startShowTerminal = true;
                                    SettingsService.startEnableCommandRunner = true;
                                    SettingsService.startPathUserFolder = "";
                                    SettingsService.startPathDocuments = "";
                                    SettingsService.startPathPictures = "";
                                    SettingsService.startPathMusic = "";
                                    SettingsService.startPathDownloads = "";
                                    SettingsService.startPathThisPC = "";
                                    SettingsService.startCustomFolder1Name = "";
                                    SettingsService.startCustomFolder1Path = "";
                                    SettingsService.startCustomFolder2Name = "";
                                    SettingsService.startCustomFolder2Path = "";
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // PAGE 2: GENERAL & DISPLAY
    Component {
        id: quickshellPage
        ScrollView {
            id: qsScroll
            clip: true
            contentWidth: availableWidth
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: ScrollBar.AlwaysOff

            Item {
                width: qsScroll.availableWidth
                implicitHeight: qsCol.implicitHeight + 40

                ColumnLayout {
                    id: qsCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: 24
                    anchors.rightMargin: 24
                    anchors.topMargin: 18
                    spacing: 16

                    SettingsGroup {
                        title: "DISPLAYS & SCALING (100% - 200%)"

                        // Revert / Keep confirmation banner
                        Rectangle {
                            visible: OutputService.confirming
                            Layout.fillWidth: true
                            implicitHeight: 52
                            radius: 8
                            color: root.isDark ? "#2D1D00" : "#FFF9E6"
                            border.width: 1
                            border.color: root.isDark ? "#855800" : "#FFD54F"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                spacing: 12

                                Text {
                                    text: "Display scale applied. Automatically reverting in 15 seconds unless kept."
                                    color: root.isDark ? "#FFD54F" : "#B78103"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                    Layout.fillWidth: true
                                    wrapMode: Text.Wrap
                                }

                                Rectangle {
                                    implicitWidth: 74
                                    implicitHeight: 28
                                    radius: 6
                                    color: keepMouse.containsMouse ? (root.isDark ? "#388E3C" : "#2E7D32") : (root.isDark ? "#4CAF50" : "#388E3C")
                                    Text { anchors.centerIn: parent; text: "Keep"; color: "#FFFFFF"; font.family: Theme.fontFamily; font.pixelSize: 12; font.weight: Font.DemiBold }
                                    MouseArea {
                                        id: keepMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: OutputService.respond(true)
                                    }
                                }

                                Rectangle {
                                    implicitWidth: 74
                                    implicitHeight: 28
                                    radius: 6
                                    color: revertMouse.containsMouse ? (root.isDark ? "#D32F2F" : "#C62828") : (root.isDark ? "#F44336" : "#D32F2F")
                                    Text { anchors.centerIn: parent; text: "Revert"; color: "#FFFFFF"; font.family: Theme.fontFamily; font.pixelSize: 12; font.weight: Font.DemiBold }
                                    MouseArea {
                                        id: revertMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: OutputService.respond(false)
                                    }
                                }
                            }
                        }

                        // Display list
                        Repeater {
                            model: OutputService.outputs
                            ColumnLayout {
                                id: displayItem
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                spacing: 10

                                readonly property real currentScale: Number(modelData.scale || 1.0)
                                readonly property int currentScalePercent: Math.round(currentScale * 100)

                                // Display Monitor Header
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 46
                                    radius: 8
                                    color: root.isDark ? "#141418" : "#F0F0F3"
                                    border.width: 1
                                    border.color: root.colBorder

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12
                                        spacing: 10

                                        Rectangle {
                                            Layout.preferredWidth: 26
                                            Layout.preferredHeight: 26
                                            radius: 6
                                            color: root.isDark ? "#24242C" : "#E2E2E8"
                                            Image {
                                                anchors.centerIn: parent
                                                width: 14; height: 14
                                                source: "assets/settings.svg"
                                                opacity: 0.8
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1

                                            Text {
                                                text: displayItem.modelData.name + (displayItem.modelData.model ? " • " + displayItem.modelData.model : "")
                                                color: root.colTextPrimary
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 13
                                                font.weight: Font.DemiBold
                                            }

                                            Text {
                                                text: displayItem.modelData.width + " × " + displayItem.modelData.height + " @ " + (displayItem.modelData.refresh / 1000).toFixed(2) + " Hz"
                                                color: root.colTextSecondary
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                            }
                                        }

                                        // Current scale badge
                                        Rectangle {
                                            implicitWidth: scaleBadgeText.implicitWidth + 16
                                            implicitHeight: 24
                                            radius: 12
                                            color: root.isDark ? "#282832" : "#E0E0E6"
                                            border.width: 1
                                            border.color: root.isDark ? "#3A3A48" : "#D0D0D8"

                                            Text {
                                                id: scaleBadgeText
                                                anchors.centerIn: parent
                                                text: displayItem.currentScalePercent + "%"
                                                color: root.colTextPrimary
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                                font.weight: Font.DemiBold
                                            }
                                        }
                                    }
                                }

                                // Quick Scale Presets (100% to 200%)
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Text {
                                        text: "DISPLAY SCALE PRESETS"
                                        color: root.colTextSecondary
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        font.weight: Font.Medium
                                        Layout.leftMargin: 4
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6

                                        Repeater {
                                            model: [
                                                { label: "100%", scale: 1.0, desc: "Native" },
                                                { label: "125%", scale: 1.25, desc: "Compact" },
                                                { label: "150%", scale: 1.5, desc: "Recommended" },
                                                { label: "175%", scale: 1.75, desc: "Large" },
                                                { label: "200%", scale: 2.0, desc: "2× HiDPI" }
                                            ]

                                            Rectangle {
                                                id: presetBtn
                                                required property var modelData
                                                Layout.fillWidth: true
                                                implicitHeight: 48
                                                radius: 8
                                                readonly property bool isSelected: Math.abs(displayItem.currentScale - presetBtn.modelData.scale) < 0.02

                                                color: isSelected
                                                    ? (root.isDark ? "#FFFFFF" : "#000000")
                                                    : (presetMouse.containsMouse ? (root.isDark ? "#22222A" : "#E5E5EB") : (root.isDark ? "#141418" : "#F4F4F6"))
                                                border.width: 1
                                                border.color: isSelected ? (root.isDark ? "#FFFFFF" : "#000000") : root.colBorder

                                                Behavior on color { ColorAnimation { duration: 100 } }

                                                ColumnLayout {
                                                    anchors.centerIn: parent
                                                    spacing: 1

                                                    Text {
                                                        Layout.alignment: Qt.AlignHCenter
                                                        text: presetBtn.modelData.label
                                                        color: presetBtn.isSelected ? (root.isDark ? "#000000" : "#FFFFFF") : root.colTextPrimary
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 13
                                                        font.weight: presetBtn.isSelected ? Font.Bold : Font.Medium
                                                    }

                                                    Text {
                                                        Layout.alignment: Qt.AlignHCenter
                                                        text: presetBtn.modelData.desc
                                                        color: presetBtn.isSelected ? (root.isDark ? "#333333" : "#CCCCCC") : root.colTextSecondary
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 9
                                                    }
                                                }

                                                MouseArea {
                                                    id: presetMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        OutputService.edit(displayItem.index, "scale", presetBtn.modelData.scale);
                                                        OutputService.apply(OutputService.outputs);
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Fine-grain Scale Slider (100% to 200%)
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 52
                                    radius: 8
                                    color: root.isDark ? "#101014" : "#F7F7F9"
                                    border.width: 1
                                    border.color: root.colBorder

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 14
                                        anchors.rightMargin: 14
                                        spacing: 12

                                        ColumnLayout {
                                            Layout.preferredWidth: 100
                                            spacing: 1

                                            Text {
                                                text: "Fine Scaling"
                                                color: root.colTextPrimary
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 12
                                                font.weight: Font.Medium
                                            }

                                            Text {
                                                text: Math.round(scaleSlider.value * 100) + "% (" + (Math.round(scaleSlider.value * 100) / 100).toFixed(2) + "×)"
                                                color: root.colTextSecondary
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                            }
                                        }

                                        Slider {
                                            id: scaleSlider
                                            Layout.fillWidth: true
                                            from: 1.0
                                            to: 2.0
                                            stepSize: 0.05
                                            value: displayItem.currentScale
                                            onMoved: {
                                                const rounded = Math.round(value * 100) / 100;
                                                OutputService.edit(displayItem.index, "scale", rounded);
                                            }

                                            background: Rectangle {
                                                x: scaleSlider.leftPadding
                                                y: scaleSlider.topPadding + scaleSlider.availableHeight / 2 - 2
                                                width: scaleSlider.availableWidth
                                                height: 4
                                                radius: 2
                                                color: root.isDark ? "#282830" : "#E5E5EA"

                                                Rectangle {
                                                    width: Math.min(parent.width, Math.max(0, ((scaleSlider.value - 1.0) / 1.0) * parent.width))
                                                    height: parent.height
                                                    color: root.isDark ? "#FFFFFF" : "#000000"
                                                    radius: 2
                                                }
                                            }

                                            handle: Rectangle {
                                                x: scaleSlider.leftPadding + Math.max(0, Math.min(scaleSlider.availableWidth - width, ((scaleSlider.value - 1.0) / 1.0) * (scaleSlider.availableWidth - width)))
                                                y: scaleSlider.topPadding + scaleSlider.availableHeight / 2 - height / 2
                                                implicitWidth: 14
                                                implicitHeight: 14
                                                radius: 7
                                                color: root.isDark ? "#FFFFFF" : "#000000"
                                                border.width: 1
                                                border.color: root.colBorder
                                            }
                                        }

                                        Rectangle {
                                            implicitWidth: 80
                                            implicitHeight: 28
                                            radius: 6
                                            color: applyBtnMouse.containsMouse ? (root.isDark ? "#32323D" : "#DCDCE2") : (root.isDark ? "#22222A" : "#EAEAEA")
                                            border.width: 1
                                            border.color: root.colBorder

                                            Text {
                                                anchors.centerIn: parent
                                                text: "Apply"
                                                color: root.colTextPrimary
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 12
                                                font.weight: Font.Medium
                                            }

                                            MouseArea {
                                                id: applyBtnMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: OutputService.apply(OutputService.outputs)
                                            }
                                        }
                                    }
                                }

                                // Resolution & Refresh Rate Selector
                                SettingsChoice {
                                    label: "Resolution & Refresh Rate"
                                    description: displayItem.modelData.width + " × " + displayItem.modelData.height + " @ " + (displayItem.modelData.refresh / 1000).toFixed(2) + " Hz"
                                    value: String(displayItem.modelData.modes.findIndex(m => m.width === displayItem.modelData.width && m.height === displayItem.modelData.height && m.refresh === displayItem.modelData.refresh))
                                    choices: displayItem.modelData.modes.map((m, i) => ({
                                        value: String(i),
                                        label: m.width + " × " + m.height + " @ " + (m.refresh / 1000).toFixed(2) + " Hz" + (m.preferred ? " (Recommended)" : "")
                                    }))
                                    onSelected: value => {
                                        const mode = displayItem.modelData.modes[Number(value)];
                                        const copy = OutputService.outputs.map(o => Object.assign({}, o));
                                        Object.assign(copy[displayItem.index], { width: mode.width, height: mode.height, refresh: mode.refresh });
                                        OutputService.outputs = copy;
                                        OutputService.apply(OutputService.outputs);
                                    }
                                }
                            }
                        }

                        // Display Profiles & Auto-Restore
                        SettingsToggle {
                            label: "Auto-restore display scaling"
                            description: "Automatically reapply saved scale and layout when monitors are reconnected"
                            checked: SettingsService.outputAutoRestore
                            onToggled: value => SettingsService.outputAutoRestore = value
                        }

                        SettingsButton {
                            label: "Refresh connected displays"
                            description: "Query hardware outputs and EDID via Wayland output management"
                            buttonText: "Refresh"
                            enabled: !OutputService.busy
                            onClicked: OutputService.refresh()
                        }
                    }

                    SettingsGroup {
                        title: "INTERFACE & MOTION"
                        SettingsToggle {
                            label: "24-hour clock"; description: "Use 24-hour time in the taskbar and control center"
                            checked: SettingsService.clock24Hour
                            onToggled: value => SettingsService.clock24Hour = value
                        }
                        SettingsToggle {
                            label: "Reduced motion"; description: "Disable shell animations while preserving geometry and timing state"
                            checked: SettingsService.reducedMotion
                            onToggled: value => SettingsService.reducedMotion = value
                        }
                        SettingsToggle {
                            label: "Accessibility labels"; description: "Expose names and descriptions for Settings controls"
                            checked: SettingsService.tooltipsEnabled
                            onToggled: value => SettingsService.tooltipsEnabled = value
                        }
                        SettingsToggle {
                            label: "Unload closed flyouts"; description: "Release large popup trees after they close"
                            checked: SettingsService.unloadClosedFlyouts
                            onToggled: value => SettingsService.unloadClosedFlyouts = value
                        }
                    }

                    SettingsGroup {
                        title: "NOTIFICATIONS & TOASTS"
                        SettingsToggle {
                            label: "Do Not Disturb"; description: "Keep bounded history but suppress toast surfaces"
                            checked: SettingsService.dndEnabled
                            onToggled: SystemService.toggleDnd()
                        }
                        SettingsToggle {
                            label: "Persistent notification history"; description: "Restore safe notification metadata after a shell reload"
                            checked: SettingsService.persistentNotificationHistory
                            onToggled: value => SettingsService.persistentNotificationHistory = value
                        }
                        SettingsToggle {
                            label: "Notification sounds"; description: "Play the desktop message sound for new visible notifications"
                            checked: SettingsService.notificationSounds
                            enabled: SystemService.has("canberra-gtk-play")
                            onToggled: value => SettingsService.notificationSounds = value
                        }
                        SettingsButton {
                            label: "History limit"; description: "Bound notification memory and disk storage"
                            buttonText: String(SettingsService.notificationHistoryLimit)
                            onClicked: SettingsService.notificationHistoryLimit = SettingsService.notificationHistoryLimit >= 200 ? 50 : SettingsService.notificationHistoryLimit + 50
                        }
                        SettingsButton {
                            label: "Toast duration"; description: "Time before non-resident notification toasts hide"
                            buttonText: (SettingsService.notificationTimeout / 1000).toFixed(1) + " s"
                            onClicked: SettingsService.notificationTimeout = SettingsService.notificationTimeout >= 10000 ? 3000 : SettingsService.notificationTimeout + 1000
                        }
                        SettingsField {
                            label: "Muted notification apps"; description: "Comma-separated desktop IDs or application names"
                            text: SettingsService.mutedNotificationApps; placeholder: "discord, steam"
                            onAccepted: value => SettingsService.mutedNotificationApps = value
                        }
                    }

                    SettingsGroup {
                        title: "SCREEN CAPTURE & RECORDING"
                        SettingsButton {
                            label: "Screenshot mode"; description: "Region, active window selection, or entire screen"
                            buttonText: SettingsService.screenshotMode.charAt(0).toUpperCase() + SettingsService.screenshotMode.slice(1)
                            enabled: SystemService.has("grim")
                            onClicked: root.cycleScreenshotMode()
                        }
                        SettingsToggle {
                            label: "Copy screenshots"; description: "Place the captured PNG on the Wayland clipboard"
                            checked: SettingsService.screenshotCopy; enabled: SystemService.has("wl-copy")
                            onToggled: value => SettingsService.screenshotCopy = value
                        }
                        SettingsToggle {
                            label: "Open annotation"; description: "Hand successful captures to Swappy"
                            checked: SettingsService.screenshotAnnotate; enabled: SystemService.has("swappy")
                            onToggled: value => SettingsService.screenshotAnnotate = value
                        }
                        SettingsButton {
                            label: "Take screenshot"; description: SystemService.has("grim") ? "Uses the selected capture workflow" : "grim is not installed"
                            buttonText: "Capture"; enabled: SystemService.has("grim")
                            onClicked: SystemService.captureScreenshot()
                        }
                        SettingsButton {
                            label: "Recording source"; description: "Portal prompts for a source; Screen records the first output directly"
                            buttonText: SettingsService.recordingSource === "portal" ? "Portal" : "Screen"
                            enabled: SystemService.has("gpu-screen-recorder")
                            onClicked: root.cycleRecordingSource()
                        }
                        SettingsToggle {
                            label: "Record microphone"; description: "Mix the default input with desktop audio"
                            checked: SettingsService.recordingMicrophone
                            onToggled: value => SettingsService.recordingMicrophone = value
                        }
                        SettingsButton {
                            label: RecorderService.recording ? "Screen recording in progress" : "Screen recording"
                            description: RecorderService.recording ? (RecorderService.elapsedSeconds + " seconds • " + RecorderService.outputPath) : "GPU-accelerated H.264/HEVC/AV1 capture"
                            buttonText: RecorderService.recording ? "Stop" : "Start"
                            active: RecorderService.recording
                            enabled: SystemService.has("gpu-screen-recorder")
                            onClicked: RecorderService.toggle()
                        }
                    }

                    SettingsGroup {
                        title: "CLIPBOARD MANAGER"
                        SettingsToggle {
                            label: "Clipboard history"; description: "Event-driven text history with pin, search, delete, and clear"
                            checked: SettingsService.clipboardEnabled; enabled: SystemService.has("wl-paste")
                            onToggled: value => SettingsService.clipboardEnabled = value
                        }
                        SettingsToggle {
                            label: "Sensitive-content filter"; description: "Do not retain likely passwords, API tokens, or private keys"
                            checked: SettingsService.clipboardSensitiveFilter
                            onToggled: value => SettingsService.clipboardSensitiveFilter = value
                        }
                        SettingsToggle {
                            label: "Clipboard images"; description: "Retain bounded PNG, JPEG, and WebP items in the private cache"
                            checked: SettingsService.clipboardImagesEnabled
                            onToggled: value => SettingsService.clipboardImagesEnabled = value
                        }
                        SettingsButton {
                            label: "Clipboard history panel"; description: ClipboardService.history.length + " retained text items"
                            buttonText: "Open"; enabled: SettingsService.clipboardEnabled
                            onClicked: ShellState.toggleClipboard()
                        }
                    }

                    SettingsGroup {
                        title: "PERFORMANCE & MAINTENANCE"
                        SettingsButton {
                            label: "Visible metrics interval"; description: "Sampling speed while a telemetry surface is visible"
                            buttonText: SettingsService.metricsActiveInterval + " ms"
                            onClicked: SettingsService.metricsActiveInterval = SettingsService.metricsActiveInterval >= 2000 ? 500 : SettingsService.metricsActiveInterval + 500
                        }
                        SettingsButton {
                            label: "Idle metrics interval"; description: "Lower background wakeups while telemetry is hidden"
                            buttonText: (SettingsService.metricsIdleInterval / 1000) + " s"
                            onClicked: SettingsService.metricsIdleInterval = SettingsService.metricsIdleInterval >= 30000 ? 5000 : SettingsService.metricsIdleInterval + 5000
                        }
                        SettingsButton {
                            label: "Preview cache"; description: SettingsService.previewCacheLimit + " images, " + SettingsService.previewMaxAgeHours + " hour maximum age"
                            buttonText: "Clean"
                            onClicked: SystemService.enqueue(["preview-clean", String(SettingsService.previewCacheLimit), String(SettingsService.previewMaxAgeHours)], "previews", "preview-clean", false)
                        }
                        SettingsButton {
                            label: "Reset General settings"; description: "Restore Weylume defaults without touching Labwc or system files"
                            buttonText: "Reset Defaults"; danger: true
                            onClicked: SettingsService.resetDefaults()
                        }
                    }
                }
            }
        }
    }

    // PAGE 3: WINDOW MANAGER (LABWC)
    Component {
        id: labwcPage
        ScrollView {
            id: labwcScroll
            clip: true
            contentWidth: availableWidth
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: ScrollBar.AlwaysOff

            Item {
                width: labwcScroll.availableWidth
                implicitHeight: labwcCol.implicitHeight + 40

                ColumnLayout {
                    id: labwcCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: 24
                    anchors.rightMargin: 24
                    anchors.topMargin: 18
                    spacing: 16

                    SettingsGroup {
                        title: "COMPOSITOR CORE"
                        SettingsButton {
                            label: "Labwc configuration"; description: SystemService.labwc.configPath || "~/.config/labwc/rc.xml"
                            buttonText: "Edit"; enabled: SystemService.has("featherpad")
                            onClicked: Quickshell.execDetached(["featherpad", SystemService.labwc.configPath || (Quickshell.env("HOME") + "/.config/labwc/rc.xml")])
                        }
                        SettingsButton {
                            label: "Reload Labwc"; description: "Apply rc.xml, environment, menu, and theme changes without logging out"
                            buttonText: "Reload"
                            onClicked: Quickshell.execDetached(["labwc", "--reconfigure"])
                        }
                    }

                    SettingsGroup {
                        title: "KEYBOARD & INPUT"
                        SettingsField {
                            label: "Keyboard layout"; description: "Applied through Labwc's XKB environment and live reconfigure"
                            text: SettingsService.keyboardLayout; placeholder: "us"
                            onAccepted: value => SystemService.setKeyboardLayout(value)
                        }
                        SettingsField {
                            label: "Layout cycle"; description: "Comma-separated layouts used by the tray button"
                            text: SettingsService.keyboardLayouts; placeholder: "us,de,sorani"
                            onAccepted: value => SettingsService.keyboardLayouts = value
                        }
                        SettingsField {
                            label: "Repeat rate"; description: "Key repeats per second"
                            text: String(SystemService.labwc.repeatRate ?? 25); placeholder: "25"
                            onAccepted: value => SystemService.setLabwc("repeatRate", value)
                        }
                        SettingsField {
                            label: "Repeat delay"; description: "Milliseconds before a held key repeats"
                            text: String(SystemService.labwc.repeatDelay ?? 600); placeholder: "600"
                            onAccepted: value => SystemService.setLabwc("repeatDelay", value)
                        }
                    }

                    SettingsGroup {
                        title: "POINTER & TOUCHPAD"
                        SettingsField { label: "Pointer speed"; description: "Labwc/libinput speed from -1.0 to 1.0"; text: String(SystemService.labwc.pointerSpeed ?? 0); placeholder: "0"; onAccepted: value => SystemService.setLabwc("pointerSpeed", value) }
                        SettingsButton {
                            label: "Pointer acceleration"; description: "Flat is predictable for gaming; adaptive follows movement speed"
                            buttonText: SystemService.labwc.accelProfile === "flat" ? "Flat" : "Adaptive"
                            onClicked: SystemService.setLabwc("accelProfile", SystemService.labwc.accelProfile === "flat" ? "adaptive" : "flat")
                        }
                        SettingsToggle { label: "Natural scrolling"; description: "Reverse wheel/gesture direction for non-touch pointer devices"; checked: Boolean(SystemService.labwc.naturalScroll); onToggled: value => SystemService.setLabwc("naturalScroll", value) }
                        SettingsToggle { label: "Touchpad tap-to-click"; description: "Applies only when a touchpad is present"; checked: Boolean(SystemService.labwc.tapToClick); onToggled: value => SystemService.setLabwc("tapToClick", value) }
                        SettingsField { label: "Scroll factor"; description: "Scale pointer wheel scrolling from 0.1 to 10"; text: String(SystemService.labwc.scrollFactor ?? 1); placeholder: "1"; onAccepted: value => SystemService.setLabwc("scrollFactor", value) }
                    }

                    SettingsGroup {
                        title: "WORKSPACES"
                        SettingsField {
                            label: "Workspace count"; description: "Adds safe Super+number and Super+Shift+number bindings when missing"
                            text: String(SystemService.labwc.workspaceCount ?? SettingsService.workspaceCount); placeholder: "4"
                            onAccepted: value => SystemService.setLabwc("workspaceCount", value)
                        }
                        SettingsField {
                            label: "Workspace names"; description: "Comma-separated names; the count follows the list"
                            text: (SystemService.labwc.workspaceNames || []).join(", "); placeholder: "Main, Web, Chat, Games"
                            onAccepted: value => SystemService.setLabwc("workspaceNames", value)
                        }
                        Item {
                            Layout.fillWidth: true
                            implicitHeight: workspaceButtons.implicitHeight + 16
                            Flow {
                                id: workspaceButtons
                                width: parent.width - 24
                                anchors.centerIn: parent
                                spacing: 6
                                Repeater {
                                    model: SystemService.labwc.workspaceNames || []
                                    Rectangle {
                                        required property var modelData
                                        required property int index
                                        implicitWidth: workspaceLabel.implicitWidth + 20
                                        height: 28; radius: 6
                                        color: workspaceMouse.containsMouse ? (root.isDark ? "#242430" : "#E2E2E6") : (root.isDark ? "#16161C" : "#EBEBEF")
                                        border.width: 1
                                        border.color: root.colBorder
                                        Text {
                                            id: workspaceLabel
                                            anchors.centerIn: parent
                                            text: (index + 1) + "  " + modelData
                                            color: root.colTextPrimary
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                        }
                                        MouseArea {
                                            id: workspaceMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: WorkspaceService.activate(index + 1)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    SettingsGroup {
                        title: "WINDOW BEHAVIOR & TILING"
                        SettingsToggle { label: "Focus follows mouse"; description: "Focus a window when the pointer enters it"; checked: Boolean(SystemService.labwc.followMouse); onToggled: value => SystemService.setLabwc("followMouse", value) }
                        SettingsToggle { label: "Raise on focus"; description: "Raise windows when pointer focus changes"; checked: Boolean(SystemService.labwc.raiseOnFocus); onToggled: value => SystemService.setLabwc("raiseOnFocus", value) }
                        SettingsButton {
                            label: "Window placement"; description: "Cycle between cascade, center, and automatic placement"
                            buttonText: SystemService.labwc.placementPolicy || "cascade"
                            onClicked: {
                                const values = ["cascade", "center", "automatic"];
                                SystemService.setLabwc("placementPolicy", values[(values.indexOf(SystemService.labwc.placementPolicy) + 1) % values.length]);
                            }
                        }
                        SettingsField { label: "Window gap"; description: "Labwc core gap in pixels"; text: String(SystemService.labwc.gap ?? 0); placeholder: "0"; onAccepted: value => SystemService.setLabwc("gap", value) }
                        SettingsButton {
                            label: "Decoration mode"; description: "Server-side preserves the current Weylume window style"
                            buttonText: SystemService.labwc.decoration || "server"
                            onClicked: SystemService.setLabwc("decoration", SystemService.labwc.decoration === "client" ? "server" : "client")
                        }
                        SettingsToggle { label: "Window edge snapping"; description: "Snap dragged windows at output edges"; checked: Boolean(SystemService.labwc.snappingEnabled); onToggled: value => SystemService.setLabwc("snappingEnabled", value) }
                        SettingsToggle { label: "Snapping overlay"; description: "Show Labwc's target preview during edge snapping"; checked: Boolean(SystemService.labwc.snappingOverlay); onToggled: value => SystemService.setLabwc("snappingOverlay", value) }
                        SettingsToggle { label: "Top-edge maximize"; description: "Maximize a window when it is dragged to the top edge"; checked: Boolean(SystemService.labwc.topMaximize); onToggled: value => SystemService.setLabwc("topMaximize", value) }
                    }

                    SettingsGroup {
                        title: "DISPLAY & PRESENTATION"
                        SettingsToggle { label: "Adaptive sync / VRR"; description: "Enable Labwc adaptive sync when the output supports it"; checked: Boolean(SystemService.labwc.adaptiveSync); onToggled: value => SystemService.setLabwc("adaptiveSync", value) }
                        SettingsToggle { label: "Allow tearing"; description: "Permits lower-latency presentation for opted-in fullscreen games"; checked: Boolean(SystemService.labwc.allowTearing); onToggled: value => SystemService.setLabwc("allowTearing", value) }
                        SettingsToggle { label: "HDR"; description: "Enable Labwc HDR; only use with a compatible output and game"; checked: Boolean(SystemService.labwc.hdr); onToggled: value => SystemService.setLabwc("hdr", value) }
                        SettingsToggle { label: "Persistent XWayland"; description: "Keep XWayland warm to reduce first X11-app startup latency; applies after Labwc restart"; checked: Boolean(SystemService.labwc.xwaylandPersistence); onToggled: value => SystemService.setLabwc("xwaylandPersistence", value) }
                        SettingsToggle { label: "Reuse output mode"; description: "Reduce display blanking/flicker when Labwc starts"; checked: Boolean(SystemService.labwc.reuseOutputMode); onToggled: value => SystemService.setLabwc("reuseOutputMode", value) }
                        SettingsButton {
                            label: "Inspect Wayland outputs"; description: "Open wlr-randr output details in Kitty"
                            buttonText: "Inspect"; enabled: SystemService.has("wlr-randr") && SystemService.has("kitty")
                            onClicked: Quickshell.execDetached(["kitty", "-e", "wlr-randr"])
                        }
                    }
                }
            }
        }
    }

    // PAGE 4: ARCH SYSTEM & POWER
    Component {
        id: systemPage
        ScrollView {
            id: sysScroll
            clip: true
            contentWidth: availableWidth
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: ScrollBar.AlwaysOff

            Item {
                width: sysScroll.availableWidth
                implicitHeight: sysCol.implicitHeight + 40

                ColumnLayout {
                    id: sysCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: 24
                    anchors.rightMargin: 24
                    anchors.topMargin: 18
                    spacing: 16

                    SettingsGroup {
                        title: "POWER & THERMAL PROFILES"
                        Item {
                            Layout.fillWidth: true
                            implicitHeight: 64
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 10
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 2
                                    Text { text: "Power profile"; color: root.colTextPrimary; font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Font.DemiBold }
                                    Text { text: UPower.displayDevice.ready && UPower.displayDevice.isLaptopBattery ? Math.round(UPower.displayDevice.percentage * 100) + "% battery • " + Math.round(UPower.displayDevice.healthPercentage * 100) + "% health" : "Desktop power source • " + SystemService.powerProfile; color: root.colTextSecondary; font.family: Theme.fontFamily; font.pixelSize: 11 }
                                }
                                Repeater {
                                    model: ["power-saver", "balanced", "performance"]
                                    Rectangle {
                                        id: profileButton
                                        required property string modelData
                                        implicitWidth: profileText.implicitWidth + 18; height: 28; radius: 6
                                        color: SystemService.powerProfile === modelData ? (root.isDark ? "#242430" : "#FFFFFF") : (profileMouse.containsMouse ? (root.isDark ? "#1C1C24" : "#ECECED") : "transparent")
                                        border.width: 1; border.color: SystemService.powerProfile === modelData ? (root.isDark ? "#4F4F60" : "#D0D0D6") : root.colBorder
                                        Text {
                                            id: profileText
                                            anchors.centerIn: parent
                                            text: profileButton.modelData === "power-saver" ? "Saver" : profileButton.modelData.charAt(0).toUpperCase() + profileButton.modelData.slice(1)
                                            color: SystemService.powerProfile === profileButton.modelData ? root.colTextPrimary : root.colTextSecondary
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                            font.weight: SystemService.powerProfile === profileButton.modelData ? Font.DemiBold : Font.Normal
                                        }
                                        MouseArea { id: profileMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: SystemService.setPowerProfile(profileButton.modelData) }
                                    }
                                }
                            }
                        }
                        SettingsToggle {
                            label: "Gaming mode"; description: "Atomically applies performance, DND, and optional tearing policy, then restores previous state"
                            checked: SettingsService.gamingMode
                            onToggled: value => SystemService.setGamingMode(value)
                        }
                        SettingsToggle { label: "Gaming: suppress notifications"; description: "Enable DND while gaming mode is active"; checked: SettingsService.gamingDnd; onToggled: value => SettingsService.gamingDnd = value }
                        SettingsToggle { label: "Gaming: performance profile"; description: "Use power-profiles-daemon performance mode and restore it afterward"; checked: SettingsService.gamingPerformanceProfile; enabled: SystemService.powerProfile !== "unavailable"; onToggled: value => SettingsService.gamingPerformanceProfile = value }
                        SettingsToggle { label: "Gaming: allow tearing"; description: "Temporarily permit Labwc tearing for lower-latency games"; checked: SettingsService.gamingAllowTearing; onToggled: value => SettingsService.gamingAllowTearing = value }
                    }

                    SettingsGroup {
                        title: "DEVICES & CONNECTIVITY"
                        SettingsButton { label: "Network connections"; description: "Interactive NetworkManager configuration"; buttonText: "Open"; enabled: SystemService.has("nmtui") && SystemService.has("kitty"); onClicked: Quickshell.execDetached(["kitty", "-e", "nmtui"]) }
                        SettingsButton { label: "Riseup VPN"; description: SystemService.activeVpn ? "A NetworkManager VPN is active" : "Open the installed VPN client"; buttonText: "Open"; enabled: SystemService.has("riseup-vpn"); onClicked: Quickshell.execDetached(["riseup-vpn"]) }
                        SettingsButton { label: "Bluetooth console"; description: "Pair, trust, inspect, and remove devices"; buttonText: "Open"; enabled: SystemService.has("bluetoothctl") && SystemService.has("kitty"); onClicked: Quickshell.execDetached(["kitty", "-e", "bluetoothctl"]) }
                        SettingsButton { label: "PulseAudio controls"; description: "PipeWire-compatible devices, ports, and streams"; buttonText: "Open"; enabled: SystemService.has("pavucontrol"); onClicked: Quickshell.execDetached(["pavucontrol"]) }
                        SettingsButton { label: "EasyEffects"; description: "PipeWire input/output effects and presets"; buttonText: "Open"; enabled: SystemService.has("easyeffects"); onClicked: Quickshell.execDetached(["easyeffects"]) }
                        SettingsButton { label: "Waydroid Helper"; description: "Android container configuration"; buttonText: "Open"; enabled: SystemService.has("waydroid-helper"); onClicked: Quickshell.execDetached(["waydroid-helper"]) }
                    }

                    SettingsGroup {
                        title: "SERVICE RECOVERY"
                        SettingsButton {
                            label: "Restart user audio stack"; description: "Restart PipeWire, Pulse compatibility, and WirePlumber after an audio failure"
                            buttonText: "Restart"; danger: true
                            onClicked: {
                                SystemService.enqueue(["service", "user", "restart", "pipewire"], "service", "pipewire", false);
                                SystemService.enqueue(["service", "user", "restart", "pipewire-pulse"], "service", "pipewire-pulse", false);
                                SystemService.enqueue(["service", "user", "restart", "wireplumber"], "service", "wireplumber", false);
                            }
                        }
                    }

                    SettingsGroup {
                        title: "UPDATES & SECURITY"
                        SettingsButton {
                            label: "Arch package updates"; description: SystemService.updateCount < 0 ? "Check on demand; never polled in the background" : (SystemService.updateCount + " updates available")
                            buttonText: "Check"; enabled: SystemService.has("checkupdates")
                            onClicked: SystemService.checkUpdates()
                        }
                        SettingsButton { label: "CachyOS Update"; description: "Open the installed graphical updater"; buttonText: "Open"; enabled: SystemService.has("cachy-update"); onClicked: Quickshell.execDetached(["cachy-update"]) }
                        SettingsButton { label: "Firewall status"; description: "Inspect UFW in a terminal; privileged changes remain explicit"; buttonText: "Inspect"; enabled: SystemService.has("ufw") && SystemService.has("kitty"); onClicked: Quickshell.execDetached(["kitty", "-e", "sh", "-c", "sudo ufw status verbose || ufw status verbose; echo; read -n 1 -s -r -p 'Press any key to close...'"]) }
                        SettingsButton { label: "Firmware updates"; description: "Run fwupdmgr interactively in Kitty"; buttonText: "Open"; enabled: SystemService.has("fwupdmgr") && SystemService.has("kitty"); onClicked: Quickshell.execDetached(["kitty", "-e", "sh", "-c", "fwupdmgr get-updates; echo; read -n 1 -s -r -p 'Press any key to close...'"]) }
                    }

                    SettingsGroup {
                        title: "INSTALLED SYSTEM TOOLS"
                        Repeater {
                            model: [
                                { label: "Mission Center", detail: "Processes and resources", command: "missioncenter" },
                                { label: "Btop", detail: "Terminal system monitor", command: "btop", terminal: true },
                                { label: "LACT", detail: "AMD GPU controls", command: "lact" },
                                { label: "GOverlay", detail: "MangoHud configuration", command: "goverlay" },
                                { label: "Piper", detail: "Gaming mouse settings", command: "piper" },
                                { label: "EasyEffects", detail: "PipeWire effects", command: "easyeffects" },
                                { label: "Btrfs Assistant", detail: "Snapshots and Btrfs", command: "btrfs-assistant" },
                                { label: "QDirStat", detail: "Disk usage analysis", command: "qdirstat" },
                                { label: "Kernel Manager", detail: "CachyOS kernels", command: "cachyos-kernel-manager" },
                                { label: "Package Installer", detail: "CachyOS packages", command: SystemService.has("cachyos-pi") ? "cachyos-pi" : "cachyos-packageinstaller" },
                                { label: "GPU Recorder", detail: "Advanced recording UI", command: "gpu-screen-recorder-gtk" },
                                { label: "AMDGPU Top", detail: "Live GPU telemetry", command: "amdgpu_top", terminal: true },
                                { label: "Heroic", detail: "Epic and GOG game launcher", command: "heroic" },
                                { label: "Steam", detail: "Steam game platform", command: "steam" },
                                { label: "Bitwarden", detail: "Password manager", command: SystemService.has("bitwarden-desktop") ? "bitwarden-desktop" : "bitwarden" },
                                { label: "Riseup VPN", detail: "Privacy VPN client", command: "riseup-vpn" },
                                { label: "SCX Manager", detail: "CachyOS scheduler controls", command: "scx-manager" },
                                { label: "Waydroid Helper", detail: "Android container tools", command: "waydroid-helper" }
                            ]
                            SettingsButton {
                                required property var modelData
                                label: modelData.label; description: modelData.detail; buttonText: "Open"
                                enabled: SystemService.has(modelData.command) && (!modelData.terminal || SystemService.has("kitty"))
                                onClicked: Quickshell.execDetached(modelData.terminal ? ["kitty", "-e", modelData.command] : [modelData.command])
                            }
                        }
                    }

                    SettingsGroup {
                        title: "SESSION CONTROLS"
                        SettingsToggle { label: "Confirm session actions"; description: "Show inhibitors and require confirmation before logout, reboot, or shutdown"; checked: SettingsService.confirmSessionActions; onToggled: value => SettingsService.confirmSessionActions = value }
                        SettingsButton { label: "Suspend"; description: SystemService.inhibitors.length ? SystemService.inhibitors.length + " active inhibitors will be shown" : "Suspend the current system safely"; buttonText: "Suspend"; onClicked: ShellState.requestSessionAction("suspend") }
                        SettingsButton { label: "Restart"; description: "Close the current desktop session and reboot"; buttonText: "Restart"; danger: true; onClicked: ShellState.requestSessionAction("reboot") }
                        SettingsButton { label: "Shut down"; description: "Power off the system"; buttonText: "Power off"; danger: true; onClicked: ShellState.requestSessionAction("shutdown") }
                    }
                }
            }
        }
    }
}
