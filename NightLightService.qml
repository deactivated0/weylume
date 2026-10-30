pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property bool enabled: false
    property int temperature: 3800
    property bool autoSchedule: true
    property int startHour: 20
    property int startMinute: 0
    property int endHour: 7
    property int endMinute: 0
    property bool inScheduleWindow: false
    property int queuedHardwareTemperature: 6500
    property int activeHardwareTemperature: 6500
    property bool temperatureWritePending: false
    property bool temperatureBackendWriting: false

    readonly property bool active: enabled || (autoSchedule && inScheduleWindow)

    onActiveChanged: queueHardwareTemperature()
    onTemperatureChanged: queueHardwareTemperature()
    onStartHourChanged: checkSchedule()
    onStartMinuteChanged: checkSchedule()
    onEndHourChanged: checkSchedule()
    onEndMinuteChanged: checkSchedule()

    function queueHardwareTemperature() {
        const target = root.active ? root.temperature : 6500;
        if (!root.temperatureBackendWriting && !temperatureWriter.running && target === root.activeHardwareTemperature) return;
        root.queuedHardwareTemperature = target;
        root.temperatureWritePending = true;
        root.startTemperatureWrite();
    }

    function startTemperatureWrite() {
        if (root.temperatureBackendWriting || temperatureWriter.running || temperatureFallback.running || !root.temperatureWritePending) return;
        root.temperatureWritePending = false;
        root.activeHardwareTemperature = root.queuedHardwareTemperature;
        root.temperatureBackendWriting = SystemData.writeGamma("Temperature", root.activeHardwareTemperature, root.finishTemperatureWrite);
        if (root.temperatureBackendWriting) return;
        temperatureWriter.command = [
            Quickshell.shellPath("weylume-native"), "gamma-set", "Temperature", String(root.activeHardwareTemperature)
        ];
        temperatureWriter.running = true;
    }

    function finishTemperatureWrite(success) {
        root.temperatureBackendWriting = false;
        if (!success) {
            temperatureFallback.command = [Quickshell.shellPath("weylume-native"), "temperature", String(root.activeHardwareTemperature)];
            temperatureFallback.running = true;
        } else if (root.temperatureWritePending) Qt.callLater(root.startTemperatureWrite);
    }

    Process {
        id: temperatureWriter
        onExited: (exitCode, exitStatus) => root.finishTemperatureWrite(exitCode === 0)
    }

    Process {
        id: temperatureFallback
        onExited: if (root.temperatureWritePending) Qt.callLater(root.startTemperatureWrite)
    }

    FileView {
        id: configStore
        path: StateStore.ready ? Quickshell.shellPath("nightlight.json") : ""
        onLoaded: {
            try {
                const raw = text();
                if (raw && raw.trim().length > 0) {
                    const parsed = JSON.parse(raw);
                    if (parsed.enabled !== undefined) root.enabled = Boolean(parsed.enabled);
                    if (parsed.temperature !== undefined) root.temperature = Math.max(2500, Math.min(6500, Number(parsed.temperature)));
                    if (parsed.autoSchedule !== undefined) root.autoSchedule = Boolean(parsed.autoSchedule);
                    if (parsed.startHour !== undefined) root.startHour = Number(parsed.startHour);
                    if (parsed.startMinute !== undefined) root.startMinute = Number(parsed.startMinute);
                    if (parsed.endHour !== undefined) root.endHour = Number(parsed.endHour);
                    if (parsed.endMinute !== undefined) root.endMinute = Number(parsed.endMinute);
                    root.checkSchedule();
                    return;
                }
            } catch (e) {
                console.warn("NightLightService load error:", e);
            }
            save();
        }
    }

    function save() {
        try {
            const data = {
                enabled: root.enabled,
                temperature: root.temperature,
                autoSchedule: root.autoSchedule,
                startHour: root.startHour,
                startMinute: root.startMinute,
                endHour: root.endHour,
                endMinute: root.endMinute
            };
            configStore.setText(JSON.stringify(data, null, 2));
        } catch (e) {
            console.warn("NightLightService save error:", e);
        }
    }

    function toggle() {
        enabled = !enabled;
        save();
    }

    function setTemperature(temp) {
        const next = Math.max(2500, Math.min(6500, Math.round(temp)));
        if (next === temperature) return;
        temperature = next;
        configSaveTimer.restart();
    }

    function setAutoSchedule(auto) {
        autoSchedule = auto;
        checkSchedule();
        save();
    }

    function setStartTime(h, m) {
        const nextH = Math.max(0, Math.min(23, Math.floor(h)));
        const nextM = Math.max(0, Math.min(59, Math.floor(m)));
        if (startHour === nextH && startMinute === nextM) return;
        startHour = nextH;
        startMinute = nextM;
        checkSchedule();
        configSaveTimer.restart();
    }

    function setEndTime(h, m) {
        const nextH = Math.max(0, Math.min(23, Math.floor(h)));
        const nextM = Math.max(0, Math.min(59, Math.floor(m)));
        if (endHour === nextH && endMinute === nextM) return;
        endHour = nextH;
        endMinute = nextM;
        checkSchedule();
        configSaveTimer.restart();
    }

    function setScheduleTimes(sH, sM, eH, eM) {
        startHour = Math.max(0, Math.min(23, Math.floor(sH)));
        startMinute = Math.max(0, Math.min(59, Math.floor(sM)));
        endHour = Math.max(0, Math.min(23, Math.floor(eH)));
        endMinute = Math.max(0, Math.min(59, Math.floor(eM)));
        checkSchedule();
        configSaveTimer.restart();
    }

    function formatTime(h, m) {
        const hh = (h < 10 ? "0" : "") + (h || 0);
        const mm = (m < 10 ? "0" : "") + (m || 0);
        return hh + ":" + mm;
    }

    function checkSchedule() {
        const now = new Date();
        const curMins = now.getHours() * 60 + now.getMinutes();
        const startMins = startHour * 60 + startMinute;
        const endMins = endHour * 60 + endMinute;

        if (startMins > endMins) {
            // Overnights (e.g. 20:00 to 07:00)
            inScheduleWindow = (curMins >= startMins || curMins < endMins);
        } else {
            // Same day (e.g. 18:00 to 23:00)
            inScheduleWindow = (curMins >= startMins && curMins < endMins);
        }
    }

    Connections {
        target: ShellState
        enabled: root.autoSchedule
        function onCurrentMinuteChanged() { root.checkSchedule(); }
    }

    Timer {
        id: configSaveTimer
        interval: 200
        onTriggered: root.save()
    }
}
