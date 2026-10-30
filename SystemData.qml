pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    signal networkChanged()
    signal prepareSleep(bool sleeping)
    function setRecording(active) { if (backend.running) backend.write(active ? "recording on\n" : "recording off\n"); }
    property bool backendReady: false
    property double gammaSerial: 0
    property var gammaRequests: ({})

    function writeGamma(name, value, finished) {
        if (!root.backendReady || !backend.running || !isFinite(value)) return false;
        const id = ++root.gammaSerial;
        root.gammaRequests[id] = finished;
        backend.write("gamma " + JSON.stringify([id, name, value]) + "\n");
        return true;
    }

    function finishGamma(message) {
        const finished = root.gammaRequests[message.id];
        if (!finished) return;
        delete root.gammaRequests[message.id];
        finished(Boolean(message.ok));
    }

    function cancelGamma() {
        const pending = root.gammaRequests;
        root.gammaRequests = ({});
        for (const id of Object.keys(pending)) pending[id](false);
    }

    property int restartDelay: 3000

    property string uptime: "—"
    property string cpuModel: "AMD Ryzen 5 3600"
    property string cpuFrequency: "—"
    property string cpuTemperature: "—"
    property real cpuUsage: 0
    property string gpuModel: "AMD Radeon RX 590 Series"
    property string gpuTemperature: "—"
    property real gpuUsage: 0
    property string memoryUsed: "—"
    property string memoryTotal: "23.4 GiB"
    property real memoryUsage: 0
    property string networkInterface: "enp5s0"
    property string networkReceive: "0.0 MB/s"
    property string networkSend: "0.0 MB/s"
    property var drives: []
    property bool drivesStale: false
    property var desktopItems: []

    function requestDrives() {
        if (backend.running) backend.write("drives\nrefresh\n");
    }

    function updateInterval() {
        const active = ShellState.sidebarVisible || ShellState.quickOpen;
        const interval = active ? SettingsService.metricsActiveInterval : SettingsService.metricsIdleInterval;
        if (backend.running) backend.write("interval " + interval + "\n");
    }

    function areDesktopItemsEqual(a, b) {
        if (a === b) return true;
        if (!a || !b || a.length !== b.length) return false;
        for (let i = 0; i < a.length; i++) {
            const x = a[i], y = b[i];
            if (!x || !y) return false;
            if (x.path !== y.path || x.name !== y.name || x.icon !== y.icon || x.thumbnail !== y.thumbnail) {
                return false;
            }
        }
        return true;
    }

    function areDrivesEqual(a, b) {
        if (a === b) return true;
        if (!a || !b || a.length !== b.length) return false;
        for (let i = 0; i < a.length; i++) {
            const x = a[i], y = b[i];
            if (!x || !y) return false;
            if (x.name !== y.name || x.used !== y.used || x.total !== y.total || x.mount !== y.mount) return false;
        }
        return true;
    }

    function applyMetrics(data) {
        if (!data || !data.cpu || !data.gpu || !data.memory || !data.network) return;
        const up = data.uptime ?? "—";
        if (root.uptime !== up) root.uptime = up;

        const cm = data.cpu.model ?? "—";
        if (root.cpuModel !== cm) root.cpuModel = cm;

        const cf = data.cpu.frequency ?? "—";
        if (root.cpuFrequency !== cf) root.cpuFrequency = cf;

        const ct = data.cpu.temperature ?? "—";
        if (root.cpuTemperature !== ct) root.cpuTemperature = ct;

        const cu = Number(data.cpu.usage ?? 0);
        if (root.cpuUsage !== cu) root.cpuUsage = cu;

        const gm = data.gpu.model ?? "—";
        if (root.gpuModel !== gm) root.gpuModel = gm;

        const gt = data.gpu.temperature ?? "—";
        if (root.gpuTemperature !== gt) root.gpuTemperature = gt;

        const gu = Number(data.gpu.usage ?? 0);
        if (root.gpuUsage !== gu) root.gpuUsage = gu;

        const mu = data.memory.used ?? "—";
        if (root.memoryUsed !== mu) root.memoryUsed = mu;

        const mt = data.memory.total ?? "—";
        if (root.memoryTotal !== mt) root.memoryTotal = mt;

        const mus = Number(data.memory.usage ?? 0);
        if (root.memoryUsage !== mus) root.memoryUsage = mus;

        const ni = data.network.interface ?? "enp5s0";
        if (root.networkInterface !== ni) root.networkInterface = ni;

        const nr = data.network.receive ?? "0 B/s";
        if (root.networkReceive !== nr) root.networkReceive = nr;

        const ns = data.network.send ?? "0 B/s";
        if (root.networkSend !== ns) root.networkSend = ns;

        if (Array.isArray(data.drives) && !root.areDrivesEqual(root.drives, data.drives)) {
            root.drives = data.drives;
        }
    }

    function handleLine(line) {
        try {
            const message = JSON.parse(line);
            if (message.type === "metrics") root.applyMetrics(message.data);
            else if (message.type === "desktop" && Array.isArray(message.items)) {
                if (!root.areDesktopItemsEqual(root.desktopItems, message.items)) {
                    root.desktopItems = message.items;
                }
            }
            else if (message.type === "network-changed") root.networkChanged();
            else if (message.type === "drives") {
                const stale = Boolean(message.stale);
                if (root.drivesStale !== stale) root.drivesStale = stale;
                if (Array.isArray(message.data) && !root.areDrivesEqual(root.drives, message.data)) {
                    root.drives = message.data;
                }
            }
            else if (message.type === "prepare-sleep") root.prepareSleep(Boolean(message.sleeping));
            else if (message.type === "recording-warning") OsdService.show("Recorder",message.message,"dialog-warning",-1,true);
            else if (message.type === "gamma") root.finishGamma(message);
            root.restartDelay = 3000;
        } catch (error) {
            console.warn("weylume backend:", error);
        }
    }

    Process {
        id: backend
        command: [Quickshell.shellPath("weylume-native"), "backend"]
        stdinEnabled: true
        running: true
        stdout: SplitParser { onRead: data => root.handleLine(data) }
        onStarted: {
            root.backendReady = true;
            root.updateInterval();
            if (RecorderService.recording) root.setRecording(true);
        }
        onExited: {
            root.backendReady = false;
            root.cancelGamma();
            restartTimer.interval = root.restartDelay;
            restartTimer.restart();
            root.restartDelay = Math.min(60000, root.restartDelay * 2);
        }
    }

    Connections {
        target: SettingsService
        function onMetricsActiveIntervalChanged() { root.updateInterval(); }
        function onMetricsIdleIntervalChanged() { root.updateInterval(); }
    }

    Connections {
        target: ShellState
        function onSidebarVisibleChanged() { root.updateInterval(); }
        function onQuickOpenChanged() { root.updateInterval(); }
    }

    Timer {
        id: restartTimer
        interval: 3000
        onTriggered: if (!backend.running) backend.running = true
    }
}
