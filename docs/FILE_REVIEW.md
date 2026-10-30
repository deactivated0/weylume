# Weylume file, timer and dependency review

> Earlier optimization snapshot. See `BUGFIX_REPORT.md` for follow-up fixes and current verification. Counts and unresolved items below describe the earlier revision.

Disposition is based on the supplied archive and final source diff. “Unchanged”
means byte-identical to the uploaded file, not a claim that the component has no
possible improvements. The current design takes precedence over speculative
object/layout removal. Native modules are described in `native/README.md`.

## All QML files

| File | Responsibility | Final disposition / review finding |
|---|---|---|
| AudioMixer.qml | Devices, streams and mixer UI | Unchanged; shared native audio service/tracker retained. Large explicit visual tree is behavior-sensitive. |
| AudioService.qml | Audio models, mutations, matching | Consolidated node filters and mutations; remove redundant command writes when native audio exists; keep routing fallbacks. |
| CalendarService.qml | Local calendar/tasks data | Unchanged; no real calendar synchronization/reminder scheduler. |
| ClipboardPanel.qml | Clipboard UI | Unchanged; clipboard history now receives events from repaired service capability. |
| ClipboardService.qml | History, persistence, watcher | Compiled capture command replaces Python; wl-paste watcher remains setting/capability gated. Pin/cache ownership and crash backoff need follow-up. |
| Desktop.qml | Wallpaper/icon grid, drag/file actions | Helper substitutions only. File listing/event handling optimized in Rust. |
| DesktopContextMenu.qml | File/app context actions | Helper substitutions only; preserve explicit external-script Run in Terminal behavior. |
| MetricBar.qml | Shared metric visualization | Unchanged; small useful visual abstraction. |
| NewItemDialog.qml | New file/folder UI | Helper substitution only; preserve 60 ms focus/name delay. |
| NightLightService.qml | Temperature schedule/persistence | Native gamma command; retain minute schedule and save debounce. |
| NotificationCenter.qml | Calendar/tasks/history UI | Unchanged; dynamic icon names explain apparently unreferenced assets. |
| NotificationService.qml | Notification retention, persistence and toast | Release objects no longer owned by toast/history; rendered subtree unchanged. Native lifecycle remains a live test. |
| Osd.qml | OSD rendering per output | Unchanged; audit output hotplug/fallback in roadmap. |
| OsdService.qml | OSD state and expiry | Unchanged; one-shot 1900 ms timer is interaction behavior. |
| PinnedApps.qml | Taskbar pin state, launching/matching | Unchanged; overlaps favorites but different schemas/defaults/behavior make a shared wrapper questionable. |
| PolkitDialog.qml | Authentication prompt | Unchanged; native Quickshell integration preferred over new Rust agent. Requires real permission/cancel testing. |
| QuickSettings.qml | Network/Bluetooth/media/audio/system controls | Unchanged; native services retained; media progress updates only while visible/playing. |
| RecorderService.qml | Recorder process/pause/time | Helper substitution only; pause accounting and failure acknowledgment are separate correctness roadmap items. |
| SessionDialog.qml | Session actions and countdown | Unchanged; countdown runs only when requested. Real lock/inhibitor support not proven by command availability. |
| SettingsButton.qml | Shared settings action control | Unchanged; preserves padding, focus and implicit size. |
| SettingsCenter.qml | Settings pages and application launchers | Unchanged; schema/compositor support and optional machine-specific launchers documented. |
| SettingsField.qml | Shared editable settings field | Unchanged; meaningful reuse without a new runtime framework. |
| SettingsService.qml | Saved configuration/defaults | Unchanged; 180 ms write debounce, default flyout unloading and metric intervals retained. |
| SettingsToggle.qml | Shared settings switch | Unchanged; no styling/animation changes. |
| ShellState.qml | Flyout ownership, brightness/system interactions | Native gamma read/write helper substitutions; state/geometry preserved. |
| StartFavorites.qml | Start Menu favorites | Unchanged; distinct defaults/persistence from taskbar pins retained. |
| StartMenu.qml | Launcher/search/navigation/session menu | Unchanged; explicit shell command mode and configured launch targets retained. |
| SystemData.qml | Backend process/JSON/state | Native backend command and network-event dispatch; existing crash recovery preserved. |
| SystemMonitor.qml | Metrics sidebar | Unchanged; created only when sidebar visible. Sensor discovery/sampling optimized underneath. |
| SystemService.qml | Action queue, capabilities and data snapshots | Rust helper commands, network event connection/debounce, collection equality guards; nmcli monitor/restart timer removed. |
| Taskbar.qml | Per-output taskbar/grouping/actions | Unchanged; native stream mute already avoids redundant fallback; hover and action queue timings retained. |
| TaskContextMenu.qml | Window/application actions | Unchanged; direct native window methods retained where available; wtype-specific actions require external Labwc bindings. |
| TaskPreview.qml | Hover preview popup | Native command substitution only; cache filename/capture scalability problems kept visible in roadmap. |
| Theme.qml | Visual constants | Unchanged. |
| TrayConfig.qml | System/app tray model and persistence | Unchanged; native networking/Bluetooth/PipeWire/tray service models are appropriate QML. |
| TrayItemMenu.qml | Tray popup/native menu | Replace 30 ms polling with children binding; remove unused anchor/import/handler; rendered subtree unchanged. |
| TrayOverflow.qml | Overflow tray popup | Unchanged; visibility/lazy ownership remains existing policy. |
| WinButton.qml | Taskbar application button | Unchanged; preserve icons, animations, hover and audio indicator. |
| shell.qml | Root windows/singletons/IPC | Remove separate device-monitor Process only; per-output root and notification server unchanged. |

