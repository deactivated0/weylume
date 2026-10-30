pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    property bool ready: false
    property string error: ""
    property var repaired: []

    Timer {
        interval: 8000
        running: !root.ready && !root.error
        onTriggered: root.error = "Cannot start weylume-native. Check executable permissions, required libraries and the native/ build for this architecture."
    }

    Process {
        id: repair
        command: [Quickshell.shellPath("weylume-native"), "state-validate"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const reply = JSON.parse(text);
                    if (reply.ok) {
                        root.error = "";
                        root.repaired = reply.data?.repaired || [];
                        root.ready = true;
                    } else root.error = reply.message || "State repair failed";
                } catch (error) { root.error = "Cannot start weylume-native. Check executable permissions and rebuild native/ for this architecture."; }
            }
        }
        onExited: (code, status) => {
            if (code !== 0 && !root.ready && !root.error) root.error = "Cannot validate configuration; state writes are disabled.";
        }
    }
}
