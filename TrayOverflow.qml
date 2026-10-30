import QtQuick
import QtQuick.Layouts
import Quickshell

PopupWindow {
    id: root
    required property var anchorItem
    visible: ShellState.trayOpen || overflowMenu.menuVisible

    readonly property var hiddenList: TrayConfig.hiddenItems
    readonly property int count: hiddenList.length
    readonly property int itemSize: 36
    readonly property int itemSpacing: 4
    readonly property int pad: 6
    readonly property int maxCols: 4
    readonly property int cols: Math.max(1, Math.min(maxCols, count))
    readonly property int rows: Math.max(1, Math.ceil(Math.max(1, count) / cols))

    implicitWidth: count === 0 ? 124 : (cols * itemSize + (cols - 1) * itemSpacing + pad * 2 + 8)
    implicitHeight: count === 0 ? 46 : (rows * itemSize + (rows - 1) * itemSpacing + pad * 2 + 8)
    color: "transparent"
    grabFocus: true
    surfaceFormat.opaque: false
    anchor.item: anchorItem
    anchor.edges: Edges.Top
    anchor.gravity: Edges.Top

    Shortcut {
        sequence: "Escape"
        enabled: root.visible
        onActivated: ShellState.trayOpen = false
    }

    onVisibleChanged: {
        if (!visible) {
            if (ShellState.trayOpen) ShellState.trayOpen = false;
            if (overflowMenu.menuVisible) overflowMenu.dismiss();
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 4
        radius: 10
        color: Theme.background
        border.width: 1
        border.color: Theme.border
        clip: true

        Text {
            anchors.centerIn: parent
            visible: root.count === 0
            text: "No hidden icons"
            color: "#777777"
            font.family: Theme.fontFamily
            font.pixelSize: 10
        }

        GridLayout {
            id: overflowGrid
            anchors.centerIn: parent
            visible: root.count > 0
            columns: root.cols
            rowSpacing: root.itemSpacing
            columnSpacing: root.itemSpacing

            Repeater {
                model: ScriptModel { values: root.hiddenList }

                Item {
                    id: hiddenItemBox
                    required property var modelData
                    required property int index
                    implicitWidth: root.itemSize
                    implicitHeight: root.itemSize
                    Layout.preferredWidth: root.itemSize
                    Layout.preferredHeight: root.itemSize

                        property real dragOffsetX: 0
                        property real dragOffsetY: 0
                        property real pressStartX: 0
                        property real pressStartY: 0
                        property bool isDragging: false

                        onIndexChanged: {
                            pressStartX = 0;
                            pressStartY = 0;
                            dragOffsetX = 0;
                            dragOffsetY = 0;
                            isDragging = false;
                        }

                        onModelDataChanged: {
                            pressStartX = 0;
                            pressStartY = 0;
                            dragOffsetX = 0;
                            dragOffsetY = 0;
                            isDragging = false;
                        }

                        z: isDragging ? 1000 : 1

                        Rectangle {
                            id: visualBox
                            anchors.fill: parent
                            radius: 6
                            color: overflowMouse.pressed ? "#222222" : (overflowMouse.containsMouse ? "#181818" : "transparent")
                            border.width: 1
                            border.color: overflowMouse.containsMouse ? "#2c2c2c" : "transparent"
                            opacity: hiddenItemBox.isDragging ? 0.75 : 1.0
                            scale: hiddenItemBox.isDragging ? 1.15 : 1.0

                            Behavior on color { ColorAnimation { duration: SettingsService.reducedMotion ? 0 : 100 } }
                            Behavior on scale { NumberAnimation { duration: SettingsService.reducedMotion ? 0 : 90; easing.type: Easing.OutQuad } }
                            Behavior on opacity { NumberAnimation { duration: SettingsService.reducedMotion ? 0 : 90 } }

                            transform: Translate {
                                x: hiddenItemBox.dragOffsetX
                                y: hiddenItemBox.dragOffsetY
                            }

                            Image {
                                id: hiddenIconImg
                                anchors.centerIn: parent
                                width: 20
                                height: 20
                                sourceSize: Qt.size(40, 40)
                                source: {
                                    const ic = hiddenItemBox.modelData?.icon;
                                    if (!ic) return "";
                                    const lower = ic.toLowerCase();
                                    if (lower === "steam" || lower.includes("steam")) return Quickshell.shellPath("assets/steam.svg");
                                    return (ic.startsWith("/") || ic.startsWith("image://") || ic.startsWith("file://")) ? ic : Quickshell.iconPath(ic, "application-x-executable");
                                }
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                mipmap: true
                                visible: status === Image.Ready
                            }

                            Text {
                                anchors.centerIn: parent
                                text: hiddenItemBox.modelData?.fallback || "•"
                                visible: !hiddenIconImg.visible
                                color: Theme.text
                                font.pixelSize: 12
                            }
                        }

                        MouseArea {
                            id: overflowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

                            onPressed: event => {
                                if (event.button === Qt.RightButton) {
                                    ShellState.taskMenusCloseRequested();
                                }
                                if (event.button === Qt.LeftButton) {
                                    const local = overflowMouse.mapToItem(overflowGrid, event.x, event.y);
                                    hiddenItemBox.pressStartX = local.x;
                                    hiddenItemBox.pressStartY = local.y;
                                    hiddenItemBox.isDragging = false;
                                    hiddenItemBox.dragOffsetX = 0;
                                    hiddenItemBox.dragOffsetY = 0;
                                }
                            }

                            onPositionChanged: event => {
                                if (pressed && (pressedButtons & Qt.LeftButton) && hiddenItemBox.pressStartX !== 0) {
                                    const local = overflowMouse.mapToItem(overflowGrid, event.x, event.y);
                                    const dx = local.x - hiddenItemBox.pressStartX;
                                    const dy = local.y - hiddenItemBox.pressStartY;
                                    if (!hiddenItemBox.isDragging && (Math.abs(dx) >= 12 || Math.abs(dy) >= 12)) {
                                        hiddenItemBox.isDragging = true;
                                    }
                                    if (hiddenItemBox.isDragging) {
                                        hiddenItemBox.dragOffsetX = dx;
                                        hiddenItemBox.dragOffsetY = dy;
                                    }
                                }
                            }

                            onCanceled: {
                                hiddenItemBox.pressStartX = 0;
                                hiddenItemBox.pressStartY = 0;
                                hiddenItemBox.dragOffsetX = 0;
                                hiddenItemBox.dragOffsetY = 0;
                                hiddenItemBox.isDragging = false;
                            }

                            onReleased: event => {
                                if (event.button === Qt.RightButton) {
                                    overflowMenu.openFor(hiddenItemBox, hiddenItemBox.modelData);
                                    return;
                                } else if (event.button === Qt.MiddleButton) {
                                    TrayConfig.toggle(hiddenItemBox.modelData);
                                    return;
                                }
                                if (hiddenItemBox.isDragging) {
                                    const ox = hiddenItemBox.dragOffsetX;
                                    const oy = hiddenItemBox.dragOffsetY;
                                    hiddenItemBox.pressStartX = 0;
                                    hiddenItemBox.pressStartY = 0;
                                    hiddenItemBox.dragOffsetX = 0;
                                    hiddenItemBox.dragOffsetY = 0;
                                    hiddenItemBox.isDragging = false;

                                    if (oy > 15 || ox > 20) {
                                        TrayConfig.pin(hiddenItemBox.modelData);
                                    }
                                } else {
                                    hiddenItemBox.pressStartX = 0;
                                    hiddenItemBox.pressStartY = 0;
                                    if (hiddenItemBox.modelData?.activate) hiddenItemBox.modelData.activate();
                                }
                            }
                        }
                    }
                }
            }
        }

    TrayItemMenu { id: overflowMenu }
}