## Non-QML source migration

| Removed source/build artifact | Destination / reason |
|---|---|
| system_helper.py | Rust system/network/labwc/clipboard/bus/util modules; same action-oriented JSON interface. |
| desktop_helper.py | Rust desktop module; native filesystem and GIO operations. |
| device_monitor.py | Rust devices module integrated into backend, no separate process. |
| scripts/clipboard_capture.py | Rust clipboard-capture subcommand invoked only on clipboard changes. |
| native/backend.c | Rust backend; same metrics/desktop protocol with watcher/deadline fixes. |
| native/preview_helper.c | Rust preview module; same native protocol/capture behavior. |
| native/generated protocol C/header | Rust static protocol definitions; original license retained. |
| native/Makefile | Cargo.toml/Cargo.lock and documented build commands. |
| weylume_backend / weylume_previews | One release weylume-native executable. |

No separate scripting implementation remains. Rust tests in
`native/tests/contracts.rs` are development-only. Cargo build directories,
original helpers and analysis tools are excluded from the final archive.

## Timers and event sources

| Owner | Timer / event | Decision |
|---|---|---|
| AudioService | 20 ms volume synchronization | Keep one-shot debounce and cross-device propagation timing. |
| ClipboardService | 2 s initial restart delay; 300 ms save | Keep failure retry and coalesced writes; neither runs continuously in healthy idle. |
| SystemData | 3 s initial backend restart delay | Keep recovery; failure-only timer. |
| SystemService | 220 ms network debounce | Keep; coalesces native events. Removed separate monitor restart timer. |
| TrayItemMenu | Former repeating 30 ms menu read | Removed; native children binding observes data. |
| NotificationService | 300 ms save; configured toast expiry | Keep both one-shot timers; history ownership now bounded by retention. |
| StartMenu | 500 ms submenu close; 30 ms focus | Keep interaction timing. |
| SessionDialog | 1 s countdown | Keep; explicitly started for a requested countdown and stopped on close. |
| RecorderService | 1 s elapsed display | Keep while recording; paused-time semantics need separate fix. |
| NightLightService | 200 ms config save | Keep one-shot; schedule uses shared minute clock rather than its own perpetual timer. |
| NewItemDialog | 60 ms name/focus delay | Keep existing behavior. |
| OsdService | 1900 ms expiry | Keep one-shot. |
| QuickSettings | 500 ms media position; 10 s Bluetooth scan end | Media tick gated by open/playing; scan timer is a deadline, not repeated scanning. |
| TaskPreview | 350 ms hide | Keep one-shot hover behavior. |
| Taskbar | 220 ms preview; 50 ms queued Labwc action | Preserve hover delay; action timer stops when queue empties. |
| SettingsService | 180 ms save | Keep coalesced writes. |
| Native backend | 1 s active / 10 s idle defaults | Keep requested metric cadence; fd poll also receives stdin, inotify, udev and NM events. |
| Shared SystemClock | Minute-resolution clock/schedule | Keep; necessary date/clock/schedule updates. |

There are 20 remaining QML Timer declarations. Repeating does not mean always
active. No timer is removed merely because it exists; many preserve visible
interaction timing or avoid repeated disk writes. No animation timing was edited.

## Dependencies and commands

