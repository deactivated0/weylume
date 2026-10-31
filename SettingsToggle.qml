import QtQuick
import QtQuick.Layouts
import qs

Rectangle {
    id: root
    property string label: ""
    property string description: ""
    property bool checked: false
    property string iconSource: ""
    property color iconColor: isDark ? "#282830" : "#E5E5EA"
    property bool showDivider: false
    signal toggled(bool checked)

    readonly property bool isDark: SettingsService.darkMode !== false
    readonly property color colTextPrimary: isDark ? "#FFFFFF" : "#000000"
    readonly property color colTextSecondary: isDark ? "#8E8E93" : "#6E6E73"
    readonly property color colBorder: isDark ? "#1F1F22" : "#E5E5EA"
    readonly property color colAccent: isDark ? "#FFFFFF" : "#000000"
    readonly property color colSwitchOn: isDark ? "#FFFFFF" : "#000000"
    readonly property color colSwitchOff: isDark ? "#28282E" : "#E5E5EA"
    readonly property color colHover: isDark ? "#141418" : "#F4F4F6"

    Layout.fillWidth: true
    implicitHeight: description ? 52 : 44
    color: mouse.containsMouse ? colHover : "transparent"
    opacity: enabled ? 1.0 : 0.4
    activeFocusOnTab: enabled

    Accessible.role: Accessible.CheckBox
    Accessible.name: label
    Accessible.onPressAction: if (enabled) toggled(!checked)
    Accessible.description: description
    Accessible.checked: checked
    Keys.onSpacePressed: if (enabled) toggled(!checked)
    Keys.onReturnPressed: if (enabled) toggled(!checked)

    // Focus ring
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.width: root.activeFocus ? 2 : 0
        border.color: colAccent
        radius: 4
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        spacing: 12

        // Optional leading SF icon badge
        Rectangle {
            visible: root.iconSource.length > 0
            width: 24; height: 24; radius: 5
            color: root.iconColor
            Image {
                anchors.centerIn: parent
                width: 14; height: 14
                sourceSize: Qt.size(28, 28)
                source: root.iconSource
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                text: root.label
                color: colTextPrimary
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: Font.Normal
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            Text {
                visible: root.description.length > 0
                text: root.description
                color: colTextSecondary
                font.family: Theme.fontFamily
                font.pixelSize: 11
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }

        // Native macOS Sequoia Toggle Switch
        Rectangle {
            id: switchPill
            width: 36; height: 20; radius: 10
            color: root.checked ? colSwitchOn : colSwitchOff

            Behavior on color { ColorAnimation { duration: SettingsService.reducedMotion ? 0 : 120 } }

            Rectangle {
                width: 16; height: 16; radius: 8
                anchors.verticalCenter: parent.verticalCenter
                x: root.checked ? parent.width - width - 2 : 2
                color: root.checked ? (isDark ? "#000000" : "#FFFFFF") : (isDark ? "#8E8E93" : "#FFFFFF")

                Behavior on color { ColorAnimation { duration: SettingsService.reducedMotion ? 0 : 120 } }
                Behavior on x { NumberAnimation { duration: SettingsService.reducedMotion ? 0 : 120; easing.type: Easing.OutQuad } }
            }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 14
        height: 1
        color: root.colBorder
        visible: root.showDivider
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled(!root.checked)
    }
}
