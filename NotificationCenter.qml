import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import qs

PopupWindow {
    id: root
    required property var anchorItem
    Shortcut { sequence: "Escape"; onActivated: ShellState.closeFlyouts() }
    visible: ShellState.notifOpen
    implicitWidth: Math.min(460, Math.max(160, (ShellState.popupScreen?.width || 1920) - 8))
    implicitHeight: Math.min((680), Math.max(120, (ShellState.popupScreen?.height || 1080) - Theme.taskbarHeight - 12))
    color: "transparent"
    grabFocus: true
    surfaceFormat.opaque: false
    anchor.item: anchorItem
    anchor.edges: Edges.Top | Edges.Right
    anchor.gravity: Edges.Top | Edges.Left

    property string currentTab: ShellState.notifCenterTab // calendar, tasks, schedule, notifications
    property date selectedDate: new Date()
    property date currentMonth: new Date()
    property string taskFilter: "all" // all, open, done
    property string activeModal: "" // "", "add", "search", "settings", "details"
    property string searchQuery: ""
    property var selectedEvent: null

    readonly property int calRev: CalendarService.revision

    // New Event fields
    property string newTitle: ""
    property string newDate: Qt.formatDate(new Date(), "yyyy-MM-dd")
    property string newStart: "09:00"
    property string newEnd: "10:00"
    property string newMeta: ""
    property string newType: "study"

    // New Task field
    property string newTaskName: ""

    onVisibleChanged: {
        if (visible) {
            currentTab = ShellState.notifCenterTab;
            selectedDate = new Date();
            currentMonth = new Date(selectedDate.getFullYear(), selectedDate.getMonth(), 1);
            activeModal = "";
            searchQuery = "";
        } else if (ShellState.notifOpen) {
            ShellState.notifOpen = false;
        }
    }

    function keyFor(d) {
        return Qt.formatDate(d, "yyyy-MM-dd");
    }

    function parseKey(key) {
        const parts = (key || "").split("-");
        if (parts.length < 3) return null;
        return { year: parseInt(parts[0]), month: parseInt(parts[1]) - 1, day: parseInt(parts[2]) };
    }

    function typeIcon(t) {
        const map = { "study": "book", "lab": "flask", "meeting": "users", "task": "check", "event": "flag" };
        return map[t] || "flag";
    }

    function changeMonth(delta) {
        const y = currentMonth.getFullYear();
        const m = currentMonth.getMonth() + delta;
        currentMonth = new Date(y, m, 1);
    }

    function isSameDay(d1, d2) {
        return d1.getFullYear() === d2.getFullYear() &&
               d1.getMonth() === d2.getMonth() &&
               d1.getDate() === d2.getDate();
    }

    function getDaysInMonthGrid() {
        const y = currentMonth.getFullYear();
        const m = currentMonth.getMonth();
        const firstDay = new Date(y, m, 1);
        let firstIndex = firstDay.getDay();
        if (CalendarService.weekStartsMonday) {
            firstIndex = (firstIndex + 6) % 7;
        }
        const start = new Date(y, m, 1 - firstIndex);
        const days = [];
        for (let i = 0; i < 42; i++) {
            const d = new Date(start);
            d.setDate(start.getDate() + i);
            days.push(d);
        }
        return days;
    }

    function getMonthProgress() {
        const _rev = calRev;
        const m = currentMonth.getMonth();
        const y = currentMonth.getFullYear();
        const mEvs = CalendarService.events.filter(e => {
            const p = parseKey(e.date);
            return p && p.year === y && p.month === m;
        });
        const tasks = CalendarService.tasks;
        const total = mEvs.length + tasks.length;
        const done = mEvs.filter(e => e.completed).length + tasks.filter(t => t.done).length;
        const pct = total > 0 ? Math.round(done / total * 100) : 0;
        return { total: total, done: done, pct: pct };
    }

    function getWeekBarData() {
        const _rev = calRev;
        const sel = new Date(selectedDate.getFullYear(), selectedDate.getMonth(), selectedDate.getDate());
        const dayOfWeek = sel.getDay();
        const offset = CalendarService.weekStartsMonday ? (dayOfWeek === 0 ? 6 : dayOfWeek - 1) : dayOfWeek;
        const weekStart = new Date(sel);
        weekStart.setDate(sel.getDate() - offset);

        const labels = CalendarService.weekStartsMonday ? ["M", "T", "W", "T", "F", "S", "S"] : ["S", "M", "T", "W", "T", "F", "S"];
        const result = [];
        for (let i = 0; i < 7; i++) {
            const d = new Date(weekStart);
            d.setDate(weekStart.getDate() + i);
            const k = keyFor(d);
            const evs = CalendarService.events.filter(e => e.date === k);
            const done = evs.filter(e => e.completed).length;
            const isToday = isSameDay(d, new Date());
            const isSelected = isSameDay(d, selectedDate);
            result.push({
                label: labels[i],
                dateKey: k,
                count: evs.length,
                done: done,
                isToday: isToday,
                isSelected: isSelected,
                heightPct: Math.max(12, Math.min(100, evs.length * 30))
            });
        }
        return result;
    }

    // AMOLED Shell Container
    Rectangle {
        anchors.fill: parent
        anchors.margins: 4
        radius: 24
        color: Theme.background
        border.width: 1
        border.color: Theme.border
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 8

            // 1. TOPBAR
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ColumnLayout {
                    spacing: 1

                    RowLayout {
                        spacing: 6
                        Text {
                            text: Qt.formatDate(root.currentMonth, "MMMM yyyy")
                            color: "#f8f8f8"
                            font.family: Theme.fontFamily
                            font.pixelSize: 22
                            font.weight: Font.DemiBold
                            font.letterSpacing: -0.5
                        }
                        // Month prev/next buttons
                        Rectangle {
                            width: 24; height: 24; radius: 12; color: prevMMouse.containsMouse ? "#20ffffff" : "transparent"
                            Text { anchors.centerIn: parent; text: "‹"; color: "#a0a0a0"; font.pixelSize: 16 }
                            MouseArea { id: prevMMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.changeMonth(-1) }
                        }
                        Rectangle {
                            width: 24; height: 24; radius: 12; color: nextMMouse.containsMouse ? "#20ffffff" : "transparent"
                            Text { anchors.centerIn: parent; text: "›"; color: "#a0a0a0"; font.pixelSize: 16 }
                            MouseArea { id: nextMMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.changeMonth(1) }
                        }
                    }

                    Text {
                        text: Qt.formatDate(root.selectedDate, "dddd, MMMM d")
                        color: "#9e9e9e"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                // Action Buttons
                RowLayout {
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    spacing: 4
                    Rectangle {
                        width: 32; height: 32; radius: 16
                        color: sBtnM.containsMouse ? "#202020" : "transparent"
                        border.width: 1
                        border.color: sBtnM.containsMouse ? "#333333" : "transparent"
                        Image { id: sI; anchors.centerIn: parent; width: 14; height: 14; source: "assets/search.svg"; visible: false }
                        MultiEffect { anchors.fill: sI; source: sI; colorization: 1.0; colorizationColor: "#ffffff" }
                        MouseArea { id: sBtnM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.activeModal = "search" }
                    }
                    Rectangle {
                        width: 32; height: 32; radius: 16
                        color: addBtnM.containsMouse ? "#202020" : "transparent"
                        border.width: 1
                        border.color: addBtnM.containsMouse ? "#333333" : "transparent"
                        Image { id: aI; anchors.centerIn: parent; width: 14; height: 14; source: "assets/plus.svg"; visible: false }
                        MultiEffect { anchors.fill: aI; source: aI; colorization: 1.0; colorizationColor: "#ffffff" }
                        MouseArea {
                            id: addBtnM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.newDate = root.keyFor(root.selectedDate);
                                root.newTitle = "";
                                root.newMeta = "";
                                root.activeModal = "add";
                            }
                        }
                    }
                    Rectangle {
                        width: 32; height: 32; radius: 16
                        color: cfgBtnM.containsMouse ? "#202020" : "transparent"
                        border.width: 1
                        border.color: cfgBtnM.containsMouse ? "#333333" : "transparent"
                        Image { id: cI; anchors.centerIn: parent; width: 14; height: 14; source: "assets/settings.svg"; visible: false }
                        MultiEffect { anchors.fill: cI; source: cI; colorization: 1.0; colorizationColor: Theme.accent }
                        MouseArea { id: cfgBtnM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.activeModal = "settings" }
                    }
                    Rectangle {
                        width: 32; height: 32; radius: 16
                        color: closeBtnM.containsMouse ? "#202020" : "transparent"
                        border.width: 1
                        border.color: closeBtnM.containsMouse ? "#333333" : "transparent"
                        Text { anchors.centerIn: parent; text: "✕"; color: closeBtnM.containsMouse ? "#ffffff" : "#a6a6a6"; font.pixelSize: 11 }
                        MouseArea { id: closeBtnM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ShellState.closeFlyouts() }
                    }
                }
            }

            // 2. MAIN CONTENT AREA
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // VIEW 1: CALENDAR
                Flickable {
                    anchors.fill: parent
                    visible: root.currentTab === "calendar"
                    contentWidth: width
                    contentHeight: calContentCol.implicitHeight + 10
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: calContentCol
                        width: parent.width
                        spacing: 10

                        // Weekday Strip
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Repeater {
                                model: CalendarService.weekStartsMonday ? ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"] : ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: 20
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData
                                        color: "#888888"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 9
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }
                        }

                        // Calendar Grid Card
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 250
                            radius: 16
                            color: "#101010"
                            border.width: 1
                            border.color: "#222222"

                            GridLayout {
                                anchors.fill: parent
                                anchors.margins: 6
                                columns: 7
                                rowSpacing: 2
                                columnSpacing: 2

                                Repeater {
                                    model: root.getDaysInMonthGrid()

                                    Rectangle {
                                        id: dayCell
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        radius: 10
                                        readonly property bool isSelected: root.isSameDay(modelData, root.selectedDate)
                                        readonly property bool isToday: root.isSameDay(modelData, new Date())
                                        readonly property bool isOutside: modelData.getMonth() !== root.currentMonth.getMonth()
                                        readonly property var dayEvents: CalendarService.events.filter(e => e.date === root.keyFor(modelData))

                                        color: isSelected ? "#f6f6f6" : (cellMouse.containsMouse ? "#1c1c1c" : "transparent")
                                        border.width: (isToday && !isSelected) ? 1 : 0
                                        border.color: "#888888"

                                        ColumnLayout {
                                            anchors.centerIn: parent
                                            spacing: 1

                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: dayCell.modelData.getDate()
                                                color: dayCell.isSelected ? "#050505" : (dayCell.isOutside ? "#444444" : "#f0f0f0")
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                                font.weight: dayCell.isSelected ? Font.Bold : Font.Normal
                                            }

                                            // Event dots
                                            RowLayout {
                                                Layout.alignment: Qt.AlignHCenter
                                                spacing: 2
                                                visible: dayCell.dayEvents.length > 0
                                                Repeater {
                                                    model: Math.min(3, dayCell.dayEvents.length)
                                                    Rectangle {
                                                        width: 3; height: 3; radius: 1.5
                                                        color: dayCell.isSelected ? "#111111" : "#bbbbbb"
                                                    }
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: cellMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: {
                                                root.selectedDate = dayCell.modelData;
                                                if (dayCell.modelData.getMonth() !== root.currentMonth.getMonth()) {
                                                    root.currentMonth = new Date(dayCell.modelData.getFullYear(), dayCell.modelData.getMonth(), 1);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Selected Day Agenda Card
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: Math.max(80, agendaCol.implicitHeight + 20)
                            radius: 16
                            color: "#101010"
                            border.width: 1
                            border.color: "#222222"

                            ColumnLayout {
                                id: agendaCol
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        text: (root.isSameDay(root.selectedDate, new Date()) ? "Today" : Qt.formatDate(root.selectedDate, "dddd")) + " • " + Qt.formatDate(root.selectedDate, "MMM d")
                                        color: "#f5f5f5"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                    }
                                    Item { Layout.fillWidth: true }
                                    Rectangle {
                                        implicitWidth: 70; implicitHeight: 22; radius: 11; color: viewDayM.containsMouse ? "#262626" : "#1a1a1a"
                                        Text { anchors.centerIn: parent; text: "Schedule ›"; color: "#e0e0e0"; font.family: Theme.fontFamily; font.pixelSize: 9 }
                                        MouseArea { id: viewDayM; anchors.fill: parent; hoverEnabled: true; onClicked: root.currentTab = "schedule" }
                                    }
                                }

                                readonly property var selEvents: CalendarService.events.filter(e => e.date === root.keyFor(root.selectedDate))

                                Text {
                                    visible: parent.selEvents.length === 0
                                    Layout.fillWidth: true
                                    text: "No events scheduled for this day"
                                    color: "#666666"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    horizontalAlignment: Text.AlignHCenter
                                }

                                Repeater {
                                    model: parent.selEvents

                                    Rectangle {
                                        id: evRow
                                        required property var modelData
                                        Layout.fillWidth: true
                                        implicitHeight: 48
                                        radius: 10
                                        color: evRowM.containsMouse ? "#181818" : "#141414"
                                        border.width: 1
                                        border.color: "#202020"

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 8
                                            spacing: 8

                                            Rectangle {
                                                width: 32; height: 32; radius: 10; color: "#202020"
                                                Image {
                                                    id: evI
                                                    anchors.centerIn: parent
                                                    width: 14; height: 14
                                                    source: "assets/" + root.typeIcon(evRow.modelData.type) + ".svg"
                                                    visible: false
                                                }
                                                MultiEffect { anchors.fill: evI; source: evI; colorization: 1.0; colorizationColor: "#ffffff" }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 0
                                                Text {
                                                    text: evRow.modelData.title
                                                    color: evRow.modelData.completed ? "#777777" : "#f5f5f5"
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 11
                                                    font.weight: Font.DemiBold
                                                    font.strikeout: evRow.modelData.completed
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }
                                                Text {
                                                    text: evRow.modelData.meta || "No location details"
                                                    color: "#888888"
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 9
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }
                                            }

                                            Text {
                                                text: evRow.modelData.start ? (evRow.modelData.start + (evRow.modelData.end ? "\n" + evRow.modelData.end : "")) : "All Day"
                                                color: "#aaaaaa"
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 9
                                                horizontalAlignment: Text.AlignRight
                                            }

                                            Rectangle {
                                                width: 22; height: 22; radius: 11; color: chkM.containsMouse ? "#30ffffff" : "#1affffff"
                                                Text { anchors.centerIn: parent; text: evRow.modelData.completed ? "✓" : "○"; color: "#fff"; font.pixelSize: 10 }
                                                MouseArea {
                                                    id: chkM
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    onClicked: CalendarService.toggleEventCompleted(evRow.modelData.id)
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: evRowM
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            z: -1
                                            onClicked: {
                                                root.selectedEvent = evRow.modelData;
                                                root.activeModal = "details";
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Month Progress & Activity Bars Card
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 74
                            radius: 16
                            color: "#101010"
                            border.width: 1
                            border.color: "#222222"

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 12

                                // Circular % Ring Box
                                Rectangle {
                                    width: 48; height: 48; radius: 24; color: "#181818"; border.width: 2; border.color: "#ffffff"
                                    Text {
                                        anchors.centerIn: parent
                                        text: root.getMonthProgress().pct + "%"
                                        color: "#f5f5f5"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Text {
                                        text: Qt.formatDate(root.currentMonth, "MMMM") + " Progress"
                                        color: "#f5f5f5"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                    }
                                    Text {
                                        text: {
                                            const p = root.getMonthProgress();
                                            return p.done + " of " + p.total + " to‑dos & events completed";
                                        }
                                        color: "#888888"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 9
                                    }
                                }

                                // 7 Day Activity Bars
                                RowLayout {
                                    spacing: 5
                                    Repeater {
                                        model: root.getWeekBarData()

                                        ColumnLayout {
                                            required property var modelData
                                            spacing: 3
                                            Layout.alignment: Qt.AlignBottom

                                            Rectangle {
                                                Layout.alignment: Qt.AlignHCenter
                                                width: 7
                                                height: Math.max(6, Math.min(34, modelData.count * 10))
                                                radius: 3.5
                                                color: modelData.count > 0 ? (modelData.done === modelData.count ? "#ffffff" : "#aaaaaa") : "#242424"
                                            }

                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: modelData.label
                                                color: modelData.isSelected ? "#ffffff" : "#666666"
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 8
                                                font.weight: modelData.isSelected ? Font.Bold : Font.Normal
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // VIEW 2: TASKS
                ColumnLayout {
                    anchors.fill: parent
                    visible: root.currentTab === "tasks"
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "Tasks & To‑Dos"; color: "#f5f5f5"; font.family: Theme.fontFamily; font.pixelSize: 12; font.weight: Font.DemiBold }
                        Item { Layout.fillWidth: true }
                        // Filter chips
                        RowLayout {
                            spacing: 4
                            Repeater {
                                model: ["all", "open", "done"]
                                Rectangle {
                                    required property var modelData
                                    implicitWidth: 44; implicitHeight: 22; radius: 11
                                    color: root.taskFilter === modelData ? "#f4f4f4" : "#161616"
                                    border.width: 1
                                    border.color: root.taskFilter === modelData ? "#ffffff" : "#242424"
                                    Text {
                                        anchors.centerIn: parent
                                        text: parent.modelData.toUpperCase()
                                        color: root.taskFilter === parent.modelData ? "#000" : "#888"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 8
                                        font.weight: Font.Bold
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: root.taskFilter = parent.modelData }
                                }
                            }
                        }
                    }

                    // Quick Task Input Bar
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 34
                        radius: 10
                        color: "#121212"
                        border.width: 1
                        border.color: "#282828"

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 6
                            spacing: 6
                            TextInput {
                                id: qTaskInput
                                Layout.fillWidth: true
                                color: "#ffffff"
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                text: root.newTaskName
                                onTextChanged: root.newTaskName = text
                                onAccepted: {
                                    if (text.trim().length > 0) {
                                        CalendarService.addTask({
                                            id: "t" + Date.now(),
                                            name: text.trim(),
                                            sub: "Personal • Created today",
                                            priority: "Normal",
                                            done: false
                                        });
                                        text = "";
                                    }
                                }
                            }
                            Text {
                                visible: qTaskInput.text.length === 0
                                text: "+ Add a quick task and press Enter..."
                                color: "#555555"
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                            }
                        }
                    }

                    // Tasks List
                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        ListView {
                            id: tasksList
                            model: CalendarService.tasks.filter(t => root.taskFilter === "all" ? true : (root.taskFilter === "done" ? t.done : !t.done))
                            spacing: 6
                            delegate: Rectangle {
                                required property var modelData
                                width: tasksList.width
                                height: 46
                                radius: 10
                                color: "#121212"
                                border.width: 1
                                border.color: "#1e1e1e"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 8

                                    Rectangle {
                                        width: 20; height: 20; radius: 6
                                        color: modelData.done ? "#f4f4f4" : "#1c1c1c"
                                        border.width: 1
                                        border.color: modelData.done ? "#f4f4f4" : "#383838"
                                        Text { anchors.centerIn: parent; text: modelData.done ? "✓" : ""; color: "#000"; font.pixelSize: 11; font.weight: Font.Bold }
                                        MouseArea { anchors.fill: parent; onClicked: CalendarService.toggleTaskDone(modelData.id) }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        Text {
                                            text: modelData.name
                                            color: modelData.done ? "#666" : "#f5f5f5"
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                            font.weight: Font.DemiBold
                                            font.strikeout: modelData.done
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                        Text {
                                            text: modelData.sub || ""
                                            color: "#777777"
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 9
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }

                                    Rectangle {
                                        implicitWidth: 42; implicitHeight: 18; radius: 9; color: "#1a1a1a"; border.width: 1; border.color: "#282828"
                                        Text { anchors.centerIn: parent; text: modelData.priority || "Normal"; color: "#aaa"; font.family: Theme.fontFamily; font.pixelSize: 8 }
                                    }

                                    Rectangle {
                                        width: 18; height: 18; radius: 9; color: tDelM.containsMouse ? "#33ffffff" : "transparent"
                                        Text { anchors.centerIn: parent; text: "✕"; color: "#666"; font.pixelSize: 8 }
                                        MouseArea { id: tDelM; anchors.fill: parent; hoverEnabled: true; onClicked: CalendarService.deleteTask(modelData.id) }
                                    }
                                }
                            }
                        }
                    }
                }

                // VIEW 3: HOURLY SCHEDULE
                ColumnLayout {
                    anchors.fill: parent
                    visible: root.currentTab === "schedule"
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "Day Schedule • " + Qt.formatDate(root.selectedDate, "MMM d"); color: "#f5f5f5"; font.family: Theme.fontFamily; font.pixelSize: 12; font.weight: Font.DemiBold }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            implicitWidth: 56; implicitHeight: 22; radius: 11; color: todayJumpM.containsMouse ? "#282828" : "#1a1a1a"
                            Text { anchors.centerIn: parent; text: "Today"; color: "#e0e0e0"; font.family: Theme.fontFamily; font.pixelSize: 9 }
                            MouseArea {
                                id: todayJumpM; anchors.fill: parent; hoverEnabled: true
                                onClicked: {
                                    root.selectedDate = new Date();
                                    root.currentMonth = new Date(root.selectedDate.getFullYear(), root.selectedDate.getMonth(), 1);
                                }
                            }
                        }
                    }

                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true

                        ColumnLayout {
                            width: parent.width
                            spacing: 4

                            Repeater {
                                model: 16 // 07:00 to 22:00
                                Rectangle {
                                    required property int index
                                    readonly property int hour: index + 7
                                    readonly property string hourStr: (hour < 10 ? "0" + hour : "" + hour) + ":00"
                                    readonly property var hourEvs: CalendarService.events.filter(e => {
                                        if (e.date !== root.keyFor(root.selectedDate) || !e.start) return false;
                                        const h = parseInt(e.start.split(":")[0]);
                                        return h === hour;
                                    })

                                    Layout.fillWidth: true
                                    implicitHeight: Math.max(38, hourEvs.length * 36 + 6)
                                    color: "transparent"

                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 8

                                        Text {
                                            text: parent.parent.hourStr
                                            color: "#666666"
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 9
                                            Layout.preferredWidth: 38
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            radius: 8
                                            color: parent.parent.hourEvs.length > 0 ? "#181818" : "#0e0e0e"
                                            border.width: 1
                                            border.color: parent.parent.hourEvs.length > 0 ? "#333333" : "#181818"

                                            ColumnLayout {
                                                anchors.fill: parent
                                                anchors.margins: 4
                                                spacing: 2

                                                Repeater {
                                                    model: parent.parent.parent.parent.hourEvs
                                                    Rectangle {
                                                        required property var modelData
                                                        Layout.fillWidth: true
                                                        implicitHeight: 28
                                                        radius: 6
                                                        color: "#222222"
                                                        RowLayout {
                                                            anchors.fill: parent
                                                            anchors.margins: 4
                                                            spacing: 6
                                                            Text { text: modelData.title; color: "#ffffff"; font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true }
                                                            Text { text: modelData.start + (modelData.end ? " – " + modelData.end : ""); color: "#aaaaaa"; font.family: Theme.fontFamily; font.pixelSize: 8 }
                                                        }
                                                        MouseArea {
                                                            anchors.fill: parent
                                                            onClicked: {
                                                                root.selectedEvent = modelData;
                                                                root.activeModal = "details";
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
                    }
                }

                // VIEW 4: NOTIFICATIONS
                ColumnLayout {
                    anchors.fill: parent
                    visible: root.currentTab === "notifications"
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "System Notifications"; color: "#f5f5f5"; font.family: Theme.fontFamily; font.pixelSize: 12; font.weight: Font.DemiBold }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            visible: NotificationService.history.length > 0
                            implicitWidth: 64; implicitHeight: 22; radius: 11
                            color: clrNotifM.containsMouse ? "#202020" : "#101010"
                            border.width: 1
                            border.color: clrNotifM.containsMouse ? "#333333" : "#202020"
                            Text { anchors.centerIn: parent; text: "Clear all"; color: "#e0e0e0"; font.family: Theme.fontFamily; font.pixelSize: 9 }
                            MouseArea { id: clrNotifM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: NotificationService.clearAll() }
                        }
                    }

                    Text {
                        visible: NotificationService.history.length === 0
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        text: "No new notifications"
                        color: "#666666"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    ScrollView {
                        visible: NotificationService.history.length > 0
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        ListView {
                            id: notifsList
                            model: NotificationService.history
                            spacing: 6
                            delegate: Rectangle {
                                id: notifCenterCard
                                required property var modelData
                                required property int index
                                width: notifsList.width
                                height: 50
                                radius: 10
                                color: notifCardHover.containsMouse ? "#141414" : "#000000"
                                border.width: 1
                                border.color: notifCardHover.containsMouse ? "#2c2c2c" : "#1c1c1c"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 8

                                    Rectangle {
                                        width: 32; height: 32; radius: 16
                                        color: "#0a0a0a"
                                        border.width: 1
                                        border.color: "#202020"

                                        Image {
                                            anchors.centerIn: parent
                                            width: 16; height: 16
                                            source: {
                                                const img = notifCenterCard.modelData.image;
                                                if (img && !img.startsWith("image://qsimage/")) return img;
                                                return Quickshell.iconPath(notifCenterCard.modelData.appIcon || "dialog-information");
                                            }
                                            fillMode: Image.PreserveAspectFit
                                            smooth: true
                                            mipmap: true
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        Text {
                                            text: notifCenterCard.modelData.summary || "Notification"
                                            color: notifCardHover.containsMouse ? "#ffffff" : "#f0f0f0"
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                        Text {
                                            text: notifCenterCard.modelData.body || ""
                                            color: "#888888"
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 9
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }

                                    Rectangle {
                                        width: 20; height: 20; radius: 10
                                        color: nDelM.containsMouse ? "#280e12" : "transparent"
                                        border.width: 1
                                        border.color: nDelM.containsMouse ? "#501820" : "transparent"

                                        Text {
                                            anchors.centerIn: parent
                                            text: "✕"
                                            color: nDelM.containsMouse ? "#ff7070" : "#727272"
                                            font.pixelSize: 8
                                        }
                                        MouseArea {
                                            id: nDelM
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: NotificationService.removeAt(index)
                                        }
                                    }
                                }

                                MouseArea {
                                    id: notifCardHover
                                    anchors.fill: parent
                                    z: -1
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        NotificationService.activateNotification(notifCenterCard.modelData);
                                        NotificationService.removeAt(index);
                                        ShellState.closeFlyouts();
                                    }
                                }
                            }
                        }
                    }
                }

                // MODAL OVERLAY BOX
                Rectangle {
                    visible: root.activeModal !== ""
                    anchors.fill: parent
                    radius: 16
                    color: "#0c0c0c"
                    border.width: 1
                    border.color: "#383838"
                    z: 50

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 10

                        // Modal Header
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: root.activeModal === "add" ? "Create Event" : root.activeModal === "search" ? "Search Calendar" : root.activeModal === "settings" ? "Calendar Settings" : "Event Details"
                                color: "#f8f8f8"
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.weight: Font.Bold
                            }
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                width: 24; height: 24; radius: 12; color: clsModalM.containsMouse ? "#33ffffff" : "transparent"
                                Text { anchors.centerIn: parent; text: "✕"; color: "#999"; font.pixelSize: 10 }
                                MouseArea { id: clsModalM; anchors.fill: parent; hoverEnabled: true; onClicked: root.activeModal = "" }
                            }
                        }

                        // Add Event Form
                        ColumnLayout {
                            visible: root.activeModal === "add"
                            Layout.fillWidth: true
                            spacing: 8

                            Text { text: "Title"; color: "#888"; font.family: Theme.fontFamily; font.pixelSize: 9 }
                            Rectangle {
                                Layout.fillWidth: true; implicitHeight: 32; radius: 8; color: "#161616"; border.width: 1; border.color: "#282828"
                                TextInput { anchors.fill: parent; anchors.margins: 6; color: "#fff"; text: root.newTitle; onTextChanged: root.newTitle = text }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 2
                                    Text { text: "Date (YYYY-MM-DD)"; color: "#888"; font.family: Theme.fontFamily; font.pixelSize: 9 }
                                    Rectangle {
                                        Layout.fillWidth: true; implicitHeight: 32; radius: 8; color: "#161616"; border.width: 1; border.color: "#282828"
                                        TextInput { anchors.fill: parent; anchors.margins: 6; color: "#fff"; text: root.newDate; onTextChanged: root.newDate = text }
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 2
                                    Text { text: "Time (Start - End)"; color: "#888"; font.family: Theme.fontFamily; font.pixelSize: 9 }
                                    RowLayout {
                                        Rectangle { Layout.fillWidth: true; implicitHeight: 32; radius: 8; color: "#161616"; border.width: 1; border.color: "#282828"; TextInput { anchors.fill: parent; anchors.margins: 6; color: "#fff"; text: root.newStart; onTextChanged: root.newStart = text } }
                                        Rectangle { Layout.fillWidth: true; implicitHeight: 32; radius: 8; color: "#161616"; border.width: 1; border.color: "#282828"; TextInput { anchors.fill: parent; anchors.margins: 6; color: "#fff"; text: root.newEnd; onTextChanged: root.newEnd = text } }
                                    }
                                }
                            }

                            Text { text: "Location / Details"; color: "#888"; font.family: Theme.fontFamily; font.pixelSize: 9 }
                            Rectangle {
                                Layout.fillWidth: true; implicitHeight: 32; radius: 8; color: "#161616"; border.width: 1; border.color: "#282828"
                                TextInput { anchors.fill: parent; anchors.margins: 6; color: "#fff"; text: root.newMeta; onTextChanged: root.newMeta = text }
                            }

                            Rectangle {
                                Layout.fillWidth: true; implicitHeight: 36; radius: 10; color: "#f4f4f4"
                                Text { anchors.centerIn: parent; text: "Save Event"; color: "#000"; font.family: Theme.fontFamily; font.pixelSize: 11; font.weight: Font.Bold }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        if (root.newTitle.trim().length > 0) {
                                            CalendarService.addEvent({
                                                id: "e" + Date.now(),
                                                title: root.newTitle.trim(),
                                                date: root.newDate.trim() || root.keyFor(root.selectedDate),
                                                start: root.newStart,
                                                end: root.newEnd,
                                                meta: root.newMeta.trim(),
                                                type: root.newType,
                                                completed: false
                                            });
                                            root.activeModal = "";
                                        }
                                    }
                                }
                            }
                        }

                        // Search Box
                        ColumnLayout {
                            visible: root.activeModal === "search"
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 8

                            Rectangle {
                                Layout.fillWidth: true; implicitHeight: 34; radius: 8; color: "#161616"; border.width: 1; border.color: "#282828"
                                TextInput {
                                    anchors.fill: parent; anchors.margins: 6; color: "#fff"; text: root.searchQuery
                                    onTextChanged: root.searchQuery = text
                                }
                            }

                            ScrollView {
                                Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                                ListView {
                                    id: searchResultList
                                    model: CalendarService.events.filter(e => root.searchQuery.trim().length > 0 && (e.title + " " + e.meta + " " + e.date).toLowerCase().includes(root.searchQuery.toLowerCase()))
                                    spacing: 4
                                    delegate: Rectangle {
                                        required property var modelData
                                        width: searchResultList.width; height: 38; radius: 8; color: "#141414"
                                        RowLayout {
                                            anchors.fill: parent; anchors.margins: 6
                                            Text { text: modelData.title; color: "#fff"; font.family: Theme.fontFamily; font.pixelSize: 10; elide: Text.ElideRight; Layout.fillWidth: true }
                                            Text { text: modelData.date; color: "#888"; font.family: Theme.fontFamily; font.pixelSize: 9 }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                root.selectedEvent = modelData;
                                                root.activeModal = "details";
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Details Box
                        ColumnLayout {
                            visible: root.activeModal === "details" && root.selectedEvent !== null
                            Layout.fillWidth: true
                            spacing: 8

                            Text { text: root.selectedEvent?.title || ""; color: "#fff"; font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Font.Bold }
                            Text { text: "Date: " + (root.selectedEvent?.date || ""); color: "#aaa"; font.family: Theme.fontFamily; font.pixelSize: 10 }
                            Text { text: "Time: " + (root.selectedEvent?.start || "All Day") + (root.selectedEvent?.end ? " – " + root.selectedEvent.end : ""); color: "#aaa"; font.family: Theme.fontFamily; font.pixelSize: 10 }
                            Text { text: "Location: " + (root.selectedEvent?.meta || "None"); color: "#aaa"; font.family: Theme.fontFamily; font.pixelSize: 10 }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                Rectangle {
                                    Layout.fillWidth: true; implicitHeight: 32; radius: 8; color: "#f4f4f4"
                                    Text { anchors.centerIn: parent; text: root.selectedEvent?.completed ? "Mark Incomplete" : "Mark Complete"; color: "#000"; font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Font.Bold }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            if (root.selectedEvent) CalendarService.toggleEventCompleted(root.selectedEvent.id);
                                            root.activeModal = "";
                                        }
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true; implicitHeight: 32; radius: 8; color: "#221111"; border.width: 1; border.color: "#442222"
                                    Text { anchors.centerIn: parent; text: "Delete Event"; color: "#ff6666"; font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Font.Bold }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            if (root.selectedEvent) CalendarService.deleteEvent(root.selectedEvent.id);
                                            root.activeModal = "";
                                        }
                                    }
                                }
                            }
                        }

                        // Settings Box
                        ColumnLayout {
                            visible: root.activeModal === "settings"
                            Layout.fillWidth: true
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "Week Starts Monday"; color: "#f5f5f5"; font.family: Theme.fontFamily; font.pixelSize: 11 }
                                Item { Layout.fillWidth: true }
                                Switch {
                                    checked: CalendarService.weekStartsMonday
                                    onToggled: {
                                        CalendarService.weekStartsMonday = checked;
                                        CalendarService.save();
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "Motion & Animations"; color: "#f5f5f5"; font.family: Theme.fontFamily; font.pixelSize: 11 }
                                Item { Layout.fillWidth: true }
                                Switch {
                                    checked: CalendarService.motion
                                    onToggled: {
                                        CalendarService.motion = checked;
                                        CalendarService.save();
                                    }
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }
                    }
                }
            }

            // 3. BOTTOM NAVIGATION CARD
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 48
                radius: 14
                color: "#080808"
                border.width: 1
                border.color: "#1c1c1c"

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 4
                    spacing: 4

                    Repeater {
                        model: [
                            { id: "calendar", name: "Calendar", icon: "calendar" },
                            { id: "tasks", name: "Tasks", icon: "check" },
                            { id: "schedule", name: "Schedule", icon: "flask" },
                            { id: "notifications", name: "Notifications", icon: "bell" }
                        ]

                        Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 10
                            color: root.currentTab === modelData.id ? "#181818" : "transparent"
                            border.width: 1
                            border.color: root.currentTab === modelData.id ? "#282828" : "transparent"

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 5
                                Item {
                                    Layout.preferredWidth: 13
                                    Layout.preferredHeight: 13
                                    Image {
                                        id: bNavI
                                        anchors.fill: parent
                                        source: "assets/" + parent.parent.parent.modelData.icon + ".svg"
                                        visible: false
                                    }
                                    MultiEffect {
                                        anchors.fill: parent
                                        source: bNavI
                                        colorization: 1.0
                                        colorizationColor: root.currentTab === parent.parent.parent.modelData.id ? "#ffffff" : "#777777"
                                    }
                                }
                                Text {
                                    text: parent.parent.modelData.name
                                    color: root.currentTab === parent.parent.modelData.id ? "#ffffff" : "#777777"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.weight: root.currentTab === parent.parent.modelData.id ? Font.DemiBold : Font.Normal
                                }
                            }

                            // Active underline bar
                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 2
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 24; height: 2; radius: 1
                                color: "#ffffff"
                                visible: root.currentTab === parent.modelData.id
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.currentTab = parent.modelData.id
                            }
                        }
                    }
                }
            }
        }
    }
}
