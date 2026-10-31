pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    readonly property var defaultFavorites: []

    property var items: defaultFavorites

    function isAppInstalled(fav) {
        if (!fav) return false;
        const lbl = String(fav.label || fav.name || "").toLowerCase();
        if (lbl === "settings" || (fav.command && Array.isArray(fav.command) && fav.command.includes("toggleSettings"))) {
            return true;
        }
        const ids = fav.appIds || (fav.appId ? [fav.appId] : (fav.id ? [fav.id] : []));
        for (let i = 0; i < ids.length; i++) {
            const id = ids[i];
            if (id && (DesktopEntries.byId(id) || DesktopEntries.heuristicLookup(id))) return true;
        }
        if (fav.command && Array.isArray(fav.command) && fav.command.length > 0) {
            const cmd = fav.command[0];
            if (cmd && (DesktopEntries.byId(cmd) || DesktopEntries.heuristicLookup(cmd))) return true;
        }
        if (fav.label && DesktopEntries.heuristicLookup(fav.label)) return true;
        return false;
    }

    FileView {
        id: store
        path: StateStore.ready ? Quickshell.shellPath("start_favorites.json") : ""
        onLoaded: {
            try {
                const str = text();
                if (str && str.trim().length > 0) {
                    const parsed = JSON.parse(str);
                    if (Array.isArray(parsed)) {
                        root.items = parsed.filter(item => root.isAppInstalled(item));
                        return;
                    }
                }
            } catch (e) {
                console.warn("StartFavorites load error:", e);
            }
            save(root.defaultFavorites);
        }
    }

    function save(newItems) {
        root.items = newItems;
        try {
            store.setText(JSON.stringify(newItems, null, 2));
        } catch (e) {
            console.warn("StartFavorites save error:", e);
        }
    }

    function isFavorite(appId, label) {
        const id = (appId || "").toLowerCase();
        const lbl = (label || "").toLowerCase();
        for (let i = 0; i < items.length; i++) {
            const fav = items[i];
            if (lbl && fav.label && fav.label.toLowerCase() === lbl) return true;
            if (lbl && fav.name && fav.name.toLowerCase() === lbl) return true;
            const ids = fav.appIds || (fav.appId ? [fav.appId] : (fav.id ? [fav.id] : []));
            for (let j = 0; j < ids.length; j++) {
                if (id && ids[j] && (ids[j].toLowerCase() === id || id.includes(ids[j].toLowerCase()) || ids[j].toLowerCase().includes(id)))
                    return true;
            }
        }
        return false;
    }

    function addFavorite(app) {
        if (!app) return;
        const label = app.name || app.label || app.appId || "Application";
        const appId = app.id || app.appId || label.toLowerCase();
        if (isFavorite(appId, label)) return;

        const current = items.slice();
        const icon = app.icon || "application-x-executable";
        const cmd = (app.command && app.command.length > 0)
            ? app.command
            : (app.execute ? [appId.replace(".desktop", "")] : [appId.replace(".desktop", "")]);
        const appIds = app.appIds || [appId.replace(".desktop", "")];

        current.push({
            label: label,
            icon: icon,
            command: cmd,
            appIds: appIds
        });
        save(current);
    }

    function removeFavorite(appId, label) {
        const id = (appId || "").toLowerCase();
        const lbl = (label || "").toLowerCase();
        const current = items.filter(fav => {
            if (lbl && (fav.label || fav.name) && (fav.label || fav.name).toLowerCase() === lbl) return false;
            const ids = fav.appIds || (fav.appId ? [fav.appId] : (fav.id ? [fav.id] : []));
            for (let j = 0; j < ids.length; j++) {
                if (id && ids[j] && (ids[j].toLowerCase() === id || id.includes(ids[j].toLowerCase()) || ids[j].toLowerCase().includes(id)))
                    return false;
            }
            return true;
        });
        save(current);
    }

    function toggleFavorite(app) {
        const label = app.name || app.label || app.appId || "Application";
        const appId = app.id || app.appId || label.toLowerCase();
        if (isFavorite(appId, label)) {
            removeFavorite(appId, label);
        } else {
            addFavorite(app);
        }
    }

    function removeByIndex(index) {
        if (index < 0 || index >= items.length) return;
        const current = items.slice();
        current.splice(index, 1);
        save(current);
    }

    function move(from, to) {
        if (from === to || from < 0 || to < 0 || from >= items.length || to >= items.length) return;
        const current = items.slice();
        const [moved] = current.splice(from, 1);
        current.splice(to, 0, moved);
        save(current);
    }
}
