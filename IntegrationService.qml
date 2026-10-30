pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    property bool windowPickerOpen: false
    property var windows: []
    property string enterpriseSsid: ""
    property var audioDetails: ({ cards: [], sinks: [], sources: [] })
    property var diagnostics: ({})
    function chooseWindow() { root.windows = []; root.windowPickerOpen = true; windowReader.running = true; }
    function captureWindow(id) { root.windowPickerOpen = false; Qt.callLater(() => SystemService.captureScreenshot("window:" + id)); }
    function authenticate(ssid) { root.enterpriseSsid = ssid; }
    function refreshAudio() { SystemService.enqueue(["audio-details"], "audio-details", "audio-details", true); }
    function diagnose() { SystemService.enqueue(["diagnostics"], "diagnostics", "diagnostics", false); }
    Connections {
        target: SystemService
        function onActionFinished(domain, success, message, data) {
            if (domain === "audio-details" && success) root.audioDetails = data;
            if (domain === "audio-profile" || domain === "audio-port") root.refreshAudio();
            if (domain === "diagnostics" && success) root.diagnostics = data;
        }
    }
    Process {
        id: windowReader
        command: [Quickshell.shellPath("weylume-native"), "windows"]
        stdout: StdioCollector {
            onStreamFinished: { try { root.windows = JSON.parse(text); } catch (error) {} }
        }
        onExited: (code, status) => { if (code !== 0) OsdService.show("Window capture unavailable", "The compositor must provide ext-foreign-toplevel-list-v1 and grim window capture.", "dialog-warning", -1, true); }
    }
    LazyLoader { active: root.windowPickerOpen; WindowPicker {} }
    LazyLoader { active: root.enterpriseSsid.length > 0; NetworkAuthDialog {} }
}
