import QtQuick
import QtQuick.Layouts
import qs

ColumnLayout {
    id: root
    default property alias content: cardLayout.data
    property string title: ""
    property string caption: ""

    readonly property bool isDark: SettingsService.darkMode !== false
    readonly property color colSurface: isDark ? "#0C0C0E" : "#FBFBFD"
    readonly property color colBorder: isDark ? "#1F1F22" : "#E5E5EA"
    readonly property color colTextSecondary: isDark ? "#8E8E93" : "#6E6E73"

    Layout.fillWidth: true
    spacing: 6

    Text {
        visible: root.title.length > 0
        text: root.title
        color: colTextSecondary
        font.family: Theme.fontFamily
        font.pixelSize: 11
        font.weight: Font.DemiBold
        Layout.leftMargin: 4
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: cardLayout.implicitHeight
        radius: 10
        color: colSurface
        border.width: 1
        border.color: colBorder
        clip: true

        ColumnLayout {
            id: cardLayout
            anchors.fill: parent
            spacing: 0
            onChildrenChanged: Qt.callLater(root.updateDividers)
        }
    }

    function updateDividers() {
        let items = [];
        for (let i = 0; i < cardLayout.children.length; i++) {
            let c = cardLayout.children[i];
            if (c.visible) items.push(c);
        }
        for (let i = 0; i < items.length; i++) {
            let c = items[i];
            if ("showDivider" in c) {
                c.showDivider = (i < items.length - 1);
            }
        }
    }

    Text {
        visible: root.caption.length > 0
        text: root.caption
        color: colTextSecondary
        font.family: Theme.fontFamily
        font.pixelSize: 11
        wrapMode: Text.Wrap
        Layout.fillWidth: true
        Layout.leftMargin: 4
    }
}
