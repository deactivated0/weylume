import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs
FloatingWindow {
    id: root
    visible: IntegrationService.enterpriseSsid.length > 0
    title: "Enterprise Wi-Fi"
    implicitWidth: 560; implicitHeight: 610; color: "transparent"
    property string method: "peap"
    onVisibleChanged: if (!visible) IntegrationService.enterpriseSsid = ""
    Shortcut { sequence: "Escape"; onActivated: IntegrationService.enterpriseSsid = "" }
    Rectangle {
        anchors.fill: parent; radius: 18; color: "#050505"; border.width: 1; border.color: "#343434"
        ColumnLayout {
            anchors.fill: parent; anchors.margins: 18; spacing: 7
            Text { text: "Connect to " + IntegrationService.enterpriseSsid; color: "white"; font.family: Theme.fontFamily; font.pixelSize: 14; font.weight: Font.DemiBold }
            SettingsButton { label: "Authentication"; buttonText: root.method.toUpperCase(); onClicked: root.method = ["peap","ttls","tls"][( ["peap","ttls","tls"].indexOf(root.method)+1)%3] }
            SettingsField { id: identity; label: "Identity"; placeholder: "user@example.org" }
            SettingsField { id: password; label: root.method === "tls" ? "Private-key password" : "Password"; secret: true }
            SettingsField { id: domain; label: "Server domain"; description: "Required to verify the authentication server"; placeholder: "radius.example.org" }
            SettingsField { id: ca; label: "CA certificate"; placeholder: "~/network-ca.pem" }
            SettingsField { id: certificate; visible: root.method === "tls"; label: "Client certificate"; placeholder: "~/client.pem" }
            SettingsField { id: privateKey; visible: root.method === "tls"; label: "Private key"; placeholder: "~/client.key" }
            Text { Layout.fillWidth: true; wrapMode: Text.Wrap; text: "Use the certificate and domain supplied by your network administrator. Credentials are sent directly to NetworkManager."; color: "#888888"; font.pixelSize: 10 }
            Item { Layout.fillHeight: true }
            SettingsButton {
                label: "Connect"; buttonText: "Connect"
                enabled: identity.text.length > 0 && domain.text.length > 0 && ca.text.length > 0
                onClicked: {
                    const accepted = SystemService.enqueue(["wifi-enterprise", IntegrationService.enterpriseSsid], "network", "wifi-connect", false,
                        {method:root.method,identity:identity.text,password:password.text,domain:domain.text,ca:ca.text,certificate:certificate.text,privateKey:privateKey.text});
                    if (accepted) { password.text = ""; IntegrationService.enterpriseSsid = ""; }
                }
            }
            SettingsButton { label: "Cancel"; buttonText: "Cancel"; onClicked: { password.text = ""; IntegrationService.enterpriseSsid = ""; } }
        }
    }
}
