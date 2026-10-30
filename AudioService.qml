pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

Scope {
    id: root

    readonly property var defaultSink: Pipewire.defaultAudioSink
    readonly property var defaultSource: Pipewire.defaultAudioSource

    readonly property var audioModel: classifyAudioNodes()
    readonly property var sinks: audioModel.sinks
    readonly property var sources: audioModel.sources
    readonly property var streams: audioModel.streams
    readonly property var inputStreams: audioModel.inputStreams

    function classifyAudioNodes() {
        const model = { sinks: [], sources: [], streams: [], inputStreams: [], matches: [] };
        const all = (Pipewire.nodes && Pipewire.nodes.values) ? Pipewire.nodes.values : [];
        for (let i = 0; i < all.length; ++i) {
            const node = all[i];
            if (!node || !node.properties) continue;
            const cls = node.properties["media.class"] || "";
            if (cls.startsWith("Audio/Sink") || (cls.includes("Sink") && !cls.includes("Stream")))
                model.sinks.push(node);
            if (cls.startsWith("Audio/Source") || (cls.includes("Source") && !cls.includes("Stream")))
                model.sources.push(node);
            if (node.properties["pulse.corked"] === "true") continue;
            if (cls === "Stream/Output/Audio") {
                model.streams.push(node);
                model.matches.push(audioMatchRecord(node));
            } else if (cls === "Stream/Input/Audio") model.inputStreams.push(node);
        }
        model.sinks.sort((a, b) => a.id - b.id);
        model.sources.sort((a, b) => a.id - b.id);
        return model;
    }

    function getDiscordFlavor(str) {
        if (!str) return null;
        const s = str.toLowerCase();
        if (s.includes("canary")) return "canary";
        if (s.includes("ptb")) return "ptb";
        if (s.includes("development") || s.includes("discord-dev") || s.includes("discorddev")) return "development";
        if (s.includes("discord")) return "stable";
        return null;
    }

    function audioMatchRecord(n) {
        const appName = (n.properties["application.name"] || "").trim().toLowerCase();
        const binary = (n.properties["application.process.binary"] || "").trim().toLowerCase();
        const nodeName = (n.name || "").trim().toLowerCase();
        const iconName = (n.properties["application.icon-name"] || "").trim().toLowerCase();
        const portalAppId = (n.properties["pipewire.access.portal.app_id"] || "").trim().toLowerCase();
        const applicationId = (n.properties["application.id"] || "").trim().toLowerCase();

        const nodeStr = [appName, binary, nodeName, iconName, portalAppId, applicationId].join(" ");
        let nodeFlavor = null;
        if (nodeStr.includes("discord") || appName === "webrtc voiceengine") {
            if (nodeStr.includes("canary")) nodeFlavor = "canary";
            else if (nodeStr.includes("ptb")) nodeFlavor = "ptb";
            else if (nodeStr.includes("development") || nodeStr.includes("discord-dev") || nodeStr.includes("discorddev")) nodeFlavor = "development";
            else nodeFlavor = "stable";
        }

        const streamIds = [appName, binary, nodeName, iconName, portalAppId, applicationId].filter(x => x.length > 0);
        if (binary.includes("spotify") || appName.includes("spotify")) streamIds.push("spotify");
        if (binary.includes("steam") || appName.includes("steam")) streamIds.push("steam");
        if (binary.includes("firefox") || appName.includes("firefox")) streamIds.push("firefox");
        if (binary.includes("chrome") || appName.includes("chrome") || binary.includes("chromium") || appName.includes("chromium")) {
            streamIds.push("chromium");
            streamIds.push("google-chrome");
        }

        return { node: n, flavor: nodeFlavor, ids: streamIds };
    }
    function nodesForApp(appIds, label) {
        const records = root.audioModel.matches;
        let matched = [];
        let targets = [];
        if (Array.isArray(appIds)) {
            for (let i = 0; i < appIds.length; i++) {
                const a = (appIds[i] || "").trim().toLowerCase();
                if (a.length > 0) targets.push(a);
            }
        } else if (appIds) {
            targets.push(String(appIds).trim().toLowerCase());
        }
        if (label) {
            const l = String(label).trim().toLowerCase();
            if (l.length > 0 && !targets.includes(l)) targets.push(l);
        }
        if (targets.length === 0) return [];

        let targetFlavor = null;
        for (let i = 0; i < targets.length; i++) {
            const f = root.getDiscordFlavor(targets[i]);
            if (f === "ptb" || f === "canary" || f === "development") {
                targetFlavor = f;
                break;
            }
            if (f === "stable") targetFlavor = "stable";
        }

        for (let i = 0; i < records.length; i++) {
            const record = records[i];
            const n = record.node;
            const nodeFlavor = record.flavor;
            if (targetFlavor !== null) {
                if (nodeFlavor === targetFlavor) {
                    matched.push(n);
                }
                continue;
            } else if (nodeFlavor !== null) {
                // Skip discord streams if target is not discord
                continue;
            }

            const streamIds = record.ids;
            const isMatch = targets.some(target => {
                return streamIds.some(id => {
                    if (id === target) return true;
                    if (target.length >= 3 && (id.includes(target) || target.includes(id))) return true;
                    if (id.endsWith("." + target) || target.endsWith("." + id)) return true;
                    return false;
                });
            });

            if (isMatch) matched.push(n);
        }
        return matched;
    }

    function isSinkDefault(node) {
        return node !== null && node === Pipewire.defaultAudioSink;
    }

    function isSourceDefault(node) {
        return node !== null && node === Pipewire.defaultAudioSource;
    }

    property var pendingVolNode: null
    property real pendingVolVal: 0

    // Preserve default/EasyEffects propagation to the other devices.
    function linkedDevices(node) {
        const cls = node.properties?.["media.class"] || "";
        const source = cls.includes("Source");
        if (!source && !cls.includes("Sink")) return [];
        const name = node.properties?.["node.name"] || node.name || "";
        const effects = name.toLowerCase().includes("easyeffects")
            || (node.properties?.["node.description"] || "").toLowerCase().includes("easyeffects");
        return effects || (source ? isSourceDefault(node) : isSinkDefault(node))
            ? (source ? root.sources : root.sinks) : [];
    }

    function writeAudio(node, property, value, primary = false) {
        if (!node) return;
        if (node.audio) {
            node.audio[property] = value;
            return;
        }
        // Compatibility path for nodes without native audio support.
        const id = String(node.id || "");
        const name = node.properties?.["node.name"] || node.name || "";
        const cls = node.properties?.["media.class"] || "";
        const volume = property === "volume";
        const arg = volume ? value.toFixed(2) : (value ? "1" : "0");
        if (id) Quickshell.execDetached(["wpctl", volume ? "set-volume" : "set-mute", id, arg]);
        const kind = cls.includes("Source") ? "source" : cls.includes("Sink") ? "sink"
            : cls === "Stream/Input/Audio" ? "source-output" : cls === "Stream/Output/Audio" ? "sink-input" : "";
        if (primary && (kind === "source" ? isSourceDefault(node) : kind === "sink" && isSinkDefault(node))) {
            Quickshell.execDetached(["wpctl", volume ? "set-volume" : "set-mute",
                kind === "source" ? "@DEFAULT_AUDIO_SOURCE@" : "@DEFAULT_AUDIO_SINK@", arg]);
            Quickshell.execDetached(["pactl", "set-" + kind + "-" + (volume ? "volume" : "mute"),
                kind === "source" ? "@DEFAULT_SOURCE@" : "@DEFAULT_SINK@",
                volume ? Math.round(value * 100) + "%" : arg]);
        }
        const target = kind.endsWith("output") || kind.endsWith("input")
            ? String(node.properties?.["object.serial"] || id) : name;
        if (kind && target) Quickshell.execDetached(["pactl", "set-" + kind + "-" + (volume ? "volume" : "mute"),
            target, volume ? Math.round(value * 100) + "%" : arg]);
    }

    Timer {
        id: volumeSyncTimer
        interval: 20
        onTriggered: {
            const node = root.pendingVolNode;
            root.pendingVolNode = null;
            if (!node) return;
            const devices = root.linkedDevices(node);
            for (let i = 0; i < devices.length; ++i)
                if (devices[i].id !== node.id) root.writeAudio(devices[i], "volume", root.pendingVolVal);
            if (!node.audio) root.writeAudio(node, "volume", root.pendingVolVal, true);
        }
    }

    function setVolume(node, val) {
        if (!node) return;
        const clamped = Math.max(0.0, Math.min(1.5, Math.round(val * 100) / 100));
        if (node.audio) node.audio.volume = clamped;
        root.pendingVolNode = node;
        root.pendingVolVal = clamped;
        volumeSyncTimer.restart();
    }

    function toggleMute(node) {
        if (!node) return;
        const value = !(node.audio?.muted ?? false);
        writeAudio(node, "muted", value, true);
        const devices = linkedDevices(node);
        for (let i = 0; i < devices.length; ++i)
            if (devices[i].id !== node.id) writeAudio(devices[i], "muted", value);
    }

    function setDefaultSink(node) {
        if (!node || !node.id) return;
        Pipewire.preferredDefaultAudioSink = node;

        const idStr = String(node.id);
        const nameStr = node.properties?.["node.name"] || node.name || "";

        SystemService.enqueue(["audio-default", idStr, nameStr], "audio", "audio-output", true);

        if (typeof OsdService !== "undefined" && OsdService.show) {
            const desc = node.properties?.["node.description"] || node.properties?.["node.nick"] || node.name || "Output Device";
            OsdService.show("Audio Output", desc, "audio-volume-high", -1, false);
        }
    }

    function setDefaultSource(node) {
        if (!node || !node.id) return;
        Pipewire.preferredDefaultAudioSource = node;

        const idStr = String(node.id);
        const nameStr = node.properties?.["node.name"] || node.name || "";

        SystemService.enqueue(["audio-source-default", idStr, nameStr], "audio", "audio-input", true);

        if (typeof OsdService !== "undefined" && OsdService.show) {
            const desc = node.properties?.["node.description"] || node.properties?.["node.nick"] || node.name || "Input Device";
            OsdService.show("Microphone", desc, "audio-input-microphone", -1, false);
        }
    }

    function moveStream(streamNode, targetSinkNode) {
        if (!streamNode || !targetSinkNode) return;
        const streamId = String(streamNode.id || "");
        const targetSinkId = String(targetSinkNode.id || "");
        const targetSinkName = targetSinkNode.properties?.["node.name"] || targetSinkNode.name || "";
        const streamSerial = String(streamNode.properties?.["object.serial"] || streamNode.properties?.["object.id"] || streamId);

        Quickshell.execDetached(["pw-metadata", "-n", "default", streamId, "target.node", targetSinkId]);
        Quickshell.execDetached(["pw-metadata", "-n", "default", streamId, "target.object", targetSinkId]);
        if (targetSinkName) {
            Quickshell.execDetached(["pactl", "move-sink-input", streamSerial, targetSinkName]);
            Quickshell.execDetached(["pactl", "move-sink-input", streamId, targetSinkName]);
        }

        if (typeof OsdService !== "undefined" && OsdService.show) {
            const app = getAppDisplayName(streamNode);
            const dev = targetSinkNode.properties?.["node.description"] || targetSinkNode.properties?.["node.nick"] || targetSinkNode.name || "Output";
            OsdService.show(app, "Routed to " + dev, "audio-volume-high", -1, false);
        }
    }

    function getStreamSink(streamNode) {
        if (!streamNode) return root.defaultSink;
        const driverId = String(streamNode.properties?.["node.driver-id"] || "");
        const targetNode = String(streamNode.properties?.["target.node"] || "");
        const targetObject = String(streamNode.properties?.["node.target"] || streamNode.properties?.["target.object"] || "");

        for (let i = 0; i < root.sinks.length; i++) {
            const s = root.sinks[i];
            const sId = String(s.id);
            const sName = s.properties?.["node.name"] || s.name || "";
            if (driverId === sId || targetNode === sId) return s;
            if (targetObject !== "" && (targetObject === sName || targetObject === sId)) return s;
        }

        return root.defaultSink;
    }

    function getDeviceKind(node) {
        if (!node) return "speakers";
        const desc = (node.properties?.["node.description"] || node.properties?.["node.nick"] || node.name || "").toLowerCase();
        if (desc.includes("headphone") || desc.includes("headset") || desc.includes("hyperx") || desc.includes("cloud") || desc.includes("earphone") || desc.includes("airpods") || desc.includes("buds")) {
            return "headphones";
        }
        if (desc.includes("hdmi") || desc.includes("displayport") || desc.includes("dp-") || desc.includes("tv") || desc.includes("monitor")) {
            return "monitor";
        }
        if (desc.includes("easyeffects") || desc.includes("effects") || desc.includes("virtual")) {
            return "effects";
        }
        return "speakers";
    }

    function getAppDisplayName(node) {
        if (!node) return "Audio Stream";
        const appName = node.properties?.["application.name"] || "";
        const binary = node.properties?.["application.process.binary"] || "";
        const nodeName = node.name || "";
        const mediaName = node.properties?.["media.name"] || "";
        const combined = [appName, binary, nodeName, mediaName,
            node.properties?.["application.icon-name"], node.properties?.["application.icon_name"],
            node.properties?.["pipewire.access.portal.app_id"], node.properties?.["application.id"]]
            .join(" ").toLowerCase();

        if (combined.includes("discord") || appName.toLowerCase() === "webrtc voiceengine") {
            if (combined.includes("canary")) return "Discord Canary";
            if (combined.includes("ptb")) return "Discord PTB";
            if (combined.includes("development") || combined.includes("discord-dev") || combined.includes("discorddev")) return "Discord Development";
            return "Discord";
        }
        if (combined.includes("spotify")) return "Spotify";
        if (combined.includes("steam")) return "Steam";
        if (combined.includes("firefox")) return "Firefox";
        if (combined.includes("chrome") || combined.includes("chromium")) return "Chromium";
        if (combined.includes("helium")) return "Helium";
        if (combined.includes("vlc")) return "VLC Media Player";
        if (combined.includes("obs")) return "OBS Studio";
        if (combined.includes("mpv")) return "mpv";
        if (combined.includes("telegram")) return "Telegram";
        if (combined.includes("prism") || combined.includes("minecraft")) return "Minecraft";

        return appName || binary || mediaName || nodeName || "Audio Application";
    }

    function getAppIconPath(node) {
        if (!node) return Quickshell.iconPath("audio-volume-high", "application-x-executable");
        const appName = (node.properties?.["application.name"] || "").toLowerCase();
        const binary = (node.properties?.["application.process.binary"] || "").toLowerCase();
        const nodeName = (node.name || "").toLowerCase();
        const combined = [appName, binary, nodeName,
            node.properties?.["application.icon-name"], node.properties?.["application.icon_name"],
            node.properties?.["pipewire.access.portal.app_id"], node.properties?.["application.id"]]
            .join(" ").toLowerCase();

        if (combined.includes("discord") || appName === "webrtc voiceengine") {
            if (combined.includes("canary")) return Quickshell.iconPath("discord-canary", "applications-chat");
            if (combined.includes("ptb")) return Quickshell.iconPath("discord-ptb", "applications-chat");
            if (combined.includes("development") || combined.includes("discord-dev") || combined.includes("discorddev")) return Quickshell.iconPath("discord-development", "applications-chat");
            return Quickshell.iconPath("discord", "applications-chat");
        }
        if (combined.includes("spotify")) return Quickshell.iconPath("spotify", "audio-player");
        if (combined.includes("firefox")) return Quickshell.iconPath("firefox", "web-browser");
        if (combined.includes("steam")) return Quickshell.shellPath("assets/steam.svg");
        if (combined.includes("chrome") || combined.includes("chromium")) return Quickshell.iconPath("chromium", "web-browser");
        if (combined.includes("helium")) return Quickshell.iconPath("helium", "web-browser");
        if (combined.includes("vlc")) return Quickshell.iconPath("vlc", "multimedia-player");
        if (combined.includes("obs")) return Quickshell.iconPath("obs", "application-x-executable");
        if (combined.includes("telegram")) return Quickshell.iconPath("telegram", "applications-chat");

        const iconName = node.properties?.["application.icon-name"] || node.properties?.["application.icon_name"] || node.properties?.["pipewire.access.portal.app_id"];
        if (iconName) {
            const p = Quickshell.iconPath(iconName, "application-x-executable");
            if (p && p.toString() !== "") return p;
        }

        return Quickshell.iconPath("audio-volume-high", "application-x-executable");
    }
}
