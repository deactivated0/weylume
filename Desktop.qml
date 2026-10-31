import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: root
    color: Theme.background
    anchors { top: true; right: true; bottom: true; left: true }
    exclusiveZone: -1
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "weylume-desktop"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    readonly property var desktopItems: SystemData.desktopItems
    property var positions: ({})
    property bool positionsLoaded: false
    function parsePositions(raw) {
        try {
            if (raw && raw.trim().length > 0) return JSON.parse(raw);
        } catch(e) {}
        return ({});
    }

    property var selectedMap: ({})
    property int selectedCount: 0
    property int selectedIndex: -1
    property int renamingIndex: -1
    property var dragHoverFolder: null

    property int dragLeaderIndex: -1
    property real dragDeltaX: 0
    property real dragDeltaY: 0
    readonly property bool isGroupDragging: root.dragLeaderIndex >= 0 && root.selectedCount > 1
    property var currentDraggingWrapper: null
    property string currentDraggingKey: ""
    property int currentDraggingIndex: -1
    property bool dropHandled: false

    readonly property var targetDropSlot: {
        if (!ShellState.isDraggingFile) return null;
        const gx = ShellState.dragGlobalX;
        const gy = ShellState.dragGlobalY;
        if (gx <= 0 && gy <= 0) return null;
        const dropX = gx - ShellState.dragGrabOffsetX;
        const dropY = gy - ShellState.dragGrabOffsetY;
        const rawCol = Math.round((dropX + root.itemWidth / 2 - root.gridOriginX - root.colWidth / 2) / root.colWidth);
        const rawRow = Math.round((dropY + root.itemHeight / 2 - root.gridOriginY - root.rowHeight / 2) / root.rowHeight);
        const freeSlot = root.findFreeGridSlot(rawCol, rawRow, root.currentDraggingKey || "");
        const slotX = Math.max(4, Math.min(root.width - root.itemWidth - 4, root.gridOriginX + freeSlot.col * root.colWidth + (root.colWidth - root.itemWidth) / 2));
        const slotY = Math.max(4, Math.min(root.height - Theme.taskbarHeight - root.itemHeight - 4, root.gridOriginY + freeSlot.row * root.rowHeight + (root.rowHeight - root.itemHeight) / 2));
        return { col: freeSlot.col, row: freeSlot.row, x: slotX, y: slotY };
    }

    property real desktopIconScale: SettingsService.desktopIconScale || 1.0

    function zoomInIcons() {
        const next = Math.min(1.40, Math.round((root.desktopIconScale + 0.08) * 100) / 100);
        if (next !== root.desktopIconScale) {
            root.desktopIconScale = next;
            SettingsService.desktopIconScale = next;
            SettingsService.save();
        }
    }

    function zoomOutIcons() {
        const next = Math.max(0.80, Math.round((root.desktopIconScale - 0.08) * 100) / 100);
        if (next !== root.desktopIconScale) {
            root.desktopIconScale = next;
            SettingsService.desktopIconScale = next;
            SettingsService.save();
        }
    }

    readonly property bool hasSelection: root.selectedCount > 0 || root.selectedIndex >= 0

    onDesktopItemsChanged: {
        if (root.positionsLoaded) root.ensurePositions();
    }

    Component.onCompleted: {
        if (root.positionsLoaded) root.ensurePositions();
        keyHandler.forceActiveFocus();
    }

    property string typeAheadBuffer: ""

    Timer {
        id: typeAheadTimer
        interval: 850
        repeat: false
        onTriggered: {
            root.typeAheadBuffer = "";
        }
    }

    function handleTypeAhead(char) {
        const items = root.desktopItems;
        if (!items || items.length === 0) return;

        typeAheadTimer.restart();

        let isRepeat = false;
        if (root.typeAheadBuffer.length === 1 && root.typeAheadBuffer.toLowerCase() === char.toLowerCase()) {
            isRepeat = true;
        } else if (root.typeAheadBuffer.length === 0 && root.selectedIndex >= 0 && root.selectedIndex < items.length) {
            const currentItem = items[root.selectedIndex];
            const currentName = (currentItem && currentItem.name) ? currentItem.name.trim().toLowerCase() : "";
            if (currentName.startsWith(char.toLowerCase())) {
                isRepeat = true;
            }
        }

        let searchStr = "";
        if (isRepeat) {
            root.typeAheadBuffer = char;
            searchStr = char.toLowerCase();
        } else {
            root.typeAheadBuffer += char;
            searchStr = root.typeAheadBuffer.toLowerCase();
        }

        let matches = [];
        for (let i = 0; i < items.length; i++) {
            const it = items[i];
            if (!it) continue;
            const name = (it.name || "").trim().toLowerCase();
            if (name.startsWith(searchStr)) {
                matches.push(i);
            }
        }

        if (matches.length === 0 && root.typeAheadBuffer.length > 1) {
            root.typeAheadBuffer = char;
            searchStr = char.toLowerCase();
            for (let i = 0; i < items.length; i++) {
                const it = items[i];
                if (!it) continue;
                const name = (it.name || "").trim().toLowerCase();
                if (name.startsWith(searchStr)) {
                    matches.push(i);
                }
            }
        }

        if (matches.length === 0) return;

        matches.sort((a, b) => {
            const nameA = (items[a].name || "").toLowerCase();
            const nameB = (items[b].name || "").toLowerCase();
            return nameA.localeCompare(nameB);
        });

        let targetIndex = matches[0];
        if (isRepeat) {
            const currentPos = matches.indexOf(root.selectedIndex);
            if (currentPos >= 0) {
                targetIndex = matches[(currentPos + 1) % matches.length];
            } else {
                targetIndex = matches[0];
            }
        } else {
            if (root.selectedIndex >= 0 && matches.indexOf(root.selectedIndex) >= 0) {
                targetIndex = root.selectedIndex;
            } else {
                targetIndex = matches[0];
            }
        }

        root.setSingleSelection(targetIndex);
        keyHandler.forceActiveFocus();
    }

    function handleDesktopKeyPress(event) {
        if (event.modifiers & Qt.ControlModifier) {
            if (event.key === Qt.Key_Up) {
                if (root.hasSelection && root.renamingIndex < 0) {
                    root.zoomInIcons();
                    event.accepted = true;
                    return;
                }
            } else if (event.key === Qt.Key_Down) {
                if (root.hasSelection && root.renamingIndex < 0) {
                    root.zoomOutIcons();
                    event.accepted = true;
                    return;
                }
            } else if (event.key === Qt.Key_A) {
                if (root.renamingIndex < 0 && root.desktopItems) {
                    const allMap = {};
                    for (let i = 0; i < root.desktopItems.length; i++) {
                        allMap[i] = true;
                    }
                    root.selectedMap = allMap;
                    root.selectedCount = root.desktopItems.length;
                    root.selectedIndex = root.desktopItems.length > 0 ? 0 : -1;
                    event.accepted = true;
                    return;
                }
            }
        }

        if (event.key === Qt.Key_Delete) {
            root.deleteSelectedItem();
            event.accepted = true;
            return;
        } else if (event.key === Qt.Key_F2) {
            root.startRenameSelectedItem();
            event.accepted = true;
            return;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.openSelectedItem();
            event.accepted = true;
            return;
        } else if (event.key === Qt.Key_Escape) {
            root.clearSelection();
            root.renamingIndex = -1;
            root.typeAheadBuffer = "";
            event.accepted = true;
            return;
        }

        if (root.renamingIndex < 0 && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
            if (event.key === Qt.Key_Down || event.key === Qt.Key_Right) {
                if (root.desktopItems && root.desktopItems.length > 0) {
                    const nextIdx = (root.selectedIndex >= 0) ? ((root.selectedIndex + 1) % root.desktopItems.length) : 0;
                    root.setSingleSelection(nextIdx);
                    keyHandler.forceActiveFocus();
                    event.accepted = true;
                    return;
                }
            } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Left) {
                if (root.desktopItems && root.desktopItems.length > 0) {
                    const prevIdx = (root.selectedIndex >= 0) ? ((root.selectedIndex - 1 + root.desktopItems.length) % root.desktopItems.length) : (root.desktopItems.length - 1);
                    root.setSingleSelection(prevIdx);
                    keyHandler.forceActiveFocus();
                    event.accepted = true;
                    return;
                }
            }
        }

        if (root.renamingIndex < 0 && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
            let charToSearch = event.text;
            if (!charToSearch || charToSearch.length === 0 || charToSearch.charCodeAt(0) < 32 || charToSearch.charCodeAt(0) === 127) {
                if (event.key >= Qt.Key_A && event.key <= Qt.Key_Z) {
                    charToSearch = String.fromCharCode((event.modifiers & Qt.ShiftModifier) ? event.key : (event.key + 32));
                } else if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9) {
                    charToSearch = String.fromCharCode(event.key);
                }
            }
            if (charToSearch && charToSearch.length > 0) {
                const code = charToSearch.charCodeAt(0);
                if (code >= 33 && code !== 127) {
                    root.handleTypeAhead(charToSearch);
                    event.accepted = true;
                    return;
                }
            }
        }
    }

    function isIndexSelected(idx) {
        return Boolean(root.selectedMap && root.selectedMap[idx]);
    }

    function getSelectedIndices() {
        const result = [];
        const items = root.desktopItems;
        if (!items) return result;
        for (let i = 0; i < items.length; i++) {
            if (root.selectedMap && root.selectedMap[i]) {
                result.push(i);
            }
        }
        return result;
    }

    function clearSelection() {
        root.selectedMap = ({});
        root.selectedCount = 0;
        root.selectedIndex = -1;
    }

    function setSingleSelection(idx) {
        if (root.selectedIndex === idx && root.selectedCount === 1 && root.selectedMap && root.selectedMap[idx]) return;
        const next = {};
        next[idx] = true;
        root.selectedMap = next;
        root.selectedCount = 1;
        root.selectedIndex = idx;
    }

    function toggleSelection(idx) {
        const next = Object.assign({}, root.selectedMap);
        if (next[idx]) {
            delete next[idx];
        } else {
            next[idx] = true;
        }
        const keys = Object.keys(next);
        root.selectedMap = next;
        root.selectedCount = keys.length;
        root.selectedIndex = keys.length > 0 ? (next[idx] ? idx : parseInt(keys[0])) : -1;
    }

    onSelectedIndexChanged: {
        if (selectedIndex >= 0) {
            keyHandler.forceActiveFocus();
        }
    }

    onSelectedCountChanged: {
        if (selectedCount > 0) {
            keyHandler.forceActiveFocus();
        }
    }

    function deleteSelectedItem() {
        const indices = root.getSelectedIndices();
        if (indices.length === 0) {
            if (root.selectedIndex >= 0 && root.selectedIndex < (root.desktopItems?.length ?? 0)) {
                const item = root.desktopItems[root.selectedIndex];
                if (item && !item.isSpecial && item.path) {
                    Quickshell.execDetached([Quickshell.shellPath("weylume-native"), "desktop", "trash", item.path]);
                }
            }
            root.clearSelection();
            root.renamingIndex = -1;
            return;
        }

        root.clearSelection();
        root.renamingIndex = -1;
        for (let i = 0; i < indices.length; i++) {
            const item = root.desktopItems[indices[i]];
            if (!item || item.isSpecial || !item.path) continue;
            Quickshell.execDetached([Quickshell.shellPath("weylume-native"), "desktop", "trash", item.path]);
        }
    }

    function startRenameSelectedItem() {
        let idx = root.selectedIndex;
        if (idx < 0) {
            const indices = root.getSelectedIndices();
            if (indices.length === 1) idx = indices[0];
        }
        if (idx < 0 || idx >= (root.desktopItems?.length ?? 0)) return;
        const item = root.desktopItems[idx];
        if (!item || item.isSpecial || !item.path) return;
        root.renamingIndex = idx;
    }

    function openItem(item) {
        if (!item) return;
        const isFolder = item.isDir || item.isFolder || (item.isSpecial && item.path && item.path.startsWith("/")) || item.type === "directory" || item.icon === "folder";
        if (isFolder && item.path) {
            Quickshell.execDetached(["pcmanfm-qt", item.path]);
            return;
        }
        if (item.exec && item.exec.length > 0) {
            Quickshell.execDetached(item.exec);
            return;
        }
        if (item.path) {
            Quickshell.execDetached(["xdg-open", item.path]);
        }
    }

    function openSelectedItem() {
        const indices = root.getSelectedIndices();
        if (indices.length === 0) {
            if (root.selectedIndex >= 0 && root.selectedIndex < (root.desktopItems?.length ?? 0)) {
                root.openItem(root.desktopItems[root.selectedIndex]);
            }
            return;
        }
        for (let i = 0; i < indices.length; i++) {
            root.openItem(root.desktopItems[indices[i]]);
        }
    }

    // Grid constants
    readonly property int gridOriginX: 12
    readonly property int gridOriginY: 12
    readonly property int baseColWidth: 64
    readonly property int baseRowHeight: 70
    readonly property int baseItemWidth: 54
    readonly property int baseItemHeight: 60
    readonly property int baseIconSize: 32
    readonly property int baseFontSize: 11

    readonly property int baseMaxRows: Math.max(1, Math.floor((root.height - Theme.taskbarHeight - 24) / root.baseRowHeight))
    readonly property int baseMaxCols: Math.max(1, Math.floor((root.width - 24) / root.baseColWidth))

    readonly property int colWidth: Math.max(54, Math.round(root.baseColWidth * root.desktopIconScale))
    readonly property int maxAllowedRowHeight: Math.floor((root.height - Theme.taskbarHeight - 24) / root.baseMaxRows)
    readonly property int rowHeight: Math.max(62, Math.min(Math.round(root.baseRowHeight * root.desktopIconScale), root.maxAllowedRowHeight))

    // Strictly enforce minimum 6px vertical spacing and 8px horizontal spacing so icons NEVER overlap
    readonly property int itemHeight: Math.max(54, Math.min(root.rowHeight - 6, Math.round(root.baseItemHeight * root.desktopIconScale)))
    readonly property int itemWidth: Math.max(44, Math.min(root.colWidth - 8, Math.round(root.baseItemWidth * root.desktopIconScale)))

    // Avatar fits cleanly inside tile without overflow or collision with text
    readonly property int iconSize: Math.max(22, Math.min(root.itemHeight - 28, Math.round(root.baseIconSize * root.desktopIconScale)))
    readonly property int iconTextSize: root.baseFontSize

    readonly property int maxRows: Math.max(1, Math.floor((root.height - Theme.taskbarHeight - 24) / root.rowHeight))
    readonly property int maxCols: Math.max(1, Math.floor((root.width - 24) / root.colWidth))

    readonly property var _imageExts: ({
        "png": 1, "jpg": 1, "jpeg": 1, "webp": 1, "svg": 1, "gif": 1,
        "bmp": 1, "ico": 1, "avif": 1, "jxl": 1, "tiff": 1, "tif": 1,
        "heic": 1, "heif": 1
    })

    readonly property var _videoExts: ({
        "mp4": 1, "mkv": 1, "avi": 1, "webm": 1, "mov": 1,
        "flv": 1, "wmv": 1, "m4v": 1, "ts": 1, "3gp": 1
    })

    function isImageItem(item) {
        if (!item || item.isDir || item.isDesktop || item.isSpecial) return false;
        if (item.isImage) return true;
        const p = item.path || item.name || "";
        const dot = p.lastIndexOf(".");
        if (dot === -1) return false;
        return root._imageExts[p.substring(dot + 1).toLowerCase()] === 1;
    }

    function isVideoItem(item) {
        if (!item || item.isDir || item.isDesktop || item.isSpecial) return false;
        if (item.isVideo) return true;
        const p = item.path || item.name || "";
        const dot = p.lastIndexOf(".");
        if (dot === -1) return false;
        return root._videoExts[p.substring(dot + 1).toLowerCase()] === 1;
    }

    function itemPreviewSource(item) {
        if (!item || item.isDir || item.isDesktop || item.isSpecial) return "";
        if (item.thumbnail) return "file://" + item.thumbnail;
        if (item.isImage) return "file://" + item.path;
        if (root.isImageItem(item) && item.path) return "file://" + item.path;
        return "";
    }

    function findFolderAt(dropX, dropY, excludeKey) {
        for (let i = 0; i < root.desktopItems.length; i++) {
            const it = root.desktopItems[i];
            if (!it || !it.isDir || it.isSpecial) continue;
            const key = it.path || it.name || ("item_" + i);
            if (key === excludeKey) continue;

            const p = root.positions[key];
            const col = (p && p.x !== undefined) ? Math.round((p.x - root.gridOriginX) / root.baseColWidth) : Math.floor(i / root.baseMaxRows);
            const row = (p && p.y !== undefined) ? Math.round((p.y - root.gridOriginY) / root.baseRowHeight) : (i % root.baseMaxRows);

            const posX = Math.max(4, Math.min(root.width - root.itemWidth - 4, root.gridOriginX + col * root.colWidth + (root.colWidth - root.itemWidth) / 2));
            const posY = Math.max(4, Math.min(root.height - Theme.taskbarHeight - root.itemHeight - 4, root.gridOriginY + row * root.rowHeight + (root.rowHeight - root.itemHeight) / 2));

            if (dropX >= posX - 4 && dropX <= posX + root.itemWidth + 4 &&
                dropY >= posY - 4 && dropY <= posY + root.itemHeight + 4) {
                return it;
            }
        }
        return null;
    }

    function findFreeGridSlot(targetCol, targetRow, currentKey, customOccupied) {
        let occupied = {};
        for (let key in root.positions) {
            if (key === currentKey) continue;
            const p = root.positions[key];
            if (p && p.x !== undefined && p.y !== undefined) {
                const bc = Math.round((p.x - root.gridOriginX) / root.baseColWidth);
                const br = Math.round((p.y - root.gridOriginY) / root.baseRowHeight);
                occupied[bc + "," + br] = true;
            }
        }
        if (customOccupied) {
            for (let coord in customOccupied) {
                occupied[coord] = true;
            }
        }

        targetCol = Math.max(0, Math.min(root.maxCols - 1, targetCol));
        targetRow = Math.max(0, Math.min(root.maxRows - 1, targetRow));

        if (!occupied[targetCol + "," + targetRow]) {
            return { col: targetCol, row: targetRow };
        }

        for (let dist = 1; dist < root.maxCols + root.maxRows; dist++) {
            for (let dc = 0; dc <= dist; dc++) {
                let dr = dist - dc;
                let candidates = [
                    { c: targetCol + dc, r: targetRow + dr },
                    { c: targetCol + dc, r: targetRow - dr },
                    { c: targetCol - dc, r: targetRow + dr },
                    { c: targetCol - dc, r: targetRow - dr }
                ];
                for (let i = 0; i < candidates.length; i++) {
                    const cand = candidates[i];
                    if (cand.c >= 0 && cand.c < root.maxCols && cand.r >= 0 && cand.r < root.maxRows) {
                        if (!occupied[cand.c + "," + cand.r]) {
                            return { col: cand.c, row: cand.r };
                        }
                    }
                }
            }
        }

        return { col: targetCol, row: targetRow };
    }

    function cleanupDragState() {
        ShellState.isDraggingFile = false;
        ShellState.dragFileData = null;
        root.dragHoverFolder = null;
        root.dragLeaderIndex = -1;
        root.dragDeltaX = 0;
        root.dragDeltaY = 0;
        if (root.currentDraggingWrapper) {
            root.currentDraggingWrapper.restoreBindings();
        }
        root.currentDraggingWrapper = null;
        root.currentDraggingKey = "";
        root.currentDraggingIndex = -1;
        root.dropHandled = false;
    }

    function cancelDesktopDrag() {
        root.cleanupDragState();
    }

    function handleDesktopDrop(dropGlobalX, dropGlobalY) {
        if (!ShellState.isDraggingFile) return;

        let gx = (dropGlobalX !== undefined && dropGlobalX > 0) ? dropGlobalX : ShellState.dragGlobalX;
        let gy = (dropGlobalY !== undefined && dropGlobalY > 0) ? dropGlobalY : ShellState.dragGlobalY;
        if (gx <= 0 && gy <= 0) {
            root.cleanupDragState();
            return;
        }

        const draggingWrapper = root.currentDraggingWrapper;
        const draggingKey = root.currentDraggingKey || (draggingWrapper ? draggingWrapper.itemKey : "");

        if (root.dragHoverFolder) {
            const targetFolder = root.dragHoverFolder;
            if (targetFolder && targetFolder.path) {
                const indices = (draggingWrapper && draggingWrapper.isSelected) ? root.getSelectedIndices() : (draggingWrapper ? [draggingWrapper.index] : []);
                for (let i = 0; i < indices.length; i++) {
                    const it = root.desktopItems[indices[i]];
                    if (it && it.path && !it.isSpecial) {
                        Quickshell.execDetached([Quickshell.shellPath("weylume-native"), "desktop", "move", it.path, targetFolder.path]);
                    }
                }
                root.clearSelection();
            }
            root.cleanupDragState();
            return;
        }

        if (!draggingWrapper && !draggingKey) {
            root.cleanupDragState();
            return;
        }

        const dropX = gx - ShellState.dragGrabOffsetX;
        const dropY = gy - ShellState.dragGrabOffsetY;
        const originX = draggingWrapper ? draggingWrapper.baseX : (root.positions[draggingKey]?.x ?? 0);
        const originY = draggingWrapper ? draggingWrapper.baseY : (root.positions[draggingKey]?.y ?? 0);
        const dist = Math.hypot(dropX - originX, dropY - originY);

        if (dist > 8) {
            const wasGroup = draggingWrapper ? (draggingWrapper.isSelected && root.selectedCount > 1) : false;

            if (wasGroup) {
                const selIndices = root.getSelectedIndices();
                let selKeys = {};
                for (let s = 0; s < selIndices.length; s++) {
                    const sit = root.desktopItems[selIndices[s]];
                    if (sit) {
                        const skey = sit.path || sit.name || ("item_" + selIndices[s]);
                        selKeys[skey] = true;
                    }
                }

                let occupied = {};
                for (let k in root.positions) {
                    if (selKeys[k]) continue;
                    const p = root.positions[k];
                    if (p && p.x !== undefined && p.y !== undefined) {
                        const bc = Math.round((p.x - root.gridOriginX) / root.baseColWidth);
                        const br = Math.round((p.y - root.gridOriginY) / root.baseRowHeight);
                        occupied[bc + "," + br] = true;
                    }
                }

                const leaderOrigCol = Math.round((originX + root.itemWidth / 2 - root.gridOriginX - root.colWidth / 2) / root.colWidth);
                const leaderOrigRow = Math.round((originY + root.itemHeight / 2 - root.gridOriginY - root.rowHeight / 2) / root.rowHeight);
                const leaderRawCol = Math.round((dropX + root.itemWidth / 2 - root.gridOriginX - root.colWidth / 2) / root.colWidth);
                const leaderRawRow = Math.round((dropY + root.itemHeight / 2 - root.gridOriginY - root.rowHeight / 2) / root.rowHeight);
                const deltaCol = leaderRawCol - leaderOrigCol;
                const deltaRow = leaderRawRow - leaderOrigRow;

                let updated = Object.assign({}, root.positions);

                const leaderSlot = root.findFreeGridSlot(leaderRawCol, leaderRawRow, draggingKey, occupied);
                occupied[leaderSlot.col + "," + leaderSlot.row] = true;
                const leaderBaseX = root.gridOriginX + leaderSlot.col * root.baseColWidth;
                const leaderBaseY = root.gridOriginY + leaderSlot.row * root.baseRowHeight;
                updated[draggingKey] = { x: leaderBaseX, y: leaderBaseY };

                for (let s = 0; s < selIndices.length; s++) {
                    const idx = selIndices[s];
                    if (draggingWrapper && idx === draggingWrapper.index) continue;
                    const it = root.desktopItems[idx];
                    if (!it) continue;
                    const k = it.path || it.name || ("item_" + idx);

                    const p = root.positions[k];
                    const origCol = (p && p.x !== undefined) ? Math.round((p.x - root.gridOriginX) / root.baseColWidth) : Math.floor(idx / root.baseMaxRows);
                    const origRow = (p && p.y !== undefined) ? Math.round((p.y - root.gridOriginY) / root.baseRowHeight) : (idx % root.baseMaxRows);

                    const desiredCol = origCol + deltaCol;
                    const desiredRow = origRow + deltaRow;

                    const slot = root.findFreeGridSlot(desiredCol, desiredRow, k, occupied);
                    occupied[slot.col + "," + slot.row] = true;

                    const sX = root.gridOriginX + slot.col * root.baseColWidth;
                    const sY = root.gridOriginY + slot.row * root.baseRowHeight;
                    updated[k] = { x: sX, y: sY };
                }

                root.positions = updated;
                posStore.setText(JSON.stringify(updated, null, 2));
            } else {
                const rawCol = Math.round((dropX + root.itemWidth / 2 - root.gridOriginX - root.colWidth / 2) / root.colWidth);
                const rawRow = Math.round((dropY + root.itemHeight / 2 - root.gridOriginY - root.rowHeight / 2) / root.rowHeight);
                const freeSlot = root.findFreeGridSlot(rawCol, rawRow, draggingKey);

                const baseSnappedX = root.gridOriginX + freeSlot.col * root.baseColWidth;
                const baseSnappedY = root.gridOriginY + freeSlot.row * root.baseRowHeight;

                let updated = Object.assign({}, root.positions);
                updated[draggingKey] = { x: baseSnappedX, y: baseSnappedY };
                root.positions = updated;
                posStore.setText(JSON.stringify(updated, null, 2));
            }

            if (draggingWrapper && draggingWrapper.modelData?.path && !draggingWrapper.modelData?.isSpecial) {
                Quickshell.execDetached([Quickshell.shellPath("weylume-native"), "desktop", "copy-uri", draggingWrapper.modelData.path]);
            }
        }

        root.cleanupDragState();
    }

    function ensurePositions() {
        if (!root.positionsLoaded || !root.desktopItems || root.desktopItems.length === 0) return;

        // Fast path: if all desktop items already have valid positions and no dead keys exist, skip work.
        let needsWork = false;
        const validKeys = {};
        for (let i = 0; i < root.desktopItems.length; i++) {
            const it = root.desktopItems[i];
            if (!it) continue;
            const key = it.path || it.name || ("item_" + i);
            validKeys[key] = true;
            const p = root.positions ? root.positions[key] : null;
            if (!p || p.x === undefined || p.y === undefined) {
                needsWork = true;
            }
        }

        if (!needsWork && root.positions) {
            for (let key in root.positions) {
                if (!validKeys[key] && !key.startsWith("trash:///") && key !== "/mnt" && key !== "/home/pc") {
                    needsWork = true;
                    break;
                }
            }
            if (!needsWork) return;
        }

        let occupied = {};
        let missing = [];
        let updated = Object.assign({}, root.positions || {});
        let cleaned = false;

        for (let key in root.positions) {
            if (!validKeys[key] && !key.startsWith("trash:///") && key !== "/mnt" && key !== "/home/pc") {
                delete updated[key];
                cleaned = true;
                continue;
            }
            const p = updated[key];
            if (p && p.x !== undefined && p.y !== undefined) {
                const c = Math.round((p.x - root.gridOriginX) / root.baseColWidth);
                const r = Math.round((p.y - root.gridOriginY) / root.baseRowHeight);
                occupied[c + "," + r] = true;
            }
        }

        for (let i = 0; i < root.desktopItems.length; i++) {
            const it = root.desktopItems[i];
            if (!it) continue;
            const key = it.path || it.name || ("item_" + i);
            if (!updated[key] || updated[key].x === undefined || updated[key].y === undefined) {
                missing.push(key);
            }
        }

        if (missing.length === 0) {
            if (cleaned) {
                root.positions = updated;
                if (StateStore.ready) {
                    posStore.setText(JSON.stringify(updated, null, 2));
                }
            }
            return;
        }

        let curCol = 0;
        let curRow = 0;

        for (let m = 0; m < missing.length; m++) {
            const key = missing[m];
            let placed = false;
            while (!placed && curCol < root.baseMaxCols) {
                const coord = curCol + "," + curRow;
                if (!occupied[coord]) {
                    occupied[coord] = true;
                    updated[key] = {
                        x: root.gridOriginX + curCol * root.baseColWidth,
                        y: root.gridOriginY + curRow * root.baseRowHeight
                    };
                    placed = true;
                }
                curRow++;
                if (curRow >= root.baseMaxRows) {
                    curRow = 0;
                    curCol++;
                }
            }
            if (!placed) {
                const fallback = root.findFreeGridSlot(0, 0, key, occupied);
                occupied[fallback.col + "," + fallback.row] = true;
                updated[key] = {
                    x: root.gridOriginX + fallback.col * root.baseColWidth,
                    y: root.gridOriginY + fallback.row * root.baseRowHeight
                };
            }
        }

        root.positions = updated;
        if (StateStore.ready) {
            posStore.setText(JSON.stringify(updated, null, 2));
        }
    }

    function sortIconsByName() {
        let items = (root.desktopItems || []).slice();
        items.sort((a, b) => {
            if (a.isSpecial !== b.isSpecial) return a.isSpecial ? -1 : 1;
            if (a.isDir !== b.isDir) return a.isDir ? -1 : 1;
            return (a.name || "").localeCompare(b.name || "");
        });
        root.applyArrangedPositions(items);
    }

    function sortIconsByDate() {
        let items = (root.desktopItems || []).slice();
        items.sort((a, b) => {
            if (a.isSpecial !== b.isSpecial) return a.isSpecial ? -1 : 1;
            return (b.mtime || 0) - (a.mtime || 0);
        });
        root.applyArrangedPositions(items);
    }

    function autoArrangeIcons() {
        root.applyArrangedPositions(root.desktopItems || []);
    }

    function applyArrangedPositions(items) {
        let updated = {};
        let curCol = 0;
        let curRow = 0;
        for (let i = 0; i < items.length; i++) {
            const it = items[i];
            if (!it) continue;
            const key = it.path || it.name || ("item_" + i);
            updated[key] = {
                x: root.gridOriginX + curCol * root.baseColWidth,
                y: root.gridOriginY + curRow * root.baseRowHeight
            };
            curRow++;
            if (curRow >= root.baseMaxRows) {
                curRow = 0;
                curCol++;
            }
        }
        root.positions = updated;
        if (StateStore.ready) {
            posStore.setText(JSON.stringify(updated, null, 2));
        }
    }

    FileView {
        id: posStore
        path: StateStore.ready ? Quickshell.shellPath("desktop_positions.json") : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const raw = text();
            if (raw && raw.trim().length > 0) {
                root.positions = root.parsePositions(raw);
            }
            root.positionsLoaded = true;
            root.ensurePositions();
        }
    }

    readonly property string effectiveWallpaper: ShellState.wallpaperPath || ""

    Image {
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        source: root.effectiveWallpaper ? (root.effectiveWallpaper.startsWith("file://") ? root.effectiveWallpaper : "file://" + root.effectiveWallpaper) : ""
        sourceSize: Qt.size(root.width > 0 ? root.width : 1920, root.height > 0 ? root.height : 1080)
        visible: Boolean(root.effectiveWallpaper && root.effectiveWallpaper !== "")
        smooth: true
        mipmap: true
        z: -1
    }

    Item {
        id: bgMenuAnchor
        width: 1
        height: 1
    }

    DropArea {
        id: desktopDropArea
        anchors.fill: parent
        z: 0

        onEntered: drag => {
            drag.acceptProposedAction();
        }

        onDropped: drop => {
            drop.acceptProposedAction();
        }
    }

    // Dismiss selection on background click, drag rubberband selection, & open context menu on right click
    MouseArea {
        id: bgMouse
        anchors.fill: parent
        z: 0
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        property real startX: 0
        property real startY: 0
        property bool dragOccurred: false
        property var initialSelection: null
        property var cachedItemBounds: null
        property string lastSelectionSig: ""

        onPressed: mouse => {
            if (mouse.button === Qt.RightButton) {
                bgMenuAnchor.x = mouse.x;
                bgMenuAnchor.y = mouse.y;
                return;
            }

            if (desktopContextMenu.menuVisible) {
                desktopContextMenu.dismiss();
            }

            startX = mouse.x;
            startY = mouse.y;
            dragOccurred = false;
            lastSelectionSig = "";

            const isCtrl = Boolean(mouse.modifiers & Qt.ControlModifier);
            initialSelection = isCtrl ? Object.assign({}, root.selectedMap) : ({});

            // Pre-calculate desktop item bounding boxes once per drag start (fast numeric AABB check)
            const items = root.desktopItems;
            const bounds = [];
            if (items) {
                for (let i = 0; i < items.length; i++) {
                    const it = items[i];
                    if (!it) continue;
                    const key = it.path || it.name || ("item_" + i);
                    const p = root.positions[key];
                    const col = (p && p.x !== undefined) ? Math.round((p.x - root.gridOriginX) / root.baseColWidth) : Math.floor(i / root.baseMaxRows);
                    const row = (p && p.y !== undefined) ? Math.round((p.y - root.gridOriginY) / root.baseRowHeight) : (i % root.baseMaxRows);
                    const posX = Math.max(4, Math.min(root.width - root.itemWidth - 4, root.gridOriginX + col * root.colWidth + (root.colWidth - root.itemWidth) / 2));
                    const posY = Math.max(4, Math.min(root.height - Theme.taskbarHeight - root.itemHeight - 4, root.gridOriginY + row * root.rowHeight + (root.rowHeight - root.itemHeight) / 2));
                    bounds.push({
                        index: i,
                        x1: posX,
                        y1: posY,
                        x2: posX + root.itemWidth,
                        y2: posY + root.itemHeight
                    });
                }
            }
            cachedItemBounds = bounds;
        }

        onPositionChanged: mouse => {
            if (!pressed || (mouse.buttons !== Qt.LeftButton)) return;

            const curX = mouse.x;
            const curY = mouse.y;
            const dx = Math.abs(curX - startX);
            const dy = Math.abs(curY - startY);

            if (!dragOccurred) {
                if (dx >= 4 || dy >= 4) {
                    dragOccurred = true;
                    marqueeBox.visible = true;
                    ShellState.closeFlyouts();
                    desktopContextMenu.dismiss();
                } else {
                    return;
                }
            }

            const bx = Math.min(startX, curX);
            const by = Math.min(startY, curY);
            const bw = Math.max(1, dx);
            const bh = Math.max(1, dy);

            marqueeBox.x = bx;
            marqueeBox.y = by;
            marqueeBox.width = bw;
            marqueeBox.height = bh;

            if (!cachedItemBounds) return;

            const bRight = bx + bw;
            const bBottom = by + bh;

            const nextMap = initialSelection ? Object.assign({}, initialSelection) : {};
            const hitIndices = [];

            for (let i = 0; i < cachedItemBounds.length; i++) {
                const b = cachedItemBounds[i];
                if (!(b.x1 > bRight || b.x2 < bx || b.y1 > bBottom || b.y2 < by)) {
                    nextMap[b.index] = true;
                    hitIndices.push(b.index);
                }
            }

            const sig = hitIndices.join(",");
            if (sig !== lastSelectionSig) {
                lastSelectionSig = sig;
                const keys = Object.keys(nextMap);
                root.selectedMap = nextMap;
                root.selectedCount = keys.length;
                root.selectedIndex = keys.length > 0 ? parseInt(keys[keys.length - 1]) : -1;
            }
        }

        onReleased: mouse => {
            if (mouse.button === Qt.RightButton) {
                root.clearSelection();
                root.renamingIndex = -1;
                ShellState.closeFlyouts(false);
                bgMenuAnchor.x = mouse.x;
                bgMenuAnchor.y = mouse.y;
                desktopContextMenu.openFor(bgMenuAnchor, null);
                return;
            }

            if (dragOccurred) {
                dragOccurred = false;
                marqueeBox.visible = false;
                keyHandler.forceActiveFocus();
            } else {
                const isCtrl = Boolean(mouse.modifiers & Qt.ControlModifier);
                if (!isCtrl) {
                    root.clearSelection();
                }
                root.renamingIndex = -1;
                ShellState.closeFlyouts();
                desktopContextMenu.dismiss();
                keyHandler.forceActiveFocus();
            }

            cachedItemBounds = null;
            initialSelection = null;
            lastSelectionSig = "";
        }

        onCanceled: {
            dragOccurred = false;
            marqueeBox.visible = false;
            cachedItemBounds = null;
            initialSelection = null;
            lastSelectionSig = "";
        }

        onWheel: wheel => {
            if (root.hasSelection && (wheel.modifiers & Qt.ControlModifier)) {
                if (wheel.angleDelta.y > 0) {
                    root.zoomInIcons();
                } else if (wheel.angleDelta.y < 0) {
                    root.zoomOutIcons();
                }
                wheel.accepted = true;
            }
        }
    }

    Rectangle {
        id: marqueeBox
        visible: false
        z: 200
        color: "#25ffffff"
        border.color: "#80ffffff"
        border.width: 1
        radius: 2
    }

    Item {
        id: keyHandler
        anchors.fill: parent
        focus: true
        Keys.onDeletePressed: root.deleteSelectedItem()
        Keys.onEscapePressed: {
            if (ShellState.isDraggingFile) {
                root.cleanupDragState();
            }
        }
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape && ShellState.isDraggingFile) {
                root.cleanupDragState();
                event.accepted = true;
                return;
            }
            root.handleDesktopKeyPress(event);
        }
    }

    Item {
        anchors.fill: parent
        z: 1

        Repeater {
            model: root.desktopItems

            Item {
                id: itemWrapper
                required property var modelData
                required property int index

                readonly property string itemKey: modelData.path || modelData.name || ("item_" + index)
                readonly property bool isHoverTarget: root.dragHoverFolder && root.dragHoverFolder.path === itemWrapper.modelData.path
                readonly property bool isRenaming: root.renamingIndex === itemWrapper.index
                readonly property bool isSelected: Boolean(root.selectedMap && root.selectedMap[itemWrapper.index])

                readonly property int baseCol: (root.positions[itemKey] && root.positions[itemKey].x !== undefined)
                    ? Math.round((root.positions[itemKey].x - root.gridOriginX) / root.baseColWidth)
                    : Math.floor(index / root.baseMaxRows)
                readonly property int baseRow: (root.positions[itemKey] && root.positions[itemKey].y !== undefined)
                    ? Math.round((root.positions[itemKey].y - root.gridOriginY) / root.baseRowHeight)
                    : (index % root.baseMaxRows)

                readonly property int gridCol: baseCol
                readonly property int gridRow: baseRow

                readonly property real minX: 4
                readonly property real maxX: Math.max(minX, root.width - root.itemWidth - 4)
                readonly property real minY: 4
                readonly property real maxY: Math.max(minY, root.height - Theme.taskbarHeight - root.itemHeight - 4)

                readonly property real cellX: root.gridOriginX + gridCol * root.colWidth
                readonly property real cellY: root.gridOriginY + gridRow * root.rowHeight

                readonly property real baseX: Math.max(minX, Math.min(maxX, cellX + (root.colWidth - root.itemWidth) / 2))
                readonly property real baseY: Math.max(minY, Math.min(maxY, cellY + (root.rowHeight - root.itemHeight) / 2))

                function restoreBindings() {
                    itemWrapper.x = Qt.binding(function() { return itemWrapper.baseX; });
                    itemWrapper.y = Qt.binding(function() { return itemWrapper.baseY; });
                }

                x: baseX
                y: baseY

                Behavior on x {
                    NumberAnimation { duration: SettingsService.reducedMotion ? 0 : 120; easing.type: Easing.OutQuad }
                }
                Behavior on y {
                    NumberAnimation { duration: SettingsService.reducedMotion ? 0 : 120; easing.type: Easing.OutQuad }
                }

                width: root.itemWidth
                height: root.itemHeight

                Behavior on width {
                    NumberAnimation { duration: SettingsService.reducedMotion ? 0 : 100; easing.type: Easing.OutQuad }
                }
                Behavior on height {
                    NumberAnimation { duration: SettingsService.reducedMotion ? 0 : 100; easing.type: Easing.OutQuad }
                }

                z: (ShellState.isDraggingFile && ShellState.dragFileData?.path === itemWrapper.modelData?.path) ? 100 : (itemWrapper.isSelected ? 10 : 1)
                focus: itemWrapper.isSelected

                opacity: (ShellState.isDraggingFile && (ShellState.dragFileData?.path === itemWrapper.modelData?.path || (root.selectedCount > 1 && itemWrapper.isSelected))) ? 0.35 : 1.0
                Behavior on opacity { NumberAnimation { duration: SettingsService.reducedMotion ? 0 : 100 } }

                Keys.onDeletePressed: root.deleteSelectedItem()
                Keys.onPressed: event => root.handleDesktopKeyPress(event)

                Rectangle {
                    anchors.fill: parent
                    radius: 4
                    color: itemWrapper.isHoverTarget
                        ? "#300078d4"
                        : (itemWrapper.isSelected
                            ? (itemMouse.containsMouse ? "#38ffffff" : "#26ffffff")
                            : (itemMouse.containsMouse ? "#14ffffff" : "transparent"))
                    border.width: itemWrapper.isHoverTarget ? 2 : ((itemWrapper.isSelected || itemMouse.containsMouse) ? 1 : 0)
                    border.color: itemWrapper.isHoverTarget
                        ? "#0078d4"
                        : (itemWrapper.isSelected
                            ? (itemMouse.containsMouse ? "#70ffffff" : "#55ffffff")
                            : (itemMouse.containsMouse ? "#28ffffff" : "transparent"))

                    Behavior on color { ColorAnimation { duration: SettingsService.reducedMotion ? 0 : 80 } }
                    Behavior on border.color { ColorAnimation { duration: SettingsService.reducedMotion ? 0 : 80 } }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.topMargin: 3
                        anchors.bottomMargin: 2
                        anchors.leftMargin: 2
                        anchors.rightMargin: 2
                        spacing: 2

                        Item {
                            id: iconContainer
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.iconSize
                            Layout.minimumHeight: root.iconSize
                            Layout.maximumHeight: root.iconSize
                            Layout.alignment: Qt.AlignHCenter | Qt.AlignTop

                            readonly property string previewSource: root.itemPreviewSource(itemWrapper.modelData)
                            readonly property bool hasPreview: previewSource !== ""
                            readonly property bool isVideo: root.isVideoItem(itemWrapper.modelData)

                            Image {
                                id: previewImg
                                anchors.centerIn: parent
                                width: root.iconSize
                                height: root.iconSize
                                sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)
                                asynchronous: true
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                mipmap: true
                                visible: status === Image.Ready
                                source: iconContainer.previewSource

                                Behavior on width { NumberAnimation { duration: SettingsService.reducedMotion ? 0 : 100; easing.type: Easing.OutQuad } }
                                Behavior on height { NumberAnimation { duration: SettingsService.reducedMotion ? 0 : 100; easing.type: Easing.OutQuad } }
                            }

                            Rectangle {
                                id: videoBadge
                                visible: iconContainer.isVideo && previewImg.visible
                                width: Math.max(12, Math.round(root.iconSize * 0.32))
                                height: Math.max(12, Math.round(root.iconSize * 0.32))
                                radius: width / 2
                                color: "#b0000000"
                                anchors.right: previewImg.right
                                anchors.bottom: previewImg.bottom
                                anchors.margins: 1
                                border.color: "#60ffffff"
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    anchors.horizontalCenterOffset: 1
                                    text: "▶"
                                    color: "#ffffff"
                                    font.pixelSize: Math.max(7, Math.round(parent.width * 0.55))
                                }
                            }

                            Image {
                                id: iconImg
                                anchors.centerIn: parent
                                width: root.iconSize
                                height: root.iconSize
                                sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)
                                source: {
                                    if ((!iconContainer.hasPreview || previewImg.status === Image.Error) && itemWrapper.modelData.icon) {
                                        const ic = itemWrapper.modelData.icon;
                                        if (ic === "weylume-settings" || ic === "preferences-system" || itemWrapper.modelData.label === "Settings") {
                                            return Theme.settingsIcon;
                                        }
                                        return Quickshell.iconPath(ic);
                                    }
                                    return "";
                                }
                                fillMode: Image.PreserveAspectFit
                                visible: !previewImg.visible && status === Image.Ready
                                smooth: true
                                mipmap: true

                                Behavior on width { NumberAnimation { duration: SettingsService.reducedMotion ? 0 : 100; easing.type: Easing.OutQuad } }
                                Behavior on height { NumberAnimation { duration: SettingsService.reducedMotion ? 0 : 100; easing.type: Easing.OutQuad } }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: itemWrapper.modelData.fallback || "•"
                                color: "#ffffff"
                                font.pixelSize: Math.round(root.iconSize * 0.65)
                                visible: !previewImg.visible && !iconImg.visible
                            }
                        }

                        // Normal label
                        Text {
                            visible: !itemWrapper.isRenaming
                            Layout.fillWidth: true
                            Layout.leftMargin: 2
                            Layout.rightMargin: 2
                            Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
                            text: itemWrapper.modelData.name || ""
                            color: "#ffffff"
                            font.family: Theme.fontFamily
                            font.pixelSize: root.iconTextSize
                            font.weight: Font.Normal
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            maximumLineCount: 2
                            wrapMode: Text.Wrap
                            style: Text.Sunken
                            styleColor: "#80000000"
                        }

                        // Inline Rename Input
                        Rectangle {
                            visible: itemWrapper.isRenaming
                            Layout.fillWidth: false
                            Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
                            Layout.preferredWidth: Math.min(root.colWidth + 24, Math.max(itemWrapper.width, renameInput.contentWidth + 16))
                            implicitHeight: Math.max(22, root.iconTextSize + 10)
                            color: "#0d0d0d"
                            border.width: 1
                            border.color: "#ffffff"
                            radius: 4

                            TextInput {
                                id: renameInput
                                anchors.fill: parent
                                anchors.leftMargin: 4
                                anchors.rightMargin: 4
                                anchors.topMargin: 2
                                anchors.bottomMargin: 2
                                verticalAlignment: TextInput.AlignVCenter
                                horizontalAlignment: TextInput.AlignHCenter
                                text: itemWrapper.modelData.name || ""
                                color: "#ffffff"
                                selectionColor: "#ffffff"
                                selectedTextColor: "#000000"
                                font.family: Theme.fontFamily
                                font.pixelSize: root.iconTextSize
                                selectByMouse: true
                                focus: itemWrapper.isRenaming
                                clip: true

                                function selectBaseName() {
                                    const val = text;
                                    const dot = (!itemWrapper.modelData.isDir && !itemWrapper.modelData.isSpecial) ? val.lastIndexOf(".") : -1;
                                    if (dot > 0) {
                                        select(0, dot);
                                    } else {
                                        selectAll();
                                    }
                                }

                                Component.onCompleted: {
                                    if (itemWrapper.isRenaming) {
                                        forceActiveFocus();
                                        selectBaseName();
                                    }
                                }

                                onVisibleChanged: {
                                    if (visible) {
                                        text = itemWrapper.modelData.name || "";
                                        forceActiveFocus();
                                        selectBaseName();
                                    }
                                }

                                Keys.onPressed: event => {
                                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                        const val = text.trim();
                                        if (val.length > 0 && val !== itemWrapper.modelData.name) {
                                            const oldPath = itemWrapper.modelData.path;
                                            const oldKey = itemWrapper.itemKey;
                                            const oldPos = root.positions[oldKey] || root.positions[oldPath];

                                            if (oldPath) {
                                                const slashIdx = oldPath.lastIndexOf("/");
                                                const dir = slashIdx > 0 ? oldPath.substring(0, slashIdx) : "/home/pc/Desktop";
                                                const newPath = dir + "/" + val;

                                                if (oldPos) {
                                                    let updated = Object.assign({}, root.positions);
                                                    updated[newPath] = { x: oldPos.x, y: oldPos.y };
                                                    delete updated[oldKey];
                                                    delete updated[oldPath];
                                                    root.positions = updated;
                                                    if (StateStore.ready) {
                                                        posStore.setText(JSON.stringify(updated, null, 2));
                                                    }
                                                }
                                                Quickshell.execDetached([Quickshell.shellPath("weylume-native"), "desktop", "rename", oldPath, val]);
                                            }
                                        }
                                        root.renamingIndex = -1;
                                        keyHandler.forceActiveFocus();
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_Escape) {
                                        root.renamingIndex = -1;
                                        keyHandler.forceActiveFocus();
                                        event.accepted = true;
                                    }
                                }
                            }
                        }
                    }
                }

                MouseArea {
                    id: itemMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton

                    property real pressX: 0
                    property real pressY: 0
                    property bool isDraggingItem: false

                    onPressed: mouse => {
                        pressX = mouse.x;
                        pressY = mouse.y;
                        isDraggingItem = false;

                        ShellState.dragGrabOffsetX = mouse.x;
                        ShellState.dragGrabOffsetY = mouse.y;
                        ShellState.dragItemWidth = root.itemWidth;
                        ShellState.dragItemHeight = root.itemHeight;
                        ShellState.dragIconSize = root.iconSize;

                        const pt = itemMouse.mapToItem(null, mouse.x, mouse.y);
                        ShellState.dragGlobalX = pt.x;
                        ShellState.dragGlobalY = pt.y;

                        root.dragHoverFolder = null;
                        if (desktopContextMenu.menuVisible) {
                            desktopContextMenu.dismiss();
                        }
                        root.currentDraggingWrapper = itemWrapper;
                        root.currentDraggingKey = itemWrapper.itemKey;
                        root.currentDraggingIndex = itemWrapper.index;
                        root.dropHandled = false;

                        if (mouse.button === Qt.LeftButton) {
                            const isCtrl = Boolean(mouse.modifiers & Qt.ControlModifier);
                            if (isCtrl) {
                                root.toggleSelection(itemWrapper.index);
                            } else {
                                if (!itemWrapper.isSelected) {
                                    root.setSingleSelection(itemWrapper.index);
                                }
                            }
                            if (itemWrapper.isSelected && root.selectedCount > 1) {
                                root.dragLeaderIndex = itemWrapper.index;
                            } else {
                                root.dragLeaderIndex = -1;
                            }
                        }
                        if (root.renamingIndex !== itemWrapper.index) {
                            root.renamingIndex = -1;
                        }
                        keyHandler.forceActiveFocus();
                    }

                    onPositionChanged: mouse => {
                        if (mouse.buttons & Qt.LeftButton) {
                            if (!isDraggingItem) {
                                const dist = Math.hypot(mouse.x - pressX, mouse.y - pressY);
                                if (dist >= 8) {
                                    isDraggingItem = true;
                                    ShellState.isDraggingFile = true;
                                    ShellState.dragFileData = itemWrapper.modelData;
                                    root.currentDraggingWrapper = itemWrapper;
                                    root.currentDraggingKey = itemWrapper.itemKey;
                                    root.currentDraggingIndex = itemWrapper.index;
                                }
                            }
                            if (isDraggingItem) {
                                const pt = itemMouse.mapToItem(null, mouse.x, mouse.y);
                                const clampedX = Math.max(0, Math.min(root.width, pt.x));
                                const clampedY = Math.max(0, Math.min(root.height, pt.y));
                                ShellState.dragGlobalX = clampedX;
                                ShellState.dragGlobalY = clampedY;

                                const centerX = clampedX - ShellState.dragGrabOffsetX + root.itemWidth / 2;
                                const centerY = clampedY - ShellState.dragGrabOffsetY + root.itemHeight / 2;
                                root.dragHoverFolder = root.findFolderAt(centerX, centerY, itemWrapper.itemKey);
                            }
                        }
                    }

                    onReleased: mouse => {
                        if (isDraggingItem || ShellState.isDraggingFile) {
                            const pt = itemMouse.mapToItem(null, mouse.x, mouse.y);
                            root.handleDesktopDrop(pt.x, pt.y);
                            isDraggingItem = false;
                        }
                    }

                    onCanceled: {
                        if (isDraggingItem || ShellState.isDraggingFile) {
                            root.cleanupDragState();
                            isDraggingItem = false;
                        }
                    }

                    onPressAndHold: {
                        if (!isDraggingItem && !ShellState.isDraggingFile) {
                            desktopContextMenu.openFor(itemWrapper, itemWrapper.modelData);
                        }
                    }

                    onClicked: event => {
                        if (isDraggingItem || ShellState.isDraggingFile) return;
                        if (event.button === Qt.RightButton) {
                            if (!itemWrapper.isSelected) {
                                root.setSingleSelection(itemWrapper.index);
                            }
                            bgMenuAnchor.x = itemWrapper.x + event.x + 2;
                            bgMenuAnchor.y = itemWrapper.y + event.y + 2;
                            desktopContextMenu.openFor(bgMenuAnchor, itemWrapper.modelData);
                            event.accepted = true;
                        } else {
                            const isCtrl = Boolean(event.modifiers & Qt.ControlModifier);
                            if (!isCtrl) {
                                root.setSingleSelection(itemWrapper.index);
                            }
                            ShellState.closeFlyouts();
                            desktopContextMenu.dismiss();
                        }
                    }

                    onDoubleClicked: event => {
                        if (isDraggingItem || ShellState.isDraggingFile) return;
                        if (event.button !== Qt.LeftButton) return;
                        if (root.selectedCount > 1) {
                            root.openSelectedItem();
                        } else {
                            root.openItem(itemWrapper.modelData);
                        }
                    }

                    onWheel: wheel => {
                        if (root.hasSelection && (wheel.modifiers & Qt.ControlModifier)) {
                            if (wheel.angleDelta.y > 0) {
                                root.zoomInIcons();
                            } else if (wheel.angleDelta.y < 0) {
                                root.zoomOutIcons();
                            }
                            wheel.accepted = true;
                        }
                    }
                }
            }
        }
    }

    // ==========================================
    // DRAG AND DROP VISUAL FEEDBACK
    // ==========================================

    // 1. Drop Target Slot Indicator (shows where item will snap to on the desktop grid)
    Rectangle {
        id: dropTargetGhost
        visible: ShellState.isDraggingFile && !root.dragHoverFolder && root.targetDropSlot !== null
        x: root.targetDropSlot ? root.targetDropSlot.x : (root.currentDraggingWrapper ? root.currentDraggingWrapper.baseX : 0)
        y: root.targetDropSlot ? root.targetDropSlot.y : (root.currentDraggingWrapper ? root.currentDraggingWrapper.baseY : 0)
        width: root.itemWidth
        height: root.itemHeight
        radius: 6
        color: Theme.isDark ? "#28ffffff" : "#20000000"
        border.width: 2
        border.color: Theme.accent
        enabled: false
        z: 900

        Rectangle {
            anchors.centerIn: parent
            width: root.iconSize + 8
            height: root.iconSize + 8
            radius: 6
            color: "transparent"
            border.width: 1
            border.color: Theme.accent
            opacity: 0.4
        }
    }

    // 2. Floating Drag Card (follows cursor showing dragged item, icon/thumbnail, and counter)
    Item {
        id: floatingDragVisual
        visible: ShellState.isDraggingFile && ShellState.dragFileData !== null
        z: 2000
        width: root.itemWidth
        height: root.itemHeight
        x: Math.round(ShellState.dragGlobalX - ShellState.dragGrabOffsetX)
        y: Math.round(ShellState.dragGlobalY - ShellState.dragGrabOffsetY)
        enabled: false

        Rectangle {
            anchors.fill: parent
            radius: 6
            color: Theme.isDark ? "#b0121212" : "#b0ffffff"
            border.width: 1.5
            border.color: root.dragHoverFolder ? "#0078d4" : Theme.accent
            scale: 1.05
            opacity: 0.95

            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: 4
                anchors.bottomMargin: 3
                anchors.leftMargin: 3
                anchors.rightMargin: 3
                spacing: 2

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.iconSize
                    Layout.alignment: Qt.AlignHCenter | Qt.AlignTop

                    Image {
                        id: dragPreviewImg
                        anchors.centerIn: parent
                        width: root.iconSize
                        height: root.iconSize
                        sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                        visible: status === Image.Ready
                        source: {
                            const d = ShellState.dragFileData;
                            if (!d) return "";
                            if (d.thumbnail) return (d.thumbnail.startsWith("file://") ? d.thumbnail : ("file://" + d.thumbnail));
                            if (d.isImage && d.path) return (d.path.startsWith("file://") ? d.path : ("file://" + d.path));
                            return "";
                        }
                    }

                    Image {
                        id: dragIconFallback
                        anchors.centerIn: parent
                        width: root.iconSize
                        height: root.iconSize
                        sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                        visible: !dragPreviewImg.visible && status === Image.Ready
                        source: {
                            const d = ShellState.dragFileData;
                            if (!d) return "";
                            const iconName = d.isImage ? "image-x-generic" : (d.icon || "application-x-generic");
                            if (iconName === "weylume-settings" || iconName === "preferences-system") return Theme.settingsIcon;
                            return Quickshell.iconPath(iconName, "application-x-generic");
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: (ShellState.dragFileData?.name || "•").charAt(0).toUpperCase()
                        visible: !dragPreviewImg.visible && !dragIconFallback.visible
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.round(root.iconSize * 0.65)
                        font.weight: Font.Bold
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
                    text: root.dragHoverFolder ? ("Move into " + (root.dragHoverFolder.name || "Folder")) : (ShellState.dragFileData?.name || "")
                    color: root.dragHoverFolder ? "#0078d4" : Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: root.iconTextSize
                    font.weight: root.dragHoverFolder ? Font.DemiBold : Font.Normal
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                }
            }

            // Multi-item counter badge
            Rectangle {
                visible: root.selectedCount > 1
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: -4
                anchors.rightMargin: -4
                width: Math.max(18, badgeText.implicitWidth + 8)
                height: 18
                radius: 9
                color: "#0078d4"
                border.width: 1.5
                border.color: "#ffffff"

                Text {
                    id: badgeText
                    anchors.centerIn: parent
                    text: "+" + root.selectedCount
                    color: "#ffffff"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Bold
                }
            }
        }
    }

    DesktopContextMenu {
        id: desktopContextMenu
        onRenameRequested: {
            root.startRenameSelectedItem();
        }
        onDeleteRequested: {
            root.deleteSelectedItem();
        }
        onAutoArrangeRequested: {
            root.autoArrangeIcons();
        }
        onSortByNameRequested: {
            root.sortIconsByName();
        }
        onSortByDateRequested: {
            root.sortIconsByDate();
        }
    }
}
