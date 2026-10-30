pragma Singleton
import QtQuick
import Quickshell
import Quickshell.WindowManager

Scope {
    id: root
    readonly property var workspaces: WindowManager.windowsets.slice().sort((a, b) => {
        const x = a.coordinates?.[0] ?? 0;
        const y = b.coordinates?.[0] ?? 0;
        return x - y || String(a.name).localeCompare(String(b.name), undefined, { numeric: true });
    })
    function activate(index) {
        index = Number(index);
        if (!Number.isInteger(index) || index < 1 || index > 16) return;
        const workspace = root.workspaces[index - 1];
        if (workspace?.canActivate) workspace.activate();
        else SystemService.enqueue(["workspace-switch", String(index)], "workspace", "workspace", false);
    }
}
