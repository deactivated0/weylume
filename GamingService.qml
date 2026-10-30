pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
Scope {
    id: root
    property var rules: []
    property string ownedRule: ""
    readonly property var matchingRule: root.rules.find(r => ToplevelManager.toplevels.values.some(w => String(w.appId).toLowerCase() === r.appId)) || null
    function saveRule(appId, performance, tearing, outputProfile) {
        appId=appId.trim().toLowerCase();
        const existing=root.rules.findIndex(r=>r.appId===appId);
        if (!appId || (existing < 0 && root.rules.length >= 64)) return;
        const rule={appId:appId,performance:performance,tearing:tearing,outputProfile:outputProfile.trim()};
        root.rules=existing < 0 ? root.rules.concat([rule]) : root.rules.map((r,i)=>i===existing ? rule : r);
        rulesFile.setText(JSON.stringify({rules:root.rules},null,2));
    }
    function removeRule(appId) { root.rules=root.rules.filter(r=>r.appId!==appId); rulesFile.setText(JSON.stringify({rules:root.rules},null,2)); }
    FileView {
        id: rulesFile
        path: StateStore.ready ? Quickshell.shellPath("game_profiles.json") : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { const data=JSON.parse(text()); root.rules=(data.rules || []).filter(r=>typeof r.appId === "string" && r.appId.length>0).slice(0,64); } catch(error) {root.rules=[];} }
    }
    property bool owned: false
    property bool suppressed: false
    property bool pending: false
    readonly property bool matching: {
        const apps = SettingsService.gamingApps.split(",").map(s => s.trim().toLowerCase()).filter(s => s.length);
        return root.matchingRule !== null || apps.length > 0 && ToplevelManager.toplevels.values.some(w => apps.includes(String(w.appId).toLowerCase()));
    }
    function manualOverride() { root.suppressed = root.matching; root.owned = false; }
    function reconcile() {
        if (!SystemService.ready || root.pending) return;
        if (!root.matching) root.suppressed = false;
        const key=JSON.stringify(root.matchingRule);
        if (root.owned && root.matching && SettingsService.gamingMode && root.ownedRule !== key) {
            root.pending=SystemService.setGamingMode(false,true); return;
        }
        if (root.matching && !root.suppressed && !SettingsService.gamingMode) {
            root.pending = true; root.owned = true;
            root.ownedRule=key;
            if (!SystemService.setGamingMode(true, true, root.matchingRule)) { root.pending = false; root.owned = false; root.suppressed = true; }
        } else if (!root.matching && root.owned) {
            root.pending = true;
            if (!SystemService.setGamingMode(false, true)) root.pending = false;
        }
    }
    onMatchingRuleChanged: Qt.callLater(root.reconcile)
    onMatchingChanged: Qt.callLater(root.reconcile)
    Connections {
        target: SystemService
        function onReadyChanged() { Qt.callLater(root.reconcile); }
        function onActionFinished(domain, success, message, data) {
            if (domain !== "gaming") return;
            root.pending = false;
            if (!success) { root.suppressed = root.matching; root.owned = false; }
            else if (!data?.gaming) root.owned = false;
            Qt.callLater(root.reconcile);
        }
    }
}
