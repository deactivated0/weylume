import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs

PopupWindow {
    id: root
    required property var anchorItem
    Shortcut { sequence: "Escape"; onActivated: ShellState.closeFlyouts() }

    visible: ShellState.audioMixerOpen
    implicitWidth: Math.min(380, Math.max(160, (ShellState.popupScreen?.width || 1920) - 8))
    implicitHeight: Math.min((root.deviceSelectorOpen ? 560 : 490), Math.max(120, (ShellState.popupScreen?.height || 1080) - Theme.taskbarHeight - 12))
    color: "transparent"
    grabFocus: true
    surfaceFormat.opaque: false
    anchor.item: anchorItem
    anchor.edges: Edges.Top | Edges.Right
    anchor.gravity: Edges.Top | Edges.Left

    property bool deviceSelectorOpen: false
    property string activeTab: "outputs" // "outputs" | "inputs"
    property var activeContextMenuStream: null
    readonly property var displayedStreams: root.activeTab === "inputs" ? AudioService.inputStreams : AudioService.streams

    onVisibleChanged: {
        if (visible) {
            activeContextMenuStream = null;
        } else {
            deviceSelectorOpen = false;
            activeContextMenuStream = null;
            if (ShellState.audioMixerOpen) ShellState.audioMixerOpen = false;
        }
    }

    readonly property var currentActiveSink: AudioService.defaultSink
    readonly property var currentActiveSource: AudioService.defaultSource

    function getSinkDisplayName(sinkNode) {
        if (!sinkNode) return "Default Output";
        return sinkNode.properties?.["node.description"] || sinkNode.properties?.["node.nick"] || sinkNode.name || "Output Device";
    }

    function getSourceDisplayName(sourceNode) {
        if (!sourceNode) return "Default Input";
        return sourceNode.properties?.["node.description"] || sourceNode.properties?.["node.nick"] || sourceNode.name || "Input Device";
    }

    // AMOLED Shell Box
    Rectangle {
        id: mainContainer
        anchors.fill: parent
        anchors.margins: 4
        radius: 16
        color: Theme.background
        border.width: 1
        border.color: Theme.border
        clip: true

        ColumnLayout {
            id: contentCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            // 1. Header: Device Selector Button & Close
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                // Device Switcher Dropdown Button
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 38
                    radius: 8
                    color: devHeaderMouse.containsMouse ? "#0a0a0a" : "#000000"
                    border.width: 1
                    border.color: root.deviceSelectorOpen ? "#282828" : "#141414"

                    Behavior on color { ColorAnimation { duration: 100 } }
                    Behavior on border.color { ColorAnimation { duration: 100 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        // Device Type Indicator Icon
                        Rectangle {
                            width: 22; height: 22; radius: 5
                            color: "#080808"
                            border.width: 1
                            border.color: "#181818"

                            Image {
                                id: devHeaderIcon
                                anchors.centerIn: parent
                                width: 12; height: 12
                                sourceSize: Qt.size(24, 24)
                                source: root.activeTab === "inputs"
                                    ? "assets/mic.svg"
                                    : (AudioService.getDeviceKind(root.currentActiveSink) === "headphones" ? "assets/headphones.svg" : "assets/volume.svg")
                                visible: false
                            }
                            MultiEffect {
                                anchors.fill: devHeaderIcon
                                source: devHeaderIcon
                                colorization: 1.0
                                colorizationColor: "#ffffff"
                            }
                        }

                        // Current Device Name
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            Text {
                                text: root.activeTab === "inputs"
                                    ? root.getSourceDisplayName(root.currentActiveSource)
                                    : root.getSinkDisplayName(root.currentActiveSink)
                                color: "#ffffff"
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Text {
                                text: root.activeTab === "inputs" ? "Active Input Device" : "Active Output Device"
                                color: "#888888"
                                font.family: Theme.fontFamily
                                font.pixelSize: 8
                            }
                        }

                        // Dropdown Arrow
                        Text {
                            text: root.deviceSelectorOpen ? "▴" : "▾"
                            color: "#888888"
                            font.pixelSize: 11
                            font.weight: Font.Bold
                        }
                    }

                    MouseArea {
                        id: devHeaderMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.deviceSelectorOpen = !root.deviceSelectorOpen
                    }
                }

                // Close Button
                Rectangle {
                    width: 28; height: 28; radius: 7
                    color: closeBtnMouse.containsMouse ? "#181818" : "#080808"
                    border.width: 1
                    border.color: "#181818"

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: "#999999"
                        font.pixelSize: 10
                    }

                    MouseArea {
                        id: closeBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ShellState.closeFlyouts()
                    }
                }
            }

            // 2. Expandable Device Selector Panel (OUTPUTS / INPUTS)
            Rectangle {
                id: deviceSelectorPanel
                visible: root.deviceSelectorOpen
                Layout.fillWidth: true
                implicitHeight: devSelectCol.implicitHeight + 16
                radius: 10
                color: "#000000"
                border.width: 1
                border.color: "#141414"

                ColumnLayout {
                    id: devSelectCol
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8

                    // Segmented Tabs Header
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 26
                            radius: 6
                            color: root.activeTab === "outputs" ? "#ffffff" : (outTabMouse.containsMouse ? "#141414" : "#080808")
                            border.width: 1
                            border.color: root.activeTab === "outputs" ? "#ffffff" : "#181818"

                            Text {
                                anchors.centerIn: parent
                                text: "OUTPUTS"
                                color: root.activeTab === "outputs" ? "#000000" : "#888888"
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                font.weight: Font.Bold
                            }

                            MouseArea {
                                id: outTabMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.activeTab = "outputs"
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 26
                            radius: 6
                            color: root.activeTab === "inputs" ? "#ffffff" : (inTabMouse.containsMouse ? "#141414" : "#080808")
                            border.width: 1
                            border.color: root.activeTab === "inputs" ? "#ffffff" : "#181818"

                            Text {
                                anchors.centerIn: parent
                                text: "INPUTS"
                                color: root.activeTab === "inputs" ? "#000000" : "#888888"
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                font.weight: Font.Bold
                            }

                            MouseArea {
                                id: inTabMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.activeTab = "inputs"
                            }
                        }
                    }

                    // Sinks List
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        visible: root.activeTab === "outputs"

                        Repeater {
                            model: AudioService.sinks

                            Rectangle {
                                id: sinkRow
                                required property var modelData
                                required property int index
                                readonly property bool isDefault: AudioService.isSinkDefault(modelData)

                                Layout.fillWidth: true
                                implicitHeight: 32
                                radius: 6
                                color: isDefault ? "#141414" : (sinkRowMouse.containsMouse ? "#101010" : "transparent")
                                border.width: 1
                                border.color: isDefault ? "#ffffff" : (sinkRowMouse.containsMouse ? "#242424" : "transparent")

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 8

                                    Text {
                                        text: sinkRow.isDefault ? "✓" : " "
                                        color: "#ffffff"
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        Layout.preferredWidth: 12
                                    }

                                    Text {
                                        text: root.getSinkDisplayName(sinkRow.modelData)
                                        color: sinkRow.isDefault ? "#ffffff" : "#cccccc"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        font.weight: sinkRow.isDefault ? Font.DemiBold : Font.Normal
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    Text {
                                        text: Math.round((sinkRow.modelData.audio?.volume ?? 1.0) * 100) + "%"
                                        color: "#888888"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 9
                                    }
                                }

                                MouseArea {
                                    id: sinkRowMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        AudioService.setDefaultSink(sinkRow.modelData);
                                    }
                                }
                            }
                        }
                    }

                    // Sources List
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        visible: root.activeTab === "inputs"

                        Repeater {
                            model: AudioService.sources

                            Rectangle {
                                id: sourceRow
                                required property var modelData
                                required property int index
                                readonly property bool isDefault: AudioService.isSourceDefault(modelData)

                                Layout.fillWidth: true
                                implicitHeight: 32
                                radius: 6
                                color: isDefault ? "#141414" : (sourceRowMouse.containsMouse ? "#101010" : "transparent")
                                border.width: 1
                                border.color: isDefault ? "#ffffff" : (sourceRowMouse.containsMouse ? "#242424" : "transparent")

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 8

                                    Text {
                                        text: sourceRow.isDefault ? "✓" : " "
                                        color: "#ffffff"
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        Layout.preferredWidth: 12
                                    }

                                    Text {
                                        text: root.getSourceDisplayName(sourceRow.modelData)
                                        color: sourceRow.isDefault ? "#ffffff" : "#cccccc"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        font.weight: sourceRow.isDefault ? Font.DemiBold : Font.Normal
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    Text {
                                        text: Math.round((sourceRow.modelData.audio?.volume ?? 1.0) * 100) + "%"
                                        color: "#888888"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 9
                                    }
                                }

                                MouseArea {
                                    id: sourceRowMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        AudioService.setDefaultSource(sourceRow.modelData);
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // 3. Master Volume Section
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: masterCol.implicitHeight + 12
                radius: 10
                color: "#000000"
                border.width: 1
                border.color: "#141414"

                ColumnLayout {
                    id: masterCol
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        // Master Mute Button
                        Rectangle {
                            width: 28; height: 28; radius: 6
                            color: masterMuteMouse.containsMouse ? "#141414" : "#080808"
                            border.width: 1
                            border.color: "#181818"

                            readonly property bool isMuted: root.activeTab === "inputs"
                                ? (root.currentActiveSource?.audio?.muted ?? false)
                                : (root.currentActiveSink?.audio?.muted ?? false)

                            Image {
                                id: masterMuteIcon
                                anchors.centerIn: parent
                                width: 14; height: 14
                                sourceSize: Qt.size(28, 28)
                                source: parent.isMuted
                                    ? "assets/speaker-muted-mono.svg"
                                    : (root.activeTab === "inputs" ? "assets/mic.svg" : "assets/volume.svg")
                                visible: false
                            }
                            MultiEffect {
                                anchors.fill: masterMuteIcon
                                source: masterMuteIcon
                                colorization: 1.0
                                colorizationColor: parent.isMuted ? "#ff5555" : "#ffffff"
                            }

                            MouseArea {
                                id: masterMuteMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.activeTab === "inputs") {
                                        AudioService.toggleMute(root.currentActiveSource);
                                    } else {
                                        AudioService.toggleMute(root.currentActiveSink);
                                    }
                                }
                            }
                        }

                        // Master Volume Slider
                        Slider {
                            id: masterSlider
                            Layout.fillWidth: true
                            from: 0.0; to: 1.0
                            value: root.activeTab === "inputs"
                                ? (root.currentActiveSource?.audio?.volume ?? 1.0)
                                : (root.currentActiveSink?.audio?.volume ?? 0.5)

                            onMoved: {
                                const targetNode = root.activeTab === "inputs" ? root.currentActiveSource : root.currentActiveSink;
                                AudioService.setVolume(targetNode, value);
                            }

                            background: Rectangle {
                                x: masterSlider.leftPadding
                                y: masterSlider.topPadding + masterSlider.availableHeight / 2 - 2
                                implicitWidth: 140
                                implicitHeight: 4
                                width: masterSlider.availableWidth
                                height: 4
                                radius: 2
                                color: "#222222"

                                Rectangle {
                                    width: masterSlider.visualPosition * parent.width
                                    height: parent.height
                                    color: (root.activeTab === "inputs" ? (AudioService.defaultSource?.audio?.muted ?? false) : (AudioService.defaultSink?.audio?.muted ?? false)) ? "#666666" : "#ffffff"
                                    radius: 2
                                }
                            }

                            handle: Rectangle {
                                x: masterSlider.leftPadding + masterSlider.visualPosition * (masterSlider.availableWidth - width)
                                y: masterSlider.topPadding + masterSlider.availableHeight / 2 - height / 2
                                implicitWidth: 14
                                implicitHeight: 14
                                radius: 7
                                color: "#ffffff"
                                border.width: 1
                                border.color: "#0a0a0a"
                            }
                        }

                        // Master Volume Percentage
                        Text {
                            text: Math.round(masterSlider.value * 100) + "%"
                            color: "#ffffff"
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            Layout.preferredWidth: 32
                            horizontalAlignment: Text.AlignRight
                        }
                    }

                    // Subtitle text (master output / master input)
                    Text {
                        text: root.activeTab === "inputs" ? "master input" : "master output"
                        color: "#727272"
                        font.family: Theme.fontFamily
                        font.pixelSize: 8
                        Layout.leftMargin: 36
                    }
                }
            }

            // Divider
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: "#181818"
                Layout.topMargin: 2
                Layout.bottomMargin: 2
            }

            // 4. Per-Application Streams Area
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: root.activeTab === "inputs" ? "RECORDING APPLICATIONS" : "APPLICATIONS"
                    color: "#888888"
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    Layout.fillWidth: true
                }
                Text {
                    text: root.displayedStreams.length > 0 ? (root.displayedStreams.length + (root.activeTab === "inputs" ? " recording" : " active")) : "idle"
                    color: "#555555"
                    font.family: Theme.fontFamily
                    font.pixelSize: 8
                }
            }

            // Scrollable App List
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 120
                clip: true
                contentWidth: availableWidth

                ColumnLayout {
                    width: parent.width
                    spacing: 6

                    // Empty State Notice
                    Rectangle {
                        visible: root.displayedStreams.length === 0
                        Layout.fillWidth: true
                        implicitHeight: 64
                        radius: 8
                        color: "#080808"
                        border.width: 1
                        border.color: "#141414"

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 3
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: root.activeTab === "inputs" ? "No active recording applications" : "No active application audio"
                                color: "#666666"
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: root.activeTab === "inputs" ? "Apps recording microphone appear here dynamically" : "Apps appear here dynamically when playing sound"
                                color: "#444444"
                                font.family: Theme.fontFamily
                                font.pixelSize: 8
                            }
                        }
                    }

                    // Active Stream Rows
                    Repeater {
                        model: root.displayedStreams

                        Rectangle {
                            id: appCard
                            required property var modelData
                            required property int index

                            readonly property var routedSink: AudioService.getStreamSink(modelData)
                            readonly property string appName: AudioService.getAppDisplayName(modelData)
                            readonly property string appIcon: AudioService.getAppIconPath(modelData)
                            readonly property bool isMuted: modelData.audio?.muted ?? false
                            readonly property real currentVol: modelData.audio?.volume ?? 1.0

                            Layout.fillWidth: true
                            implicitHeight: appRowCol.implicitHeight + 10
                            radius: 8
                            color: appCardMouse.containsMouse ? "#080808" : "#000000"
                            border.width: 1
                            border.color: appCardMouse.containsMouse ? "#1c1c1c" : "#101010"

                            ColumnLayout {
                                id: appRowCol
                                anchors.fill: parent
                                anchors.margins: 6
                                spacing: 3

                                // Top line: Icon, Name, Target Device, Menu Button
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    // App Icon
                                    Rectangle {
                                        width: 20; height: 20; radius: 4
                                        color: "#080808"
                                        border.width: 1
                                        border.color: "#161616"

                                        Image {
                                            id: aIcon
                                            anchors.centerIn: parent
                                            width: 14; height: 14
                                            sourceSize: Qt.size(28, 28)
                                            source: appCard.appIcon
                                            fillMode: Image.PreserveAspectFit
                                            visible: status === Image.Ready
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            text: appCard.appName.charAt(0).toUpperCase()
                                            visible: !aIcon.visible
                                            color: "#ffffff"
                                            font.pixelSize: 9
                                            font.weight: Font.Bold
                                        }
                                    }

                                    // App Name
                                    Text {
                                        text: appCard.appName
                                        color: "#ffffff"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    // Route Tag (Target Sink)
                                    Text {
                                        text: "→ " + root.getSinkDisplayName(appCard.routedSink)
                                        color: "#727272"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 8
                                        elide: Text.ElideRight
                                        Layout.maximumWidth: 100
                                    }

                                    // Context Menu ⋯ Button
                                    Rectangle {
                                        width: 18; height: 18; radius: 4
                                        color: menuBtnMouse.containsMouse ? "#202020" : "transparent"
                                        Text {
                                            anchors.centerIn: parent
                                            text: "⋯"
                                            color: "#999999"
                                            font.pixelSize: 11
                                        }
                                        MouseArea {
                                            id: menuBtnMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.activeContextMenuStream = (root.activeContextMenuStream === appCard.modelData) ? null : appCard.modelData;
                                            }
                                        }
                                    }
                                }

                                // Bottom line: Speaker Mute + Slider + Percent
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    // Speaker Mute Button
                                    Rectangle {
                                        width: 22; height: 22; radius: 5
                                        color: appMuteMouse.containsMouse ? "#141414" : "#080808"
                                        border.width: 1
                                        border.color: "#181818"

                                        Image {
                                            id: appSpeakerIcon
                                            anchors.centerIn: parent
                                            width: 11; height: 11
                                            sourceSize: Qt.size(22, 22)
                                            source: appCard.isMuted ? "assets/speaker-muted-mono.svg" : "assets/volume.svg"
                                            visible: false
                                        }
                                        MultiEffect {
                                            anchors.fill: appSpeakerIcon
                                            source: appSpeakerIcon
                                            colorization: 1.0
                                            colorizationColor: appCard.isMuted ? "#ff5555" : "#ffffff"
                                        }

                                        MouseArea {
                                            id: appMuteMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: AudioService.toggleMute(appCard.modelData)
                                        }
                                    }

                                    // App Volume Slider (0.0 to 1.5)
                                    Slider {
                                        id: appVolSlider
                                        Layout.fillWidth: true
                                        from: 0.0; to: 1.5
                                        value: appCard.currentVol
                                        onMoved: AudioService.setVolume(appCard.modelData, value)

                                        background: Rectangle {
                                            x: appVolSlider.leftPadding
                                            y: appVolSlider.topPadding + appVolSlider.availableHeight / 2 - 2
                                            implicitWidth: 120
                                            implicitHeight: 4
                                            width: appVolSlider.availableWidth
                                            height: 4
                                            radius: 2
                                            color: "#141414"

                                            Rectangle {
                                                width: Math.min(parent.width, (appVolSlider.value / 1.5) * parent.width)
                                                height: parent.height
                                                color: appCard.isMuted ? "#555555" : "#ffffff"
                                                radius: 2
                                            }
                                        }

                                        handle: Rectangle {
                                            x: appVolSlider.leftPadding + (appVolSlider.value / 1.5) * (appVolSlider.availableWidth - width)
                                            y: appVolSlider.topPadding + appVolSlider.availableHeight / 2 - height / 2
                                            implicitWidth: 12
                                            implicitHeight: 12
                                            radius: 6
                                            color: "#ffffff"
                                            border.width: 1
                                            border.color: "#080808"
                                        }
                                    }

                                    // Percent Text
                                    Text {
                                        text: Math.round(appCard.currentVol * 100) + "%"
                                        color: "#ffffff"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                        Layout.preferredWidth: 30
                                        horizontalAlignment: Text.AlignRight
                                    }
                                }

                                // Embedded EarTrumpet Route Context Menu (When Activated)
                                Rectangle {
                                    visible: root.activeContextMenuStream === appCard.modelData
                                    Layout.fillWidth: true
                                    implicitHeight: menuBoxCol.implicitHeight + 12
                                    radius: 6
                                    color: "#000000"
                                    border.width: 1
                                    border.color: "#202020"

                                    ColumnLayout {
                                        id: menuBoxCol
                                        anchors.fill: parent
                                        anchors.margins: 6
                                        spacing: 4

                                        // Mute Toggle Row
                                        Rectangle {
                                            Layout.fillWidth: true
                                            implicitHeight: 24
                                            radius: 4
                                            color: menuMuteMouse.containsMouse ? "#121212" : "transparent"
                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 6
                                                anchors.rightMargin: 6
                                                spacing: 6
                                                Text { text: appCard.isMuted ? "🔊" : "🔇"; font.pixelSize: 10 }
                                                Text { text: appCard.isMuted ? "Unmute" : "Mute"; color: "#ffffff"; font.family: Theme.fontFamily; font.pixelSize: 9; Layout.fillWidth: true }
                                            }
                                            MouseArea {
                                                id: menuMuteMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: AudioService.toggleMute(appCard.modelData)
                                            }
                                        }

                                        // Reset Volume Row
                                        Rectangle {
                                            Layout.fillWidth: true
                                            implicitHeight: 24
                                            radius: 4
                                            color: menuResetMouse.containsMouse ? "#121212" : "transparent"
                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 6
                                                anchors.rightMargin: 6
                                                spacing: 6
                                                Text { text: "↺"; color: "#ffffff"; font.pixelSize: 11; font.weight: Font.Bold }
                                                Text { text: "Reset volume (100%)"; color: "#ffffff"; font.family: Theme.fontFamily; font.pixelSize: 9; Layout.fillWidth: true }
                                            }
                                            MouseArea {
                                                id: menuResetMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: AudioService.setVolume(appCard.modelData, 1.0)
                                            }
                                        }

                                        // Route Section Header
                                        Text {
                                            text: "Play audio on:"
                                            color: "#888888"
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 8
                                            font.weight: Font.Bold
                                            Layout.leftMargin: 4
                                            Layout.topMargin: 2
                                        }

                                        // Output Sinks Destination Selector
                                        Repeater {
                                            model: AudioService.sinks

                                             Rectangle {
                                                 id: destRow
                                                 required property var modelData
                                                 required property int index
                                                 readonly property bool isCurrentRoute: (appCard.routedSink && destRow.modelData.id === appCard.routedSink.id) || (destRow.modelData.properties?.["node.name"] === appCard.routedSink?.properties?.["node.name"])

                                                 Layout.fillWidth: true
                                                 implicitHeight: 24
                                                 radius: 4
                                                 color: isCurrentRoute ? "#141414" : (destRowMouse.containsMouse ? "#0e0e0e" : "transparent")

                                                 RowLayout {
                                                     anchors.fill: parent
                                                     anchors.leftMargin: 6
                                                     anchors.rightMargin: 6
                                                     spacing: 6

                                                     Text {
                                                         text: destRow.isCurrentRoute ? "✓" : " "
                                                         color: "#ffffff"
                                                         font.pixelSize: 10
                                                         font.weight: Font.Bold
                                                         Layout.preferredWidth: 10
                                                     }

                                                     Text {
                                                         text: root.getSinkDisplayName(destRow.modelData)
                                                         color: destRow.isCurrentRoute ? "#ffffff" : "#b0b0b0"
                                                         font.family: Theme.fontFamily
                                                         font.pixelSize: 9
                                                         font.weight: destRow.isCurrentRoute ? Font.DemiBold : Font.Normal
                                                         elide: Text.ElideRight
                                                         Layout.fillWidth: true
                                                     }
                                                 }

                                                 MouseArea {
                                                     id: destRowMouse
                                                     anchors.fill: parent
                                                     hoverEnabled: true
                                                     cursorShape: Qt.PointingHandCursor
                                                     onClicked: {
                                                         AudioService.moveStream(appCard.modelData, destRow.modelData);
                                                         root.activeContextMenuStream = null;
                                                     }
                                                 }
                                             }
                                        }
                                    }
                                }
                            }

                            // Right-click to toggle stream context menu
                            MouseArea {
                                id: appCardMouse
                                anchors.fill: parent
                                z: -1
                                hoverEnabled: true
                                acceptedButtons: Qt.RightButton
                                onClicked: {
                                    root.activeContextMenuStream = (root.activeContextMenuStream === appCard.modelData) ? null : appCard.modelData;
                                }
                            }
                        }
                    }
                }
            }

            // Divider
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: "#141414"
                Layout.topMargin: 2
                Layout.bottomMargin: 2
            }

            // 5. Footer: More audio settings
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 32
                radius: 8
                color: footSettingsMouse.containsMouse ? "#0a0a0a" : "#000000"
                border.width: 1
                border.color: footSettingsMouse.containsMouse ? "#202020" : "#121212"

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 8

                    Rectangle {
                        width: 20; height: 20; radius: 5
                        color: "#161616"
                        Image {
                            id: footSetIcon
                            anchors.centerIn: parent
                            width: 11; height: 11
                            sourceSize: Qt.size(22, 22)
                            source: "assets/settings.svg"
                            visible: false
                        }
                        MultiEffect {
                            anchors.fill: footSetIcon
                            source: footSetIcon
                            colorization: 1.0
                            colorizationColor: Theme.accent
                        }
                    }

                    Text {
                        text: "More audio settings"
                        color: "#d0d0d0"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        Layout.fillWidth: true
                    }

                    Text {
                        text: "›"
                        color: "#888888"
                        font.pixelSize: 13
                        font.weight: Font.Bold
                    }
                }

                MouseArea {
                    id: footSettingsMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        ShellState.closeFlyouts();
                        ShellState.toggleSettings(root.screen?.name);
                    }
                }
            }
        }
    }
}
