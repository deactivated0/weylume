import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PanelWindow {
    Component.onCompleted: SystemData.requestDrives()
    visible: ShellState.sidebarVisible
    implicitWidth: Theme.sidebarWidth
    color: "transparent"
    anchors { top: true; right: true; bottom: true }
    margins { top: 1; right: 1; bottom: Theme.taskbarHeight + 1 }
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "weylume-monitor"

    Rectangle {
        anchors.fill: parent
        color: Theme.background
        radius: 8
        border.width: 1
        border.color: Theme.border

        ScrollView {
            anchors.fill: parent
            anchors.margins: 13
            clip: true
            contentWidth: availableWidth

            ColumnLayout {
                width: parent.width
                spacing: 9

                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "▣"; color: Theme.text; font.pixelSize: 13 }
                    Text {
                        text: "SYSTEM"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.Bold
                    }
                    Item { Layout.fillWidth: true }
                    WinButton {
                        implicitWidth: 24; implicitHeight: 24; iconSize: 14
                        fallback: "×"
                        onClicked: ShellState.sidebarVisible = false
                    }
                }
                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.border }
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "Uptime"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 10 }
                    Item { Layout.fillWidth: true }
                    Text { text: SystemData.uptime; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Font.DemiBold }
                }

                SectionTitle { title: "▣  CPU" }
                InfoRow { label: "Model"; value: SystemData.cpuModel }
                InfoRow { label: "Frequency"; value: SystemData.cpuFrequency }
                InfoRow { label: "Temperature"; value: SystemData.cpuTemperature }
                MetricBar { Layout.fillWidth: true; label: "Usage"; value: SystemData.cpuUsage + "%"; fraction: SystemData.cpuUsage / 100 }

                SectionTitle { title: "▣  GPU" }
                InfoRow { label: "Model"; value: SystemData.gpuModel }
                InfoRow { label: "Temperature"; value: SystemData.gpuTemperature }
                MetricBar { Layout.fillWidth: true; label: "Usage"; value: SystemData.gpuUsage + "%"; fraction: SystemData.gpuUsage / 100 }

                SectionTitle { title: "▣  MEMORY" }
                InfoRow { label: "Used"; value: SystemData.memoryUsed + " / " + SystemData.memoryTotal }
                MetricBar { Layout.fillWidth: true; label: "Usage"; value: SystemData.memoryUsage + "%"; fraction: SystemData.memoryUsage / 100 }

                SectionTitle { title: "▣  DRIVES" }
                Text { visible: SystemData.drivesStale; text: "Disk information is stale; reopen to retry"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
                Repeater {
                    model: SystemData.drives
                    ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 4
                        MetricBar {
                            Layout.fillWidth: true
                            label: modelData.name
                            value: modelData.available === false ? "—" : modelData.usage + "%"
                            fraction: modelData.usage / 100
                        }
                        Text {
                            text: modelData.used
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                }

                SectionTitle { title: "▣  NETWORK" }
                Text {
                    text: "Active (" + SystemData.networkInterface + ")"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
                InfoRow { label: "↓  Receive"; value: SystemData.networkReceive }
                InfoRow { label: "↑  Send"; value: SystemData.networkSend }
                Item { implicitHeight: 4 }
            }
        }
    }

    component SectionTitle: ColumnLayout {
        required property string title
        Layout.fillWidth: true
        Layout.topMargin: 3
        spacing: 7
        Text {
            text: title
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 12
            font.weight: Font.Bold
        }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.border }
    }

    component InfoRow: RowLayout {
        required property string label
        required property string value
        Layout.fillWidth: true
        Text { text: label; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 9 }
        Item { Layout.fillWidth: true }
        Text {
            text: value
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 9
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            Layout.maximumWidth: 142
        }
    }
}
