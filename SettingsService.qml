pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    readonly property int schemaVersion: 3
    property bool loaded: false
    property bool initialized: false

    // Quickshell / UX. Defaults preserve the existing shell.
    property bool darkMode: true
    property bool clock24Hour: false
    property bool reducedMotion: false
    property bool tooltipsEnabled: true
    property bool notificationSounds: false
    property int notificationTimeout: 6500
    property int notificationHistoryLimit: 100
    property bool persistentNotificationHistory: true
    property string mutedNotificationApps: ""
    property bool unloadClosedFlyouts: true
    property int metricsActiveInterval: 1000
    property int metricsIdleInterval: 10000
    property int previewCacheLimit: 96
    property int previewMaxAgeHours: 6

    // Capture, clipboard and integration policy.
    property bool clipboardEnabled: true
    property bool clipboardImagesEnabled: true
    property int clipboardHistoryLimit: 50
    property bool clipboardSensitiveFilter: true
    property string screenshotMode: "region"
    property bool screenshotCopy: true
    property bool screenshotAnnotate: true
    property string recordingSource: "portal"
    property int recordingFps: 60
    property string recordingCodec: "h264"
    property string recordingContainer: "mkv"
    property bool recordingMicrophone: false

    // Session, notifications and gaming.
    property bool dndEnabled: false
    property bool confirmSessionActions: true
    property bool gamingMode: false
    property bool gamingDnd: true
    property bool gamingPerformanceProfile: true
    property bool gamingAllowTearing: false
    property string gamingPreviousPowerProfile: "balanced"
    property bool gamingPreviousTearing: false

    // Lock Screen & Security
    property bool lockscreenEnabled: true
    property string lockscreenMode: "pin" // "pin" or "password"
    property string lockscreenPin: "1234"
    property bool autoUnlockPin: true
    property bool lockOnStart: false
    property string lockscreenUserName: ""

    // Labwc/input defaults. Actual compositor state is refreshed by SystemService.
    property string bluetoothAdapter: ""
    property string gamingApps: ""
    property bool outputAutoRestore: false

    property string keyboardLayouts: "us,de,sorani"
    property string keyboardLayout: "us"
    property int workspaceCount: 4
    property real desktopIconScale: 1.0

    // Start Menu customization
    property int startMenuWidth: 450
    property int startMenuHeight: 575
    property bool startDefaultAllPrograms: false
    property bool startCompactMode: false
    property int startAppIconSize: 32
    property bool startShowUserFolder: true
    property bool startShowDocuments: true
    property bool startShowPictures: true
    property bool startShowMusic: true
    property bool startShowDownloads: true
    property bool startShowThisPC: true
    property bool startShowSettings: true
    property bool startShowTerminal: true
    property bool startEnableCommandRunner: true

    // Custom Start Menu Directory Paths
    property string startPathUserFolder: ""
    property string startPathDocuments: ""
    property string startPathPictures: ""
    property string startPathMusic: ""
    property string startPathDownloads: ""
    property string startPathThisPC: ""
    property string startCustomFolder1Name: ""
    property string startCustomFolder1Path: ""
    property string startCustomFolder2Name: ""
    property string startCustomFolder2Path: ""

    function boundedNumber(value, fallback, minimum, maximum) {
        const number = Number(value);
        return isFinite(number) ? Math.max(minimum, Math.min(maximum, Math.round(number))) : fallback;
    }

    function apply(data) {
        if (!data || typeof data !== "object") return;
        const booleanKeys = [
            "darkMode", "outputAutoRestore", "clock24Hour", "reducedMotion", "tooltipsEnabled", "notificationSounds",
            "persistentNotificationHistory", "unloadClosedFlyouts", "clipboardEnabled",
            "clipboardImagesEnabled", "clipboardSensitiveFilter", "screenshotCopy", "screenshotAnnotate",
            "recordingMicrophone", "dndEnabled", "confirmSessionActions", "gamingMode",
            "gamingDnd", "gamingPerformanceProfile", "gamingAllowTearing", "gamingPreviousTearing",
            "lockscreenEnabled", "autoUnlockPin", "lockOnStart"
        ];
        for (let i = 0; i < booleanKeys.length; ++i) {
            const key = booleanKeys[i];
            if (data[key] !== undefined) root[key] = Boolean(data[key]);
        }

        root.notificationTimeout = boundedNumber(data.notificationTimeout, root.notificationTimeout, 1500, 30000);
        root.notificationHistoryLimit = boundedNumber(data.notificationHistoryLimit, root.notificationHistoryLimit, 10, 500);
        root.metricsActiveInterval = boundedNumber(data.metricsActiveInterval, root.metricsActiveInterval, 500, 10000);
        root.metricsIdleInterval = boundedNumber(data.metricsIdleInterval, root.metricsIdleInterval, 2000, 60000);
        root.previewCacheLimit = boundedNumber(data.previewCacheLimit, root.previewCacheLimit, 8, 512);
        root.previewMaxAgeHours = boundedNumber(data.previewMaxAgeHours, root.previewMaxAgeHours, 1, 168);
        root.clipboardHistoryLimit = boundedNumber(data.clipboardHistoryLimit, root.clipboardHistoryLimit, 10, 500);
        root.recordingFps = boundedNumber(data.recordingFps, root.recordingFps, 15, 240);
        root.workspaceCount = boundedNumber(data.workspaceCount, root.workspaceCount, 1, 16);

        const screenshotModes = ["region", "screen", "window"];
        const recordingSources = ["portal", "screen"];
        const codecs = ["h264", "hevc", "av1"];
        const containers = ["mkv", "mp4"];
        if (screenshotModes.includes(data.screenshotMode)) root.screenshotMode = data.screenshotMode;
        if (recordingSources.includes(data.recordingSource)) root.recordingSource = data.recordingSource;
        if (codecs.includes(data.recordingCodec)) root.recordingCodec = data.recordingCodec;
        if (containers.includes(data.recordingContainer)) root.recordingContainer = data.recordingContainer;
        if (typeof data.keyboardLayouts === "string" && data.keyboardLayouts.trim()) root.keyboardLayouts = data.keyboardLayouts;
        if (typeof data.keyboardLayout === "string" && /^[A-Za-z0-9_-]{2,16}$/.test(data.keyboardLayout)) root.keyboardLayout = data.keyboardLayout.toLowerCase();
        if (typeof data.bluetoothAdapter === "string") root.bluetoothAdapter = data.bluetoothAdapter;
        if (typeof data.gamingApps === "string") root.gamingApps = data.gamingApps.slice(0, 4096);
        if (typeof data.mutedNotificationApps === "string") root.mutedNotificationApps = data.mutedNotificationApps.slice(0, 2048);
        if (["balanced", "performance", "power-saver"].includes(data.gamingPreviousPowerProfile))
            root.gamingPreviousPowerProfile = data.gamingPreviousPowerProfile;
        if (typeof data.desktopIconScale === "number" && isFinite(data.desktopIconScale))
            root.desktopIconScale = Math.max(0.70, Math.min(1.50, Math.round(data.desktopIconScale * 100) / 100));

        if (["pin", "password"].includes(data.lockscreenMode)) root.lockscreenMode = data.lockscreenMode;
        if (typeof data.lockscreenPin === "string" && data.lockscreenPin.length >= 4) root.lockscreenPin = data.lockscreenPin;
        if (typeof data.lockscreenUserName === "string") root.lockscreenUserName = data.lockscreenUserName.slice(0, 64);

        const startMenuBooleans = [
            "startDefaultAllPrograms", "startCompactMode", "startShowUserFolder",
            "startShowDocuments", "startShowPictures", "startShowMusic",
            "startShowDownloads", "startShowThisPC", "startShowSettings",
            "startShowTerminal", "startEnableCommandRunner"
        ];
        for (let i = 0; i < startMenuBooleans.length; ++i) {
            const key = startMenuBooleans[i];
            if (data[key] !== undefined) root[key] = Boolean(data[key]);
        }
        root.startMenuWidth = boundedNumber(data.startMenuWidth, root.startMenuWidth, 360, 800);
        root.startMenuHeight = boundedNumber(data.startMenuHeight, root.startMenuHeight, 400, 900);
        root.startAppIconSize = boundedNumber(data.startAppIconSize, root.startAppIconSize, 20, 64);

        const startMenuStrings = [
            "startPathUserFolder", "startPathDocuments", "startPathPictures",
            "startPathMusic", "startPathDownloads", "startPathThisPC",
            "startCustomFolder1Name", "startCustomFolder1Path",
            "startCustomFolder2Name", "startCustomFolder2Path"
        ];
        for (let i = 0; i < startMenuStrings.length; ++i) {
            const key = startMenuStrings[i];
            if (typeof data[key] === "string") root[key] = data[key];
        }
    }

    function snapshot() {
        return {
            version: root.schemaVersion,
            darkMode: root.darkMode,
            bluetoothAdapter, gamingApps, outputAutoRestore,
            clock24Hour, reducedMotion, tooltipsEnabled, notificationSounds,
            notificationTimeout, notificationHistoryLimit, persistentNotificationHistory, mutedNotificationApps,
            unloadClosedFlyouts, metricsActiveInterval, metricsIdleInterval,
            previewCacheLimit, previewMaxAgeHours, clipboardEnabled, clipboardImagesEnabled, clipboardHistoryLimit,
            clipboardSensitiveFilter, screenshotMode, screenshotCopy, screenshotAnnotate,
            recordingSource, recordingFps, recordingCodec, recordingContainer,
            recordingMicrophone, dndEnabled, confirmSessionActions, gamingMode,
            gamingDnd, gamingPerformanceProfile, gamingAllowTearing,
            gamingPreviousPowerProfile, gamingPreviousTearing,
            keyboardLayouts, keyboardLayout, workspaceCount,
            desktopIconScale: root.desktopIconScale,
            startMenuWidth: root.startMenuWidth,
            startMenuHeight: root.startMenuHeight,
            startDefaultAllPrograms: root.startDefaultAllPrograms,
            startCompactMode: root.startCompactMode,
            startAppIconSize: root.startAppIconSize,
            startShowUserFolder: root.startShowUserFolder,
            startShowDocuments: root.startShowDocuments,
            startShowPictures: root.startShowPictures,
            startShowMusic: root.startShowMusic,
            startShowDownloads: root.startShowDownloads,
            startShowThisPC: root.startShowThisPC,
            startShowSettings: root.startShowSettings,
            startShowTerminal: root.startShowTerminal,
            startEnableCommandRunner: root.startEnableCommandRunner,
            startPathUserFolder: root.startPathUserFolder,
            startPathDocuments: root.startPathDocuments,
            startPathPictures: root.startPathPictures,
            startPathMusic: root.startPathMusic,
            startPathDownloads: root.startPathDownloads,
            startPathThisPC: root.startPathThisPC,
            startCustomFolder1Name: root.startCustomFolder1Name,
            startCustomFolder1Path: root.startCustomFolder1Path,
            startCustomFolder2Name: root.startCustomFolder2Name,
            startCustomFolder2Path: root.startCustomFolder2Path,
            lockscreenEnabled: root.lockscreenEnabled,
            lockscreenMode: root.lockscreenMode,
            lockscreenPin: root.lockscreenPin,
            autoUnlockPin: root.autoUnlockPin,
            lockOnStart: root.lockOnStart,
            lockscreenUserName: root.lockscreenUserName
        };
    }

    function save() {
        if (!root.loaded) return;
        saveTimer.restart();
    }

    function saveNow() {
        try {
            store.setText(JSON.stringify(snapshot(), null, 2) + "\n");
        } catch (error) {
            console.warn("SettingsService save error:", error);
        }
    }

    function resetDefaults() {
        root.loaded = false;
        root.darkMode = true;
        root.desktopIconScale = 1.0;
        root.clock24Hour = false;
        root.reducedMotion = false;
        root.tooltipsEnabled = true;
        root.notificationSounds = false;
        root.notificationTimeout = 6500;
        root.notificationHistoryLimit = 100;
        root.persistentNotificationHistory = true;
        root.mutedNotificationApps = "";
        root.unloadClosedFlyouts = true;
        root.metricsActiveInterval = 1000;
        root.metricsIdleInterval = 10000;
        root.previewCacheLimit = 96;
        root.previewMaxAgeHours = 6;
        root.clipboardEnabled = true;
        root.clipboardImagesEnabled = true;
        root.clipboardHistoryLimit = 50;
        root.clipboardSensitiveFilter = true;
        root.screenshotMode = "region";
        root.screenshotCopy = true;
        root.screenshotAnnotate = true;
        root.recordingSource = "portal";
        root.recordingFps = 60;
        root.recordingCodec = "h264";
        root.recordingContainer = "mkv";
        root.recordingMicrophone = false;
        root.dndEnabled = false;
        root.confirmSessionActions = true;
        root.gamingMode = false;
        root.gamingDnd = true;
        root.gamingPerformanceProfile = true;
        root.gamingAllowTearing = false;
        root.gamingPreviousPowerProfile = "balanced";
        root.gamingPreviousTearing = false;
        root.bluetoothAdapter = "";
        root.gamingApps = "";
        root.outputAutoRestore = false;
        root.keyboardLayouts = "us,de,sorani";
        root.keyboardLayout = "us";
        root.workspaceCount = 4;
        root.startMenuWidth = 450;
        root.startMenuHeight = 575;
        root.startDefaultAllPrograms = false;
        root.startCompactMode = false;
        root.startAppIconSize = 32;
        root.startShowUserFolder = true;
        root.startShowDocuments = true;
        root.startShowPictures = true;
        root.startShowMusic = true;
        root.startShowDownloads = true;
        root.startShowThisPC = true;
        root.startShowSettings = true;
        root.startShowTerminal = true;
        root.startEnableCommandRunner = true;
        root.startPathUserFolder = "";
        root.startPathDocuments = "";
        root.startPathPictures = "";
        root.startPathMusic = "";
        root.startPathDownloads = "";
        root.startPathThisPC = "";
        root.startCustomFolder1Name = "";
        root.startCustomFolder1Path = "";
        root.startCustomFolder2Name = "";
        root.startCustomFolder2Path = "";
        root.lockscreenEnabled = true;
        root.lockscreenMode = "pin";
        root.lockscreenPin = "1234";
        root.autoUnlockPin = true;
        root.lockOnStart = false;
        root.lockscreenUserName = "";
        root.loaded = true;
        saveNow();
    }

    FileView {
        id: store
        path: StateStore.ready ? Quickshell.shellPath("settings.json") : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root.loaded = false;
            try {
                const raw = text();
                if (raw && raw.trim()) root.apply(JSON.parse(raw));
            } catch (error) {
                console.warn("SettingsService load error:", error);
            }
            root.loaded = true;
            root.initialized = true;
            if (!text().trim()) root.saveNow();
            SystemService.setSystemTheme(root.darkMode, true);
        }
    }

    Timer { id: saveTimer; interval: 180; onTriggered: root.saveNow() }

    onDarkModeChanged: {
        save();
        if (root.initialized) SystemService.setSystemTheme(root.darkMode, false);
    }
    onBluetoothAdapterChanged: save()
    onGamingAppsChanged: save()
    onOutputAutoRestoreChanged: save()
    onClock24HourChanged: save()
    onReducedMotionChanged: save()
    onTooltipsEnabledChanged: save()
    onNotificationSoundsChanged: save()
    onNotificationTimeoutChanged: save()
    onNotificationHistoryLimitChanged: save()
    onPersistentNotificationHistoryChanged: save()
    onMutedNotificationAppsChanged: save()
    onUnloadClosedFlyoutsChanged: save()
    onMetricsActiveIntervalChanged: save()
    onMetricsIdleIntervalChanged: save()
    onPreviewCacheLimitChanged: save()
    onPreviewMaxAgeHoursChanged: save()
    onClipboardEnabledChanged: save()
    onClipboardImagesEnabledChanged: save()
    onClipboardHistoryLimitChanged: save()
    onClipboardSensitiveFilterChanged: save()
    onScreenshotModeChanged: save()
    onScreenshotCopyChanged: save()
    onScreenshotAnnotateChanged: save()
    onRecordingSourceChanged: save()
    onRecordingFpsChanged: save()
    onRecordingCodecChanged: save()
    onRecordingContainerChanged: save()
    onRecordingMicrophoneChanged: save()
    onDndEnabledChanged: save()
    onConfirmSessionActionsChanged: save()
    onGamingModeChanged: save()
    onGamingDndChanged: save()
    onGamingPerformanceProfileChanged: save()
    onGamingAllowTearingChanged: save()
    onGamingPreviousPowerProfileChanged: save()
    onGamingPreviousTearingChanged: save()
    onKeyboardLayoutsChanged: save()
    onKeyboardLayoutChanged: save()
    onWorkspaceCountChanged: save()
    onDesktopIconScaleChanged: save()
    onStartMenuWidthChanged: save()
    onStartMenuHeightChanged: save()
    onStartDefaultAllProgramsChanged: save()
    onStartCompactModeChanged: save()
    onStartAppIconSizeChanged: save()
    onStartShowUserFolderChanged: save()
    onStartShowDocumentsChanged: save()
    onStartShowPicturesChanged: save()
    onStartShowMusicChanged: save()
    onStartShowDownloadsChanged: save()
    onStartShowThisPCChanged: save()
    onStartShowSettingsChanged: save()
    onStartShowTerminalChanged: save()
    onStartEnableCommandRunnerChanged: save()
    onStartPathUserFolderChanged: save()
    onStartPathDocumentsChanged: save()
    onStartPathPicturesChanged: save()
    onStartPathMusicChanged: save()
    onStartPathDownloadsChanged: save()
    onStartPathThisPCChanged: save()
    onStartCustomFolder1NameChanged: save()
    onStartCustomFolder1PathChanged: save()
    onStartCustomFolder2NameChanged: save()
    onStartCustomFolder2PathChanged: save()
    onLockscreenEnabledChanged: save()
    onLockscreenModeChanged: save()
    onLockscreenPinChanged: save()
    onAutoUnlockPinChanged: save()
    onLockOnStartChanged: save()
    onLockscreenUserNameChanged: save()
}
