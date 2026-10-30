import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
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

    Item {
        width: root.availableWidth
        implicitHeight: lockCol.implicitHeight + 40

        ColumnLayout {
            id: lockCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 24
            anchors.rightMargin: 24
            anchors.topMargin: 18
            spacing: 16

            // 1. LOCK SCREEN CONTROLS
            SettingsGroup {
                title: "LOCK SCREEN SESSION"

                SettingsToggle {
                    label: "Enable lock screen"
                    description: "Secure the desktop session with the macOS-inspired AMOLED lock screen"
                    checked: SettingsService.lockscreenEnabled
                    onToggled: value => SettingsService.lockscreenEnabled = value
                }

                SettingsButton {
                    label: "Lock screen now"
                    description: "Instantly lock the display to test your credentials and layout"
                    buttonText: "Lock Now"
                    onClicked: ShellState.lock()
                }

                SettingsToggle {
                    label: "Lock on system startup"
                    description: "Require PIN or password before desktop appears when starting the session"
                    checked: SettingsService.lockOnStart
                    onToggled: value => SettingsService.lockOnStart = value
                }

                SettingsButton {
                    label: "Global keyboard shortcut"
                    description: "Press Win + L (W-l) anywhere to trigger instant session lock"
                    buttonText: "Win + L"
                    enabled: false
                }
            }

            // 2. SECURITY & AUTHENTICATION
            SettingsGroup {
                title: "AUTHENTICATION & DIRECT UNLOCK"

                SettingsChoice {
                    label: "Authentication mode"
                    description: "Choose between quick numeric PIN or standard password"
                    value: SettingsService.lockscreenMode
                    choices: [
                        { label: "PIN Code", value: "pin" },
                        { label: "Password", value: "password" }
                    ]
                    onSelected: value => SettingsService.lockscreenMode = value
                }

                SettingsField {
                    label: "PIN / Password code"
                    description: "Minimum 4 numbers or characters. Default PIN is 1234."
                    text: SettingsService.lockscreenPin
                    placeholder: "1234"
                    onAccepted: value => {
                        const trimmed = value.trim();
                        if (trimmed.length >= 4) {
                            SettingsService.lockscreenPin = trimmed;
                        }
                    }
                }

                SettingsToggle {
                    label: "Direct auto-unlock"
                    description: "4 or more numbers: logs in directly without pressing Enter when correct"
                    checked: SettingsService.autoUnlockPin
                    onToggled: value => SettingsService.autoUnlockPin = value
                }

                SettingsField {
                    label: "User display name"
                    description: "Custom label shown above user input on the lock screen"
                    text: SettingsService.lockscreenUserName
                    placeholder: Quickshell.env("USER") || "pc"
                    onAccepted: value => SettingsService.lockscreenUserName = value.trim()
                }
            }

            // 3. DESIGN SPECIFICATION
            SettingsGroup {
                title: "AMOLED DISPLAY DESIGN"

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 90
                    radius: 8
                    color: root.isDark ? "#0A0A0C" : "#F4F4F6"
                    border.width: 1
                    border.color: root.colBorder

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 14

                        Rectangle {
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 36
                            radius: 18
                            color: "#000000"
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.2)
                            clip: true

                            Item {
                                anchors.centerIn: parent
                                width: 20; height: 20
                                Rectangle { width: 8; height: 8; radius: 4; color: "#FFFFFF"; anchors.horizontalCenter: parent.horizontalCenter; y: 2 }
                                Rectangle { width: 16; height: 10; radius: 5; color: "#FFFFFF"; anchors.horizontalCenter: parent.horizontalCenter; y: 11 }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3

                            Text {
                                text: "Pure AMOLED Black (#000000)"
                                color: root.colTextPrimary
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                            }

                            Text {
                                text: "Zero wallpaper bleeding, large tabular clock, macOS eye toggle, auto-unlock on 4+ digits, power actions, battery & Wi-Fi indicators."
                                color: root.colTextSecondary
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                            }
                        }
                    }
                }
            }
        }
    }
}
