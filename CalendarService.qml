pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property var events: []
    property var tasks: []
    readonly property var eventsByDate: {
        const _rev = root.revision;
        const evs = root.events || [];
        const map = Object.create(null);
        for (let i = 0; i < evs.length; ++i) {
            const e = evs[i];
            if (!e || !e.date) continue;
            if (!map[e.date]) map[e.date] = [e];
            else map[e.date].push(e);
        }
        return map;
    }
    property bool weekStartsMonday: true
    property bool compact: false
    property bool motion: true
    property int revision: 0
    property bool loaded: false
    property string pendingReminder: ""
    property var failedReminders: []
    function initialize() {}
    property string nextReminderId: ""

    readonly property var demoEvents: [
        { id: "e1", title: "DSP Exam Review", date: Qt.formatDate(new Date(), "yyyy-MM-dd"), start: "09:00", end: "10:30", meta: "EE 411 • Main Building, Room 203", type: "study", completed: true },
        { id: "e2", title: "Control Systems Lab", date: Qt.formatDate(new Date(), "yyyy-MM-dd"), start: "11:00", end: "13:00", meta: "EE 351 • Lab 4", type: "lab", completed: true },
        { id: "e3", title: "Project Sync", date: Qt.formatDate(new Date(), "yyyy-MM-dd"), start: "14:00", end: "15:00", meta: "Team Meeting • Online", type: "meeting", completed: false },
        { id: "e4", title: "System Update Reminder", date: Qt.formatDate(new Date(), "yyyy-MM-dd"), start: "19:00", end: "19:30", meta: "Personal Task", type: "task", completed: false },
        { id: "e5", title: "Control Systems Midterm", date: Qt.formatDate(new Date(new Date().getTime() + 86400000 * 3), "yyyy-MM-dd"), start: "09:00", end: "11:00", meta: "Engineering Hall", type: "study", completed: false },
        { id: "e6", title: "Advisor Meeting", date: Qt.formatDate(new Date(new Date().getTime() + 86400000 * 5), "yyyy-MM-dd"), start: "10:00", end: "11:00", meta: "Faculty Office", type: "meeting", completed: false }
    ]

    readonly property var demoTasks: [
        { id: "t1", name: "Finish DSP formula sheet", sub: "Study • Due today", priority: "High", done: false },
        { id: "t2", name: "Upload Control Systems lab report", sub: "EE 351 • Due tomorrow", priority: "High", done: false },
        { id: "t3", name: "Review project milestone notes", sub: "Project • This week", priority: "Normal", done: true },
        { id: "t4", name: "Update system packages", sub: "Personal • Weekend", priority: "Low", done: false }
    ]

    FileView {
        id: fileStore
        path: StateStore.ready ? Quickshell.shellPath("calendar.json") : ""
        onLoaded: {
            try {
                const raw = text();
                if (raw && raw.trim().length > 0) {
                    const parsed = JSON.parse(raw);
                    if (Array.isArray(parsed.events)) root.events = parsed.events;
                    else root.events = root.demoEvents;

                    if (Array.isArray(parsed.tasks)) root.tasks = parsed.tasks;
                    else root.tasks = root.demoTasks;

                    if (parsed.weekStartsMonday !== undefined) root.weekStartsMonday = Boolean(parsed.weekStartsMonday);
                    if (parsed.compact !== undefined) root.compact = Boolean(parsed.compact);
                    if (parsed.motion !== undefined) root.motion = Boolean(parsed.motion);
                    root.loaded = true;
                    root.revision++;
                    root.scheduleReminder();
                    return;
                }
            } catch (e) {
                console.warn("CalendarService load error:", e);
            }
            root.loaded = true;
            root.events = root.demoEvents;
            root.tasks = root.demoTasks;
            root.revision++;
            save();
        }
    }

    function save() {
        if (!root.loaded) return;
        try {
            const data = {
                events: root.events,
                tasks: root.tasks,
                weekStartsMonday: root.weekStartsMonday,
                compact: root.compact,
                motion: root.motion
            };
            fileStore.setText(JSON.stringify(data, null, 2));
        } catch (e) {
            console.warn("CalendarService save error:", e);
        }
        root.revision++;
        root.scheduleReminder();
    }

    function importFile(path) {
        SystemService.enqueue(["calendar-import", path], "calendar", "calendar-import", false);
    }
    Connections {
        target: SystemService
        function onActionFinished(domain, success, message, data) {
            if (domain === "calendar-reminder:" + root.pendingReminder && root.pendingReminder) {
                const id = root.pendingReminder; root.pendingReminder = "";
                if (success) { root.events = root.events.map(e => e.id === id ? Object.assign({}, e, {reminded:true}) : e); root.save(); }
                else { root.failedReminders = root.failedReminders.concat([id]); root.scheduleReminder(); }
                return;
            }
            if (domain !== "calendar" || !success || !Array.isArray(data?.events)) return;
            const ids = new Set(data.events.map(e => e.id));
            const imported = data.events.filter(e => !e.cancelled).map(e => {
                const start = new Date(e.startTimestamp), end = new Date(e.endTimestamp);
                return Object.assign({}, e, { date: Qt.formatDate(start, "yyyy-MM-dd"), start: Qt.formatTime(start, "HH:mm"), end: Qt.formatTime(end, "HH:mm") });
            });
            root.events = root.events.filter(e => !ids.has(e.id)).concat(imported);
            root.save();
            if (data.warnings?.length) OsdService.show("Calendar import", data.warnings.join("\n"), "dialog-warning", -1, true);
        }
    }
    Connections { target: SystemData; function onPrepareSleep(sleeping) { if (!sleeping) { root.failedReminders = []; root.scheduleReminder(); } } }
    function scheduleReminder() {
        reminder.stop();
        if (!root.loaded || root.pendingReminder) return;
        const now = Date.now();
        let earliest = null;
        let earliestTimestamp = Infinity;
        const failed = root.failedReminders;
        const evs = root.events;
        for (let i = 0; i < evs.length; i++) {
            const e = evs[i];
            if (e.completed || e.reminded) continue;
            const rt = Number(e.reminderTimestamp);
            const st = Number(e.startTimestamp);
            if (rt > 0 && st > now && !failed.includes(e.id)) {
                if (rt < earliestTimestamp) {
                    earliestTimestamp = rt;
                    earliest = e;
                }
            }
        }
        if (!earliest) { root.nextReminderId = ""; return; }
        root.nextReminderId = earliest.id;
        reminder.interval = Math.max(1, Math.min(2147483647, earliestTimestamp - now));
        reminder.start();
    }
    Timer {
        id: reminder
        onTriggered: {
            const item = root.events.find(e => e.id === root.nextReminderId);
            if (item && Number(item.reminderTimestamp) <= Date.now()) {
                root.pendingReminder = item.id;
                if (!SystemService.enqueue(["calendar-notify", item.title || "Calendar reminder", (item.date || "") + " " + (item.start || "") + " • " + (item.meta || "")], "calendar-reminder:" + item.id, "", false)) {
                    root.pendingReminder = ""; root.failedReminders = root.failedReminders.concat([item.id]); root.scheduleReminder();
                }
            } else root.scheduleReminder();
        }
    }

    function addEvent(ev) {
        const copy = events.slice();
        copy.push(ev);
        events = copy;
        save();
    }

    function deleteEvent(id) {
        events = events.filter(e => e.id !== id);
        save();
    }

    function toggleEventCompleted(id) {
        events = events.map(e => {
            if (e.id === id) {
                const updated = Object.assign({}, e);
                updated.completed = !updated.completed;
                return updated;
            }
            return e;
        });
        save();
    }

    function addTask(t) {
        const copy = tasks.slice();
        copy.unshift(t);
        tasks = copy;
        save();
    }

    function toggleTaskDone(id) {
        tasks = tasks.map(t => {
            if (t.id === id) {
                const updated = Object.assign({}, t);
                updated.done = !updated.done;
                return updated;
            }
            return t;
        });
        save();
    }

    function deleteTask(id) {
        tasks = tasks.filter(t => t.id !== id);
        save();
    }
}
