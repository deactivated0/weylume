//@ pragma IconTheme YAMIS-Cosmic
//@ pragma ShellId weylume
//@ pragma NativeTextRendering
//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import qs

ShellRoot {
    function defaultScreenName() {
        const screens = Quickshell.screens;
        return screens && screens.length > 0 ? screens[0].name : "";
    }

    Variants {
        model: Quickshell.screens
        Desktop { required property var modelData; screen: modelData }
    }

    Variants {
        model: Quickshell.screens
        Taskbar { required property var modelData; screen: modelData }
    }

    Variants {
        model: ShellState.sidebarVisible ? Quickshell.screens : []
        SystemMonitor { required property var modelData; screen: modelData }
    }

    Variants {
        model: Quickshell.screens
        Osd { required property var modelData; screen: modelData }
    }

    Component.onCompleted: { NightLightService.checkSchedule(); GamingService.reconcile(); OutputService.initialize(); CalendarService.initialize(); }

    NotificationServer {
        bodySupported: true
        imageSupported: true
        actionsSupported: true
        inlineReplySupported: true
        keepOnReload: true
        onNotification: notification => NotificationService.handleNotification(notification)
    }

    Connections { target: StateStore; function onErrorChanged() { if (StateStore.error) OsdService.show("Configuration startup failed", StateStore.error, "dialog-error", -1, true); } }

    PolkitDialog {}
    SessionDialog {}
    LazyLoader {
        active: ShellState.settingsOpen
        SettingsCenter {}
    }

    LazyLoader {
        id: newItemDialogLoader
        NewItemDialog {
            onDialogOpenChanged: if (!dialogOpen) Qt.callLater(() => {
                if (!dialogOpen) newItemDialogLoader.active = false;
            })
        }
    }

    IpcHandler {
        target: "shell"
        function toggleStart(): void { ShellState.toggleStart(defaultScreenName()); }
        function toggleQuick(): void { ShellState.toggleQuick(defaultScreenName()); }
        function toggleMixer(): void { ShellState.toggleMixer(defaultScreenName()); }
        function toggleTray(): void { ShellState.toggleTray(defaultScreenName()); }
        function toggleSidebar(): void { ShellState.sidebarVisible = !ShellState.sidebarVisible; }
        function toggleLayout(): void { ShellState.toggleLayout(); }
        function toggleSettings(): void { ShellState.toggleSettings(defaultScreenName()); }
        function toggleClipboard(): void { ShellState.toggleClipboard(defaultScreenName()); }
        function toggleEmoji(): void { ShellState.toggleEmoji(defaultScreenName()); }
        function toggleNotif(): void { ShellState.toggleNotif(defaultScreenName()); }
        function screenshot(mode: string): void { SystemService.captureScreenshot(mode); }
        function toggleRecording(): void { RecorderService.toggle(); }
        function toggleGaming(): void { SystemService.setGamingMode(!SettingsService.gamingMode); }
        function workspace(index: int): void { WorkspaceService.activate(index); }
        function session(action: string): void { ShellState.requestSessionAction(action); }
        function launchPinned(num: int): void { PinnedApps.launchPinIndex(num - 1); }
        function createItem(type: string): void {
            newItemDialogLoader.active = true;
            if (newItemDialogLoader.item) {
                newItemDialogLoader.item.openForType(type);
            } else {
                Qt.callLater(() => {
                    if (newItemDialogLoader.item) newItemDialogLoader.item.openForType(type);
                });
            }
        }
        function setWallpaper(path: string): void { ShellState.setWallpaper(path); }
        function closeAll(): void { ShellState.closeFlyouts(); }
    }
}
