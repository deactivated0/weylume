pragma Singleton
import QtQuick
import Quickshell

QtObject {
    readonly property bool isDark: SettingsService.darkMode !== false
    readonly property color background: isDark ? "#000000" : "#ffffff"
    readonly property color card: isDark ? "#080808" : "#f6f6f6"
    readonly property color cardHover: isDark ? "#181818" : "#ebebeb"
    readonly property color border: isDark ? "#202020" : "#dcdcdc"
    readonly property color text: isDark ? "#fff3f3f3" : "#ff000000"
    readonly property color muted: isDark ? "#ffaaaaaa" : "#ff555555"
    readonly property color accent: isDark ? "#ffffff" : "#000000"
    readonly property color danger: isDark ? "#ffff6262" : "#ffd32f2f"
    readonly property string fontFamily: "SF Pro Display"
    readonly property int taskbarHeight: 44
    readonly property int sidebarWidth: 240
    readonly property string settingsIcon: isDark ? Quickshell.shellPath("assets/weylume-gear-darkmode.svg") : Quickshell.shellPath("assets/weylume-gear-lightmode.svg")
}
