pragma Singleton
import QtQuick
import Quickshell

Scope {
    id: root
    property bool visible: false
    property string title: ""
    property string detail: ""
    property string icon: ""
    property real value: -1
    property bool error: false
    property string screenName: ""
    property string defaultScreenName: ""

    function registerScreen(name) {
        if (!root.defaultScreenName && name) root.defaultScreenName = name;
    }

    function show(title, detail, icon, value, error, screenName) {
        root.title = title || "Weylume";
        root.detail = detail || "";
        root.icon = icon || "dialog-information";
        root.value = value === undefined ? -1 : Number(value);
        root.error = Boolean(error);
        root.screenName = screenName || ShellState.popupScreenName || root.defaultScreenName;
        root.visible = true;
        hideTimer.restart();
    }

    function dismiss() {
        root.visible = false;
        hideTimer.stop();
    }

    Timer {
        id: hideTimer
        interval: 1900
        onTriggered: root.visible = false
    }
}
