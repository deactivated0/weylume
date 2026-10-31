import QtQuick
import QtQuick.Layouts
import qs

Rectangle {
    id: root
    property string label: ""
    property string description: ""
    property alias text: input.text
    property string placeholder: ""
    property bool secret: false
    property string iconSource: ""
    property color iconColor: isDark ? "#282830" : "#E5E5EA"
    property bool showDivider: false
    signal accepted(string value)

    readonly property bool isDark: SettingsService.darkMode !== false
    readonly property color colTextPrimary: isDark ? "#FFFFFF" : "#000000"
    readonly property color colTextSecondary: isDark ? "#8E8E93" : "#6E6E73"
    readonly property color colBorder: isDark ? "#1F1F22" : "#E5E5EA"
    readonly property color colAccent: isDark ? "#FFFFFF" : "#000000"
    readonly property color colHover: isDark ? "#141418" : "#F4F4F6"
    readonly property color colInputBg: isDark ? "#16161B" : "#FFFFFF"
    readonly property color colInputBorder: isDark ? "#282832" : "#D1D1D6"

    Layout.fillWidth: true
    implicitHeight: description ? 54 : 44
    color: "transparent"

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

        // Native-styled macOS Input Box
        Rectangle {
            Layout.preferredWidth: 200
            implicitHeight: 28
            radius: 6
            color: colInputBg
            border.width: input.activeFocus ? 2 : 1
            border.color: input.activeFocus ? colAccent : colInputBorder

            TextInput {
                id: input
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                anchors.topMargin: 4
                anchors.bottomMargin: 4
                color: colTextPrimary
                font.family: Theme.fontFamily
                font.pixelSize: 12
                selectByMouse: true
                echoMode: root.secret ? TextInput.Password : TextInput.Normal
                activeFocusOnTab: true
                Accessible.role: Accessible.EditableText
                Accessible.name: root.label
                Accessible.description: root.description
                onAccepted: root.accepted(text)
                onEditingFinished: root.accepted(text)
            }

            Text {
                anchors.fill: parent
                anchors.margins: 8
                visible: input.text.length === 0
                text: root.placeholder
                color: colTextSecondary
                font.family: Theme.fontFamily
                font.pixelSize: 12
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
}
