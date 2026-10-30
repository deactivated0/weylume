pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
Scope {
    id: root
    property bool recording: recorder.running
    property bool paused: false
    property bool preparing: false
    property bool active: false
    property bool stopping: false
    property bool ipc: false
    property bool timestampSupported: false
    property bool finalized: false
    property int exitCode: -1
    property int elapsedSeconds: 0
    property string outputPath: ""
    property string socketPath: ""
    property string lastError: ""
    property string deferredSession: ""
    readonly property string stateLabel: preparing ? "Preparing capture" : stopping ? "Finalizing recording" : active ? (paused ? "Paused" : "Capturing") : recording ? (timestampSupported ? "Waiting for the first frame / portal permission" : "Recorder running; this version cannot acknowledge capture start") : "No Weylume capture is active"
    function start() {
        if (recording || preparing || control.running || verify.running) return;
        if (!SystemService.has("gpu-screen-recorder")) { OsdService.show("Screen recording unavailable", "gpu-screen-recorder was not found", "dialog-error", -1, true); return; }
        preparing = true; prepare.running = true;
    }
    function startPrepared(data) {
        outputPath = data.path; socketPath = data.socket; ipc = Boolean(data.ipc); timestampSupported = Boolean(data.timestamp);
        lastError = ""; elapsedSeconds = 0; paused = false; active = false; stopping = false; finalized = false; exitCode = -1; stopAfterControl = false; deferredSession = "";
        const args = ["gpu-screen-recorder", "-w", SettingsService.recordingSource, "-f", String(SettingsService.recordingFps), "-k", SettingsService.recordingCodec, "-c", SettingsService.recordingContainer, "-a", SettingsService.recordingMicrophone ? "default_output|default_input" : "default_output", "-o", outputPath];
        if (ipc) args.push("-ipc", socketPath);
        if (timestampSupported) args.push("-write-first-frame-ts", "yes");
        recorder.command = args; recorder.running = true;
    }
    function send(action) { if (control.running) return false; control.action = action; control.command = [Quickshell.shellPath("weylume-native"), "recording-control", socketPath, action]; control.running = true; return true; }
    function stop() {
        if (!recording || stopping) return;
        stopping = true;
        if (!ipc || !active) recorder.signal(2);
        else if (!send("stop")) { stopping = false; stopAfterControl = true; }
    }
    property bool stopAfterControl: false
    function toggle() { if (recording) stop(); else if (preparing) preparing = false; else start(); }
    function togglePause() {
        if (!recording || stopping || !active) return;
        if (!ipc) { OsdService.show("Pause unavailable", "Update gpu-screen-recorder for acknowledged pause control", "dialog-warning", -1, true); return; }
        send(paused ? "resume" : "pause");
    }
    function beforeSession(action) { deferredSession = action; stop(); }
    function finish() {
        if (recorder.running || control.running || exitCode === -1 || verify.running) return;
        const code = exitCode; exitCode = -1;
        if (code !== 0 && code !== 130) {
            OsdService.show("Recording failed", lastError || ("Exit code " + code), "dialog-error", -1, true);
            deferredSession = ""; stopping = false; return;
        }
        verify.running = true;
    }
    FileView {
        id: firstFrame
        path: root.recording && root.timestampSupported && !root.active ? root.outputPath + ".ts" : ""
        watchChanges: true; printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const lines = text().trim().split("\n");
            if (lines.length >= 2 && Number(lines[1].trim().split(/\s+/)[0]) > 0) {
                root.active = true;
                OsdService.show("Recording started", root.outputPath, "media-record", -1, false);
            }
        }
    }
    Process {
        id: prepare
        command: [Quickshell.shellPath("weylume-native"), "prepare-recording", SettingsService.recordingContainer]
        stdout: StdioCollector { onStreamFinished: { const r=SystemService.parseEnvelope(text); const wanted=root.preparing; root.preparing=false; if(!wanted)return; if(r.ok) root.startPrepared(r.data); else OsdService.show("Recording failed",r.message,"dialog-error",-1,true); } }
        onExited: Qt.callLater(() => { if (root.preparing) { root.preparing=false; OsdService.show("Recording failed","Could not start the recording helper","dialog-error",-1,true); } })
    }
    Process {
        id: recorder
        stderr: SplitParser { onRead: line => { root.lastError = (root.lastError + "\n" + line).slice(-4096); } }
        onStarted: SystemData.setRecording(true)
        onExited: (code, status) => { root.exitCode=code; root.active=false; root.paused=false; SystemData.setRecording(false); Qt.callLater(root.finish); }
    }
    Process {
        id: control
        property string action: ""
        property bool responded: false
        onStarted: responded = false
        stdout: StdioCollector {
            onStreamFinished: {
                control.responded = true;
                const r=SystemService.parseEnvelope(text);
                if (r.ok && control.action === "stop") root.finalized = r.data?.path === root.outputPath;
                else if (r.ok && root.recording) { root.paused = control.action === "pause"; OsdService.show(root.paused ? "Recording paused" : "Recording resumed", "", "media-record", -1, false); }
                else if (!r.ok) {
                    OsdService.show("Recorder request failed",r.message,"dialog-warning",-1,true);
                    if(control.action === "stop" && root.recording) recorder.signal(2);
                }
            }
        }
        onExited: Qt.callLater(() => {
            if (!control.responded) {
                OsdService.show("Recorder request failed", "The control helper exited without a reply", "dialog-warning", -1, true);
                if (control.action === "stop" && root.recording) recorder.signal(2);
            }
            if (root.stopAfterControl) { root.stopAfterControl=false; root.stop(); }
            root.finish();
        })
    }
    Process {
        id: verify
        property bool responded: false
        onStarted: responded = false
        command: [Quickshell.shellPath("weylume-native"), "recording-check", root.outputPath]
        stdout: StdioCollector {
            onStreamFinished: {
                verify.responded = true;
                const r=SystemService.parseEnvelope(text); root.stopping=false;
                OsdService.show(r.ok ? (root.finalized ? "Recording saved" : "Recorder finished") : "Recording failed", r.ok ? root.outputPath : r.message,"media-record",-1,!r.ok);
                const action=root.deferredSession; root.deferredSession="";
                if(r.ok && action) SystemService.enqueue(["session",action],"session","session",false);
            }
        }
        onExited: Qt.callLater(() => {
            if (!verify.responded) {
                root.stopping = false; root.deferredSession = "";
                OsdService.show("Recording failed", "Could not verify the recording output", "dialog-error", -1, true);
            }
        })
    }
    Connections { target: SystemData; function onPrepareSleep(sleeping) { if(sleeping && root.recording) root.stop(); } }
    Timer { interval:1000; repeat:true; running:root.recording && !root.paused && (root.active || !root.timestampSupported); onTriggered:root.elapsedSeconds++ }
}
