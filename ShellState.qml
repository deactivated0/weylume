pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Pipewire

Scope {
    id: root
    signal taskMenusCloseRequested()
    signal createFolderRequested()

    property bool startOpen: false
    property bool quickOpen: false
    property bool trayOpen: false
    property bool notifOpen: false
    property bool audioMixerOpen: false
    property bool settingsOpen: false
    property bool clipboardOpen: false
    property bool emojiOpen: false
    property bool sidebarVisible: false
    property bool sessionDialogOpen: false
    property bool isLocked: false
    property string pendingSessionAction: ""
    property bool isDraggingFile: false
    property var dragFileData: null
    property real dragGlobalX: 0
    property real dragGlobalY: 0
    property real dragItemWidth: 60
    property real dragItemHeight: 66
    property real dragIconSize: 32
    property real dragGrabOffsetX: 30
    property real dragGrabOffsetY: 33
    property string popupScreenName: Quickshell.screens && Quickshell.screens.length > 0 ? Quickshell.screens[0].name : ""
    property var returnWindow: null
    readonly property var popupScreen: Quickshell.screens.find(s => s.name === root.popupScreenName) || Quickshell.screens[0] || null
    Connections {
        target: Quickshell
        function onScreensChanged() {
            if (!Quickshell.screens.some(s => s.name === root.popupScreenName)) {
                root.closeFlyouts();
                root.popupScreenName = Quickshell.screens[0]?.name || "";
            }
        }
    }
    property string notifCenterTab: "calendar"
    function formatLayout(layout) {
        const l = String(layout || "us").trim().toLowerCase();
        if (l === "sorani" || l === "ckb") return "SOR";
        return l.toUpperCase();
    }
    property string kbLayout: formatLayout(SettingsService.keyboardLayout)
    property real brightness: 1.0
    readonly property real minHardwareBrightness: 0.15
    property string wallpaperPath: ""
    property real queuedHardwareBrightness: 1.0
    property real activeHardwareBrightness: 1.0
    property bool brightnessWritePending: false
    property bool brightnessBackendWriting: false
    readonly property date currentDate: systemClock.date
    readonly property int currentHour: systemClock.hours
    readonly property int currentMinute: systemClock.minutes

    SystemClock { id: systemClock; precision: SystemClock.Minutes }

    FileView {
        path: StateStore.ready ? Quickshell.shellPath("wallpaper.json") : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                root.wallpaperPath = parsed?.path || "";
            } catch (error) {
                root.wallpaperPath = "";
            }
        }
    }

    Connections {
        target: SettingsService
        function onLoadedChanged() {
            if (SettingsService.loaded && SettingsService.lockOnStart && SettingsService.lockscreenEnabled) {
                root.isLocked = true;
            }
        }
    }

    Component.onCompleted: {
        if (SettingsService.loaded && SettingsService.lockOnStart && SettingsService.lockscreenEnabled) {
            root.isLocked = true;
        }
    }

    // Bind PipeWire nodes once for the entire shell instead of once per panel/monitor.
    PwObjectTracker {
        objects: Pipewire.nodes ? Pipewire.nodes.values : []
    }

    Process {
        running: true
        command: [Quickshell.shellPath("weylume-native"), "gamma-get"]
        stdout: StdioCollector {
            onStreamFinished: {
                const match = text.trim().match(/(-?\d+(?:\.\d+)?)$/);
                const parsed = match ? Number(match[1]) : NaN;
                if (!isNaN(parsed) && parsed >= 0.0 && parsed <= 1.0) {
                    const norm = Math.max(0.0, (parsed - root.minHardwareBrightness) / (1.0 - root.minHardwareBrightness));
                    const linear = Math.pow(norm, 1.0 / 1.25);
                    root.brightness = Math.max(0.0, Math.min(1.0, Math.round(linear * 100) / 100));
                }
            }
        }
    }

    function finishBrightnessWrite(success) {
        root.brightnessBackendWriting = false;
        if (!success) {
            brightnessFallback.command = [Quickshell.shellPath("weylume-native"), "brightness", root.activeHardwareBrightness.toFixed(2)];
            brightnessFallback.running = true;
        } else if (root.brightnessWritePending) Qt.callLater(root.startBrightnessWrite);
    }

    Process {
        id: brightnessWriter
        onExited: (exitCode, exitStatus) => root.finishBrightnessWrite(exitCode === 0)
    }

    Process {
        id: brightnessFallback
        onExited: if (root.brightnessWritePending) Qt.callLater(root.startBrightnessWrite)
    }

    function startBrightnessWrite() {
        if (root.brightnessBackendWriting || brightnessWriter.running || brightnessFallback.running || !root.brightnessWritePending) return;
        root.brightnessWritePending = false;
        root.activeHardwareBrightness = root.queuedHardwareBrightness;
        root.brightnessBackendWriting = SystemData.writeGamma("Brightness", Number(root.activeHardwareBrightness.toFixed(2)), root.finishBrightnessWrite);
        if (root.brightnessBackendWriting) return;
        brightnessWriter.command = [
            Quickshell.shellPath("weylume-native"), "gamma-set", "Brightness", root.activeHardwareBrightness.toFixed(2)
        ];
        brightnessWriter.running = true;
    }

    Timer {
        id: flyoutGcTimer
        interval: 1500
        repeat: false
        onTriggered: gc()
    }

    function closeFlyouts(restoreFocus = true) {
        startOpen = false;
        quickOpen = false;
        trayOpen = false;
        notifOpen = false;
        audioMixerOpen = false;
        clipboardOpen = false;
        emojiOpen = false;
        taskMenusCloseRequested();
        flyoutGcTimer.restart();
        if (restoreFocus && root.returnWindow) {
            try { root.returnWindow.activate(); } catch (error) {}
            root.returnWindow = null;
        }
    }

    function useScreen(screenName) {
        if (!root.startOpen && !root.quickOpen && !root.notifOpen && !root.settingsOpen && !root.clipboardOpen && !root.emojiOpen && !root.audioMixerOpen)
            root.returnWindow = ToplevelManager.activeToplevel;
        if (screenName && popupScreenName !== screenName) popupScreenName = screenName;
    }

    function toggleStart(screenName) {
        if (isLocked) return;
        useScreen(screenName);
        const next = !startOpen;
        closeFlyouts(false);
        startOpen = next;
    }

    function toggleQuick(screenName) {
        if (isLocked) return;
        useScreen(screenName);
        const next = !quickOpen;
        closeFlyouts(false);
        quickOpen = next;
    }

    function toggleTray(screenName) {
        if (isLocked) return;
        useScreen(screenName);
        const next = !trayOpen;
        closeFlyouts(false);
        trayOpen = next;
    }

    function openCalendar(screenName) {
        if (isLocked) return;
        useScreen(screenName);
        notifCenterTab = "calendar";
        closeFlyouts(false);
        notifOpen = true;
    }

    function openNotifications(screenName) {
        if (isLocked) return;
        useScreen(screenName);
        notifCenterTab = "notifications";
        closeFlyouts(false);
        notifOpen = true;
    }

    function toggleNotif(screenName, tab) {
        if (isLocked) return;
        useScreen(screenName);
        if (tab) notifCenterTab = tab;
        const next = !notifOpen;
        closeFlyouts(false);
        notifOpen = next;
    }

    function toggleMixer(screenName) {
        if (isLocked) return;
        useScreen(screenName);
        const next = !audioMixerOpen;
        closeFlyouts(false);
        audioMixerOpen = next;
    }

    function toggleSettings(screenName) {
        if (isLocked) return;
        settingsOpen = !settingsOpen;
    }

    function toggleClipboard(screenName) {
        if (isLocked) return;
        useScreen(screenName);
        const next = !clipboardOpen;
        closeFlyouts(false);
        clipboardOpen = next;
    }

    function toggleEmoji(screenName) {
        if (isLocked) return;
        useScreen(screenName);
        const next = !emojiOpen;
        closeFlyouts(false);
        emojiOpen = next;
    }

    function toggleSidebar() {
        if (isLocked) return;
        sidebarVisible = !sidebarVisible;
    }

    function toggleLayout() {
        SystemService.cycleKeyboardLayout();
    }

    function lock() {
        if (!SettingsService.lockscreenEnabled) return;
        closeFlyouts(false);
        settingsOpen = false;
        sessionDialogOpen = false;
        pendingSessionAction = "";
        isLocked = true;
    }

    function unlock() {
        isLocked = false;
    }

    function requestSessionAction(action) {
        closeFlyouts();
        if (action === "lock") {
            lock();
            return;
        }
        if (isLocked || !SettingsService.confirmSessionActions || action === "suspend") {
            SystemService.enqueue(["session", action], "session", "session", false);
            return;
        }
        pendingSessionAction = action;
        sessionDialogOpen = true;
        SystemService.refreshSystem();
    }

    function confirmSessionAction() {
        const action = pendingSessionAction;
        sessionDialogOpen = false;
        pendingSessionAction = "";
        if (action) SystemService.enqueue(["session", action], "session", "session", false);
    }

    function cancelSessionAction() {
        sessionDialogOpen = false;
        pendingSessionAction = "";
    }

    function setBrightness(val) {
        const next = Math.max(0.0, Math.min(1.0, Math.round(val * 100) / 100));
        if (next === brightness) return;
        brightness = next;
        // Perceptual gamma compensation curve: preserves shadow detail & avoids harsh contrast
        const perceived = Math.pow(brightness, 1.25);
        const hwVal = minHardwareBrightness + perceived * (1.0 - minHardwareBrightness);
        queuedHardwareBrightness = hwVal;
        brightnessWritePending = true;
        startBrightnessWrite();
    }

    function adjustBrightness(delta) {
        setBrightness(brightness + delta);
        OsdService.show("Brightness", Math.round(brightness * 100) + "%", "display-brightness", brightness, false);
    }

    function adjustVolume(delta) {
        const sink = AudioService.defaultSink || Pipewire.defaultAudioSink;
        if (sink) {
            const cur = sink.audio?.volume ?? 0.5;
            const next = Math.max(0, Math.min(1.5, cur + delta));
            AudioService.setVolume(sink, next);
            OsdService.show("Volume", Math.round(next * 100) + "%", (sink.audio?.muted ?? false) ? "audio-volume-muted" : "audio-volume-high", Math.min(1, next), false);
        } else {
            const step = delta > 0 ? "5%+" : "5%-";
            Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", step, "--limit", "1.5"]);
        }
    }

    function toggleMute() {
        const sink = AudioService.defaultSink || Pipewire.defaultAudioSink;
        if (sink) {
            AudioService.toggleMute(sink);
            const isMuted = sink.audio?.muted ?? false;
            OsdService.show("Volume", Math.round((sink.audio?.volume ?? 1) * 100) + "%", isMuted ? "audio-volume-muted" : "audio-volume-high", Math.min(1, sink.audio?.volume ?? 1), false);
        } else {
            Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]);
        }
    }

    function setWallpaper(path) {
        wallpaperPath = path || "";
    }
}
