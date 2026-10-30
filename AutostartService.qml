pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs

Scope {
    id: root

    property var entries: []
    property bool loading: false
    property string lastError: ""
    property string labwcScript: ""
    property bool labwcLoading: false

    readonly property int totalCount: entries.length
    readonly property int enabledCount: entries.filter(e => e.enabled).length
    readonly property int runningCount: entries.filter(e => e.running).length
    readonly property int delayedCount: entries.filter(e => e.delay > 0).length

    Component.onCompleted: refresh()

    function refresh() {
        if (listProcess.running) return;
        loading = true;
        listProcess.running = true;
    }

    function toggle(id, enable) {
        const idx = entries.findIndex(e => e.id === id);
        if (idx !== -1) {
            const updated = entries.slice();
            updated[idx] = Object.assign({}, updated[idx], { enabled: enable });
            entries = updated;
        }
        Quickshell.execDetached([Quickshell.shellPath("weylume-native"), "autostart-toggle", id, String(enable)]);
        debounceTimer.restart();
    }

    function saveEntry(entry) {
        loading = true;
        const jsonStr = JSON.stringify(entry);
        Quickshell.execDetached([Quickshell.shellPath("weylume-native"), "autostart-save", jsonStr]);
        OsdService.show("Startup Application Saved", entry.name || "Autostart updated", "dialog-information", -1, true);
        debounceTimer.restart();
    }

    function deleteEntry(id, name) {
        Quickshell.execDetached([Quickshell.shellPath("weylume-native"), "autostart-delete", id]);
        OsdService.show("Startup App Removed", name || id, "dialog-warning", -1, true);
        debounceTimer.restart();
    }

    function launch(exec, name) {
        Quickshell.execDetached([Quickshell.shellPath("weylume-native"), "autostart-launch", exec]);
        OsdService.show("Launched", name || exec, "application-x-executable", -1, true);
        debounceTimer.restart();
    }

    function openFolder() {
        Quickshell.execDetached(["pcmanfm-qt", Quickshell.env("HOME") + "/.config/autostart"]);
    }

    function loadLabwcScript() {
        labwcLoading = true;
        labwcReader.running = true;
    }

    function saveLabwcScript(content) {
        Quickshell.execDetached([Quickshell.shellPath("weylume-native"), "autostart-labwc-write", content]);
        OsdService.show("Labwc Autostart Saved", "Backup created in ~/.config/labwc/", "dialog-information", -1, true);
        debounceTimer.restart();
    }

    Process {
        id: listProcess
        command: [Quickshell.shellPath("weylume-native"), "autostart-list"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false;
                try {
                    root.entries = JSON.parse(text);
                } catch(e) {
                    root.lastError = e.toString();
                }
            }
        }
    }

    Process {
        id: labwcReader
        command: [Quickshell.shellPath("weylume-native"), "autostart-labwc-read"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.labwcLoading = false;
                try {
                    const res = JSON.parse(text);
                    if (res.ok) root.labwcScript = res.content || "";
                } catch(e) {}
            }
        }
    }

    Timer {
        id: debounceTimer
        interval: 350
        repeat: false
        onTriggered: root.refresh()
    }
}
