import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Polkit

Scope {

    PolkitAgent { id: agent }

    LazyLoader {
        id: dialogLoader
        active: agent.isActive

        FloatingWindow {
            id: polkitWindow
            visible: true
            implicitWidth: 460
            implicitHeight: 275
            color: Theme.background
            title: "Authentication required"

            function resetFocus() {
                response.text = "";
                Qt.callLater(() => response.forceActiveFocus());
            }
            Component.onCompleted: resetFocus()

            Rectangle {
                anchors.fill: parent
                color: Theme.background
                border.width: 1
                border.color: Theme.border

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true
                        Image {
                            Layout.preferredWidth: 42
                            Layout.preferredHeight: 42
                            sourceSize: Qt.size(84, 84)
                            source: Quickshell.iconPath(agent.flow?.iconName ?? "dialog-password")
                            fillMode: Image.PreserveAspectFit
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Text { text: "Authentication required"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 17; font.weight: Font.DemiBold }
                            Text { Layout.fillWidth: true; text: agent.flow?.message ?? "An application needs permission."; wrapMode: Text.WordWrap; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 11 }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: agent.flow?.supplementaryMessage ?? ""
                        visible: text !== ""
                        color: agent.flow?.supplementaryIsError ? Theme.danger : Theme.muted
                        wrapMode: Text.WordWrap
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 42
                        radius: 7
                        color: "#ff0c0c0c"
                        border.width: response.activeFocus ? 2 : 1
                        border.color: response.activeFocus ? Theme.accent : Theme.border
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 11
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !response.text
                            text: agent.flow?.inputPrompt ?? "Password"
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                        TextInput {
                            id: response
                            anchors.fill: parent
                            anchors.margins: 11
                            verticalAlignment: TextInput.AlignVCenter
                            echoMode: agent.flow?.responseVisible ? TextInput.Normal : TextInput.Password
                            color: Theme.text
                            selectionColor: Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            enabled: agent.flow?.isResponseRequired ?? false
                            Keys.onReturnPressed: {
                                if (agent.flow?.isResponseRequired) {
                                    agent.flow.submit(text);
                                    text = "";
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Item { Layout.fillWidth: true }
                        AuthButton {
                            label: "Cancel"
                            onClicked: if (agent.flow) agent.flow.cancelAuthenticationRequest()
                        }
                        AuthButton {
                            label: "Authenticate"
                            accent: true
                            enabled: agent.flow?.isResponseRequired ?? false
                            onClicked: {
                                agent.flow.submit(response.text);
                                response.text = "";
                            }
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: agent
        function onIsActiveChanged() {
            if (agent.isActive && dialogLoader.item) {
                dialogLoader.item.resetFocus();
            }
        }
    }

    component AuthButton: Rectangle {
        id: button
        required property string label
        property bool accent: false
        signal clicked()
        implicitWidth: 105
        implicitHeight: 36
        radius: 7
        opacity: enabled ? 1 : 0.45
        color: accent ? Theme.accent : (buttonMouse.containsMouse ? Theme.cardHover : Theme.card)
        Text { anchors.centerIn: parent; text: button.label; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 11; font.weight: Font.DemiBold }
        MouseArea { id: buttonMouse; anchors.fill: parent; hoverEnabled: true; enabled: button.enabled; onClicked: button.clicked() }
    }
}
