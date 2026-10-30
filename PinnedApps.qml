pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    readonly property var defaultPins: [
        { label: "Helium", icon: "helium", fallback: "H", command: ["helium"], appIds: ["helium", "helium-browser"] },
        { label: "Files", icon: "system-file-manager", fallback: "D", command: ["pcmanfm-qt", Quickshell.env("HOME")], appIds: ["pcmanfm-qt", "pcmanfm"] },
        { label: "Kitty", icon: "kitty", fallback: ">_", command: ["kitty"], appIds: ["kitty"] },
        { label: "Settings", icon: "weylume-settings", fallback: "S", command: ["qs", "-c", "weylume", "ipc", "call", "shell", "toggleSettings"], appIds: ["weylume-settings", "org.quickshell"] },
        { label: "Steam", icon: "steam", fallback: "S", command: ["steam"], appIds: ["steam", "com.valvesoftware.steam"] },
        { label: "Discord", icon: "discord", fallback: "D", command: ["discord"], appIds: ["discord"] },
        { label: "Discord PTB", icon: "discord-ptb", fallback: "P", command: ["discord-ptb"], appIds: ["discord-ptb"] },
        { label: "Discord Canary", icon: "discord-canary", fallback: "C", command: ["discord-canary"], appIds: ["discord-canary"] },
        { label: "Discord Development", icon: "discord-development", fallback: "D+", command: ["discord-development"], appIds: ["discord-development"] },
        { label: "Spotify", icon: "spotify-launcher", fallback: "♪", command: ["spotify-launcher"], appIds: ["spotify-launcher", "spotify", "Spotify"] }
    ]

    property var items: defaultPins
    readonly property var unpinnedAppGroups: getUnpinnedAppGroups()

    function getUnpinnedAppGroups() {
        const windows = ToplevelManager.toplevels.values;
        let groups = [];
        let map = Object.create(null);
        for (let i = 0; i < windows.length; i++) {
            const w = windows[i];
            if (PinnedApps.isPinned(w.appId, w.title)) continue;
            const key = PinnedApps.appGroupKey(w, i);
            if (!map[key]) {
                map[key] = {
                    key: key,
                    appId: w.appId,
                    title: w.title,
                    primaryWindow: w,
                    windows: [w]
                };
                groups.push(map[key]);
            } else {
                map[key].windows.push(w);
                if (w.activated) map[key].primaryWindow = w;
            }
        }
        return groups;
    }

    function discordFlavor(values) {
        const list = Array.isArray(values) ? values : [values];
        let hasDiscord = false;
        for (let i = 0; i < list.length; ++i) {
            const value = String(list[i] || "").toLowerCase();
            if (!value.includes("discord")) continue;
            hasDiscord = true;
            if (value.includes("canary")) return "canary";
            if (value.includes("ptb")) return "ptb";
            if (value.includes("development") || value.includes("discord-dev") || value.includes("discorddev")) return "development";
        }
        return hasDiscord ? "stable" : null;
    }

    function candidateDiscordFlavor(values) {
        const list = Array.isArray(values) ? values : [values];
        const appId = String(list[0] || "").toLowerCase();
        const title = list.slice(1);
        const idFlavor = discordFlavor(appId);
        if (idFlavor) {
            const titleFlavor = discordFlavor(title);
            return idFlavor === "stable" && titleFlavor && titleFlavor !== "stable"
                ? titleFlavor : idFlavor;
        }
        return appId.length === 0 ? discordFlavor(title) : null;
    }

    function appGroupKey(window, index) {
        const appId = String(window?.appId || "").toLowerCase();
        const title = String(window?.title || "").toLowerCase();
        const flavor = candidateDiscordFlavor([appId, title]);
        if (flavor) return "discord:" + flavor;
        return appId || title || ("win_" + index);
    }

    function cleanAppStrings(values) {
        const list = Array.isArray(values) ? values : [values];
        const res = [];
        for (let i = 0; i < list.length; ++i) {
            const v = String(list[i] || "").trim().toLowerCase();
            if (v.length > 0) res.push(v);
        }
        return res;
    }

    function matchesApp(candidateValues, targetValues) {
        const candidates = cleanAppStrings(candidateValues);
        const targets = cleanAppStrings(targetValues);
        if (candidates.length === 0 || targets.length === 0) return false;

        const candidateFlavor = candidateDiscordFlavor(candidates);
        const targetFlavor = discordFlavor(targets);
        if (candidateFlavor || targetFlavor)
            return candidateFlavor !== null && candidateFlavor === targetFlavor;

        for (let c = 0; c < candidates.length; ++c) {
            const cand = candidates[c];
            for (let t = 0; t < targets.length; ++t) {
                const target = targets[t];
                if (cand === target || (Math.min(cand.length, target.length) > 2
                    && (cand.includes(target) || target.includes(cand)))) {
                    return true;
                }
            }
        }
        return false;
    }

    function loadPinned() {
        try {
            const str = store.text();
            if (str && str.trim().length > 0) {
                const parsed = JSON.parse(str);
                if (Array.isArray(parsed) && parsed.length > 0) {
                    root.items = parsed;
                    return;
                }
            }
        } catch (e) {
            console.warn("PinnedApps load error:", e);
        }
        save(root.defaultPins);
    }

    function reload() {
        loadPinned();
    }

    FileView {
        id: store
        path: StateStore.ready ? Quickshell.shellPath("pinned.json") : ""
        watchChanges: true
        onFileChanged: root.loadPinned()
        onLoaded: root.loadPinned()
    }

    function save(newItems) {
        root.items = newItems;
        try {
            store.setText(JSON.stringify(newItems, null, 2));
        } catch (e) {
            console.warn("PinnedApps save error:", e);
        }
    }

    onItemsChanged: {
        for (let i = 0; i < items.length; i++) {
            const pin = items[i];
            const ids = pin.appIds || (pin.appId ? [pin.appId] : []);
            pin._lcIds = ids.map(x => String(x || "").trim().toLowerCase()).filter(x => x.length > 0);
            pin._lcLabel = String(pin.label || "").trim().toLowerCase();
            pin._targets = pin._lcIds.concat(pin._lcLabel ? [pin._lcLabel] : []);
            pin._flavor = discordFlavor(pin._targets);
        }
    }

    function isPinned(appId, label) {
        const idLower = String(appId || "").trim().toLowerCase();
        const labelLower = String(label || "").trim().toLowerCase();
        const candList = (idLower && labelLower) ? [idLower, labelLower] : (idLower ? [idLower] : (labelLower ? [labelLower] : []));
        if (candList.length === 0) return false;
        const candFlavor = candidateDiscordFlavor(candList);

        for (let i = 0; i < items.length; i++) {
            const pin = items[i];
            if (!pin._targets) {
                const ids = pin.appIds || (pin.appId ? [pin.appId] : []);
                pin._lcIds = ids.map(x => String(x || "").trim().toLowerCase()).filter(x => x.length > 0);
                pin._lcLabel = String(pin.label || "").trim().toLowerCase();
                pin._targets = pin._lcIds.concat(pin._lcLabel ? [pin._lcLabel] : []);
                pin._flavor = discordFlavor(pin._targets);
            }
            if (labelLower && pin._lcLabel && labelLower === pin._lcLabel) return true;
            if (candFlavor || pin._flavor) {
                if (candFlavor !== null && candFlavor === pin._flavor) return true;
            } else {
                for (let c = 0; c < candList.length; c++) {
                    const cand = candList[c];
                    for (let t = 0; t < pin._targets.length; t++) {
                        const target = pin._targets[t];
                        if (cand === target || (Math.min(cand.length, target.length) > 2 && (cand.includes(target) || target.includes(cand)))) {
                            return true;
                        }
                    }
                }
            }
        }
        return false;
    }

    function pin(app) {
        if (!app) return;
        const id = (app.appId || app.icon || app.label || "").toLowerCase();
        const label = app.label || app.appId || "Application";
        if (isPinned(app.appId, label)) return;

        const current = items.slice();
        const icon = app.icon || "application-x-executable";
        const cmd = (app.command && app.command.length > 0)
            ? app.command
            : (app.appId ? [app.appId] : [label.toLowerCase()]);
        const appIds = app.appIds || (app.appId ? [app.appId] : []);
        const fallback = label.charAt(0).toUpperCase() || "□";

        current.push({
            label: label,
            icon: icon,
            fallback: fallback,
            command: cmd,
            appIds: appIds
        });
        save(current);
    }

    function unpin(appId, label) {
        const id = (appId || "").toLowerCase();
        const lbl = (label || "").toLowerCase();
        const targetValues = [id, lbl];
        const current = items.filter(pin => {
            const ids = pin.appIds || (pin.appId ? [pin.appId] : []);
            if (matchesApp(ids.concat(pin.label || ""), targetValues)) return false;
            if (lbl && pin.label && pin.label.toLowerCase() === lbl) return false;
            return true;
        });
        save(current);
    }

    function move(from, to) {
        if (isNaN(from) || isNaN(to)) return;
        const f = Math.floor(from);
        const t = Math.floor(to);
        if (f === t || f < 0 || t < 0 || f >= items.length || t >= items.length) return;
        const current = items.slice();
        const [moved] = current.splice(f, 1);
        current.splice(t, 0, moved);
        save(current);
    }

    function launchPinIndex(index) {
        if (index < 0 || index >= items.length) return;
        const pin = items[index];
        if (!pin) return;

        const appIds = pin.appIds || (pin.appId ? [pin.appId] : [pin.label]);
        const windows = ToplevelManager.toplevels.values;
        let matches = [];
        for (let i = 0; i < windows.length; i++) {
            const w = windows[i];
            if (matchesApp([w.appId, w.title], appIds.concat(pin.label || ""))) matches.push(w);
        }

        if (matches.length === 0) {
            if (pin.command && pin.command.length > 0) Quickshell.execDetached(pin.command);
            return;
        }

        if (matches.length === 1) {
            const win = matches[0];
            if (win.activated && !ShellState.isDraggingFile) win.minimized = true;
            else {
                if (win.minimized) win.minimized = false;
                win.activate();
            }
            return;
        }

        let activeIdx = -1;
        for (let i = 0; i < matches.length; i++) {
            if (matches[i].activated) {
                activeIdx = i;
                break;
            }
        }

        const nextIdx = (activeIdx + 1) % matches.length;
        const nextWin = matches[nextIdx];
        if (nextWin.minimized) nextWin.minimized = false;
        nextWin.activate();
    }
}
