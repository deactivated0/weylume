import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import qs

PopupWindow {
    id: root
    required property var anchorItem
    Shortcut { sequence: "Escape"; onActivated: ShellState.closeFlyouts() }
    property string page: "main"
    property bool searchOpen: false
    property string searchText: ""

    // Devices & Network State
    readonly property var wifiDevice: {
        const devices = Networking.devices.values;
        for (let i = 0; i < devices.length; i++)
            if (devices[i].type === DeviceType.Wifi) return devices[i];
        return null;
    }
    readonly property var connectedWifi: {
        const networks = wifiDevice?.networks?.values ?? [];
        for (let i = 0; i < networks.length; i++)
            if (networks[i].connected) return networks[i];
        return null;
    }

    readonly property var ethState: SystemService.ethernet
    readonly property bool wifiEnabled: SystemService.wifiEnabled
    readonly property var wifiNetworks: SystemService.wifiNetworks
    property string wifiPasswordPromptSsid: ""
    property string wifiPasswordInput: ""
    property string pendingForgetSsid: ""

    // Bluetooth State
    property bool btPowered: BluetoothService.adapter?.enabled ?? true
    property bool btScanning: false
    readonly property var connectedBtDevice: {
        const devices = Bluetooth.devices.values;
        for (let i = 0; i < devices.length; i++) if (devices[i].connected) return devices[i];
        return null;
    }
    readonly property var displayedBtDevices: (BluetoothService.adapter?.devices.values || []).map(device => ({
        nativeDevice: device,
        mac: device.address,
        name: device.name || device.address,
        connected: device.connected,
        paired: device.paired,
        pairing: device.pairing,
        trusted: device.trusted,
        batteryAvailable: device.batteryAvailable,
        battery: device.battery,
        icon: device.icon,
        blocked: device.blocked
    }))

    Connections {
        target: BluetoothService.adapter
        function onEnabledChanged() { root.btPowered = BluetoothService.adapter?.enabled ?? false; }
        function onDiscoveringChanged() { root.btScanning = BluetoothService.adapter?.discovering ?? false; }
    }

    // Media Player
    readonly property var activePlayer: {
        const players = Mpris.players.values;
        for (let i = 0; i < players.length; i++) {
            if (players[i].playbackState === MprisPlaybackState.Playing) return players[i];
        }
        return players.length > 0 ? players[0] : null;
    }
    readonly property bool isPlaying: activePlayer?.playbackState === MprisPlaybackState.Playing
    property real livePosition: activePlayer ? (activePlayer.position ?? 0) : 0
    property real liveLength: activePlayer ? (activePlayer.length ?? 0) : 0
    property bool isScrubbing: false
    property real scrubRatio: 0.0

    Timer {
        interval: 500
        running: ShellState.quickOpen && root.activePlayer !== null && root.isPlaying
        repeat: true
        onTriggered: {
            root.livePosition = root.activePlayer?.position ?? 0;
            root.liveLength = root.activePlayer?.length ?? 0;
        }
    }

    Timer {
        id: bluetoothScanTimer
        interval: 10000
        onTriggered: {
            if (BluetoothService.adapter) {
                BluetoothService.adapter.discovering = false;
            } else {
                root.runSystemHelper(["bt-scan-stop"]);
            }
            root.btScanning = false;
        }
    }

    function getTrackProgress() {
        if (root.isScrubbing) return root.scrubRatio;
        if (!root.activePlayer) return 0.0;
        const len = root.liveLength || (root.activePlayer ? root.activePlayer.length : 0) || 0;
        const pos = root.livePosition || (root.activePlayer ? root.activePlayer.position : 0) || 0;
        if (!len || len <= 0) return 0.0;
        const normLen = len > 100000 ? len / 1000000.0 : len;
        const normPos = pos > 100000 ? pos / 1000000.0 : pos;
        return Math.max(0.0, Math.min(1.0, normPos / normLen));
    }

    function seekToRatio(ratio) {
        ratio = Math.max(0.0, Math.min(1.0, ratio));
        if (root.activePlayer) {
            const len = (root.activePlayer ? root.activePlayer.length : 0) || root.liveLength || 0;
            if (len && len > 0) {
                const normLen = len > 100000 ? len / 1000000.0 : len;
                const targetSec = ratio * normLen;
                root.livePosition = targetSec;
                Quickshell.execDetached(["playerctl", "position", targetSec.toFixed(2)]);
            }
        }
    }

    // Power modes
    readonly property var powerModes: ["Balanced", "Performance", "Power Saver"]
    readonly property int powerModeIndex: SystemService.powerProfile === "performance" ? 1 : (SystemService.powerProfile === "power-saver" ? 2 : 0)

    // Other toggles
    readonly property bool gamingDndActive: SettingsService.gamingMode && SettingsService.gamingDnd
    readonly property bool dndActive: SettingsService.dndEnabled || gamingDndActive
    readonly property bool vpnActive: SystemService.activeVpn !== null
    readonly property bool recordingActive: RecorderService.recording

    visible: ShellState.quickOpen
    implicitWidth: Math.min(page === "main" ? 420 : 380, Math.max(160, (ShellState.popupScreen?.width || 1920) - 8))
    implicitHeight: Math.min((page === "main" ? 630 : 560), Math.max(120, (ShellState.popupScreen?.height || 1080) - Theme.taskbarHeight - 12))
    color: "transparent"
    grabFocus: true
    surfaceFormat.opaque: false
    anchor.item: anchorItem
    anchor.edges: Edges.Top | Edges.Right
    anchor.gravity: Edges.Top | Edges.Left

    onVisibleChanged: {
        if (visible) {
            page = "main";
            searchOpen = false;
            searchText = "";
            pendingForgetSsid = "";
            SystemData.requestDrives();
        } else if (ShellState.quickOpen) {
            ShellState.quickOpen = false;
        }
    }

    function refreshNetworkData() {
        SystemService.refreshNetwork();
    }

    function runSystemHelper(args) {
        const name = args[0] || "";
        const domain = name.startsWith("wifi-") || name.startsWith("vpn-") ? "network" : name;
        SystemService.enqueue(args, domain, domain === "network" ? name : "", false);
    }

    function activateWifi(network) {
        const ssid = network.ssid || network.name;
        if (network.inUse || network.connected) root.runSystemHelper(["wifi-disconnect", ssid]);
        else if (network.saved) NetworkService.activate(ssid, "wifi");
        else if (network.enterprise) IntegrationService.authenticate(network.ssid);
        else if (network.locked && !network.known) {
            root.wifiPasswordPromptSsid = ssid;
            root.wifiPasswordInput = "";
        } else root.runSystemHelper(["wifi-connect", ssid]);
    }

    function findNativeBtDevice(address) {
        const devices = (Bluetooth.devices && Bluetooth.devices.values) ? Bluetooth.devices.values : [];
        for (let i = 0; i < devices.length; i++) if (devices[i].address === address) return devices[i];
        return null;
    }

    function controlBluetooth(action, device) {
        const nativeDevice = device?.nativeDevice || findNativeBtDevice(device?.mac || "");
        if (nativeDevice) {
            if (action === "connect") nativeDevice.connect();
            else if (action === "disconnect") nativeDevice.disconnect();
            else if (action === "remove") nativeDevice.forget();
            else if (action === "pair") BluetoothService.pair(nativeDevice);
            return;
        }
        if (device?.mac) runSystemHelper(["bt-" + action, device.mac]);
    }

    function triggerPlayPause() {
        if (root.activePlayer) {
            if (typeof root.activePlayer.togglePlaying === "function") {
                root.activePlayer.togglePlaying();
            } else if (typeof root.activePlayer.playPause === "function") {
                root.activePlayer.playPause();
            } else if (root.isPlaying) {
                root.activePlayer.pause();
            } else {
                root.activePlayer.play();
            }
        }
    }

    function triggerPrevious() {
        if (root.activePlayer) {
            if (typeof root.activePlayer.previous === "function") root.activePlayer.previous();
        }
    }

    function triggerNext() {
        if (root.activePlayer) {
            if (typeof root.activePlayer.next === "function") root.activePlayer.next();
        }
    }

    // AMOLED Shell Container
    Rectangle {
        anchors.fill: parent
        anchors.margins: 4
        radius: 22
        color: Theme.background
        border.width: 1
        border.color: Theme.border
        clip: true

        // Subpage navigation header
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8
            visible: root.page !== "main"

            RowLayout {
                Layout.fillWidth: true
                Rectangle {
                    width: 28; height: 28; radius: 14; color: backMouse.containsMouse ? "#20ffffff" : "transparent"
                    Text { anchors.centerIn: parent; text: "‹"; color: "#f5f5f5"; font.pixelSize: 18 }
                    MouseArea { id: backMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.page = "main" }
                }
                Text {
                    text: root.page === "network" ? "Network Settings" : root.page === "bluetooth" ? "Bluetooth Devices" : root.page === "nightlight" ? "Night Light Settings" : "Volume Mixer"
                    color: "#f5f5f5"
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    width: 28; height: 28; radius: 14; color: closeSubMouse.containsMouse ? "#20ffffff" : "transparent"
                    Text { anchors.centerIn: parent; text: "✕"; color: "#a6a6a6"; font.pixelSize: 10 }
                    MouseArea { id: closeSubMouse; anchors.fill: parent; hoverEnabled: true; onClicked: ShellState.closeFlyouts() }
                }
            }

            Loader {
                Layout.fillWidth: true
                Layout.fillHeight: true
                sourceComponent: root.page === "network" ? networkPage : root.page === "bluetooth" ? bluetoothPage : root.page === "nightlight" ? nightlightPage : audioPage
            }
        }

        // Main AMOLED Control Center View
        Flickable {
            anchors.fill: parent
            visible: root.page === "main"
            contentWidth: width
            contentHeight: contentCol.implicitHeight + 20
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: contentCol
                width: parent.width - 20
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 10
                spacing: 10

                // 1. TOPBAR
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 2
                    Layout.rightMargin: 2

                    ColumnLayout {
                        spacing: 1
                        Text {
                            text: {
                                const h = String(ShellState.currentHour).padStart(2, "0");
                                const m = String(ShellState.currentMinute).padStart(2, "0");
                                return h + ":" + m;
                            }
                            color: "#f5f5f5"
                            font.family: Theme.fontFamily
                            font.pixelSize: 28
                            font.weight: Font.Normal
                        }
                        Text {
                            text: Qt.formatDate(new Date(), "dddd, MMMM d")
                            color: "#b8b8b8"
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Action buttons (Search, Settings, Layout, Close)
                    RowLayout {
                        spacing: 4
                        Rectangle {
                            width: 32; height: 32; radius: 16; color: searchBtnMouse.containsMouse ? "#171717" : "transparent"
                            Image { id: sIcon; anchors.centerIn: parent; width: 14; height: 14; source: "assets/search.svg"; visible: false }
                            MultiEffect { anchors.fill: sIcon; source: sIcon; colorization: 1.0; colorizationColor: "#ffffff" }
                            MouseArea { id: searchBtnMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.searchOpen = !root.searchOpen }
                        }
                        Rectangle {
                            width: 32; height: 32; radius: 16; color: setBtnMouse.containsMouse ? (Theme.isDark ? "#171717" : "#E2E2E6") : "transparent"
                            Image { id: setIcon; anchors.centerIn: parent; width: 15; height: 15; source: "assets/settings.svg"; visible: false }
                            MultiEffect { anchors.fill: setIcon; source: setIcon; colorization: 1.0; colorizationColor: Theme.accent }
                            MouseArea { id: setBtnMouse; anchors.fill: parent; hoverEnabled: true; onClicked: ShellState.toggleSettings(ShellState.popupScreenName) }
                        }
                        Rectangle {
                            width: 32; height: 32; radius: 16; color: layBtnMouse.containsMouse ? "#171717" : "transparent"
                            Image { id: eIcon; anchors.centerIn: parent; width: 14; height: 14; source: "assets/edit.svg"; visible: false }
                            MultiEffect { anchors.fill: eIcon; source: eIcon; colorization: 1.0; colorizationColor: "#ffffff" }
                            MouseArea { id: layBtnMouse; anchors.fill: parent; hoverEnabled: true; onClicked: ShellState.toggleLayout() }
                        }
                        Rectangle {
                            width: 32; height: 32; radius: 16; color: closeBtnMouse.containsMouse ? "#171717" : "transparent"
                            Text { anchors.centerIn: parent; text: "✕"; color: "#a6a6a6"; font.pixelSize: 11 }
                            MouseArea { id: closeBtnMouse; anchors.fill: parent; hoverEnabled: true; onClicked: ShellState.closeFlyouts() }
                        }
                    }
                }

                // Search Overlay Box
                Rectangle {
                    visible: root.searchOpen
                    Layout.fillWidth: true
                    implicitHeight: 32
                    radius: 10
                    color: "#101010"
                    border.width: 1
                    border.color: "#2c2c2c"

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 6
                        Item {
                            Layout.preferredWidth: 12
                            Layout.preferredHeight: 12
                            Layout.alignment: Qt.AlignVCenter
                            Image { id: searchInputIcon; anchors.fill: parent; source: "assets/search.svg"; visible: false }
                            MultiEffect { anchors.fill: parent; source: searchInputIcon; colorization: 1.0; colorizationColor: "#888888" }
                        }
                        TextInput {
                            id: searchInput
                            Layout.fillWidth: true
                            color: "#ffffff"
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            text: root.searchText
                            onTextChanged: root.searchText = text
                        }
                        Rectangle {
                            width: 18; height: 18; radius: 9; color: "#22ffffff"; visible: searchInput.text.length > 0
                            Text { anchors.centerIn: parent; text: "✕"; font.pixelSize: 8; color: "#fff" }
                            MouseArea { anchors.fill: parent; onClicked: { searchInput.text = ""; root.searchOpen = false; } }
                        }
                    }
                }

                // 2. QUICK GRID (2 Columns, 8 AMOLED Tiles)
                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    rowSpacing: 8
                    columnSpacing: 8

                    // Tile 1: Network (Ethernet + Wi-Fi)
                    Rectangle {
                        id: tileNet
                        readonly property bool isPrimary: root.ethState.connected || (root.wifiDevice ? Networking.wifiEnabled : false) || root.wifiEnabled
                        readonly property bool isMatch: root.searchText === "" || "network wi-fi wifi ethernet internet".includes(root.searchText.toLowerCase())
                        visible: isMatch
                        Layout.fillWidth: true
                        implicitHeight: 56
                        radius: 14
                        color: tileNet.isPrimary ? "#ffffff" : (netTileMouse.containsMouse ? "#141414" : "#0c0c0c")
                        border.width: 1
                        border.color: tileNet.isPrimary ? "#ffffff" : (netTileMouse.containsMouse ? "#282828" : "#1c1c1c")

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Rectangle {
                                width: 32; height: 32; radius: 16
                                color: tileNet.isPrimary ? "#ffffff" : "#161616"
                                Image {
                                    id: netRawIcon
                                    anchors.centerIn: parent
                                    width: 16; height: 16
                                    source: "assets/wifi.svg"
                                    visible: false
                                }
                                MultiEffect {
                                    anchors.fill: netRawIcon
                                    source: netRawIcon
                                    colorization: 1.0
                                    colorizationColor: tileNet.isPrimary ? "#000000" : "#ffffff"
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text {
                                    text: "Network"
                                    color: tileNet.isPrimary ? "#000000" : "#ffffff"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    text: root.ethState.connected ? "Ethernet" : (root.wifiDevice ? (Networking.wifiEnabled ? (root.connectedWifi?.name ?? "Wi‑Fi On") : "Off") : (root.wifiEnabled ? "Wi‑Fi On" : "Off"))
                                    color: tileNet.isPrimary ? "#333333" : "#777777"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }

                            Text {
                                text: "›"
                                color: tileNet.isPrimary ? "#000000" : "#777777"
                                font.pixelSize: 13
                            }
                        }

                        MouseArea {
                            id: netTileMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.page = "network"
                        }
                    }

                    // Tile 2: Bluetooth (White Accent)
                    Rectangle {
                        id: tileBt
                        readonly property bool isPrimary: root.btPowered || (BluetoothService.adapter?.enabled ?? false)
                        readonly property bool isMatch: root.searchText === "" || "bluetooth bt".includes(root.searchText.toLowerCase())
                        visible: isMatch
                        Layout.fillWidth: true
                        implicitHeight: 56
                        radius: 14
                        color: tileBt.isPrimary ? "#ffffff" : (btTileMouse.containsMouse ? "#141414" : "#0c0c0c")
                        border.width: 1
                        border.color: tileBt.isPrimary ? "#ffffff" : (btTileMouse.containsMouse ? "#282828" : "#1c1c1c")

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Rectangle {
                                width: 32; height: 32; radius: 16
                                color: tileBt.isPrimary ? "#ffffff" : "#161616"
                                Image {
                                    id: btRawIcon
                                    anchors.centerIn: parent
                                    width: 16; height: 16
                                    source: "assets/bluetooth.svg"
                                    visible: false
                                }
                                MultiEffect {
                                    anchors.fill: btRawIcon
                                    source: btRawIcon
                                    colorization: 1.0
                                    colorizationColor: tileBt.isPrimary ? "#000000" : "#ffffff"
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text {
                                    text: "Bluetooth"
                                    color: tileBt.isPrimary ? "#000000" : "#ffffff"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    text: tileBt.isPrimary ? (root.connectedBtDevice?.name || "On") : "Off"
                                    color: tileBt.isPrimary ? "#333333" : "#777777"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }

                            Text {
                                text: "›"
                                color: tileBt.isPrimary ? "#000000" : "#777777"
                                font.pixelSize: 13
                            }
                        }

                        MouseArea {
                            id: btTileMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: event => {
                                if (event.x > parent.width - 38) {
                                    root.page = "bluetooth";
                                } else {
                                    root.btPowered = !root.btPowered;
                                    if (BluetoothService.adapter) BluetoothService.adapter.enabled = root.btPowered;
                                    else root.runSystemHelper(["bt-power", root.btPowered ? "on" : "off"]);
                                }
                            }
                        }
                    }

                    // Tile 3: Do Not Disturb
                    Rectangle {
                        id: tileDnd
                        readonly property bool isPrimary: root.dndActive
                        readonly property bool isMatch: root.searchText === "" || "do not disturb dnd quiet".includes(root.searchText.toLowerCase())
                        visible: isMatch
                        Layout.fillWidth: true
                        implicitHeight: 56
                        radius: 14
                        color: tileDnd.isPrimary ? "#ffffff" : (dndTileMouse.containsMouse ? "#141414" : "#0c0c0c")
                        border.width: 1
                        border.color: tileDnd.isPrimary ? "#ffffff" : (dndTileMouse.containsMouse ? "#282828" : "#1c1c1c")

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Rectangle {
                                width: 32; height: 32; radius: 16
                                color: tileDnd.isPrimary ? "#ffffff" : "#161616"
                                Image {
                                    id: dndRawIcon
                                    anchors.centerIn: parent
                                    width: 16; height: 16
                                    source: "assets/moon.svg"
                                    visible: false
                                }
                                MultiEffect {
                                    anchors.fill: dndRawIcon
                                    source: dndRawIcon
                                    colorization: 1.0
                                    colorizationColor: tileDnd.isPrimary ? "#000000" : "#ffffff"
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text {
                                    text: "Do Not Disturb"
                                    color: tileDnd.isPrimary ? "#000000" : "#ffffff"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    text: root.gamingDndActive && !SettingsService.dndEnabled ? "Gaming mode" : (root.dndActive ? "On" : "Off")
                                    color: tileDnd.isPrimary ? "#333333" : "#777777"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                }
                            }
                        }

                        MouseArea {
                            id: dndTileMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: SystemService.toggleDnd()
                        }
                    }

                    // Tile 4: VPN / Shield
                    Rectangle {
                        id: tileVpn
                        readonly property bool isPrimary: root.vpnActive
                        readonly property bool isMatch: root.searchText === "" || "vpn shield security".includes(root.searchText.toLowerCase())
                        visible: isMatch
                        Layout.fillWidth: true
                        implicitHeight: 56
                        radius: 14
                        color: tileVpn.isPrimary ? "#ffffff" : (vpnTileMouse.containsMouse ? "#141414" : "#0c0c0c")
                        border.width: 1
                        border.color: tileVpn.isPrimary ? "#ffffff" : (vpnTileMouse.containsMouse ? "#282828" : "#1c1c1c")

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Rectangle {
                                width: 32; height: 32; radius: 16
                                color: tileVpn.isPrimary ? "#ffffff" : "#161616"
                                Image {
                                    id: vpnRawIcon
                                    anchors.centerIn: parent
                                    width: 16; height: 16
                                    source: "assets/shield.svg"
                                    visible: false
                                }
                                MultiEffect {
                                    anchors.fill: vpnRawIcon
                                    source: vpnRawIcon
                                    colorization: 1.0
                                    colorizationColor: tileVpn.isPrimary ? "#000000" : "#ffffff"
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text {
                                    text: "VPN"
                                    color: tileVpn.isPrimary ? "#000000" : "#ffffff"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    text: root.vpnActive ? "Connected" : "Off"
                                    color: tileVpn.isPrimary ? "#333333" : "#777777"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                }
                            }
                        }

                        MouseArea {
                            id: vpnTileMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: SystemService.toggleVpn()
                        }
                    }

                    // Tile 5: Screenshot
                    Rectangle {
                        readonly property bool isPrimary: false
                        readonly property bool isMatch: root.searchText === "" || "screenshot snip capture prtsc".includes(root.searchText.toLowerCase())
                        visible: isMatch
                        Layout.fillWidth: true
                        implicitHeight: 56
                        radius: 14
                        color: shotTileMouse.containsMouse ? "#141414" : "#0c0c0c"
                        border.width: 1
                        border.color: shotTileMouse.containsMouse ? "#282828" : "#1c1c1c"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Rectangle {
                                width: 32; height: 32; radius: 16
                                color: "#161616"
                                Image {
                                    id: shotRawIcon
                                    anchors.centerIn: parent
                                    width: 16; height: 16
                                    source: "assets/screenshot.svg"
                                    visible: false
                                }
                                MultiEffect {
                                    anchors.fill: shotRawIcon
                                    source: shotRawIcon
                                    colorization: 1.0
                                    colorizationColor: "#ffffff"
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text {
                                    text: "Screenshot"
                                    color: "#ffffff"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    text: "Capture screen"
                                    color: "#777777"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                }
                            }
                        }

                        MouseArea {
                            id: shotTileMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                ShellState.closeFlyouts();
                                Qt.callLater(() => SystemService.captureScreenshot());
                            }
                        }
                    }

                    // Tile 6: Screen Record
                    Rectangle {
                        id: tileRec
                        readonly property bool isPrimary: root.recordingActive
                        readonly property bool isMatch: root.searchText === "" || "record screen video".includes(root.searchText.toLowerCase())
                        visible: isMatch
                        Layout.fillWidth: true
                        implicitHeight: 56
                        radius: 14
                        color: tileRec.isPrimary ? "#ffffff" : (recTileMouse.containsMouse ? "#141414" : "#0c0c0c")
                        border.width: 1
                        border.color: tileRec.isPrimary ? "#ffffff" : (recTileMouse.containsMouse ? "#282828" : "#1c1c1c")

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Rectangle {
                                width: 32; height: 32; radius: 16
                                color: tileRec.isPrimary ? "#ffffff" : "#161616"
                                Image {
                                    id: recRawIcon
                                    anchors.centerIn: parent
                                    width: 16; height: 16
                                    source: "assets/record.svg"
                                    visible: false
                                }
                                MultiEffect {
                                    anchors.fill: recRawIcon
                                    source: recRawIcon
                                    colorization: 1.0
                                    colorizationColor: tileRec.isPrimary ? "#000000" : "#ffffff"
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text {
                                    text: "Screen Record"
                                    color: tileRec.isPrimary ? "#000000" : "#ffffff"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    text: root.recordingActive ? "Recording..." : "Record video"
                                    color: tileRec.isPrimary ? "#333333" : "#777777"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                }
                            }
                        }

                        MouseArea {
                            id: recTileMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: RecorderService.toggle()
                        }
                    }

                    // Tile 7: Night Light (Global Blue Light Filter)
                    Rectangle {
                        id: tileNight
                        readonly property bool isPrimary: NightLightService.active
                        readonly property bool isMatch: root.searchText === "" || "night light warm gamma blue kelvin".includes(root.searchText.toLowerCase())
                        visible: isMatch
                        Layout.fillWidth: true
                        implicitHeight: 56
                        radius: 14
                        color: tileNight.isPrimary ? "#ffffff" : (nightTileMouse.containsMouse ? "#141414" : "#0c0c0c")
                        border.width: 1
                        border.color: tileNight.isPrimary ? "#ffffff" : (nightTileMouse.containsMouse ? "#282828" : "#1c1c1c")

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Rectangle {
                                width: 32; height: 32; radius: 16
                                color: tileNight.isPrimary ? "#ffffff" : "#161616"
                                Image {
                                    id: nightRawIcon
                                    anchors.centerIn: parent
                                    width: 16; height: 16
                                    source: "assets/sun.svg"
                                    visible: false
                                }
                                MultiEffect {
                                    anchors.fill: nightRawIcon
                                    source: nightRawIcon
                                    colorization: 1.0
                                    colorizationColor: tileNight.isPrimary ? "#000000" : "#ffffff"
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text {
                                    text: "Night Light"
                                    color: tileNight.isPrimary ? "#000000" : "#ffffff"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    text: NightLightService.active ? (NightLightService.temperature + "K") : "Off"
                                    color: tileNight.isPrimary ? "#333333" : "#777777"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                }
                            }

                            Text {
                                text: "›"
                                color: tileNight.isPrimary ? "#000000" : "#777777"
                                font.pixelSize: 13
                            }
                        }

                        MouseArea {
                            id: nightTileMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: event => {
                                if (event.x > parent.width - 38) {
                                    root.page = "nightlight";
                                } else {
                                    NightLightService.toggle();
                                }
                            }
                        }
                    }

                    // Tile 8: Power Mode
                    Rectangle {
                        id: tilePower
                        readonly property bool isPrimary: root.powerModeIndex === 1
                        readonly property bool isMatch: root.searchText === "" || "power battery profile performance".includes(root.searchText.toLowerCase())
                        visible: isMatch
                        Layout.fillWidth: true
                        implicitHeight: 56
                        radius: 14
                        color: tilePower.isPrimary ? "#ffffff" : (powerTileMouse.containsMouse ? "#141414" : "#0c0c0c")
                        border.width: 1
                        border.color: tilePower.isPrimary ? "#ffffff" : (powerTileMouse.containsMouse ? "#282828" : "#1c1c1c")

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Rectangle {
                                width: 32; height: 32; radius: 16
                                color: tilePower.isPrimary ? "#ffffff" : "#161616"
                                Image {
                                    id: powerRawIcon
                                    anchors.centerIn: parent
                                    width: 16; height: 16
                                    source: "assets/power.svg"
                                    visible: false
                                }
                                MultiEffect {
                                    anchors.fill: powerRawIcon
                                    source: powerRawIcon
                                    colorization: 1.0
                                    colorizationColor: tilePower.isPrimary ? "#000000" : "#ffffff"
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text {
                                    text: "Power Mode"
                                    color: tilePower.isPrimary ? "#000000" : "#ffffff"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    text: root.powerModes[root.powerModeIndex]
                                    color: tilePower.isPrimary ? "#333333" : "#777777"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }
                        }

                        MouseArea {
                            id: powerTileMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const nextIndex = (root.powerModeIndex + 1) % root.powerModes.length;
                                const profile = nextIndex === 1 ? "performance" : (nextIndex === 2 ? "power-saver" : "balanced");
                                SystemService.setPowerProfile(profile);
                            }
                        }
                    }
                }

                // 3. SLIDERS SECTION (Brightness & Volume - Identical Length)
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 90
                    radius: 18
                    color: "#101010"
                    border.width: 1
                    border.color: "#1d1d1d"

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        // Brightness row
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Item {
                                width: 16; height: 16; Layout.preferredWidth: 16
                                Image { id: sBright; anchors.fill: parent; source: "assets/sun.svg"; visible: false }
                                MultiEffect { anchors.fill: sBright; source: sBright; colorization: 1.0; colorizationColor: "#e6e6e6" }
                            }

                            Slider {
                                id: brightSlider
                                Layout.fillWidth: true
                                from: 0.0; to: 1.0
                                value: ShellState.brightness
                                onMoved: ShellState.setBrightness(value)

                                background: Rectangle {
                                    x: brightSlider.leftPadding
                                    y: brightSlider.topPadding + brightSlider.availableHeight / 2 - 2
                                    implicitWidth: 160
                                    implicitHeight: 4
                                    width: brightSlider.availableWidth
                                    height: 4
                                    radius: 2
                                    color: "#2d2d2d"

                                    Rectangle {
                                        width: brightSlider.visualPosition * parent.width
                                        height: parent.height
                                        color: "#f2f2f2"
                                        radius: 2
                                    }
                                }

                                handle: Rectangle {
                                    x: brightSlider.leftPadding + brightSlider.visualPosition * (brightSlider.availableWidth - width)
                                    y: brightSlider.topPadding + brightSlider.availableHeight / 2 - height / 2
                                    implicitWidth: 16
                                    implicitHeight: 16
                                    radius: 8
                                    color: "#f4f4f4"
                                }
                            }

                            Text {
                                text: Math.round(ShellState.brightness * 100) + "%"
                                color: "#dddddd"
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                Layout.preferredWidth: 36
                                horizontalAlignment: Text.AlignRight
                            }
                        }

                        // Volume row
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Item {
                                width: 16; height: 16; Layout.preferredWidth: 16
                                Image {
                                    id: sVol
                                    anchors.fill: parent
                                    source: (AudioService.defaultSink || Pipewire.defaultAudioSink)?.audio?.muted ? "assets/speaker-muted-mono.svg" : "assets/volume.svg"
                                    visible: false
                                }
                                MultiEffect {
                                    anchors.fill: sVol
                                    source: sVol
                                    colorization: 1.0
                                    colorizationColor: "#e6e6e6"
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        AudioService.toggleMute(AudioService.defaultSink || Pipewire.defaultAudioSink);
                                    }
                                }
                            }

                            Slider {
                                id: volSlider
                                Layout.fillWidth: true
                                from: 0.0; to: 1.0
                                value: (AudioService.defaultSink || Pipewire.defaultAudioSink)?.audio?.volume ?? 0.5
                                onMoved: AudioService.setVolume(AudioService.defaultSink || Pipewire.defaultAudioSink, value)

                                background: Rectangle {
                                    x: volSlider.leftPadding
                                    y: volSlider.topPadding + volSlider.availableHeight / 2 - 2
                                    implicitWidth: 160
                                    implicitHeight: 4
                                    width: volSlider.availableWidth
                                    height: 4
                                    radius: 2
                                    color: "#2d2d2d"

                                    Rectangle {
                                        width: volSlider.visualPosition * parent.width
                                        height: parent.height
                                        color: "#f2f2f2"
                                        radius: 2
                                    }
                                }

                                handle: Rectangle {
                                    x: volSlider.leftPadding + volSlider.visualPosition * (volSlider.availableWidth - width)
                                    y: volSlider.topPadding + volSlider.availableHeight / 2 - height / 2
                                    implicitWidth: 16
                                    implicitHeight: 16
                                    radius: 8
                                    color: "#f4f4f4"
                                }
                            }

                            Text {
                                text: Math.round(((AudioService.defaultSink || Pipewire.defaultAudioSink)?.audio?.volume ?? 0) * 100) + "%"
                                color: "#dddddd"
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                Layout.preferredWidth: 36
                                horizontalAlignment: Text.AlignRight
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.page = "audio" }
                            }
                        }
                    }
                }

                // 4. LIVE SYSTEM STATS (CPU, RAM, DISK)
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 76
                    radius: 18
                    color: "#101010"
                    border.width: 1
                    border.color: "#1d1d1d"

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 0

                        // CPU
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 8
                                Rectangle {
                                    width: 36; height: 36; radius: 18; color: "#1a1a1a"; border.width: 2; border.color: "#333"
                                    Image { id: statCpu; anchors.centerIn: parent; width: 18; height: 18; source: "assets/cpu.svg"; visible: false }
                                    MultiEffect { anchors.fill: statCpu; source: statCpu; colorization: 1.0; colorizationColor: "#eeeeee" }
                                }
                                ColumnLayout {
                                    spacing: 0
                                    Text { text: Math.round(SystemData.cpuUsage) + "%"; color: "#f5f5f5"; font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Font.DemiBold }
                                    Text { text: "CPU"; color: "#a6a6a6"; font.family: Theme.fontFamily; font.pixelSize: 10 }
                                }
                            }
                        }

                        Rectangle { implicitWidth: 1; Layout.fillHeight: true; Layout.topMargin: 4; Layout.bottomMargin: 4; color: "#2a2a2a" }

                        // RAM
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 8
                                Rectangle {
                                    width: 36; height: 36; radius: 18; color: "#1a1a1a"; border.width: 2; border.color: "#333"
                                    Image { id: statRam; anchors.centerIn: parent; width: 18; height: 18; source: "assets/ram.svg"; visible: false }
                                    MultiEffect { anchors.fill: statRam; source: statRam; colorization: 1.0; colorizationColor: "#eeeeee" }
                                }
                                ColumnLayout {
                                    spacing: 0
                                    Text { text: Math.round(SystemData.memoryUsage) + "%"; color: "#f5f5f5"; font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Font.DemiBold }
                                    Text { text: "RAM"; color: "#a6a6a6"; font.family: Theme.fontFamily; font.pixelSize: 10 }
                                }
                            }
                        }

                        Rectangle { implicitWidth: 1; Layout.fillHeight: true; Layout.topMargin: 4; Layout.bottomMargin: 4; color: "#2a2a2a" }

                        // Disk
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 8
                                Rectangle {
                                    width: 36; height: 36; radius: 18; color: "#1a1a1a"; border.width: 2; border.color: "#333"
                                    Image { id: statDisk; anchors.centerIn: parent; width: 18; height: 18; source: "assets/disk.svg"; visible: false }
                                    MultiEffect { anchors.fill: statDisk; source: statDisk; colorization: 1.0; colorizationColor: "#eeeeee" }
                                }
                                ColumnLayout {
                                    spacing: 0
                                    Text {
                                        text: SystemData.drives.length > 0 ? SystemData.drives[0].usage + "%" : "—"
                                        color: "#f5f5f5"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        font.weight: Font.DemiBold
                                    }
                                    Text { text: "Disk"; color: "#a6a6a6"; font.family: Theme.fontFamily; font.pixelSize: 10 }
                                }
                            }
                        }
                    }
                }

                // 5. MEDIA PLAYER (Album art / Vinyl disc + clean responsive controls)
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 96
                    radius: 18
                    color: "#101010"
                    border.width: 1
                    border.color: "#1d1d1d"

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 10

                        // Album Art Box
                        Rectangle {
                            Layout.preferredWidth: 64
                            Layout.preferredHeight: 64
                            radius: 10
                            color: "#171717"
                            border.width: 1
                            border.color: "#242424"
                            clip: true

                            // Track Art Image
                            Image {
                                id: trackArt
                                anchors.fill: parent
                                source: root.activePlayer?.trackArtUrl || ""
                                fillMode: Image.PreserveAspectCrop
                                visible: status === Image.Ready
                            }

                            // Fallback animated Vinyl Disc
                            Rectangle {
                                visible: !trackArt.visible
                                anchors.centerIn: parent
                                width: 56; height: 56; radius: 28
                                color: "#0d0d0d"
                                border.width: 2
                                border.color: "#282828"

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 18; height: 18; radius: 9
                                    color: "#f4f4f4"
                                    Text { anchors.centerIn: parent; text: "♪"; color: "#111"; font.pixelSize: 10 }
                                }

                                RotationAnimation on rotation {
                                    loops: Animation.Infinite
                                    from: 0; to: 360
                                    duration: 16000
                                    running: root.visible && root.isPlaying && !SettingsService.reducedMotion
                                }
                            }
                        }

                        // Track title, artist, progress
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3

                            Text {
                                Layout.fillWidth: true
                                text: root.activePlayer?.trackTitle || "No media playing"
                                color: "#f5f5f5"
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: root.activePlayer?.trackArtist || "Open a player to begin"
                                color: "#a6a6a6"
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                elide: Text.ElideRight
                            }

                            // Progress track (Interactive Seek & Scrub)
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 6
                                radius: 3
                                color: "#282828"
                                Layout.topMargin: 3
                                clip: false

                                Rectangle {
                                    id: progFill
                                    height: parent.height
                                    width: Math.max(0, Math.min(parent.width, parent.width * root.getTrackProgress()))
                                    radius: 3
                                    color: progMouse.containsMouse ? "#ffffff" : "#f2f2f2"
                                }

                                // Scrub handle on hover or drag
                                Rectangle {
                                    visible: progMouse.containsMouse || progMouse.pressed
                                    x: Math.max(0, Math.min(parent.width - width, progFill.width - width / 2))
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 10; height: 10; radius: 5
                                    color: "#ffffff"
                                }

                                MouseArea {
                                    id: progMouse
                                    anchors.fill: parent
                                    anchors.topMargin: -8
                                    anchors.bottomMargin: -8
                                    hoverEnabled: true
                                    preventStealing: true

                                    onPressed: mouse => {
                                        root.isScrubbing = true;
                                        root.scrubRatio = Math.max(0.0, Math.min(1.0, mouse.x / width));
                                    }
                                    onPositionChanged: mouse => {
                                        if (pressed) {
                                            root.isScrubbing = true;
                                            root.scrubRatio = Math.max(0.0, Math.min(1.0, mouse.x / width));
                                        }
                                    }
                                    onReleased: mouse => {
                                        const r = Math.max(0.0, Math.min(1.0, mouse.x / width));
                                        root.scrubRatio = r;
                                        root.seekToRatio(r);
                                        root.isScrubbing = false;
                                    }
                                    onCanceled: {
                                        root.isScrubbing = false;
                                    }
                                }
                            }
                        }

                        // Controls (Prev, Big Play/Pause, Next)
                        RowLayout {
                            spacing: 6
                            Rectangle {
                                width: 28; height: 28; radius: 14; color: prevMouse.containsMouse ? "#333" : "#242424"
                                Image { id: pIcon; anchors.centerIn: parent; width: 14; height: 14; source: "assets/prev.svg"; visible: false }
                                MultiEffect { anchors.fill: pIcon; source: pIcon; colorization: 1.0; colorizationColor: "#dddddd" }
                                MouseArea {
                                    id: prevMouse; anchors.fill: parent; hoverEnabled: true; z: 10
                                    onClicked: root.triggerPrevious()
                                }
                            }
                            Rectangle {
                                width: 36; height: 36; radius: 18; color: playMouse.containsMouse ? "#ffffff" : "#f0f0f0"
                                Image {
                                    id: ppIcon
                                    anchors.centerIn: parent
                                    width: 16; height: 16
                                    source: root.isPlaying ? "assets/pause.svg" : "assets/play.svg"
                                    visible: false
                                }
                                MultiEffect { anchors.fill: ppIcon; source: ppIcon; colorization: 1.0; colorizationColor: "#060606" }
                                MouseArea {
                                    id: playMouse; anchors.fill: parent; hoverEnabled: true; z: 10
                                    onClicked: root.triggerPlayPause()
                                }
                            }
                            Rectangle {
                                width: 28; height: 28; radius: 14; color: nextMouse.containsMouse ? "#333" : "#242424"
                                Image { id: nIcon; anchors.centerIn: parent; width: 14; height: 14; source: "assets/next.svg"; visible: false }
                                MultiEffect { anchors.fill: nIcon; source: nIcon; colorization: 1.0; colorizationColor: "#dddddd" }
                                MouseArea {
                                    id: nextMouse; anchors.fill: parent; hoverEnabled: true; z: 10
                                    onClicked: root.triggerNext()
                                }
                            }
                        }
                    }
                }


            }
        }
    }

    // SUBPAGE 1: Network Manager (Ethernet + Wi-Fi Access Points + Forget Network)
    Component {
        id: networkPage
        ColumnLayout {
            spacing: 10

            // Ethernet Section Card
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 64
                radius: 12
                color: "#111111"
                border.width: 1
                border.color: root.ethState.connected ? "#ffffff" : "#222222"

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 10

                    Rectangle {
                        width: 36; height: 36; radius: 18
                        color: root.ethState.connected ? "#ffffff" : "#222222"
                        Image { id: ethIcon; anchors.centerIn: parent; width: 18; height: 18; source: "assets/shield.svg"; visible: false }
                        MultiEffect { anchors.fill: ethIcon; source: ethIcon; colorization: 1.0; colorizationColor: root.ethState.connected ? "#050505" : "#ffffff" }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Text {
                            text: root.ethState.name || "Wired Connection (Ethernet)"
                            color: "#f5f5f5"
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Text {
                            text: root.ethState.connected ? ("Connected • " + (root.ethState.device || "Ethernet")) : "Cable Unplugged"
                            color: root.ethState.connected ? "#ffffff" : "#888888"
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                        }
                    }

                    Rectangle {
                        width: 76; height: 24; radius: 12
                        color: root.ethState.connected ? "#ffffff" : "#1e1e1e"
                        Text {
                            anchors.centerIn: parent
                            text: root.ethState.connected ? "Connected" : "Inactive"
                            color: root.ethState.connected ? "#080808" : "#888888"
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.weight: Font.DemiBold
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 44
                radius: 10
                color: "#111111"
                border.width: 1
                border.color: SystemService.activeVpn ? "#ffffff" : "#222222"
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8
                    Image { Layout.preferredWidth: 16; Layout.preferredHeight: 16; source: "assets/shield.svg" }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text { text: SystemService.activeVpn?.name || "VPN"; color: "#f5f5f5"; font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Font.DemiBold }
                        Text {
                            text: SystemService.activeVpn ? "Connected" : (SystemService.vpns.length ? SystemService.vpns.length + " saved profile" + (SystemService.vpns.length === 1 ? "" : "s") : "No saved NetworkManager profile")
                            color: "#777777"; font.family: Theme.fontFamily; font.pixelSize: 8
                        }
                    }
                    Rectangle {
                        implicitWidth: vpnPageText.implicitWidth + 18
                        height: 25; radius: 7
                        color: SystemService.activeVpn ? "#ffffff" : "#191919"
                        border.width: 1; border.color: SystemService.activeVpn ? "#ffffff" : "#333333"
                        Text { id: vpnPageText; anchors.centerIn: parent; text: SystemService.activeVpn ? "Disconnect" : "Connect"; color: SystemService.activeVpn ? "#080808" : "#ffffff"; font.family: Theme.fontFamily; font.pixelSize: 8; font.weight: Font.DemiBold }
                        MouseArea { anchors.fill: parent; enabled: SystemService.activeVpn !== null || SystemService.vpns.length > 0; onClicked: SystemService.toggleVpn() }
                    }
                }
            }

            Text {
                visible: SystemService.networkAddresses.length > 0
                Layout.fillWidth: true
                text: SystemService.networkAddresses.join("  •  ") + (SystemService.networkGateway ? "  •  Gateway " + SystemService.networkGateway : "")
                color: "#616161"
                font.family: Theme.fontFamily
                font.pixelSize: 8
                elide: Text.ElideRight
            }

            // Wi-Fi Header & Switch
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Text { text: "Wi‑Fi Networks"; color: "#f5f5f5"; font.family: Theme.fontFamily; font.pixelSize: 12; font.weight: Font.DemiBold }
                    Text { text: root.wifiEnabled ? "Available Access Points" : "Wi‑Fi is Disabled"; color: "#888888"; font.family: Theme.fontFamily; font.pixelSize: 10 }
                }

                Rectangle {
                    width: 28; height: 28; radius: 14; color: refreshWifiMouse.containsMouse ? "#25ffffff" : "#181818"
                    border.width: 1; border.color: "#282828"
                    Text { anchors.centerIn: parent; text: "⟳"; color: "#ffffff"; font.pixelSize: 14 }
                    MouseArea {
                        id: refreshWifiMouse; anchors.fill: parent; hoverEnabled: true
                        onClicked: {
                            root.runSystemHelper(["wifi-rescan"]);
                        }
                    }
                }

                // Amoled White Accent Switch
                Rectangle {
                    width: 44; height: 24; radius: 12
                    color: root.wifiEnabled ? "#ffffff" : "#222222"
                    border.width: 1; border.color: root.wifiEnabled ? "#ffffff" : "#383838"
                    Behavior on color { ColorAnimation { duration: SettingsService.reducedMotion ? 0 : 120 } }

                    Rectangle {
                        width: 18; height: 18; radius: 9
                        anchors.verticalCenter: parent.verticalCenter
                        x: root.wifiEnabled ? (parent.width - width - 3) : 3
                        color: root.wifiEnabled ? "#080808" : "#8e8e8e"
                        Behavior on x { NumberAnimation { duration: SettingsService.reducedMotion ? 0 : 120 } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            const next = !root.wifiEnabled;
                            if (root.wifiDevice) Networking.wifiEnabled = next;
                            root.runSystemHelper(["wifi-power", next ? "on" : "off"]);
                        }
                    }
                }
            }

            // Wi-Fi Password Input Box (if user clicked a locked network)
            Rectangle {
                visible: root.wifiPasswordPromptSsid !== ""
                Layout.fillWidth: true
                implicitHeight: 74
                radius: 10
                color: "#161616"
                border.width: 1
                border.color: "#ffffff"

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6

                    Text {
                        text: "Password for \"" + root.wifiPasswordPromptSsid + "\":"
                        color: "#ffffff"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 26
                            radius: 6
                            color: "#0c0c0c"
                            border.width: 1
                            border.color: "#333333"

                            TextInput {
                                anchors.fill: parent
                                anchors.leftMargin: 8; anchors.rightMargin: 8
                                verticalAlignment: TextInput.AlignVCenter
                                color: "#ffffff"
                                echoMode: TextInput.Password
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                text: root.wifiPasswordInput
                                onTextChanged: root.wifiPasswordInput = text
                            }
                        }

                        Rectangle {
                            width: 60; height: 26; radius: 6; color: "#ffffff"
                            Text { anchors.centerIn: parent; text: "Connect"; color: "#000000"; font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Font.DemiBold }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    root.runSystemHelper(["wifi-connect", root.wifiPasswordPromptSsid, root.wifiPasswordInput]);
                                    root.wifiPasswordPromptSsid = "";
                                    root.wifiPasswordInput = "";
                                }
                            }
                        }

                        Rectangle {
                            width: 26; height: 26; radius: 6; color: "#222222"
                            Text { anchors.centerIn: parent; text: "✕"; color: "#ffffff"; font.pixelSize: 10 }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: { root.wifiPasswordPromptSsid = ""; root.wifiPasswordInput = ""; }
                            }
                        }
                    }
                }
            }

            // Wi-Fi Networks ListView
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ListView {
                    id: wifiList
                    model: root.wifiNetworks.length > 0 ? root.wifiNetworks : (root.wifiDevice?.networks?.values ?? [])
                    spacing: 5

                    delegate: Rectangle {
                        required property var modelData
                        width: wifiList.width
                        implicitHeight: 48
                        radius: 10
                        color: cardWifiMouse.containsMouse ? "#1c1c1c" : "#111111"
                        border.width: 1
                        border.color: (modelData.inUse || modelData.connected) ? "#ffffff" : "#202020"

                        MouseArea {
                            id: cardWifiMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.activateWifi(modelData)
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 8

                            Rectangle {
                                width: 28; height: 28; radius: 14
                                color: (modelData.inUse || modelData.connected) ? "#ffffff" : "#222222"
                                Image { id: wSubIcon; anchors.centerIn: parent; width: 14; height: 14; source: "assets/wifi.svg"; visible: false }
                                MultiEffect { anchors.fill: wSubIcon; source: wSubIcon; colorization: 1.0; colorizationColor: (modelData.inUse || modelData.connected) ? "#050505" : "#ffffff" }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    text: modelData.ssid || modelData.name || "Access Point"
                                    color: "#f5f5f5"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: (modelData.inUse || modelData.connected) ? "Connected" : (modelData.saved ? "Saved" : (modelData.locked ? ("Secured • " + (modelData.signal ?? 0) + "%") : "Open Network"))
                                    color: (modelData.inUse || modelData.connected) ? "#ffffff" : "#888888"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                }
                            }

                            // Forget Network Button (Visible if saved or inUse)
                            Rectangle {
                                z: 10
                                visible: (modelData.saved || modelData.inUse || modelData.connected || modelData.known)
                                width: 50; height: 24; radius: 6
                                color: forgetWifiMouse.containsMouse ? "#2b2b2b" : "#191919"
                                border.width: 1; border.color: "#303030"

                                Text {
                                    anchors.centerIn: parent
                                    text: root.pendingForgetSsid === (modelData.ssid || modelData.name) ? "Sure?" : "Forget"
                                    color: "#a6a6a6"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 8
                                    font.weight: Font.DemiBold
                                }

                                MouseArea {
                                    id: forgetWifiMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        const ssid = modelData.ssid || modelData.name;
                                        if (root.pendingForgetSsid === ssid) {
                                            root.pendingForgetSsid = "";
                                            root.runSystemHelper(["wifi-forget", ssid]);
                                        } else {
                                            root.pendingForgetSsid = ssid;
                                        }
                                    }
                                }
                            }

                            // Connect / Disconnect Action Button
                            Rectangle {
                                z: 10
                                width: (modelData.inUse || modelData.connected) ? 68 : 60
                                height: 24; radius: 6
                                color: (modelData.inUse || modelData.connected) ? "#ffffff" : (actionWifiMouse.containsMouse ? "#2a2a2a" : "#1a1a1a")
                                border.width: 1; border.color: (modelData.inUse || modelData.connected) ? "#ffffff" : "#333333"

                                Text {
                                    anchors.centerIn: parent
                                    text: (modelData.inUse || modelData.connected) ? "Connected" : "Connect"
                                    color: (modelData.inUse || modelData.connected) ? "#080808" : "#ffffff"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    font.weight: Font.DemiBold
                                }

                                MouseArea {
                                    id: actionWifiMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.activateWifi(modelData)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // SUBPAGE 2: Bluetooth Devices (White Accent + Add Device + Device Connect/Disconnect + Forget Device)
    Component {
        id: bluetoothPage
        ColumnLayout {
            spacing: 10

            // Header Toggle (Pure White Accent)
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Text { text: "Bluetooth"; color: "#f5f5f5"; font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Font.DemiBold }
                    Text {
                        text: root.btPowered ? (root.btScanning ? "Searching for devices..." : (root.connectedBtDevice ? "Connected to " + root.connectedBtDevice.name : "Enabled • Discoverable")) : "Bluetooth Disabled"
                        color: root.btPowered ? "#ffffff" : "#888888"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                    }
                }

                // Custom White Switch (No Blue)
                Rectangle {
                    width: 44; height: 24; radius: 12
                    color: root.btPowered ? "#ffffff" : "#222222"
                    border.width: 1; border.color: root.btPowered ? "#ffffff" : "#383838"
                    Behavior on color { ColorAnimation { duration: SettingsService.reducedMotion ? 0 : 120 } }

                    Rectangle {
                        width: 18; height: 18; radius: 9
                        anchors.verticalCenter: parent.verticalCenter
                        x: root.btPowered ? (parent.width - width - 3) : 3
                        color: root.btPowered ? "#080808" : "#8e8e8e"
                        Behavior on x { NumberAnimation { duration: SettingsService.reducedMotion ? 0 : 120 } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root.btPowered = !root.btPowered;
                            if (BluetoothService.adapter) BluetoothService.adapter.enabled = root.btPowered;
                            else root.runSystemHelper(["bt-power", root.btPowered ? "on" : "off"]);
                        }
                    }
                }
            }

            // Add Device & Scan Button Bar
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 32
                    radius: 8
                    color: addBtMouse.containsMouse ? "#202020" : "#141414"
                    border.width: 1
                    border.color: "#303030"

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 6
                        Text { text: "+"; color: "#ffffff"; font.pixelSize: 14; font.weight: Font.DemiBold }
                        Text { text: "Add Device"; color: "#ffffff"; font.family: Theme.fontFamily; font.pixelSize: 11; font.weight: Font.DemiBold }
                    }

                    MouseArea {
                        id: addBtMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            root.btScanning = true;
                            if (BluetoothService.adapter) BluetoothService.adapter.discovering = true;
                            else root.runSystemHelper(["bt-scan-start"]);
                            bluetoothScanTimer.restart();
                        }
                    }
                }

                Rectangle {
                    width: 32; height: 32; radius: 8
                    color: refreshBtMouse.containsMouse ? "#202020" : "#141414"
                    border.width: 1
                    border.color: "#303030"
                    Text { anchors.centerIn: parent; text: "⟳"; color: "#ffffff"; font.pixelSize: 14 }
                    MouseArea {
                        id: refreshBtMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.btPowered = BluetoothService.adapter?.enabled ?? root.btPowered
                    }
                }
            }

            // Section Label
            Text {
                text: "Paired & Available Devices"
                color: "#a6a6a6"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.DemiBold
                Layout.topMargin: 2
            }

            // Devices List (White Accent + Forget Option)
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ListView {
                    id: btList
                    model: root.displayedBtDevices
                    spacing: 6

                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: btList.width
                        implicitHeight: 52
                        radius: 12
                        color: cardBtMouse.containsMouse ? "#1c1c1c" : "#111111"
                        border.width: 1
                        border.color: modelData.connected ? "#ffffff" : "#222222"

                        MouseArea {
                            id: cardBtMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                if (modelData.connected) {
                                    root.controlBluetooth("disconnect", modelData);
                                } else if (!modelData.paired) {
                                    root.controlBluetooth("pair", modelData);
                                } else {
                                    root.controlBluetooth("connect", modelData);
                                }
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 10

                            // Device Icon (Gamepad, Audio, or Bluetooth in circle)
                            Rectangle {
                                width: 32; height: 32; radius: 16
                                color: modelData.connected ? "#ffffff" : "#222222"
                                Image {
                                    id: btSubIcon
                                    anchors.centerIn: parent
                                    width: 16; height: 16
                                    source: modelData.icon ? Quickshell.iconPath(modelData.icon) : "assets/bluetooth.svg"
                                    visible: false
                                }
                                MultiEffect {
                                    anchors.fill: btSubIcon
                                    source: btSubIcon
                                    colorization: 1.0
                                    colorizationColor: modelData.connected ? "#050505" : "#ffffff"
                                }
                            }

                            // Device Name & Status
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text {
                                    text: modelData.name || modelData.mac
                                    color: "#f5f5f5"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: modelData.pairing ? "Pairing…" : modelData.connected
                                        ? (modelData.batteryAvailable ? "Connected • " + Math.round(modelData.battery * 100) + "%" : "Connected")
                                        : (modelData.paired ? (modelData.trusted ? "Paired • Trusted" : "Paired • Tap to connect") : "Available to pair")
                                    color: modelData.connected ? "#ffffff" : "#888888"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                }
                            }

                            // Forget Bluetooth Device Button
                            Rectangle {
                                z: 10
                                width: 50; height: 26; radius: 6
                                color: forgetBtMouse.containsMouse ? "#2b2b2b" : "#181818"
                                border.width: 1
                                border.color: "#303030"

                                Text {
                                    anchors.centerIn: parent
                                    text: "Forget"
                                    color: "#a6a6a6"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 8
                                    font.weight: Font.DemiBold
                                }

                                MouseArea {
                                    id: forgetBtMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.controlBluetooth("remove", modelData);
                                    }
                                }
                            }

                            // Connect / Disconnect Action Pill (Pure White Accent)
                            Rectangle {
                                z: 10
                                width: modelData.connected ? 74 : 64
                                height: 26; radius: 6
                                color: modelData.connected ? "#ffffff" : (actionBtMouse.containsMouse ? "#282828" : "#181818")
                                border.width: 1
                                border.color: modelData.connected ? "#ffffff" : "#383838"

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.pairing ? "Pairing…" : modelData.connected ? "Connected" : (modelData.paired ? "Connect" : "Pair")
                                    color: modelData.connected ? "#050505" : "#ffffff"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    font.weight: Font.DemiBold
                                }

                                MouseArea {
                                    id: actionBtMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (modelData.connected) {
                                            root.controlBluetooth("disconnect", modelData);
                                        } else if (!modelData.paired) {
                                            root.controlBluetooth("pair", modelData);
                                        } else {
                                            root.controlBluetooth("connect", modelData);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

        }
    }

    // SUBPAGE 3: Night Light Settings (Full Kelvin Control & Schedule)
    Component {
        id: nightlightPage
        ColumnLayout {
            spacing: 10

            // Header Toggle
            RowLayout {
                Layout.fillWidth: true
                ColumnLayout {
                    spacing: 1
                    Text { text: "Night Light"; color: "#f5f5f5"; font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Font.DemiBold }
                    Text {
                        text: NightLightService.active ? (NightLightService.enabled ? "Currently Active (Manual)" : "Currently Active (Scheduled)") : "Disabled"
                        color: NightLightService.active ? "#ffffff" : "#888888"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                    }
                }
                Item { Layout.fillWidth: true }
                Switch {
                    checked: NightLightService.enabled
                    onToggled: NightLightService.toggle()
                }
            }

            // Warmth / Temperature Card
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 124
                radius: 12
                color: "#111111"
                border.width: 1
                border.color: "#222222"

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "Color Temperature"; color: "#f5f5f5"; font.family: Theme.fontFamily; font.pixelSize: 11; font.weight: Font.DemiBold }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: {
                                const k = NightLightService.temperature;
                                const desc = k >= 6000 ? "Neutral D65" : k >= 4500 ? "Natural Warm" : k >= 3500 ? "Sunset Warm" : "Deep Candlelight";
                                return k + "K • " + desc;
                            }
                            color: "#ffffff"
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                        }
                    }

                    // Kelvin Slider (2500K - 6500K)
                    Slider {
                        id: kelvinSlider
                        Layout.fillWidth: true
                        from: 2500
                        to: 6500
                        stepSize: 50
                        value: 9000 - NightLightService.temperature
                        onMoved: NightLightService.setTemperature(9000 - value)

                        background: Rectangle {
                            x: kelvinSlider.leftPadding
                            y: kelvinSlider.topPadding + kelvinSlider.availableHeight / 2 - 2.5
                            implicitWidth: 160
                            implicitHeight: 5
                            width: kelvinSlider.availableWidth
                            height: 5
                            radius: 3
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: "#ff7700" }
                                GradientStop { position: 0.5; color: "#ffa726" }
                                GradientStop { position: 1.0; color: "#90caf9" }
                            }
                        }

                        handle: Rectangle {
                            x: kelvinSlider.leftPadding + kelvinSlider.visualPosition * (kelvinSlider.availableWidth - width)
                            y: kelvinSlider.topPadding + kelvinSlider.availableHeight / 2 - height / 2
                            implicitWidth: 16
                            implicitHeight: 16
                            radius: 8
                            color: "#ffffff"
                            border.width: 1
                            border.color: "#333333"
                        }
                    }

                    // Preset Buttons (2500K, 3500K, 4500K, 6500K)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Repeater {
                            model: [
                                { label: "2500K", k: 2500, name: "Candle" },
                                { label: "3500K", k: 3500, name: "Sunset" },
                                { label: "4500K", k: 4500, name: "Warm" },
                                { label: "6500K", k: 6500, name: "Daylight" }
                            ]

                            Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 24
                                radius: 6
                                color: NightLightService.temperature === modelData.k ? "#ffffff" : (presetMouse.containsMouse ? "#222222" : "#181818")
                                border.width: 1
                                border.color: NightLightService.temperature === modelData.k ? "#ffffff" : "#2a2a2a"

                                Text {
                                    anchors.centerIn: parent
                                    text: parent.modelData.label
                                    color: NightLightService.temperature === parent.modelData.k ? "#000000" : "#cccccc"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    font.weight: Font.DemiBold
                                }

                                MouseArea {
                                    id: presetMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: NightLightService.setTemperature(parent.modelData.k)
                                }
                            }
                        }
                    }
                }
            }

            // Automatic Schedule Card
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: scheduleCol.implicitHeight + 20
                radius: 12
                color: "#111111"
                border.width: 1
                border.color: NightLightService.autoSchedule && NightLightService.inScheduleWindow ? "#ffffff" : "#222222"

                ColumnLayout {
                    id: scheduleCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 10
                    spacing: 8

                    // Header Row: Toggle & Status
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                text: "Automatic Schedule"
                                color: "#f5f5f5"
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }
                            Text {
                                text: {
                                    if (!NightLightService.autoSchedule) return "Off";
                                    const s = NightLightService.formatTime(NightLightService.startHour, NightLightService.startMinute);
                                    const e = NightLightService.formatTime(NightLightService.endHour, NightLightService.endMinute);
                                    return s + " → " + e + (NightLightService.inScheduleWindow ? " • Active now" : " • Scheduled");
                                }
                                color: NightLightService.autoSchedule && NightLightService.inScheduleWindow ? "#ffffff" : "#888888"
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                            }
                        }

                        Switch {
                            checked: NightLightService.autoSchedule
                            onToggled: NightLightService.setAutoSchedule(checked)
                        }
                    }

                    // Presets Row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        visible: NightLightService.autoSchedule

                        Repeater {
                            model: [
                                { label: "Sunset", sH: 20, sM: 0, eH: 7, eM: 0 },
                                { label: "Night",  sH: 22, sM: 0, eH: 6, eM: 0 },
                                { label: "Late",   sH: 23, sM: 0, eH: 8, eM: 0 }
                            ]

                            Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 22
                                radius: 6
                                readonly property bool isCurrent: NightLightService.startHour === modelData.sH &&
                                                                   NightLightService.startMinute === modelData.sM &&
                                                                   NightLightService.endHour === modelData.eH &&
                                                                   NightLightService.endMinute === modelData.eM
                                color: isCurrent ? "#ffffff" : (schedPresetMouse.containsMouse ? "#222222" : "#181818")
                                border.width: 1
                                border.color: isCurrent ? "#ffffff" : "#2a2a2a"

                                Text {
                                    anchors.centerIn: parent
                                    text: parent.modelData.label
                                    color: parent.isCurrent ? "#000000" : "#cccccc"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    font.weight: Font.DemiBold
                                }

                                MouseArea {
                                    id: schedPresetMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        NightLightService.setScheduleTimes(
                                            parent.modelData.sH,
                                            parent.modelData.sM,
                                            parent.modelData.eH,
                                            parent.modelData.eM
                                        );
                                    }
                                }
                            }
                        }
                    }

                    // Time Inputs Row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: NightLightService.autoSchedule

                        // Turn on (Start Time)
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3

                            Text {
                                text: "Turn on"
                                color: "#aaaaaa"
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                font.weight: Font.DemiBold
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 32
                                radius: 8
                                color: "#161616"
                                border.width: 1
                                border.color: "#282828"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 6
                                    anchors.rightMargin: 4
                                    spacing: 2

                                    TextInput {
                                        id: startHourField
                                        text: NightLightService.startHour < 10 ? "0" + NightLightService.startHour : "" + NightLightService.startHour
                                        color: "#f5f5f5"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        verticalAlignment: TextInput.AlignVCenter
                                        horizontalAlignment: TextInput.AlignHCenter
                                        Layout.preferredWidth: 20
                                        maximumLength: 2
                                        validator: IntValidator { bottom: 0; top: 23 }
                                        selectByMouse: true
                                        onEditingFinished: {
                                            const val = Math.max(0, Math.min(23, parseInt(text, 10) || 0));
                                            NightLightService.setStartTime(val, NightLightService.startMinute);
                                            text = NightLightService.startHour < 10 ? "0" + NightLightService.startHour : "" + NightLightService.startHour;
                                        }
                                    }

                                    ColumnLayout {
                                        spacing: 1
                                        Layout.preferredWidth: 13
                                        Layout.fillHeight: true

                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            radius: 3
                                            color: startUpHMouse.containsMouse ? "#282828" : "#181818"
                                            Text { anchors.centerIn: parent; text: "▲"; color: startUpHMouse.containsMouse ? "#ffffff" : "#888888"; font.pixelSize: 6 }
                                            MouseArea {
                                                id: startUpHMouse; anchors.fill: parent; hoverEnabled: true
                                                onClicked: NightLightService.setStartTime((NightLightService.startHour + 1) % 24, NightLightService.startMinute)
                                            }
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            radius: 3
                                            color: startDownHMouse.containsMouse ? "#282828" : "#181818"
                                            Text { anchors.centerIn: parent; text: "▼"; color: startDownHMouse.containsMouse ? "#ffffff" : "#888888"; font.pixelSize: 6 }
                                            MouseArea {
                                                id: startDownHMouse; anchors.fill: parent; hoverEnabled: true
                                                onClicked: NightLightService.setStartTime((NightLightService.startHour + 23) % 24, NightLightService.startMinute)
                                            }
                                        }
                                    }

                                    Text {
                                        text: ":"
                                        color: "#666666"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                    }

                                    TextInput {
                                        id: startMinField
                                        text: NightLightService.startMinute < 10 ? "0" + NightLightService.startMinute : "" + NightLightService.startMinute
                                        color: "#f5f5f5"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        verticalAlignment: TextInput.AlignVCenter
                                        horizontalAlignment: TextInput.AlignHCenter
                                        Layout.preferredWidth: 20
                                        maximumLength: 2
                                        validator: IntValidator { bottom: 0; top: 59 }
                                        selectByMouse: true
                                        onEditingFinished: {
                                            const val = Math.max(0, Math.min(59, parseInt(text, 10) || 0));
                                            NightLightService.setStartTime(NightLightService.startHour, val);
                                            text = NightLightService.startMinute < 10 ? "0" + NightLightService.startMinute : "" + NightLightService.startMinute;
                                        }
                                    }

                                    ColumnLayout {
                                        spacing: 1
                                        Layout.preferredWidth: 13
                                        Layout.fillHeight: true

                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            radius: 3
                                            color: startUpMMouse.containsMouse ? "#282828" : "#181818"
                                            Text { anchors.centerIn: parent; text: "▲"; color: startUpMMouse.containsMouse ? "#ffffff" : "#888888"; font.pixelSize: 6 }
                                            MouseArea {
                                                id: startUpMMouse; anchors.fill: parent; hoverEnabled: true
                                                onClicked: {
                                                    const nextM = (Math.floor(NightLightService.startMinute / 5) * 5 + 5) % 60;
                                                    NightLightService.setStartTime(NightLightService.startHour, nextM);
                                                }
                                            }
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            radius: 3
                                            color: startDownMMouse.containsMouse ? "#282828" : "#181818"
                                            Text { anchors.centerIn: parent; text: "▼"; color: startDownMMouse.containsMouse ? "#ffffff" : "#888888"; font.pixelSize: 6 }
                                            MouseArea {
                                                id: startDownMMouse; anchors.fill: parent; hoverEnabled: true
                                                onClicked: {
                                                    const nextM = (Math.ceil(NightLightService.startMinute / 5) * 5 + 55) % 60;
                                                    NightLightService.setStartTime(NightLightService.startHour, nextM);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Turn off (End Time)
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3

                            Text {
                                text: "Turn off"
                                color: "#aaaaaa"
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                font.weight: Font.DemiBold
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 32
                                radius: 8
                                color: "#161616"
                                border.width: 1
                                border.color: "#282828"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 6
                                    anchors.rightMargin: 4
                                    spacing: 2

                                    TextInput {
                                        id: endHourField
                                        text: NightLightService.endHour < 10 ? "0" + NightLightService.endHour : "" + NightLightService.endHour
                                        color: "#f5f5f5"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        verticalAlignment: TextInput.AlignVCenter
                                        horizontalAlignment: TextInput.AlignHCenter
                                        Layout.preferredWidth: 20
                                        maximumLength: 2
                                        validator: IntValidator { bottom: 0; top: 23 }
                                        selectByMouse: true
                                        onEditingFinished: {
                                            const val = Math.max(0, Math.min(23, parseInt(text, 10) || 0));
                                            NightLightService.setEndTime(val, NightLightService.endMinute);
                                            text = NightLightService.endHour < 10 ? "0" + NightLightService.endHour : "" + NightLightService.endHour;
                                        }
                                    }

                                    ColumnLayout {
                                        spacing: 1
                                        Layout.preferredWidth: 13
                                        Layout.fillHeight: true

                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            radius: 3
                                            color: endUpHMouse.containsMouse ? "#282828" : "#181818"
                                            Text { anchors.centerIn: parent; text: "▲"; color: endUpHMouse.containsMouse ? "#ffffff" : "#888888"; font.pixelSize: 6 }
                                            MouseArea {
                                                id: endUpHMouse; anchors.fill: parent; hoverEnabled: true
                                                onClicked: NightLightService.setEndTime((NightLightService.endHour + 1) % 24, NightLightService.endMinute)
                                            }
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            radius: 3
                                            color: endDownHMouse.containsMouse ? "#282828" : "#181818"
                                            Text { anchors.centerIn: parent; text: "▼"; color: endDownHMouse.containsMouse ? "#ffffff" : "#888888"; font.pixelSize: 6 }
                                            MouseArea {
                                                id: endDownHMouse; anchors.fill: parent; hoverEnabled: true
                                                onClicked: NightLightService.setEndTime((NightLightService.endHour + 23) % 24, NightLightService.endMinute)
                                            }
                                        }
                                    }

                                    Text {
                                        text: ":"
                                        color: "#666666"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                    }

                                    TextInput {
                                        id: endMinField
                                        text: NightLightService.endMinute < 10 ? "0" + NightLightService.endMinute : "" + NightLightService.endMinute
                                        color: "#f5f5f5"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        verticalAlignment: TextInput.AlignVCenter
                                        horizontalAlignment: TextInput.AlignHCenter
                                        Layout.preferredWidth: 20
                                        maximumLength: 2
                                        validator: IntValidator { bottom: 0; top: 59 }
                                        selectByMouse: true
                                        onEditingFinished: {
                                            const val = Math.max(0, Math.min(59, parseInt(text, 10) || 0));
                                            NightLightService.setEndTime(NightLightService.endHour, val);
                                            text = NightLightService.endMinute < 10 ? "0" + NightLightService.endMinute : "" + NightLightService.endMinute;
                                        }
                                    }

                                    ColumnLayout {
                                        spacing: 1
                                        Layout.preferredWidth: 13
                                        Layout.fillHeight: true

                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            radius: 3
                                            color: endUpMMouse.containsMouse ? "#282828" : "#181818"
                                            Text { anchors.centerIn: parent; text: "▲"; color: endUpMMouse.containsMouse ? "#ffffff" : "#888888"; font.pixelSize: 6 }
                                            MouseArea {
                                                id: endUpMMouse; anchors.fill: parent; hoverEnabled: true
                                                onClicked: {
                                                    const nextM = (Math.floor(NightLightService.endMinute / 5) * 5 + 5) % 60;
                                                    NightLightService.setEndTime(NightLightService.endHour, nextM);
                                                }
                                            }
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            radius: 3
                                            color: endDownMMouse.containsMouse ? "#282828" : "#181818"
                                            Text { anchors.centerIn: parent; text: "▼"; color: endDownMMouse.containsMouse ? "#ffffff" : "#888888"; font.pixelSize: 6 }
                                            MouseArea {
                                                id: endDownMMouse; anchors.fill: parent; hoverEnabled: true
                                                onClicked: {
                                                    const nextM = (Math.ceil(NightLightService.endMinute / 5) * 5 + 55) % 60;
                                                    NightLightService.setEndTime(NightLightService.endHour, nextM);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Keep text fields synced when service properties change
                    Connections {
                        target: NightLightService
                        function onStartHourChanged() {
                            if (!startHourField.activeFocus) {
                                startHourField.text = NightLightService.startHour < 10 ? "0" + NightLightService.startHour : "" + NightLightService.startHour;
                            }
                        }
                        function onStartMinuteChanged() {
                            if (!startMinField.activeFocus) {
                                startMinField.text = NightLightService.startMinute < 10 ? "0" + NightLightService.startMinute : "" + NightLightService.startMinute;
                            }
                        }
                        function onEndHourChanged() {
                            if (!endHourField.activeFocus) {
                                endHourField.text = NightLightService.endHour < 10 ? "0" + NightLightService.endHour : "" + NightLightService.endHour;
                            }
                        }
                        function onEndMinuteChanged() {
                            if (!endMinField.activeFocus) {
                                endMinField.text = NightLightService.endMinute < 10 ? "0" + NightLightService.endMinute : "" + NightLightService.endMinute;
                            }
                        }
                    }
                }
            }

            // Explanatory note
            Text {
                Layout.fillWidth: true
                text: "Reduces short-wavelength blue light to help prevent eye strain and support natural sleep cycles."
                color: "#727272"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                wrapMode: Text.WordWrap
            }

            Item { Layout.fillHeight: true }
        }
    }

    // SUBPAGE 4: Volume Mixer
    Component {
        id: audioPage
        ColumnLayout {
            spacing: 8
            Text { text: "Audio Output Streams"; color: "#f5f5f5"; font.family: Theme.fontFamily; font.pixelSize: 12; font.weight: Font.DemiBold }

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                ListView {
                    id: audioList
                    model: (Pipewire.nodes && Pipewire.nodes.values) ? Pipewire.nodes.values.filter(n => n.properties?.["media.class"] === "Stream/Output/Audio") : []
                    spacing: 6
                    delegate: Rectangle {
                        required property var modelData
                        width: audioList.width
                        height: 56
                        radius: 10
                        color: "#111111"
                        border.width: 1
                        border.color: "#222222"

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: modelData.properties?.["application.name"] || modelData.name || "Audio Stream"
                                    color: "#f5f5f5"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: Math.round((modelData.audio?.volume ?? 1) * 100) + "%"
                                    color: "#a6a6a6"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Item {
                                    width: 14; height: 14
                                    Image {
                                        id: stVol
                                        anchors.fill: parent
                                        source: modelData.audio?.muted ? "assets/speaker-muted-mono.svg" : "assets/volume.svg"
                                        visible: false
                                    }
                                    MultiEffect {
                                        anchors.fill: stVol
                                        source: stVol
                                        colorization: 1.0
                                        colorizationColor: "#e6e6e6"
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: AudioService.toggleMute(modelData)
                                    }
                                }
                                Slider {
                                    Layout.fillWidth: true
                                    from: 0.0; to: 1.5
                                    value: modelData.audio?.volume ?? 1.0
                                    onMoved: AudioService.setVolume(modelData, value)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
