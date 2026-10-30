import QtQuick
import QtQuick.Layouts
import Quickshell
import qs

FloatingWindow {
    id: root
    property int countdown: 0
    visible: ShellState.sessionDialogOpen
    implicitWidth: 430
    implicitHeight: Math.max(230, content.implicitHeight + 36)
    color: "transparent"
    title: "Weylume Session Confirmation"

    function actionLabel() {
        const action = ShellState.pendingSessionAction;
        if (action === "shutdown") return "Shut down";
        if (action === "reboot") return "Restart";
        if (action === "hibernate") return "Hibernate";
        if (action === "logout") return "Log out";
        return "Suspend";
    }

    onVisibleChanged: {
        if (visible) {
            countdown = ["shutdown", "reboot", "logout"].includes(ShellState.pendingSessionAction) ? 3 : 0;
            if (countdown > 0) countdownTimer.start();
        } else countdownTimer.stop();
    }

    Timer {
        id: countdownTimer
        interval: 1000
        repeat: true
        onTriggered: {
            root.countdown--;
            if (root.countdown <= 0) stop();
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 18
        color: Theme.background
        border.width: 1
        border.color: Theme.border

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: 18
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                Rectangle {
                    width: 34; height: 34; radius: 9; color: "#241212"; border.width: 1; border.color: "#542424"
                    Text { anchors.centerIn: parent; text: "!"; color: "#ff7979"; font.pixelSize: 16; font.weight: Font.Bold }
                }
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 1
                    Text { text: root.actionLabel() + " this computer?"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 14; font.weight: Font.DemiBold }
                    Text { text: "Unsaved application data can be lost."; color: "#818181"; font.family: Theme.fontFamily; font.pixelSize: 10 }
                }
            }

            Rectangle {
                visible: SystemService.inhibitors.length > 0
                Layout.fillWidth: true
                implicitHeight: Math.min(88, inhibitorCol.implicitHeight + 16)
                radius: 9; color: "#110f08"; border.width: 1; border.color: "#3d351d"
                clip: true
                ColumnLayout {
                    id: inhibitorCol
                    width: parent.width - 16; anchors.centerIn: parent; spacing: 3
                    Text { text: "ACTIVE INHIBITORS"; color: "#c0a85d"; font.family: Theme.fontFamily; font.pixelSize: 8; font.weight: Font.DemiBold }
                    Repeater {
                        model: SystemService.inhibitors.slice(0, 3)
                        Text { required property string modelData; Layout.fillWidth: true; text: modelData; color: "#91845d"; font.family: Theme.fontFamily; font.pixelSize: 8; elide: Text.ElideRight }
                    }
                }
            }

            Text {
                visible: SystemService.inhibitors.length === 0
                text: SystemService.inhibitorsUnknown ? "Inhibitor status is unavailable." : "No active system inhibitors were reported."
                color: "#626262"
                font.family: Theme.fontFamily
                font.pixelSize: 9
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Item { Layout.fillWidth: true }
                Rectangle {
                    implicitWidth: cancelText.implicitWidth + 24; height: 34; radius: 8
                    color: cancelMouse.containsMouse ? "#242424" : "#151515"; border.width: 1; border.color: "#303030"
                    Text { id: cancelText; anchors.centerIn: parent; text: "Cancel"; color: "#eeeeee"; font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Font.DemiBold }
                    MouseArea { id: cancelMouse; anchors.fill: parent; hoverEnabled: true; onClicked: ShellState.cancelSessionAction() }
                }
                Rectangle {
                    implicitWidth: confirmText.implicitWidth + 24; height: 34; radius: 8
                    color: root.countdown > 0 ? "#281515" : (confirmMouse.containsMouse ? "#e54b4b" : "#b93636")
                    border.width: 1; border.color: root.countdown > 0 ? "#482525" : "#ef6464"
                    opacity: root.countdown > 0 ? 0.62 : 1.0
                    Text { id: confirmText; anchors.centerIn: parent; text: root.actionLabel() + (root.countdown > 0 ? " (" + root.countdown + ")" : ""); color: "#ffffff"; font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Font.DemiBold }
                    MouseArea { id: confirmMouse; anchors.fill: parent; enabled: root.countdown <= 0; hoverEnabled: true; onClicked: ShellState.confirmSessionAction() }
                }
            }
        }
    }
}
