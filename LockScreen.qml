import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.UPower
import qs

Scope {
    id: root

    WlSessionLock {
        id: sessionLock
        locked: ShellState.isLocked

        surface: Component {
            WlSessionLockSurface {
                id: surfaceWindow
                color: "#000000"

                readonly property bool isPrimaryScreen: !surfaceWindow.screen || surfaceWindow.screen === Quickshell.screens[0]

                onVisibleChanged: if (visible && isPrimaryScreen) Qt.callLater(() => pinInput.forceActiveFocus())

                Rectangle {
                    id: lockRoot
                    anchors.fill: parent
                    color: "#000000"
                    clip: true
                    focus: true
                    Keys.forwardTo: [pinInput]

                    property bool revealPassword: false

                    function formatDate(d) {
                        return Qt.formatDate(d, "dddd, MMMM d");
                    }

                    function formatTime(h, m) {
                        if (SettingsService.clock24Hour) {
                            return (h < 10 ? "0" + h : h) + ":" + (m < 10 ? "0" + m : m);
                        }
                        const hr = h % 12 || 12;
                        return hr + ":" + (m < 10 ? "0" + m : m);
                    }

                    function attemptUnlock() {
                        const val = pinInput.text;
                        const target = SettingsService.lockscreenPin;
                        if (!val) {
                            helperText.text = "Enter " + (SettingsService.lockscreenMode === "pin" ? "PIN" : "password");
                            pinInput.forceActiveFocus();
                            return;
                        }
                        if (val === target) {
                            helperText.text = "";
                            pinInput.text = "";
                            ShellState.unlock();
                        } else {
                            helperText.text = "Incorrect " + (SettingsService.lockscreenMode === "pin" ? "PIN" : "password");
                            shakeAnim.restart();
                            pinInput.selectAll();
                            pinInput.forceActiveFocus();
                        }
                    }

                    // Background Click Area (refocuses PIN input when clicked anywhere)
                    MouseArea {
                        anchors.fill: parent
                        onClicked: pinInput.forceActiveFocus()
                    }

                    // Focus retry timer: only for primary screen, stops as soon as activeFocus is achieved
                    Timer {
                        id: focusRetryTimer
                        property int attempts: 0
                        interval: 80
                        repeat: true
                        running: surfaceWindow.isPrimaryScreen && !pinInput.activeFocus && attempts < 15
                        onTriggered: {
                            attempts++;
                            pinInput.forceActiveFocus();
                            if (pinInput.activeFocus) stop();
                        }
                    }

                    Keys.onEscapePressed: {
                        pinInput.text = "";
                        helperText.text = "";
                        pinInput.forceActiveFocus();
                    }

                    Keys.onPressed: event => {
                        if (!pinInput.activeFocus) {
                            pinInput.forceActiveFocus();
                        }
                    }

                    Connections {
                        target: ShellState
                        function onIsLockedChanged() {
                            if (ShellState.isLocked) {
                                pinInput.text = "";
                                helperText.text = "";
                                if (surfaceWindow.isPrimaryScreen) {
                                    focusRetryTimer.attempts = 0;
                                    focusRetryTimer.start();
                                    Qt.callLater(() => pinInput.forceActiveFocus());
                                }
                            }
                        }
                    }

                    // TOP: Date and Clock
                    Column {
                        id: clockCol
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: Math.max(55, Math.min(128, lockRoot.height * 0.102))
                        spacing: 4

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: lockRoot.formatDate(ShellState.currentDate)
                            color: Qt.rgba(1, 1, 1, 0.96)
                            font.family: Theme.fontFamily
                            font.pixelSize: Math.max(18, Math.min(23, lockRoot.width * 0.015))
                            font.weight: Font.Medium
                            font.letterSpacing: -0.4
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: lockRoot.formatTime(ShellState.currentHour, ShellState.currentMinute)
                            color: "#FFFFFF"
                            font.family: Theme.fontFamily
                            readonly property real clockSize: Math.max(104, Math.min(184, lockRoot.width * 0.124))
                            font.pixelSize: clockSize
                            font.weight: Font.DemiBold
                            font.letterSpacing: Math.round(-0.035 * clockSize)
                            font.features: { "tnum": 1 }
                        }
                    }

                    // CENTER: Password Pill Form
                    Column {
                        id: loginCol
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Math.max(115, Math.min(175, lockRoot.height * 0.155))
                        spacing: 0

                        // Password / PIN Form Pill (Pure AMOLED)
                        Item {
                            id: formWrapper
                            width: Math.min(270, lockRoot.width - 48)
                            height: 44
                            anchors.horizontalCenter: parent.horizontalCenter

                            Rectangle {
                                id: formPill
                                anchors.fill: parent
                                radius: 22
                                transform: Translate { id: pillTranslate; x: 0 }
                                color: pinInput.activeFocus ? "#0A0A0D" : "#000000"
                                border.width: pinInput.activeFocus ? 1.5 : 1.0
                                border.color: pinInput.activeFocus ? "#FFFFFF" : ((pillHoverMouse.containsMouse || eyeMouse.containsMouse || submitMouse.containsMouse) ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(1, 1, 1, 0.22))

                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on border.color { ColorAnimation { duration: 120 } }

                                MouseArea {
                                    id: pillHoverMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    propagateComposedEvents: true
                                    cursorShape: Qt.IBeamCursor
                                    onClicked: mouse => {
                                        pinInput.forceActiveFocus();
                                        mouse.accepted = false;
                                    }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 16
                                    anchors.rightMargin: 6
                                    spacing: 6

                                    TextInput {
                                        id: pinInput
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        verticalAlignment: TextInput.AlignVCenter
                                        echoMode: lockRoot.revealPassword ? TextInput.Normal : TextInput.Password
                                        color: "#FFFFFF"
                                        selectionColor: Qt.rgba(1, 1, 1, 0.25)
                                        selectedTextColor: "#FFFFFF"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: lockRoot.revealPassword ? 14 : 16
                                        font.weight: Font.DemiBold
                                        font.letterSpacing: lockRoot.revealPassword ? 0.5 : 3.0
                                        clip: true
                                        selectByMouse: true
                                        focus: true
                                        activeFocusOnTab: true

                                        validator: SettingsService.lockscreenMode === "pin" ? pinValidator : null
                                        inputMethodHints: SettingsService.lockscreenMode === "pin"
                                            ? (Qt.ImhDigitsOnly | Qt.ImhHiddenText | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText)
                                            : (Qt.ImhHiddenText | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText)

                                        RegularExpressionValidator {
                                            id: pinValidator
                                            regularExpression: /^[0-9]*$/
                                        }

                                        Keys.onEscapePressed: {
                                            pinInput.text = "";
                                            helperText.text = "";
                                        }

                                        onAccepted: lockRoot.attemptUnlock()

                                        onTextChanged: {
                                            helperText.text = "";
                                            // Auto-unlock requirement: 4 or more numbers if correct logs in directly without pressing enter (PIN mode only)
                                            if (SettingsService.autoUnlockPin && SettingsService.lockscreenMode === "pin" && text.length >= 4) {
                                                if (text === SettingsService.lockscreenPin) {
                                                    helperText.text = "";
                                                    text = "";
                                                    ShellState.unlock();
                                                }
                                            }
                                        }

                                        Text {
                                            anchors.left: parent.left
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: !pinInput.text && !pinInput.inputMethodComposing
                                            text: SettingsService.lockscreenMode === "pin" ? "Enter PIN" : "Enter Password"
                                            color: Qt.rgba(1, 1, 1, 0.40)
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 13
                                            font.weight: Font.Normal
                                            font.letterSpacing: 0
                                        }
                                    }

                                    // Eye Icon Button (Toggle visibility)
                                    Rectangle {
                                        Layout.preferredWidth: 30
                                        Layout.preferredHeight: 30
                                        radius: 15
                                        color: eyeMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"

                                        Behavior on color { ColorAnimation { duration: 100 } }

                                        MouseArea {
                                            id: eyeMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                lockRoot.revealPassword = !lockRoot.revealPassword;
                                                pinInput.forceActiveFocus();
                                            }
                                        }

                                        Image {
                                            anchors.centerIn: parent
                                            width: 16
                                            height: 16
                                            source: lockRoot.revealPassword ? "assets/eye-off.svg" : "assets/eye.svg"
                                            opacity: eyeMouse.containsMouse ? 1.0 : 0.65
                                            Behavior on opacity { NumberAnimation { duration: 100 } }
                                        }
                                    }

                                    // Submit Circular Button (Arrow Right)
                                    Rectangle {
                                        id: submitBtn
                                        Layout.preferredWidth: 32
                                        Layout.preferredHeight: 32
                                        radius: 16
                                        color: submitMouse.pressed ? Qt.rgba(1, 1, 1, 0.75) : (submitMouse.containsMouse ? "#FFFFFF" : Qt.rgba(1, 1, 1, 0.90))
                                        scale: submitMouse.pressed ? 0.92 : (submitMouse.containsMouse ? 1.05 : 1.0)

                                        Behavior on color { ColorAnimation { duration: 100 } }
                                        Behavior on scale { NumberAnimation { duration: 100 } }

                                        MouseArea {
                                            id: submitMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: lockRoot.attemptUnlock()
                                        }

                                        Image {
                                            anchors.centerIn: parent
                                            width: 14
                                            height: 14
                                            source: "assets/arrow-right.svg"
                                        }
                                    }
                                }
                            }
                        }

                        // Shake animation on incorrect attempt
                        SequentialAnimation {
                            id: shakeAnim
                            alwaysRunToEnd: true
                            onStarted: pillTranslate.x = 0
                            onStopped: pillTranslate.x = 0
                            NumberAnimation { target: pillTranslate; property: "x"; to: -12; duration: 42; easing.type: Easing.OutQuad }
                            NumberAnimation { target: pillTranslate; property: "x"; to: 12; duration: 42; easing.type: Easing.InOutQuad }
                            NumberAnimation { target: pillTranslate; property: "x"; to: -8; duration: 42; easing.type: Easing.InOutQuad }
                            NumberAnimation { target: pillTranslate; property: "x"; to: 8; duration: 42; easing.type: Easing.InOutQuad }
                            NumberAnimation { target: pillTranslate; property: "x"; to: -3; duration: 35; easing.type: Easing.InOutQuad }
                            NumberAnimation { target: pillTranslate; property: "x"; to: 0; duration: 35; easing.type: Easing.OutQuad }
                        }

                        // Helper / Error Text
                        Item {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: formWrapper.width
                            height: 24

                            Text {
                                id: helperText
                                anchors.centerIn: parent
                                text: ""
                                color: "#FF6B6B"
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.Medium
                            }
                        }
                    }

                    // BOTTOM FOOTER: Power actions
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Math.max(28, 34)
                        spacing: Math.max(34, Math.min(52, lockRoot.width * 0.038))

                        // Sleep
                        Column {
                            spacing: 8
                            width: 56

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 40
                                height: 40
                                radius: 20
                                color: sleepMouse.pressed ? Qt.rgba(1, 1, 1, 0.22) : (sleepMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06))
                                border.width: 1
                                border.color: sleepMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.35) : Qt.rgba(1, 1, 1, 0.14)
                                y: sleepMouse.containsMouse ? -2 : 0
                                scale: sleepMouse.pressed ? 0.94 : 1.0

                                Behavior on y { NumberAnimation { duration: 120 } }
                                Behavior on scale { NumberAnimation { duration: 100 } }
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on border.color { ColorAnimation { duration: 120 } }

                                Image {
                                    anchors.centerIn: parent
                                    width: 17
                                    height: 17
                                    source: "assets/moon.svg"
                                    opacity: sleepMouse.containsMouse ? 1.0 : 0.8
                                }

                                MouseArea {
                                    id: sleepMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: ShellState.requestSessionAction("suspend")
                                }
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "Sleep"
                                color: sleepMouse.containsMouse ? "#FFFFFF" : Qt.rgba(1, 1, 1, 0.75)
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.Medium
                                font.letterSpacing: -0.2
                            }
                        }

                        // Restart
                        Column {
                            spacing: 8
                            width: 56

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 40
                                height: 40
                                radius: 20
                                color: restartMouse.pressed ? Qt.rgba(1, 1, 1, 0.22) : (restartMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06))
                                border.width: 1
                                border.color: restartMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.35) : Qt.rgba(1, 1, 1, 0.14)
                                y: restartMouse.containsMouse ? -2 : 0
                                scale: restartMouse.pressed ? 0.94 : 1.0

                                Behavior on y { NumberAnimation { duration: 120 } }
                                Behavior on scale { NumberAnimation { duration: 100 } }
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on border.color { ColorAnimation { duration: 120 } }

                                Image {
                                    anchors.centerIn: parent
                                    width: 17
                                    height: 17
                                    source: "assets/restart.svg"
                                    opacity: restartMouse.containsMouse ? 1.0 : 0.8
                                }

                                MouseArea {
                                    id: restartMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: ShellState.requestSessionAction("reboot")
                                }
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "Restart"
                                color: restartMouse.containsMouse ? "#FFFFFF" : Qt.rgba(1, 1, 1, 0.75)
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.Medium
                                font.letterSpacing: -0.2
                            }
                        }

                        // Shut Down
                        Column {
                            spacing: 8
                            width: 56

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 40
                                height: 40
                                radius: 20
                                color: shutMouse.pressed ? Qt.rgba(1, 1, 1, 0.22) : (shutMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06))
                                border.width: 1
                                border.color: shutMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.35) : Qt.rgba(1, 1, 1, 0.14)
                                y: shutMouse.containsMouse ? -2 : 0
                                scale: shutMouse.pressed ? 0.94 : 1.0

                                Behavior on y { NumberAnimation { duration: 120 } }
                                Behavior on scale { NumberAnimation { duration: 100 } }
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on border.color { ColorAnimation { duration: 120 } }

                                Image {
                                    anchors.centerIn: parent
                                    width: 17
                                    height: 17
                                    source: "assets/shutdown.svg"
                                    opacity: shutMouse.containsMouse ? 1.0 : 0.8
                                }

                                MouseArea {
                                    id: shutMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: ShellState.requestSessionAction("shutdown")
                                }
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "Shut Down"
                                color: shutMouse.containsMouse ? "#FFFFFF" : Qt.rgba(1, 1, 1, 0.75)
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.Medium
                                font.letterSpacing: -0.2
                            }
                        }
                    }

                    // BOTTOM RIGHT STATUS: Wi-Fi and Battery
                    Row {
                        anchors.right: parent.right
                        anchors.rightMargin: 30
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Math.max(36, 40)
                        spacing: 16

                        // Wi-Fi Icon
                        Image {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 18
                            height: 18
                            source: "assets/wifi.svg"
                            opacity: SystemService.wifiEnabled ? 0.9 : 0.4
                        }

                        // Battery Indicator
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6
                            visible: (UPower.displayDevice?.ready ?? false) && (UPower.displayDevice?.isLaptopBattery ?? false)

                            Rectangle {
                                width: 24
                                height: 13
                                radius: 3
                                color: "transparent"
                                border.width: 1.5
                                border.color: Qt.rgba(1, 1, 1, 0.85)

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    anchors.margins: 2
                                    width: Math.max(2, (parent.width - 4) * Math.min(1.0, (UPower.displayDevice?.percentage ?? 1.0)))
                                    radius: 1.5
                                    color: (UPower.displayDevice?.percentage ?? 1.0) < 0.2 ? "#FF5555" : "#FFFFFF"
                                }

                                // Battery nipple
                                Rectangle {
                                    anchors.left: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 2
                                    height: 5
                                    radius: 1
                                    color: Qt.rgba(1, 1, 1, 0.85)
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Math.round((UPower.displayDevice?.percentage ?? 1.0) * 100) + "%"
                                color: Qt.rgba(1, 1, 1, 0.80)
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.Medium
                            }
                        }
                    }
                }
            }
        }
    }
}
