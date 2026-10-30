import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs

FloatingWindow {
    id: root
    visible: BluetoothService.pairing
    implicitWidth: 440
    implicitHeight: content.implicitHeight + 36
    color: "transparent"
    title: "Bluetooth pairing"
    onVisibleChanged: if (!visible) BluetoothService.cancel()
    Shortcut { sequence: "Escape"; onActivated: BluetoothService.cancel() }
    Rectangle {
        anchors.fill: parent; radius: 18; color: "#050505"; border.width: 1; border.color: "#343434"
        ColumnLayout {
            id: content
            anchors.fill: parent; anchors.margins: 18; spacing: 12
            Text { text: "Pair " + (BluetoothService.device?.name || "Bluetooth device"); color: "white"; font.family: Theme.fontFamily; font.pixelSize: 14; font.weight: Font.DemiBold }
            Text {
                Layout.fillWidth: true; wrapMode: Text.Wrap; color: "#aaaaaa"; font.family: Theme.fontFamily; font.pixelSize: 11
                text: {
                    const p = BluetoothService.prompt;
                    if (!p) return "Waiting for the device…";
                    if (p.kind === "RequestPinCode") return "Enter the device PIN.";
                    if (p.kind === "RequestPasskey") return "Enter the six-digit passkey.";
                    if (p.kind === "RequestConfirmation") return "Confirm this code matches the device: " + String(p.value).padStart(6, "0");
                    if (p.kind === "DisplayPasskey" || p.kind === "DisplayPinCode") return "Type " + String(p.value).padStart(6, "0") + " on the device" + (p.entered ? " • " + p.entered + " digits entered" : "");
                    return "Allow this device to pair" + (p.kind === "AuthorizeService" ? " and use service " + p.value : "") + "?";
                }
            }
            SettingsField {
                id: pin
                visible: ["RequestPinCode", "RequestPasskey"].includes(BluetoothService.prompt?.kind)
                label: "PIN / passkey"
                onVisibleChanged: text = ""
                onAccepted: value => BluetoothService.answer(true, value)
            }
            SettingsToggle { label: "Trust this device"; description: "Allow future reconnections"; checked: BluetoothService.trustAfterPairing; onToggled: value => BluetoothService.trustAfterPairing = value }
            SettingsButton { label: "Confirm"; buttonText: "Allow"; visible: BluetoothService.prompt !== null && !BluetoothService.prompt.displayOnly; onClicked: BluetoothService.answer(true, pin.text) }
            SettingsButton { label: "Cancel pairing"; buttonText: "Cancel"; onClicked: BluetoothService.cancel() }
        }
    }
}
