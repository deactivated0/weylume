pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire

Scope {
    id: root

    property var pinnedIds: ["sys-notifications", "sys-ethernet", "sys-wifi", "sys-bluetooth", "sys-brightness", "sys-audio"]
    property var hiddenIds: []

    readonly property var wifiDevice: {
        const devices = (Networking.devices && Networking.devices.values) ? Networking.devices.values : [];
        for (let i = 0; i < devices.length; i++) if (devices[i].type === DeviceType.Wifi) return devices[i];
        return null;
    }
    readonly property var wiredDevice: {
        const devices = (Networking.devices && Networking.devices.values) ? Networking.devices.values : [];
        for (let i = 0; i < devices.length; i++) if (devices[i].type === DeviceType.Wired) return devices[i];
        return null;
    }

    FileView {
        id: store
        path: StateStore.ready ? Quickshell.shellPath("tray_config.json") : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const str = text();
                if (str && str.trim().length > 0) {
                    const parsed = JSON.parse(str);
                    if (parsed) {
                        if (Array.isArray(parsed.pinned)) root.pinnedIds = parsed.pinned;
                        if (Array.isArray(parsed.hidden)) root.hiddenIds = parsed.hidden;
                    }
                }
            } catch (e) {
                console.warn("TrayConfig load error:", e);
            }
        }
    }

    function save() {
        try {
            store.setText(JSON.stringify({
                pinned: root.pinnedIds,
                hidden: root.hiddenIds
            }, null, 2));
        } catch (e) {
            console.warn("TrayConfig save error:", e);
        }
    }

    function resolveAppTitle(it) {
        if (!it) return "Application";
        let t = (it.title || "").trim();
        if (t.length > 0 && t !== "Tray App" && t !== "Application" && t !== "System Tray") return t;
        let tip = (it.tooltip || "").trim();
        if (tip.length > 0 && tip !== "Tray App") return tip;
        const idLower = (it.id || "").toLowerCase();
        if (idLower.includes("discord-development") || idLower.includes("discorddevelopment")) return "Discord Development";
        if (idLower.includes("discord-canary") || idLower.includes("discordcanary")) return "Discord Canary";
        if (idLower.includes("discord-ptb") || idLower.includes("discordptb")) return "Discord PTB";
        if (idLower.includes("discord")) return "Discord";
        if (idLower.includes("vesktop")) return "Vesktop";
        if (idLower.includes("steam")) return "Steam";
        if (idLower.includes("easyeffects")) return "Easy Effects";
        if (it.id) {
            let base = it.id.split("_status_icon")[0].split("_snix_")[0].replace(/[-_]/g, " ").trim();
            if (base.length > 0 && !base.startsWith("app tray")) {
                return base.split(" ").map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(" ");
            }
        }
        return "Application";
    }

    function getAllItems() {
        let items = [];

        // 1. Notifications
        items.push({
            id: "sys-notifications",
            isSystem: true,
            title: "Notifications",
            icon: "preferences-desktop-notification-bell",
            fallback: "⌁",
            active: false,
            activate: () => ShellState.toggleNotif(undefined, "notifications"),
            secondaryActivate: () => ShellState.toggleNotif(undefined, "notifications"),
            display: (win, x, y) => ShellState.toggleNotif(undefined, "notifications")
        });

        // 2. Ethernet
        items.push({
            id: "sys-ethernet",
            isSystem: true,
            title: "Ethernet: " + ((root.wiredDevice?.connected ?? false) ? "Connected" : "Disconnected"),
            icon: (root.wiredDevice?.connected ?? false) ? "network-wired-activated" : "network-wired-disconnected",
            fallback: (root.wiredDevice?.connected ?? false) ? "🖧" : "▱",
            active: root.wiredDevice?.connected ?? false,
            activate: () => ShellState.toggleQuick(),
            secondaryActivate: () => ShellState.toggleQuick(),
            display: (win, x, y) => ShellState.toggleQuick()
        });

        // 3. Wi-Fi
        items.push({
            id: "sys-wifi",
            isSystem: true,
            title: "Wi-Fi: " + ((root.wifiDevice?.connected ?? false) ? "Connected" : "Disconnected"),
            icon: (root.wifiDevice?.connected ?? false) ? "network-wireless-connected" : "network-wireless-disconnected",
            fallback: (root.wifiDevice?.connected ?? false) ? "📶" : "⌁",
            active: root.wifiDevice?.connected ?? false,
            activate: () => ShellState.toggleQuick(),
            secondaryActivate: () => ShellState.toggleQuick(),
            display: (win, x, y) => ShellState.toggleQuick()
        });

        // 4. Bluetooth
        items.push({
            id: "sys-bluetooth",
            isSystem: true,
            title: "Bluetooth",
            icon: "preferences-bluetooth",
            fallback: "ᛒ",
            active: Bluetooth.defaultAdapter?.enabled ?? false,
            activate: () => ShellState.toggleQuick(),
            secondaryActivate: () => ShellState.toggleQuick(),
            display: (win, x, y) => ShellState.toggleQuick()
        });

        // 5. Brightness
        items.push({
            id: "sys-brightness",
            isSystem: true,
            title: "Brightness (" + Math.round(ShellState.brightness * 100) + "%)",
            icon: "brightness-high-symbolic",
            fallback: "☀",
            active: false,
            activate: () => ShellState.toggleQuick(),
            secondaryActivate: () => ShellState.toggleQuick(),
            wheel: dir => ShellState.adjustBrightness(dir * 0.05),
            display: (win, x, y) => ShellState.toggleQuick()
        });

        // 6. Volume (EarTrumpet Style Audio Mixer)
        const vol = Math.round((Pipewire.defaultAudioSink?.audio?.volume ?? 0) * 100);
        const isMuted = Pipewire.defaultAudioSink?.audio?.muted ?? false;
        items.push({
            id: "sys-audio",
            isSystem: true,
            title: isMuted ? "Volume (Muted)" : ("Volume (" + vol + "%)"),
            icon: isMuted
                ? "audio-volume-muted"
                : (vol > 66 ? "audio-volume-high" : (vol > 33 ? "audio-volume-medium" : (vol > 0 ? "audio-volume-low" : "audio-volume-muted"))),
            fallback: isMuted ? "🔇" : "🔊",
            active: false,
            activate: () => ShellState.toggleMixer(ShellState.popupScreenName),
            secondaryActivate: () => ShellState.toggleMute(),
            wheel: dir => ShellState.adjustVolume(dir * 0.02),
            display: (win, x, y) => ShellState.toggleMixer(ShellState.popupScreenName)
        });

        // 7. Keyboard Layout
        items.push({
            id: "sys-language",
            isSystem: true,
            title: "Keyboard Layout: " + ShellState.kbLayout,
            icon: "",
            fallback: ShellState.kbLayout,
            active: false,
            activate: () => ShellState.toggleLayout(),
            secondaryActivate: () => ShellState.toggleLayout(),
            display: (win, x, y) => ShellState.toggleLayout()
        });

        // 8. App Tray items
        const trayItems = SystemTray.items.values;
        for (let i = 0; i < trayItems.length; i++) {
            const it = trayItems[i];
            const cleanTitle = root.resolveAppTitle(it);
            items.push({
                id: it.id || it.title || it.tooltip || ("app-tray-" + i),
                isSystem: false,
                title: cleanTitle,
                fallback: cleanTitle.charAt(0).toUpperCase(),
                icon: it.icon,
                rawItem: it,
                onlyMenu: it.onlyMenu,
                activate: () => it.activate(),
                secondaryActivate: () => it.secondaryActivate(),
                display: (win, x, y) => it.display(win, x, y)
            });
        }

        return items;
    }

    function isPinned(item) {
        if (!item || !item.id) return false;
        if (root.hiddenIds.includes(item.id)) return false;
        return root.pinnedIds.includes(item.id);
    }

    function pin(item) {
        if (!item || !item.id) return;
        root.hiddenIds = root.hiddenIds.filter(x => x !== item.id);
        root.pinnedIds = root.pinnedIds.filter(x => x !== item.id).concat([item.id]);
        save();
    }

    function unpin(item) {
        if (!item || !item.id) return;
        root.pinnedIds = root.pinnedIds.filter(x => x !== item.id);
        if (!root.hiddenIds.includes(item.id)) {
            root.hiddenIds = root.hiddenIds.concat([item.id]);
        }
        save();
    }

    function toggle(item) {
        if (isPinned(item)) unpin(item);
        else pin(item);
    }

    function movePinned(from, to) {
        if (from === to) return;
        const visible = root.pinnedItems;
        if (from < 0 || to < 0 || from >= visible.length || to >= visible.length) return;

        let current = visible.map(it => it.id);
        const [moved] = current.splice(from, 1);
        current.splice(to, 0, moved);

        for (let i = 0; i < root.pinnedIds.length; i++) {
            const id = root.pinnedIds[i];
            if (!current.includes(id)) current.push(id);
        }

        root.pinnedIds = current;
        save();
    }

    function getVisibleItems(all) {
        let map = {};
        for (let i = 0; i < all.length; i++) map[all[i].id] = all[i];

        let visible = [];
        for (let i = 0; i < root.pinnedIds.length; i++) {
            const id = root.pinnedIds[i];
            if (map[id] && !root.hiddenIds.includes(id)) {
                visible.push(map[id]);
                delete map[id];
            }
        }
        for (let k in map) {
            if (isPinned(map[k])) visible.push(map[k]);
        }
        return visible;
    }

    function getHiddenItems(all) {
        return all.filter(item => !isPinned(item));
    }

    readonly property var allItems: getAllItems()
    readonly property var pinnedItems: {
        const _p = root.pinnedIds;
        const _h = root.hiddenIds;
        return getVisibleItems(allItems);
    }
    readonly property var hiddenItems: {
        const _p = root.pinnedIds;
        const _h = root.hiddenIds;
        return getHiddenItems(allItems);
    }
}
