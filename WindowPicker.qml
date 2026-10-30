import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs
FloatingWindow {
    id: root
    visible: IntegrationService.windowPickerOpen
    title: "Select a window to capture"
    implicitWidth: 460; implicitHeight: 400; color: "transparent"
    onVisibleChanged: if (!visible) IntegrationService.windowPickerOpen = false
    Shortcut { sequence: "Escape"; onActivated: IntegrationService.windowPickerOpen = false }
    Rectangle {
        anchors.fill: parent; radius: 18; color: "#050505"; border.width: 1; border.color: "#343434"
        ColumnLayout {
            anchors.fill: parent; anchors.margins: 18; spacing: 10
            Text { text: "Select a window to capture"; color: "white"; font.family: Theme.fontFamily; font.pixelSize: 14; font.weight: Font.DemiBold }
            Text { visible: IntegrationService.windows.length === 0; text: "No captureable windows are available."; color: "#aaaaaa"; font.pixelSize: 11 }
            ListView {
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 6; model: IntegrationService.windows
                delegate: SettingsButton {
                    required property var modelData
                    width: ListView.view.width
                    label: modelData.title || modelData.app || "Window"
                    description: modelData.app + " • " + modelData.id
                    buttonText: "Capture"
                    onClicked: IntegrationService.captureWindow(modelData.id)
                }
            }
            SettingsButton { label: "Cancel"; buttonText: "Close"; onClicked: IntegrationService.windowPickerOpen = false }
        }
    }
}
