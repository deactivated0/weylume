import QtQuick
import QtQuick.Layouts
import qs

Rectangle {
    id: root
    property string label: ""
    property string description: ""
    property string buttonText: "Open"
    property bool danger: false
    property bool active: false
    property string iconSource: ""
    property color iconColor: isDark ? "#282830" : "#E5E5EA"
    property bool showDivider: false
    signal clicked()

    readonly property bool isDark: SettingsService.darkMode !== false
    readonly property color colTextPrimary: isDark ? "#FFFFFF" : "#000000"
    readonly property color colTextSecondary: isDark ? "#8E8E93" : "#6E6E73"
    readonly property color colBorder: isDark ? "#1F1F22" : "#E5E5EA"
    readonly property color colAccent: isDark ? "#FFFFFF" : "#000000"
    readonly property color colHover: isDark ? "#141418" : "#F4F4F6"
    readonly property color colBtnBg: isDark ? (root.danger ? "#3A1515" : (root.active ? "#FFFFFF" : "#1E1E24")) : (root.danger ? "#FFECEC" : (root.active ? "#000000" : "#FFFFFF"))
    readonly property color colBtnBorder: isDark ? (root.danger ? "#5C2020" : (root.active ? "#FFFFFF" : "#2E2E36")) : (root.danger ? "#FFD0D0" : (root.active ? "#000000" : "#D1D1D6"))
    readonly property color colBtnText: root.active ? (isDark ? "#000000" : "#FFFFFF") : (root.danger ? (isDark ? "#FF8080" : "#D70015") : colTextPrimary)

    Layout.fillWidth: true
    implicitHeight: description ? 52 : 44
    color: mouse.containsMouse ? colHover : "transparent"
    opacity: enabled ? 1.0 : 0.4
    activeFocusOnTab: enabled

    Accessible.role: Accessible.Button
    Accessible.name: label
    Accessible.onPressAction: if (enabled) clicked()
    Accessible.description: description
    Keys.onSpacePressed: if (enabled) clicked()
    Keys.onReturnPressed: if (enabled) clicked()

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

        Rectangle {
            visible: root.iconSource.length > 0
            width: 24; height: 24; radius: 5
            color: root.iconColor
            Image {
                anchors.centerIn: parent
                width: 14; height: 14
                source: root.iconSource
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                text: root.label
                color: root.danger ? (isDark ? "#FF8080" : "#D70015") : colTextPrimary
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

        // Native-styled macOS Push Button
        Rectangle {
            id: btnRect
            implicitWidth: Math.max(64, btnText.implicitWidth + 20)
            implicitHeight: 28
            radius: 6
            color: btnMouse.containsMouse ? (isDark ? "#2A2A32" : "#E8E8ED") : colBtnBg
            border.width: 1
            border.color: colBtnBorder

            Text {
                id: btnText
                anchors.centerIn: parent
                text: root.buttonText
                color: colBtnText
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.weight: Font.Medium
            }

            MouseArea {
                id: btnMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.clicked()
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
        onClicked: root.clicked()
    }
}
