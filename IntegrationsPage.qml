import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import qs

ScrollView {
    id: root
    clip: true
    contentWidth: availableWidth
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
    ScrollBar.vertical.policy: ScrollBar.AlwaysOff
    Component.onCompleted: { IntegrationService.refreshAudio(); OutputService.refresh(); }

    Item {
        width: root.availableWidth
        implicitHeight: intCol.implicitHeight + 40

        ColumnLayout {
            id: intCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 24
            anchors.rightMargin: 24
            anchors.topMargin: 18
            spacing: 16

            SettingsGroup {
                title: "POWER & BLUETOOTH"
                Repeater {
                    model: UPower.devices.values.filter(d => d.ready && (!d.isLaptopBattery || d.isPresent))
                    SettingsButton {
                        required property var modelData
                        label: modelData.model || (modelData.isLaptopBattery ? "Battery" : modelData.nativePath)
                        description: Math.round(modelData.percentage * 100) + "% • " + (modelData.timeToEmpty > 0 ? Math.ceil(modelData.timeToEmpty / 60) + " min remaining" : modelData.timeToFull > 0 ? Math.ceil(modelData.timeToFull / 60) + " min to full" : "External power / idle") + (modelData.healthSupported ? " • " + Math.round(modelData.healthPercentage * 100) + "% health" : "")
                        buttonText: "Power"; enabled: false
                    }
                }
                SettingsChoice {
                    label: "Bluetooth adapter"; description: BluetoothService.adapter?.name || "No adapter available"
                    value: SettingsService.bluetoothAdapter
                    choices: [{value:"", label:"Default adapter"}].concat(Bluetooth.adapters.values.map(a => ({value:a.dbusPath,label:a.name + " • " + a.adapterId})))
                    onSelected: value => SettingsService.bluetoothAdapter = value
                }
                Repeater {
                    model: BluetoothService.adapter?.devices.values.filter(d => d.batteryAvailable) || []
                    SettingsButton { required property var modelData; label: modelData.name || modelData.address; description: Math.round(modelData.battery * 100) + "% battery"; buttonText: modelData.connected ? "Connected" : "Offline"; enabled: false }
                }
            }

            SettingsGroup {
                title: "AUDIO PROFILES & PORTS"
                SettingsButton { label: "Refresh audio devices"; description: "Profiles and ports are queried only on demand"; buttonText: "Refresh"; onClicked: IntegrationService.refreshAudio() }
                Repeater {
                    model: IntegrationService.audioDetails.cards || []
                    SettingsChoice {
                        required property var modelData
                        label: modelData.name; description: modelData.active; value: modelData.active
                        choices: modelData.profiles.map(p => ({value:p.name,label:p.description,available:p.available}))
                        onSelected: value => SystemService.enqueue(["audio-profile", modelData.name, value], "audio-profile", "", false)
                    }
                }
                Repeater {
                    model: (IntegrationService.audioDetails.sinks || []).map(d => Object.assign({kind:"sink"},d)).concat((IntegrationService.audioDetails.sources || []).map(d => Object.assign({kind:"source"},d)))
                    SettingsChoice {
                        required property var modelData
                        visible: modelData.ports.length > 0
                        label: modelData.description; description: modelData.active; value: modelData.active
                        choices: modelData.ports.map(p => ({value:p.name,label:p.description,available:p.available}))
                        onSelected: value => SystemService.enqueue(["audio-port", modelData.kind, modelData.name, value], "audio-port", "", false)
                    }
                }
            }

            SettingsGroup {
                title: "NETWORK & CALENDAR"
                SettingsButton { label: "Internet connectivity"; description: SystemService.networkAvailable ? SystemService.connectivity + " • " + SystemService.networkAddresses.join(", ") : "NetworkManager unavailable"; buttonText: "Check"; enabled: SystemService.networkAvailable; onClicked: SystemService.enqueue(["network-check"], "network", "network-check", false) }
                SettingsButton { visible: NetworkService.busy; label: "Network connection in progress"; description: NetworkService.connectionName; buttonText: "Cancel"; onClicked: NetworkService.cancel() }
                Repeater {
                    model: SystemService.vpns
                    SettingsButton { required property var modelData; label: modelData.name; description: modelData.state || "Disconnected"; buttonText: modelData.active ? "Disconnect" : "Connect"; onClicked: modelData.active ? SystemService.enqueue(["vpn-down",modelData.uuid], "network", "vpn", false) : NetworkService.activate(modelData.uuid,"vpn") }
                }
                SettingsField { label: "Import local calendar"; description: "Enter an .ics path; recurring events are reported and skipped"; placeholder: "~/calendar.ics"; onAccepted: value => CalendarService.importFile(value) }
            }

            SettingsGroup {
                title: "GAMING & DISPLAYS"
                SettingsField { label: "Automatic gaming mode"; description: "Comma-separated exact window app IDs; empty disables automation"; text: SettingsService.gamingApps; onAccepted: value => SettingsService.gamingApps = value }
                SettingsField { id: gameId; label: "Per-game app ID"; description: "Use the exact app ID shown in the window picker"; placeholder:"steam_app_123" }
                SettingsToggle { id: gamePower; label: "Game performance profile"; checked: true; onToggled: value => gamePower.checked = value }
                SettingsToggle { id: gameTearing; label: "Game tearing policy"; checked: false; onToggled: value => gameTearing.checked = value }
                SettingsField { id: gameOutput; label: "Game output profile"; description: "Optional name of a previously saved display layout" }
                SettingsButton { label: "Save per-game rule"; description: "The first matching rule wins; previous state is restored after exit"; buttonText:"Save"; enabled:gameId.text.trim().length>0; onClicked:GamingService.saveRule(gameId.text,gamePower.checked,gameTearing.checked,gameOutput.text) }
                Repeater { model:GamingService.rules; SettingsButton { required property var modelData; label:modelData.appId; description:(modelData.performance ? "Performance" : "Keep power") + (modelData.tearing ? " • tearing" : "") + (modelData.outputProfile ? " • " + modelData.outputProfile : ""); buttonText:"Remove"; onClicked:GamingService.removeRule(modelData.appId) } }
                SettingsToggle { label: "Restore dock profiles"; description: "Apply the unique matching saved layout after hotplug; confirm within 15s"; checked: SettingsService.outputAutoRestore; onToggled: value => SettingsService.outputAutoRestore = value }
                SettingsButton { label: "Refresh displays"; description: "Read the compositor's supported modes and VRR capability"; buttonText: "Refresh"; enabled: !OutputService.busy; onClicked: OutputService.refresh() }
                Repeater {
                    model: OutputService.outputs
                    ColumnLayout {
                        id: outputRow
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true; spacing: 5
                        SettingsToggle { label: outputRow.modelData.name; description: outputRow.modelData.description; checked: outputRow.modelData.enabled; onToggled: value => OutputService.edit(outputRow.index,"enabled",value) }
                        SettingsChoice {
                            label: "Display mode"; description: outputRow.modelData.width + "×" + outputRow.modelData.height + " @ " + (outputRow.modelData.refresh / 1000).toFixed(2) + " Hz"
                            value: String(outputRow.modelData.modes.findIndex(m => m.width === outputRow.modelData.width && m.height === outputRow.modelData.height && m.refresh === outputRow.modelData.refresh))
                            choices: outputRow.modelData.modes.map((m,i) => ({value:String(i),label:m.width + "×" + m.height + " @ " + (m.refresh/1000).toFixed(2) + " Hz"}))
                            onSelected: value => {
                                const mode = outputRow.modelData.modes[Number(value)];
                                const copy = OutputService.outputs.map(o => Object.assign({},o));
                                Object.assign(copy[outputRow.index], {width:mode.width,height:mode.height,refresh:mode.refresh});
                                OutputService.outputs = copy;
                            }
                        }
                        SettingsChoice {
                            label: "Display scale (100% - 200%)"
                            description: Math.round((outputRow.modelData.scale || 1.0) * 100) + "% (" + (outputRow.modelData.scale || 1.0) + "×)"
                            value: String(outputRow.modelData.scale || 1.0)
                            choices: [
                                { label: "100% (Standard 1.0×)", value: "1" },
                                { label: "125% (1.25×)", value: "1.25" },
                                { label: "150% (Recommended 1.5×)", value: "1.5" },
                                { label: "175% (1.75×)", value: "1.75" },
                                { label: "200% (2.0× HiDPI)", value: "2" }
                            ]
                            onSelected: value => OutputService.edit(outputRow.index, "scale", Number(value))
                        }
                        SettingsField { label: "Position x,y"; text: outputRow.modelData.x + "," + outputRow.modelData.y; onAccepted: value => { const xy=value.split(","); if(xy.length===2 && xy.every(v => Number.isFinite(Number(v)))) { const copy=OutputService.outputs.map(o=>Object.assign({},o)); Object.assign(copy[outputRow.index],{x:Number(xy[0]),y:Number(xy[1])}); OutputService.outputs=copy; } } }
                        SettingsChoice { label: "Rotation / transform"; description: String(outputRow.modelData.transform); choices: ["Normal","90°","180°","270°","Flipped","Flipped 90°","Flipped 180°","Flipped 270°"].map((label,i)=>({label:label,value:String(i)})); onSelected: value => OutputService.edit(outputRow.index,"transform",Number(value)) }
                        SettingsToggle { label: "Variable refresh rate"; description: outputRow.modelData.adaptiveSync === null ? "Not exposed by this compositor" : "The compositor tests whether this output supports the request"; enabled: outputRow.modelData.adaptiveSync !== null; checked: outputRow.modelData.adaptiveSync === true; onToggled: value => OutputService.edit(outputRow.index,"adaptiveSync",value) }
                    }
                }
                SettingsButton { label: "Apply display changes"; description: "Test first, then revert unless explicitly kept"; buttonText: "Apply"; enabled: OutputService.outputs.length > 0 && !OutputService.busy; onClicked: OutputService.apply(OutputService.outputs) }
                SettingsField { label: "Save current layout"; description: "Enter a profile name after keeping the desired layout"; enabled: !OutputService.busy; onAccepted: value => OutputService.save(value) }
                Repeater { model: Object.keys(OutputService.profiles); SettingsButton { required property string modelData; label: modelData; description: "Restore saved output profile"; buttonText: "Apply"; enabled: !OutputService.busy; onClicked: OutputService.apply(OutputService.profiles[modelData]) } }
            }

            SettingsGroup {
                title: "SHARING & DIAGNOSTICS"
                SettingsButton { label: RecorderService.recording ? "Weylume capture" : "Weylume capture inactive"; description: RecorderService.stateLabel; buttonText: "Stop"; enabled: RecorderService.recording; onClicked: RecorderService.stop() }
                SettingsButton { visible: RecorderService.recording; label: "Recording playback state"; description: RecorderService.ipc ? "Waits for the recorder to acknowledge each request" : "This recorder version has no acknowledged pause control"; buttonText: RecorderService.paused ? "Resume" : "Pause"; enabled: RecorderService.active && RecorderService.ipc && !RecorderService.stopping; onClicked: RecorderService.togglePause() }
                SettingsButton { label: "Run diagnostics"; description: "Architecture, services and required capture utilities"; buttonText: "Check"; onClicked: IntegrationService.diagnose() }
                Text { Layout.fillWidth: true; Layout.bottomMargin: 8; wrapMode: Text.Wrap; text: (IntegrationService.diagnostics.summary || []).join("\n"); color: SettingsService.darkMode !== false ? "#8E8E93" : "#6E6E73"; font.family: Theme.fontFamily; font.pixelSize: 11 }
            }
        }
    }
}
