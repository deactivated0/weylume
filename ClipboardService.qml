pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    property var history: []
    property bool loaded: false
    property double generation: 0
    property bool savePending: false
    property int restartDelay: 2000
    property real watcherStartedAt: 0
    readonly property bool watchEnabled: root.loaded && SettingsService.initialized
        && SettingsService.clipboardEnabled
        && SystemService.ready
        && SystemService.has("wl-paste")

    function sensitive(text) {
        if (!SettingsService.clipboardSensitiveFilter) return false;
        if (text.length > 32768) return true;
        const sample = text.slice(0, 4096);
        return /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/i.test(sample)
            || /(?:password|passwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token)\s*[:=]/i.test(sample)
            || /\b(?:ghp|github_pat|sk_live|sk_test)_[A-Za-z0-9_-]{16,}\b/.test(sample);
    }

    function add(text) {
        text = String(text || "");
        if (!text || sensitive(text)) return;
        const existing = root.history.find(item => item.text === text);
        const isPinned = Boolean(existing?.pinned);
        const item = {
            type: "text",
            text: text,
            timestamp: Date.now(),
            pinned: isPinned
        };
        const pinned = isPinned ? [item] : [];
        const normal = isPinned ? [] : [item];
        const old = root.history;
        for (let i = 0; i < old.length; ++i) {
            const entry = old[i];
            if (entry.text === text) continue;
            if (entry.pinned) pinned.push(entry);
            else normal.push(entry);
        }
        const maxNormal = Math.max(0, SettingsService.clipboardHistoryLimit - pinned.length);
        if (normal.length > maxNormal) normal.length = maxNormal;
        root.history = pinned.concat(normal).sort((a, b) => Number(b.timestamp) - Number(a.timestamp));
        saveTimer.restart();
    }

    function addImage(message) {
        if (!SettingsService.clipboardImagesEnabled || !message.path || !message.hash) {
            return;
        }
        const existing = root.history.find(item => item.type === "image" && item.hash === message.hash);
        const isPinned = Boolean(existing?.pinned);
        const item = {
            type: "image", path: String(message.path), mime: String(message.mime || "image/png"),
            hash: String(message.hash), timestamp: Date.now(), pinned: isPinned
        };
        const pinned = isPinned ? [item] : [];
        const normal = isPinned ? [] : [item];
        const old = root.history;
        for (let i = 0; i < old.length; ++i) {
            const entry = old[i];
            if (entry.type === "image" && entry.hash === item.hash) continue;
            if (entry.pinned) pinned.push(entry);
            else normal.push(entry);
        }
        const maxNormal = Math.max(0, SettingsService.clipboardHistoryLimit - pinned.length);
        if (normal.length > maxNormal) normal.length = maxNormal;
        root.history = pinned.concat(normal).sort((a, b) => Number(b.timestamp) - Number(a.timestamp));
        saveTimer.restart();
    }

    function removeAt(index) {
        if (index < 0 || index >= root.history.length) return;
        root.history = root.history.filter((_, itemIndex) => itemIndex !== index);
        saveTimer.restart();
    }

    function togglePin(index) {
        if (index < 0 || index >= root.history.length) return;
        const next = root.history.slice();
        const item = Object.assign({}, next[index]);
        item.pinned = !item.pinned;
        next[index] = item;
        root.history = next;
        root.save();
    }

    function clear() {
        root.history = root.history.filter(item => item.pinned);
        saveTimer.restart();
    }

    function copy(text) {
        const encoded = Qt.btoa(unescape(encodeURIComponent(String(text || ""))));
        SystemService.enqueue(["clipboard-copy", encoded], "clipboard", "clipboard-copy", true);
    }

    function copyItem(item) {
        if (item?.type === "image")
            SystemService.enqueue(["clipboard-copy-image", item.path, item.mime || "image/png"], "clipboard", "clipboard-copy", true);
        else copy(item?.text || "");
    }

    function save() {
        if (!root.loaded) return;
        if (writer.running) { root.savePending = true; return; }
        root.savePending = false;
        writer.payload = JSON.stringify({ generation: root.generation, history: root.history });
        writer.stdinEnabled = true;
        writer.running = true;
    }

    Process {
        id: writer
        property string payload: ""
        property var result: null
        command: [Quickshell.shellPath("weylume-native"), "clipboard-store"]
        onStarted: {
            result = null;
            write(payload);
            payload = "";
            stdinEnabled = false;
        }
        stdout: StdioCollector {
            onStreamFinished: { try { writer.result = JSON.parse(text); } catch (error) {} }
        }
        onExited: {
            if (result?.ok) {
                root.generation = Number(result.data.generation);
                if (root.savePending) Qt.callLater(root.save);
            } else OsdService.show("Clipboard history", result?.message || "Could not save history", "dialog-warning", -1, true);
        }
    }

    FileView {
        id: store
        path: StateStore.ready && SettingsService.initialized ? Quickshell.shellPath("clipboard_history.json") : ""
        onLoaded: {
            try {
                const parsed = JSON.parse(text() || "{}");
                if (Array.isArray(parsed.history)) {
                    root.generation = Number(parsed.generation || 0);
                    const valid = parsed.history
                        .filter(item => item && ((item.type === "image" && typeof item.path === "string")
                            || (typeof item.text === "string" && !root.sensitive(item.text))))
                        ;
                    const pins = valid.filter(item => item.pinned);
                    root.history = pins.concat(valid.filter(item => !item.pinned).slice(0, Math.max(0, SettingsService.clipboardHistoryLimit - pins.length)))
                        .sort((a, b) => Number(b.timestamp) - Number(a.timestamp));
                }
            } catch (error) {
                root.history = [];
            }
            root.loaded = true;
        }
    }

    Process {
        id: watcher
        command: ["wl-paste", "--watch", Quickshell.shellPath("weylume-native"), "clipboard-capture"]
        running: root.watchEnabled
        stdout: SplitParser {
            onRead: line => {
                try {
                    const message = JSON.parse(line);
                    if (message.type === "text") root.add(message.text);
                    else if (message.type === "image") root.addImage(message);
                    else if (message.type === "clipboard-error") OsdService.show("Clipboard", message.message, "dialog-warning", -1, true);
                } catch (error) {}
            }
        }
        onStarted: root.watcherStartedAt = Date.now()
        onExited: {
            if (root.watcherStartedAt > 0 && Date.now() - root.watcherStartedAt >= 30000) root.restartDelay = 2000;
            root.watcherStartedAt = 0;
            if (root.watchEnabled) {
                restartTimer.interval = root.restartDelay;
                root.restartDelay = Math.min(60000, root.restartDelay * 2);
                restartTimer.restart();
            }
        }
    }

    Timer {
        id: restartTimer
        interval: 2000
        onTriggered: {
            // Do not assign Process.running here: doing so would destroy its
            // declarative binding. Re-evaluate the binding after backoff.
            if (root.watchEnabled && !watcher.running) watcher.running = Qt.binding(() => root.watchEnabled);
        }
    }
    Timer { id: saveTimer; interval: 300; onTriggered: root.save() }
}
