import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs

PanelWindow {
    id: root
    visible: false

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "weylume-drag-overlay"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusiveZone: 0
    color: "transparent"
    mask: Region {}

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    Item {
        id: dragCard
        visible: false

        width: Math.round(ShellState.dragItemWidth || 60)
        height: Math.round(ShellState.dragItemHeight || 66)
        readonly property int iconSize: Math.round(ShellState.dragIconSize || 32)

        x: Math.round(ShellState.dragGlobalX - ShellState.dragGrabOffsetX)
        y: Math.round(ShellState.dragGlobalY - ShellState.dragGrabOffsetY)

        Rectangle {
            anchors.fill: parent
            radius: 4
            color: "#30ffffff"
            border.width: 1
            border.color: "#65ffffff"

            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: 3
                anchors.bottomMargin: 2
                anchors.leftMargin: 2
                anchors.rightMargin: 2
                spacing: 2

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: dragCard.iconSize
                    Layout.alignment: Qt.AlignHCenter | Qt.AlignTop

                    Image {
                        anchors.centerIn: parent
                        width: dragCard.iconSize
                        height: dragCard.iconSize
                        sourceSize: Qt.size(dragCard.iconSize * 2, dragCard.iconSize * 2)
                        source: {
                            const d = ShellState.dragFileData;
                            if (!d) return "";
                            if (d.thumbnail) return "file://" + d.thumbnail;
                            if (d.isImage && d.path) return "file://" + d.path;
                            if (d.icon) {
                                if (d.icon === "weylume-settings" || d.icon === "preferences-system") return Theme.settingsIcon;
                                return Quickshell.iconPath(d.icon, "application-x-generic");
                            }
                            if (d.path) return "file://" + d.path;
                            return "";
                        }
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: 2
                    Layout.rightMargin: 2
                    Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
                    text: ShellState.dragFileData?.name || ""
                    color: "#ffffff"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.Normal
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                    style: Text.Sunken
                    styleColor: "#80000000"
                }
            }
        }
    }
}
