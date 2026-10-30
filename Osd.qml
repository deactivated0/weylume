import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs

PanelWindow {
    id: root
    required property var screen
    visible: OsdService.visible && screen.name === OsdService.screenName
    implicitWidth: 330
    implicitHeight: OsdService.value >= 0 ? 66 : 56
    color: "transparent"
    anchors { top: true }
    margins { top: 22 }
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "weylume-osd"
    Component.onCompleted: OsdService.registerScreen(screen.name)

    readonly property bool isKeyboard: (OsdService.title || "").toLowerCase().includes("keyboard") || (OsdService.icon || "").includes("keyboard")

    function getLayoutName(code) {
        const c = (code || "").trim().toLowerCase();
        const map = {
            "us": "English (US)",
            "uk": "English (UK)",
            "gb": "English (UK)",
            "de": "German",
            "fr": "French",
            "es": "Spanish",
            "it": "Italian",
            "ru": "Russian",
            "tr": "Turkish",
            "ar": "Arabic",
            "pt": "Portuguese",
            "br": "Portuguese (BR)",
            "pl": "Polish",
            "ua": "Ukrainian",
            "jp": "Japanese",
            "kr": "Korean",
            "cn": "Chinese",
            "se": "Swedish",
            "no": "Norwegian",
            "fi": "Finnish",
            "dk": "Danish",
            "cz": "Czech",
            "gr": "Greek",
            "he": "Hebrew",
            "il": "Hebrew",
            "fa": "Persian",
            "nl": "Dutch",
            "hu": "Hungarian",
            "ro": "Romanian",
            "bg": "Bulgarian"
        };
        return map[c] || (code ? code.toUpperCase() : "Default");
    }

    Rectangle {
        id: osdCard
        anchors.fill: parent
        radius: 26
        color: "#080808"
        border.width: 1
        border.color: OsdService.error ? "#5a2222" : "#202024"
        clip: true

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 14
            anchors.topMargin: 8
            anchors.bottomMargin: 8
            spacing: 12

            // Left Squircle Icon Badge
            Rectangle {
                Layout.preferredWidth: 38
                Layout.preferredHeight: 38
                Layout.alignment: Qt.AlignVCenter
                radius: 12
                color: OsdService.error ? "#251212" : "#121215"
                border.width: 1
                border.color: OsdService.error ? "#442020" : "#22232a"

                Image {
                    anchors.centerIn: parent
                    width: 22
                    height: 22
                    sourceSize: Qt.size(44, 44)
                    source: OsdService.icon.startsWith("assets/")
                        ? Quickshell.shellPath(OsdService.icon)
                        : Quickshell.iconPath(OsdService.icon, "dialog-information")
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                }
            }

            // Center Content
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                Text {
                    text: OsdService.title.toUpperCase()
                    color: OsdService.error ? "#ff7777" : "#8e8e93"
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.6
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Text {
                    text: root.isKeyboard ? root.getLayoutName(OsdService.detail) : (OsdService.detail.length > 0 ? OsdService.detail : OsdService.title)
                    color: "#ffffff"
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                // Progress Bar (Volume / Brightness)
                Rectangle {
                    visible: OsdService.value >= 0
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    implicitHeight: 4
                    radius: 2
                    color: "#202024"

                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, OsdService.value))
                        height: parent.height
                        radius: parent.radius
                        color: OsdService.error ? "#ff6262" : "#ffffff"
                    }
                }
            }

            // Right Pill Badge (for Keyboard Layout or Percentage)
            Rectangle {
                visible: root.isKeyboard && OsdService.detail.length > 0
                Layout.preferredWidth: 38
                Layout.preferredHeight: 24
                Layout.alignment: Qt.AlignVCenter
                radius: 12
                color: "#18181c"
                border.width: 1
                border.color: "#28282e"

                Text {
                    anchors.centerIn: parent
                    text: OsdService.detail.toUpperCase()
                    color: "#f5f5f5"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.Bold
                }
            }

            Text {
                visible: !root.isKeyboard && OsdService.value >= 0
                Layout.alignment: Qt.AlignVCenter
                text: Math.round(OsdService.value * 100) + "%"
                color: "#8e8e93"
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }
        }
    }
}
