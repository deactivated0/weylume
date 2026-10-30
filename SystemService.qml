pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    signal actionFinished(string domain, bool success, string message, var data)

    property bool ready: false
    property var capabilities: ({ commands: ({}) })
    property bool busy: actionProcess.running
    property string activeDomain: ""
    property string lastMessage: ""
    property string lastError: ""
    property var actionQueue: []
    property string actionOutput: ""

    property var ethernet: ({ connected: false, name: "Wired Connection", device: "" })
    property bool networkAvailable: false
    property bool wifiEnabled: false
    property var wifiNetworks: []
    property var vpns: []
    property var activeVpn: null
    property string connectivity: "unknown"
    property string networkDevice: ""
    property var networkAddresses: []
    property string networkGateway: ""
    property var networkDns: []
    property bool networkLoading: false
    property bool networkRefreshPending: false

    property var labwc: ({
        decoration: "server", gap: 0, adaptiveSync: false, allowTearing: false,
        hdr: false, xwaylandPersistence: false, placementPolicy: "cascade",
        followMouse: false, raiseOnFocus: false, repeatRate: 25, repeatDelay: 600,
        workspaceCount: 1, workspaceNames: ["Default"], keyboardLayout: "us"
    })
    property string powerProfile: "balanced"
    property var inhibitors: []
    property var sessionCapabilities: ({})
    property bool inhibitorsUnknown: true
    property int updateCount: -1
    property var updates: []

    function has(command) {
        return Boolean(root.capabilities?.commands?.[command]);
    }

    function parseEnvelope(raw) {
        try {
            const parsed = JSON.parse((raw || "").trim());
            return parsed && typeof parsed === "object" ? parsed : ({ ok: false, message: "Invalid helper response" });
        } catch (error) {
            return ({ ok: false, message: "Invalid helper response" });
        }
    }

    function updateCollection(name, value) {
        const cur = root[name];
        if (cur === value) return;
        if (Array.isArray(cur) && Array.isArray(value) && cur.length === 0 && value.length === 0) return;
        if (JSON.stringify(cur) !== JSON.stringify(value)) root[name] = value;
    }

    function applyNetwork(data) {
        if (!data || typeof data !== "object") return;
        root.networkAvailable = Boolean(data.available);
        if (data.error) root.lastError = data.error;
        if (data.ethernet) root.updateCollection("ethernet", data.ethernet);
        if (data.wifiEnabled !== undefined) root.wifiEnabled = Boolean(data.wifiEnabled);
        if (Array.isArray(data.wifiNetworks)) root.updateCollection("wifiNetworks", data.wifiNetworks);
        if (Array.isArray(data.vpns)) root.updateCollection("vpns", data.vpns);
        root.updateCollection("activeVpn", data.activeVpn || null);
        root.connectivity = data.connectivity || "unknown";
        root.networkDevice = data.device || "";
        root.updateCollection("networkAddresses", Array.isArray(data.addresses) ? data.addresses : []);
        root.networkGateway = data.gateway || "";
        root.updateCollection("networkDns", Array.isArray(data.dns) ? data.dns : []);
    }

    function applyLabwc(data) {
        if (!data || typeof data !== "object") return;
        root.labwc = data;
        if (data.keyboardLayout) {
            SettingsService.keyboardLayout = String(data.keyboardLayout).toLowerCase();
            ShellState.kbLayout = ShellState.formatLayout(data.keyboardLayout);
        }
        if (data.workspaceCount) SettingsService.workspaceCount = Number(data.workspaceCount);
    }

    function enqueue(args, domain, coalesceKey, quiet, input) {
        if (!args || args.length === 0) return false;
        if (args[0] === "session" && RecorderService.recording) { RecorderService.beforeSession(args[1]); return true; }
        if (args[0] === "wifi-connect" && args.length > 2) {
            input = { password: args[2] };
            args = args.slice(0, 2);
        }
        const key = coalesceKey || "";
        let queue = root.actionQueue.slice();
        if (key) queue = queue.filter(item => item.key !== key);
        if (queue.length >= 12) {
            if (!quiet) OsdService.show("Action queue full", "Please wait for the current operation", "dialog-warning", -1, true);
            return false;
        }
        queue.push({ args: args, domain: domain || args[0] || "system", key: key, quiet: Boolean(quiet), input: input || null });
        root.actionQueue = queue;
        Qt.callLater(root.startNextAction);
        return true;
    }

    function startNextAction() {
        if (actionProcess.running || root.actionQueue.length === 0) return;
        const item = root.actionQueue[0];
        root.actionQueue = root.actionQueue.slice(1);
        root.activeDomain = item.domain;
        actionProcess.quiet = item.quiet;
        actionProcess.input = item.input ? JSON.stringify(item.input) : "";
        actionProcess.stdinEnabled = true;
        root.actionOutput = "";
        actionProcess.command = [Quickshell.shellPath("weylume-native")].concat(item.args);
        actionProcess.running = true;
    }

    function refreshNetwork() {
        if (!root.ready) return;
        if (networkReader.running) {
            root.networkRefreshPending = true;
            return;
        }
        root.networkLoading = true;
        networkReader.running = true;
    }

    function refreshLabwc() {
        if (!labwcReader.running) labwcReader.running = true;
    }

    function refreshSystem() {
        if (!systemReader.running) systemReader.running = true;
    }

    function toggleDnd() {
        SettingsService.dndEnabled = !SettingsService.dndEnabled;
        OsdService.show("Do Not Disturb", SettingsService.dndEnabled ? "On" : "Off", "notifications-disabled", -1, false);
    }

    function toggleVpn() {
        if (root.activeVpn?.uuid) {
            enqueue(["vpn-down", root.activeVpn.uuid], "network", "vpn", false);
        } else if (root.vpns.length > 0) {
            NetworkService.activate(root.vpns[0].uuid, "vpn");
        } else if (root.has("riseup-vpn")) {
            enqueue(["launch", "riseup-vpn"], "launch", "vpn-app", false);
        } else {
            OsdService.show("No VPN profile", "Add a VPN profile in NetworkManager first", "network-vpn", -1, true);
        }
    }

    function captureScreenshot(mode) {
        const captureMode = mode || SettingsService.screenshotMode;
        if (captureMode === "window") { IntegrationService.chooseWindow(); return; }
        enqueue([
            "screenshot", captureMode,
            SettingsService.screenshotCopy ? "1" : "0",
            SettingsService.screenshotAnnotate ? "1" : "0"
        ], "screenshot", "screenshot", false);
    }

    function setPowerProfile(profile) {
        enqueue(["power-profile", profile], "power", "power-profile", false);
    }

    function setSystemTheme(isDark, quiet = true) {
        return enqueue(["system-theme", isDark ? "dark" : "light"], "system", "system-theme", quiet);
    }

    function setLabwc(key, value, quiet = true) {
        enqueue(["labwc-set", key, String(value)], "labwc", "labwc-" + key, quiet);
    }

    function setKeyboardLayout(layout) {
        const value = String(layout || "us").toLowerCase();
        SettingsService.keyboardLayout = value;
        ShellState.kbLayout = ShellState.formatLayout(value);
        SettingsService.save();
        setLabwc("keyboardLayout", value, true);
    }

    function cycleKeyboardLayout() {
        const layouts = SettingsService.keyboardLayouts.split(",").map(item => item.trim().toLowerCase()).filter(item => item.length > 0);
        if (layouts.length === 0) return;
        const index = layouts.indexOf(SettingsService.keyboardLayout.toLowerCase());
        setKeyboardLayout(layouts[(index + 1) % layouts.length]);
    }

    function setGamingMode(enabled, automatic = false, rule = null) {
        if (!automatic) GamingService.manualOverride();
        return enqueue(["gaming-mode", enabled ? "1" : "0", (rule ? rule.performance : SettingsService.gamingPerformanceProfile) ? "1" : "0", (rule ? rule.tearing : SettingsService.gamingAllowTearing) ? "1" : "0", rule?.outputProfile || ""], "gaming", "gaming", false);
    }

    function checkUpdates() {
        enqueue(["update-check"], "updates", "updates", false);
    }

    Process {
        id: capabilitiesReader
        running: SettingsService.initialized
        command: [
            Quickshell.shellPath("weylume-native"), "startup-data",
            String(SettingsService.previewCacheLimit), String(SettingsService.previewMaxAgeHours)
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const envelope = root.parseEnvelope(text);
                if (envelope.ok && envelope.data) {
                    const data = envelope.data;
                    root.capabilities = data.capabilities || ({ commands: ({}) });
                    root.applyLabwc(data.labwc);
                    root.applyNetwork(data.network);
                    root.powerProfile = data.system?.powerProfile || "balanced";
                    root.inhibitors = data.system?.inhibitors || [];
                    root.inhibitorsUnknown = Boolean(data.system?.inhibitorsUnknown || data.system?.error);
                    root.sessionCapabilities = data.system || ({});
                    root.ready = true;
                    if (StateStore.repaired.length > 0)
                        OsdService.show("Recovered configuration", StateStore.repaired.join(", "), "dialog-warning", -1, false);
                    SettingsService.gamingMode = false;
                    if (data.outputRecovery?.error) OsdService.show("Display recovery", data.outputRecovery.error, "dialog-warning", -1, true);
                    if (data.recovery?.error) OsdService.show("Gaming recovery", data.recovery.error, "dialog-warning", -1, true);
                } else {
                    root.lastError = envelope.message || "Capability detection failed";
                }
            }
        }
    }

    Process {
        id: networkReader
        command: [Quickshell.shellPath("weylume-native"), "network-data"]
        stdout: StdioCollector {
            onStreamFinished: {
                const envelope = root.parseEnvelope(text);
                if (envelope.ok) root.applyNetwork(envelope.data);
                else root.lastError = envelope.message;
            }
        }
        onExited: {
            root.networkLoading = false;
            if (root.networkRefreshPending) {
                root.networkRefreshPending = false;
                Qt.callLater(root.refreshNetwork);
            }
        }
    }

    Connections {
        target: SystemData
        function onNetworkChanged() { if (root.ready) networkDebounce.restart(); }
    }

    Timer { id: networkDebounce; interval: 220; onTriggered: root.refreshNetwork() }

    Process {
        id: labwcReader
        command: [Quickshell.shellPath("weylume-native"), "labwc-data"]
        stdout: StdioCollector {
            onStreamFinished: {
                const envelope = root.parseEnvelope(text);
                if (envelope.ok) root.applyLabwc(envelope.data);
            }
        }
    }

    Process {
        id: systemReader
        command: [Quickshell.shellPath("weylume-native"), "system-status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const envelope = root.parseEnvelope(text);
                if (!envelope.ok || !envelope.data) return;
                root.powerProfile = envelope.data.powerProfile || "balanced";
                root.inhibitors = envelope.data.inhibitors || [];
                root.inhibitorsUnknown = Boolean(envelope.data.inhibitorsUnknown || envelope.data.error);
                root.sessionCapabilities = envelope.data;
            }
        }
    }

    Process {
        id: actionProcess
        property bool quiet: false
        property string input: ""
        onStarted: { if (input) write(input); input = ""; stdinEnabled = false; }
        stdout: StdioCollector { onStreamFinished: root.actionOutput = text }
        onExited: (exitCode, exitStatus) => {
            const domain = root.activeDomain;
            const envelope = root.parseEnvelope(root.actionOutput);
            const success = Boolean(envelope.ok) && exitCode === 0;
            const message = envelope.message || (success ? "Done" : "Action failed");
            root.lastMessage = success ? message : "";
            root.lastError = success ? "" : message;
            if (domain === "network") root.refreshNetwork();
            if (domain === "labwc" && envelope.data) root.applyLabwc(envelope.data);
            else if (domain === "labwc") root.refreshLabwc();
            if (domain === "gaming" && success) {
                SettingsService.gamingMode = Boolean(envelope.data?.gaming);
                if (envelope.data?.labwc) root.applyLabwc(envelope.data.labwc);
                root.powerProfile = envelope.data?.profile || root.powerProfile;
            }
            if (domain === "power" && success) {
                root.powerProfile = envelope.data?.profile || root.powerProfile;
                root.refreshSystem();
            }
            if (domain === "updates" && success) {
                root.updateCount = Number(envelope.data?.count ?? 0);
                root.updates = envelope.data?.updates || [];
            }
            if (!success || (!quiet && domain !== "labwc")) {
                const title = domain === "screenshot" ? (success ? "Screenshot captured" : "Screenshot failed")
                    : domain === "updates" ? "System updates" : success ? "Action complete" : "Action failed";
                OsdService.show(title, message, success ? "dialog-information" : "dialog-error", -1, !success);
            }
            root.actionFinished(domain, success, message, envelope.data || null);
            root.activeDomain = "";
            Qt.callLater(root.startNextAction);
        }
    }
}
