pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
Scope {
    id: root
    property var outputs: []
    property var profiles: ({})
    property bool confirming: false
    property bool busy: guard.running
    property var request: []
    property bool hotplug: false
    function initialize() {
        refresh();
    }
    function refresh() { SystemService.enqueue(["outputs"], "outputs", "outputs", true); }
    function save(name) { SystemService.enqueue(["output-save", name], "output-save", "", false); }
    function apply(values) {
        if (root.busy) return;
        root.request = values;
        guard.stdinEnabled = true;
        guard.running = true;
    }
    function edit(index, key, value) {
        const copy = root.outputs.map(o => Object.assign({}, o));
        copy[index][key] = value;
        root.outputs = copy;
    }
    function respond(keep) { if (root.confirming) { guard.write(keep ? "keep\n" : "revert\n"); root.confirming = false; } }
    Connections {
        target: Quickshell
        function onScreensChanged() { if (root.busy) return; root.hotplug = true; if (SystemService.ready) Qt.callLater(root.refresh); }
    }
    Connections {
        target: SystemService
        function onActionFinished(domain, success, message, data) {
            if (domain === "output-save" && success) root.profiles = data;
            if (domain !== "outputs" || !success) return;
            root.outputs = data.outputs || [];
            root.profiles = data.profiles || ({});
            if (!root.hotplug || !SettingsService.outputAutoRestore || root.busy) { root.hotplug = false; return; }
            root.hotplug = false;
            const matches = Object.keys(root.profiles).filter(name => {
                const profile = root.profiles[name];
                return profile.length === root.outputs.length && profile.every(p => root.outputs.some(o => o.name === p.name && o.make === p.make && o.model === p.model && o.serial === p.serial));
            });
            // Ambiguous profiles require a user choice; never guess a dock layout.
            if (matches.length === 1) root.apply(root.profiles[matches[0]]);
        }
    }
    Process {
        id: guard
        property string failure: ""
        command: [Quickshell.shellPath("weylume-native"), "output-apply-json"]
        onStarted: { failure = ""; write(JSON.stringify(root.request) + "\n"); }
        stdout: SplitParser {
            onRead: line => {
                try {
                    const message = JSON.parse(line);
                    if (message.type === "applied") root.confirming = true;
                    else if (message.type === "finished") OsdService.show("Displays", message.message, "video-display", -1, !message.ok);
                } catch (error) {}
            }
        }
        stderr: StdioCollector { onStreamFinished: guard.failure = text.trim() }
        onExited: (code, status) => {
            root.confirming = false;
            if (code !== 0) OsdService.show("Display configuration failed", failure || "Recovery will be retried on the next shell start.", "dialog-warning", -1, true);
            Qt.callLater(root.refresh);
        }
    }
    LazyLoader {
        active: root.confirming
        FloatingWindow {
            title: "Keep display configuration?"
            visible: true; implicitWidth: 430; implicitHeight: 160; color: "#050505"
            onVisibleChanged: if (!visible) root.respond(false)
            Shortcut { sequence: "Escape"; onActivated: root.respond(false) }
            Column {
                anchors.fill: parent; anchors.margins: 18; spacing: 8
                Text { text: "Keep this configuration? Reverting after 15 seconds."; color: "white"; font.family: Theme.fontFamily; font.pixelSize: 11 }
                SettingsButton { width: parent.width; label: "Keep display configuration"; buttonText: "Keep"; onClicked: root.respond(true) }
                SettingsButton { width: parent.width; label: "Restore previous configuration"; buttonText: "Revert"; onClicked: root.respond(false) }
            }
        }
    }
}
