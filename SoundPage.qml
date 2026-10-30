import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import qs

ScrollView {
    id: root
    clip: true
    contentWidth: availableWidth
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
    ScrollBar.vertical.policy: ScrollBar.AlwaysOff

    readonly property bool isDark: SettingsService.darkMode !== false
    readonly property color colSurface: isDark ? "#0C0C0E" : "#FBFBFD"
    readonly property color colBorder: isDark ? "#1F1F22" : "#E5E5EA"
    readonly property color colTextPrimary: isDark ? "#FFFFFF" : "#000000"
    readonly property color colTextSecondary: isDark ? "#8E8E93" : "#6E6E73"
    readonly property color colAccent: isDark ? "#FFFFFF" : "#000000"

    readonly property var activeSink: {
        const sinks = AudioService.sinks;
        for (let i = 0; i < sinks.length; i++) {
            if (AudioService.isSinkDefault(sinks[i])) return sinks[i];
        }
        return AudioService.defaultSink;
    }

    readonly property var activeSource: {
        const sources = AudioService.sources;
        for (let i = 0; i < sources.length; i++) {
            if (AudioService.isSourceDefault(sources[i])) return sources[i];
        }
        return AudioService.defaultSource;
    }

    function sinkTitle(s) {
        if (!s) return "Default Audio Sink";
        return s.properties?.["node.description"] || s.properties?.["node.nick"] || s.name || "Output Device";
    }

    function sourceTitle(s) {
        if (!s) return "Default Audio Source";
        return s.properties?.["node.description"] || s.properties?.["node.nick"] || s.name || "Input Device";
    }

    Item {
        width: root.availableWidth
        implicitHeight: soundCol.implicitHeight + 40

        ColumnLayout {
            id: soundCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 24
            anchors.rightMargin: 24
            anchors.topMargin: 18
            spacing: 16

            // 1. OUTPUT DEVICES
            SettingsGroup {
                title: "OUTPUT DEVICES (PLAYBACK)"

                // Master Volume Slider & Mute Row
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 64
                    color: "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 12

                        // Mute button
                        Rectangle {
                            width: 32; height: 32; radius: 6
                            color: root.isDark ? (sinkMuteMouse.containsMouse ? "#24242A" : "#16161B") : (sinkMuteMouse.containsMouse ? "#E5E5EA" : "#F2F2F7")
                            border.width: 1
                            border.color: root.colBorder

                            Image {
                                anchors.centerIn: parent
                                width: 16; height: 16
                                source: (root.activeSink?.audio?.muted ?? false) ? "assets/speaker-muted-mono.svg" : "assets/volume.svg"
                            }

                            MouseArea {
                                id: sinkMuteMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (root.activeSink) AudioService.toggleMute(root.activeSink)
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "Master Output Volume"
                                    color: root.colTextPrimary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: Math.round(((root.activeSink?.audio?.volume ?? 0.5)) * 100) + "%"
                                    color: (root.activeSink?.audio?.muted ?? false) ? root.colTextSecondary : root.colTextPrimary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                }
                            }

                            Slider {
                                id: masterSlider
                                Layout.fillWidth: true
                                from: 0.0; to: 1.5
                                value: root.activeSink?.audio?.volume ?? 0.5
                                onMoved: if (root.activeSink) AudioService.setVolume(root.activeSink, value)

                                background: Rectangle {
                                    x: masterSlider.leftPadding
                                    y: masterSlider.topPadding + masterSlider.availableHeight / 2 - 2
                                    width: masterSlider.availableWidth
                                    height: 4
                                    radius: 2
                                    color: root.isDark ? "#282830" : "#E5E5EA"

                                    Rectangle {
                                        width: Math.min(parent.width, (masterSlider.value / 1.5) * parent.width)
                                        height: parent.height
                                        color: (root.activeSink?.audio?.muted ?? false) ? root.colTextSecondary : (root.isDark ? "#FFFFFF" : "#000000")
                                        radius: 2
                                    }
                                }

                                handle: Rectangle {
                                    x: masterSlider.leftPadding + (masterSlider.value / 1.5) * (masterSlider.availableWidth - width)
                                    y: masterSlider.topPadding + masterSlider.availableHeight / 2 - height / 2
                                    implicitWidth: 14
                                    implicitHeight: 14
                                    radius: 7
                                    color: root.isDark ? "#FFFFFF" : "#000000"
                                    border.width: 1
                                    border.color: root.colBorder
                                }
                            }
                        }
                    }
                }

                // Available Output Devices Repeater
                Repeater {
                    model: AudioService.sinks
                    SettingsButton {
                        required property var modelData
                        readonly property bool isDefault: AudioService.isSinkDefault(modelData)
                        label: root.sinkTitle(modelData)
                        description: isDefault ? "Active default playback sink" : "Click to set as default output"
                        buttonText: isDefault ? "Selected ✓" : "Select"
                        enabled: !isDefault
                        onClicked: AudioService.setDefaultSink(modelData)
                    }
                }

                // Test Sound Button
                SettingsButton {
                    label: "Test audio output"
                    description: "Play test chime to verify speaker balance and volume"
                    buttonText: "Play Test Sound"
                    onClicked: {
                        if (SystemService.has("canberra-gtk-play")) {
                            Quickshell.execDetached(["canberra-gtk-play", "-i", "audio-channel-front-center"]);
                        } else if (SystemService.has("paplay")) {
                            Quickshell.execDetached(["paplay", "/usr/share/sounds/freedesktop/stereo/complete.oga"]);
                        } else {
                            Quickshell.execDetached(["speaker-test", "-t", "wav", "-c", "2", "-l", "1"]);
                        }
                    }
                }
            }

            // 2. INPUT DEVICES (MICROPHONE)
            SettingsGroup {
                title: "INPUT DEVICES (RECORDING & MICROPHONES)"

                // Microphone Volume Slider & Mute Row
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 64
                    color: "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 12

                        // Mute button
                        Rectangle {
                            width: 32; height: 32; radius: 6
                            color: root.isDark ? (sourceMuteMouse.containsMouse ? "#24242A" : "#16161B") : (sourceMuteMouse.containsMouse ? "#E5E5EA" : "#F2F2F7")
                            border.width: 1
                            border.color: root.colBorder

                            Image {
                                anchors.centerIn: parent
                                width: 16; height: 16
                                source: "assets/mic.svg"
                                opacity: (root.activeSource?.audio?.muted ?? false) ? 0.3 : 1.0
                            }

                            MouseArea {
                                id: sourceMuteMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (root.activeSource) AudioService.toggleMute(root.activeSource)
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "Microphone Input Level"
                                    color: root.colTextPrimary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: Math.round(((root.activeSource?.audio?.volume ?? 1.0)) * 100) + "%"
                                    color: (root.activeSource?.audio?.muted ?? false) ? root.colTextSecondary : root.colTextPrimary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                }
                            }

                            Slider {
                                id: micSlider
                                Layout.fillWidth: true
                                from: 0.0; to: 1.5
                                value: root.activeSource?.audio?.volume ?? 1.0
                                onMoved: if (root.activeSource) AudioService.setVolume(root.activeSource, value)

                                background: Rectangle {
                                    x: micSlider.leftPadding
                                    y: micSlider.topPadding + micSlider.availableHeight / 2 - 2
                                    width: micSlider.availableWidth
                                    height: 4
                                    radius: 2
                                    color: root.isDark ? "#282830" : "#E5E5EA"

                                    Rectangle {
                                        width: Math.min(parent.width, (micSlider.value / 1.5) * parent.width)
                                        height: parent.height
                                        color: (root.activeSource?.audio?.muted ?? false) ? root.colTextSecondary : (root.isDark ? "#FFFFFF" : "#000000")
                                        radius: 2
                                    }
                                }

                                handle: Rectangle {
                                    x: micSlider.leftPadding + (micSlider.value / 1.5) * (micSlider.availableWidth - width)
                                    y: micSlider.topPadding + micSlider.availableHeight / 2 - height / 2
                                    implicitWidth: 14
                                    implicitHeight: 14
                                    radius: 7
                                    color: root.isDark ? "#FFFFFF" : "#000000"
                                    border.width: 1
                                    border.color: root.colBorder
                                }
                            }
                        }
                    }
                }

                // Available Input Sources Repeater
                Repeater {
                    model: AudioService.sources
                    SettingsButton {
                        required property var modelData
                        readonly property bool isDefault: AudioService.isSourceDefault(modelData)
                        label: root.sourceTitle(modelData)
                        description: isDefault ? "Active default microphone source" : "Click to set as default microphone"
                        buttonText: isDefault ? "Selected ✓" : "Select"
                        enabled: !isDefault
                        onClicked: AudioService.setDefaultSource(modelData)
                    }
                }
            }

            // 3. APPLICATION AUDIO MIXER
            SettingsGroup {
                title: "APPLICATION AUDIO MIXER"

                // Active App Streams
                Repeater {
                    model: AudioService.streams
                    Rectangle {
                        id: appStreamRow
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 56
                        color: "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            spacing: 12

                            // App Icon
                            Rectangle {
                                width: 28; height: 28; radius: 6
                                color: root.isDark ? "#181820" : "#EBEBEF"
                                border.width: 1
                                border.color: root.colBorder

                                Image {
                                    anchors.centerIn: parent
                                    width: 18; height: 18
                                    source: AudioService.getAppIconPath(appStreamRow.modelData)
                                }
                            }

                            // App Name & Slider
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        text: AudioService.getAppDisplayName(appStreamRow.modelData)
                                        color: root.colTextPrimary
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: Math.round(((appStreamRow.modelData?.audio?.volume ?? 1.0)) * 100) + "%"
                                        color: (appStreamRow.modelData?.audio?.muted ?? false) ? root.colTextSecondary : root.colTextPrimary
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                    }
                                }

                                Slider {
                                    id: streamSlider
                                    Layout.fillWidth: true
                                    from: 0.0; to: 1.5
                                    value: appStreamRow.modelData?.audio?.volume ?? 1.0
                                    onMoved: AudioService.setVolume(appStreamRow.modelData, value)

                                    background: Rectangle {
                                        x: streamSlider.leftPadding
                                        y: streamSlider.topPadding + streamSlider.availableHeight / 2 - 2
                                        width: streamSlider.availableWidth
                                        height: 4
                                        radius: 2
                                        color: root.isDark ? "#282830" : "#E5E5EA"

                                        Rectangle {
                                            width: Math.min(parent.width, (streamSlider.value / 1.5) * parent.width)
                                            height: parent.height
                                            color: (appStreamRow.modelData?.audio?.muted ?? false) ? root.colTextSecondary : (root.isDark ? "#FFFFFF" : "#000000")
                                            radius: 2
                                        }
                                    }

                                    handle: Rectangle {
                                        x: streamSlider.leftPadding + (streamSlider.value / 1.5) * (streamSlider.availableWidth - width)
                                        y: streamSlider.topPadding + streamSlider.availableHeight / 2 - height / 2
                                        implicitWidth: 12
                                        implicitHeight: 12
                                        radius: 6
                                        color: root.isDark ? "#FFFFFF" : "#000000"
                                        border.width: 1
                                        border.color: root.colBorder
                                    }
                                }
                            }

                            // Mute button
                            Rectangle {
                                width: 28; height: 28; radius: 5
                                color: root.isDark ? (appMuteMouse.containsMouse ? "#24242A" : "#16161B") : (appMuteMouse.containsMouse ? "#E5E5EA" : "#F2F2F7")
                                border.width: 1
                                border.color: root.colBorder

                                Image {
                                    anchors.centerIn: parent
                                    width: 14; height: 14
                                    source: (appStreamRow.modelData?.audio?.muted ?? false) ? "assets/speaker-muted-mono.svg" : "assets/volume.svg"
                                }

                                MouseArea {
                                    id: appMuteMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: AudioService.toggleMute(appStreamRow.modelData)
                                }
                            }
                        }
                    }
                }

                // If no streams active
                Rectangle {
                    visible: AudioService.streams.length === 0
                    Layout.fillWidth: true
                    implicitHeight: 44
                    color: "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "No applications are currently playing audio."
                        color: root.colTextSecondary
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                    }
                }
            }

            // 4. AUDIO STACK & UTILITIES
            SettingsGroup {
                title: "AUDIO UTILITIES & PIPES"
                SettingsButton {
                    label: "EasyEffects equalizer"; description: "System-wide DSP, parametric equalizer, and audio enhancer"
                    buttonText: "Open"; enabled: SystemService.has("easyeffects")
                    onClicked: Quickshell.execDetached(["easyeffects"])
                }
                SettingsButton {
                    label: "PulseAudio volume control (pavucontrol)"; description: "Comprehensive graphical audio mixer and configuration"
                    buttonText: "Open"; enabled: SystemService.has("pavucontrol")
                    onClicked: Quickshell.execDetached(["pavucontrol"])
                }
                SettingsButton {
                    label: "Restart PipeWire Stack"; description: "Restart pipewire, pipewire-pulse, and wireplumber daemons"
                    buttonText: "Restart"; danger: true
                    onClicked: {
                        SystemService.enqueue(["service", "user", "restart", "pipewire"], "service", "pipewire", false);
                        SystemService.enqueue(["service", "user", "restart", "pipewire-pulse"], "service", "pipewire-pulse", false);
                        SystemService.enqueue(["service", "user", "restart", "wireplumber"], "service", "wireplumber", false);
                    }
                }
            }
        }
    }
}
