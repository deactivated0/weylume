pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth

Scope {
    id: root
    readonly property var adapter: ((Bluetooth.adapters && Bluetooth.adapters.values) ? Bluetooth.adapters.values.find(a => a.dbusPath === SettingsService.bluetoothAdapter) : null) || Bluetooth.defaultAdapter
    property bool pairing: agent.running
    property var device: null
    property var prompt: null
    property bool trustAfterPairing: false
    property string error: ""
    function pair(nativeDevice) {
        if (!nativeDevice || agent.running) return;
        root.device = nativeDevice;
        root.prompt = null;
        root.error = "";
        root.trustAfterPairing = false;
        agent.command = [Quickshell.shellPath("weylume-native"), "bluetooth-pair", nativeDevice.address, nativeDevice.adapter?.dbusPath || ""];
        agent.running = true;
    }
    function answer(accepted, value) {
        if (!root.prompt || !agent.running) return;
        agent.write(JSON.stringify({ id: root.prompt.id, accept: accepted, value: value || "" }) + "\n");
        root.prompt = null;
    }
    function cancel() { if (agent.running) agent.write('{"cancel":true}\n'); }
    Process {
        id: agent
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                try {
                    const message = JSON.parse(line);
                    if (message.type === "prompt") root.prompt = message;
                    else if (message.type === "cancel") root.prompt = null;
                    else if (message.type === "finished") {
                        if (!message.ok) root.error = String(message.message || "Pairing failed");
                        else if (root.device) {
                            if (root.trustAfterPairing) root.device.trusted = true;
                            root.device.connect();
                        }
                    }
                } catch (error) {}
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.trim()) root.error = text.trim() }
        onExited: (code, status) => {
            root.prompt = null;
            if (code !== 0 && root.error) OsdService.show("Bluetooth pairing", root.error, "dialog-warning", -1, true);
            root.device = null;
        }
    }
    LazyLoader {
        active: root.pairing
        BluetoothPairDialog {}
    }
}
