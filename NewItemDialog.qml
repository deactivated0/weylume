import QtQuick
import QtQuick.Layouts
import Quickshell

Scope {
    id: root

    property bool dialogOpen: false
    property string itemType: "text"
    property string itemTitle: "Create Text Document"
    property string itemIcon: "text-x-generic"
    property string defaultName: "document.txt"
    property string fileExtension: ".txt"

    function openForType(type) {
        itemType = (type || "text").toLowerCase();
        if (itemType === "folder") {
            itemTitle = "Create New Folder";
            itemIcon = "folder-new";
            defaultName = "New Folder";
            fileExtension = "";
        } else if (itemType === "python" || itemType === "py") {
            itemTitle = "Create Python Script";
            itemIcon = "text-x-python";
            defaultName = "main.py";
            fileExtension = ".py";
        } else if (itemType === "shell" || itemType === "sh") {
            itemTitle = "Create Shell Script";
            itemIcon = "text-x-script";
            defaultName = "script.sh";
            fileExtension = ".sh";
        } else if (itemType === "markdown" || itemType === "md") {
            itemTitle = "Create Markdown Document";
            itemIcon = "text-x-generic";
            defaultName = "notes.md";
            fileExtension = ".md";
        } else {
            itemTitle = "Create Text Document";
            itemIcon = "text-x-generic";
            defaultName = "document.txt";
            fileExtension = ".txt";
        }

        nameInput.text = defaultName;
        dialogOpen = true;
        nameTimer.restart();
    }

    function dismiss() {
        dialogOpen = false;
    }

    function createItem() {
        let name = nameInput.text.trim();
        if (!name) name = defaultName;
        
        if (fileExtension && !name.toLowerCase().endsWith(fileExtension)) {
            name += fileExtension;
        }

        dismiss();

        Quickshell.execDetached([Quickshell.shellPath("weylume-native"), "desktop", "create", itemType, name]);
    }

    Timer {
        id: nameTimer
        interval: 60
        onTriggered: {
            nameInput.forceActiveFocus();
            if (fileExtension && nameInput.text.endsWith(fileExtension)) {
                nameInput.select(0, nameInput.text.length - fileExtension.length);
            } else {
                nameInput.selectAll();
            }
        }
    }

    FloatingWindow {
        visible: root.dialogOpen
        implicitWidth: 380
        implicitHeight: 154
        color: "transparent"
        title: root.itemTitle

        Rectangle {
            anchors.fill: parent
            radius: 10
            color: "#fc000000"
            border.width: 1
            border.color: "#282828"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 12

                // Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Image {
                        Layout.preferredWidth: 22
                        Layout.preferredHeight: 22
                        sourceSize: Qt.size(44, 44)
                        source: Quickshell.iconPath(root.itemIcon, "text-x-generic")
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.itemTitle
                        color: "#ffffff"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    WinButton {
                        implicitWidth: 24
                        implicitHeight: 24
                        fallback: "×"
                        iconSize: 12
                        onClicked: root.dismiss()
                    }
                }

                // Input box
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 32
                    radius: 6
                    color: "#0c0c0c"
                    border.width: 1
                    border.color: nameInput.activeFocus ? "#ffffff" : "#282828"

                    TextInput {
                        id: nameInput
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        color: "#f5f5f5"
                        selectionColor: "#50ffffff"
                        selectedTextColor: "#ffffff"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        clip: true
                        selectByMouse: true

                        Keys.onReturnPressed: root.createItem()
                        Keys.onEnterPressed: root.createItem()
                        Keys.onEscapePressed: root.dismiss()
                    }
                }

                // Buttons
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        implicitWidth: 70
                        implicitHeight: 26
                        radius: 5
                        color: cancelMouse.containsMouse ? "#20ffffff" : "#10ffffff"
                        border.width: 1
                        border.color: "#20ffffff"

                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: "#dddddd"
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }

                        MouseArea {
                            id: cancelMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.dismiss()
                        }
                    }

                    Rectangle {
                        implicitWidth: 70
                        implicitHeight: 26
                        radius: 5
                        color: createMouse.containsMouse ? "#ffffff" : "#dddddd"

                        Text {
                            anchors.centerIn: parent
                            text: "Create"
                            color: "#000000"
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: createMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.createItem()
                        }
                    }
                }
            }
        }
    }
}