| Group | Retained / removed | Why / native replacement potential |
|---|---|---|
| UI stack | QtQuick, Controls, Layouts, Effects; Quickshell core/Io/Wayland/PipeWire/Notifications/Polkit/SystemTray/Bluetooth/Networking/MPRIS and local qs types | Existing rendering/native service APIs retained. Unused tray Effects import removed. Other imports are conservatively retained without semantic module validation. |
| Compositor/session | Labwc, Wayland, logind/systemd; actual configuration absent | Required integration context. No new service unit added. |
| Rust direct crates | libc, serde_json, xmltree, sha2, base64 | Focused Linux ABI, JSON, namespace-aware XML, unchanged image hash and copy protocol. Five direct crates; no async/runtime framework. |
| Native shared libraries | libsystemd.so.0, libudev.so.1, libgio-2.0.so.0, libglib-2.0.so.0, libwayland-client.so.0 and their transitive/system runtime libraries | Direct APIs avoid CLI wrappers. Single executable links these for every subcommand; document portability and measure mapped/shared memory correctly. |
| Removed helper runtimes | Python 3; own C source/build pipeline | All helper implementations migrated. Python remains optional only for explicitly opening external user scripts. |
| Removed monitoring/operation commands | udevadm monitor, nmcli monitor, device notify-send, gio file operations, gamma busctl fast path | Direct udev/system D-Bus/GIO/gamma APIs; busctl remains for other fallback actions. |
| Network actions/snapshots | nmcli | Retained for exact profile/escaping/sorting/policy behavior; next candidate for QML/native completion after real parity tests. |
| Bluetooth fallback | bluetoothctl | Native QML handles existing exposed operations; helper fallbacks remain for current action interface. |
| Audio fallback and routing | wpctl, pactl, pw-cli, pw-metadata | Ordinary tracked native volume/mute avoids tools. Default-stream migration/fallback semantics still need these. |
| Media fallback | playerctl, busctl | Existing native MPRIS path stays preferred; fallback seek/control remains. |
| Brightness/night light | wl-gammarelay-rs, brightnessctl | Gamma protocol/service and backlight fallback retained. Native sd-bus removes property CLI calls, not the relay service itself. |
| Capture/clipboard | grim, slurp, swappy, wl-copy, wl-paste, gpu-screen-recorder | Native capture/selection/ownership work is substantial; preserve current screenshot/recording output. wl-paste is event-driven, not periodic polling. |
| Session/system controls | systemctl, systemd-inhibit, loginctl, powerprofilesctl, checkupdates, wtype, labwc | User-initiated actions/queries retained; some can move to existing Rust D-Bus. Labwc-specific injected chords need user's external bindings. |
| Open/play/launch | xdg-open, kitty, canberra-gtk-play and configured desktop-entry executables | User-requested applications/sounds are not idle helper daemons. Shell command mode explicitly uses sh. |

The capability inventory additionally lists these optional launch/control targets:
`gpu-screen-recorder-gtk`, `pcmanfm-qt`, `featherpad`, `pavucontrol`, `easyeffects`,
`missioncenter`, `btop`, `qdirstat`, `btrfs-assistant`, `cachyos-kernel-manager`,
`cachyos-packageinstaller`, `cachy-update`, `lact`, `goverlay`, `piper`, `scx-manager`,
`amdgpu_top`, `fwupdmgr`, `ufw`, `waydroid-helper`, `wlr-randr`, `riseup-vpn`,
`waydroid`, `haruna`, `spotify-launcher`, `discord-development`, `discord-canary`,
`discord-ptb`, `nmtui`, `heroic`, `bitwarden`, and `steam`. Defaults also name
`helium`, `qs` and user-configured commands. Testing whether an executable exists
does not make it a required package or start it. Arbitrary desktop entries and
user-entered commands make an exhaustive installed-application dependency count
impossible from this archive alone.

## Assets, state and structure

All 31 SVG assets remain byte-identical. Seven icons without literal `assets/X`
references are reached through NotificationCenter's event-type mapping and
navigation model: book, flask, users, check, flag, calendar and bell. They are not
unused. Hidden Image items used as MultiEffect sources are not dead UI: deleting
them would change rendered icons.

All 11 supplied JSON state files and qmldir remain intact. Persistent notification
and clipboard data was not discarded to improve size counts. Existing docs that
made obsolete or unverified completion claims were replaced with measured results
and an explicit roadmap. Dependency and protocol copyright notices are included.

Repeated visual declarations were reviewed but not collapsed into generic
wrappers. Layout nesting can affect implicit sizes, focus, clipping, event
propagation and animation; there is no target measurement proving those changes
would save resources while remaining identical. The shared Settings controls,
MetricBar, WinButton and existing LazyLoaders are useful, small abstractions.

Potential lifetime risks after the fixes are retained QObject references during
service replacement, cache/history ownership disagreement, async action queues
and popup ownership after output removal. No live leak detector or long-running
session was available, so the report does not claim the absence of memory leaks.
These are covered by the final acceptance checklist and separate roadmap.
