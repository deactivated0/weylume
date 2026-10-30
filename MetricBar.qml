import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    property string label: ""
    property string value: ""
    property real fraction: 0
    spacing: 5

    RowLayout {
        Layout.fillWidth: true
        Text {
            text: root.label
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }
        Item { Layout.fillWidth: true }
        Text {
            text: root.value
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 5
        radius: 3
        color: Theme.border
        Rectangle {
            width: Math.max(0, Math.min(1, root.fraction)) * parent.width
            height: parent.height
            radius: parent.radius
            color: "#ffffff"
        }
    }
}

