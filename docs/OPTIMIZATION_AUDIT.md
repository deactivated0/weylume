# Weylume audit — recorded before source changes

Input: the supplied weylume.zip. This is a source audit, not a measurement of the
user's desktop. No running Labwc/Quickshell session, display, fonts, GPU, audio
graph, NetworkManager configuration, or compositor configuration was supplied.

## Priorities and constraints

Preserve visual QML, assets, stored settings, interaction timing, sorting and
protocol payloads. Do not reduce the configured metric sampling rate, remove
animations, change fonts, or turn off existing features to obtain better numbers.
Use native QML where it already provides a working API. Use a synchronous Rust
helper for remaining integration work, without an async runtime or new daemon.

QML includes JavaScript expressions as part of its language. These remain inside
QML; no independent JS runtime or JS source file is needed. The explicit Start
Menu command mode deliberately accepts shell syntax. Its user-initiated `sh -lc`
invocation must remain to preserve pipes, substitutions and redirects. Replacing
it with whitespace splitting or writing a miniature shell in Rust is not a
behavior-preserving optimization. External applications launched by the desktop
are outside the rice's implementation-language boundary.

## Main findings

| Area | Evidence and consequence | Intended treatment |
|---|---|---|
| Audio CPU/processes | AudioService writes native volume/mute, then redundantly spawns wpctl/pactl for the same nodes, defaults and every same-kind device. Up to 4 + 2(N−1) processes for one default-device volume flush. | Keep native writes and the existing cross-device fan-out; eliminate duplicate writes when a tracked native audio object is available. Preserve the 20 ms secondary-device debounce. |
| Device monitoring | Python waits on an additional resident udevadm process and runs notify-send per accepted event. | Merge libudev fd monitoring into the existing metrics/desktop process; notify through native D-Bus. Keep names, icon selection, startup grace and deduplication rules. |
| Metrics wakeups | backend.c floors a remaining deadline to milliseconds; poll(0) spins in the sub-millisecond tail before each sample. Sensor directories are globbed each sample. | Use rounded-up deadlines; cache discovered sensor paths and rediscover on hardware events. Preserve intervals and output formatting. |
| Desktop watcher | IN_DELETE_SELF/IN_MOVE_SELF invalidate a watch but the stored watch id remains nonnegative. A replaced Desktop directory can stop updating. Every event rebuilds the complete model. | Watch the parent as well, rearm on replacement and emit only changed item payloads. |
| Network | Each nmcli monitor event triggers a Python reader that runs about 6–8 nmcli queries. Full arrays are reassigned even when unchanged. Existing native Networking is also used by tray/quick controls. | Remove Python; compare returned collection state before notifying QML models. Preserve nmcli's sorting, profile names and display strings until native equivalents can be compared on the target. |
| Tray polling | TrayItemMenu uses a repeating 30 ms timer until there are children; a menu with zero children never stops it. | Observe the actual children model changes. |
| Clipboard correctness | ClipboardService requires has("wl-paste"), but capabilities never lists wl-paste. Watcher is consequently disabled. | Add the missing capability; replace per-copy Python encoder with compiled Rust. |
| Clipboard filesystem | Image capture enumerates/sorts up to 100 files; helper uses predictable temporary filename. Pinned history and image-file eviction can disagree. | Atomic unique temporary writes; preserve SHA-256 names and limits. Document pinned-image lifecycle issue separately. |
| RAM/lifetime | Flyouts mostly already use LazyLoader; unloadClosedFlyouts is true. One PipeWire tracker is already shared. DND/history can retain tracked notifications after history trimming. | Preserve existing lazy loading; review notification ownership before changing lifetime. |
| Preview overhead | Every hover captures all windows through sequential grim processes. Titles collide; C filename truncation differs from QML for Unicode/long names. | Port protocol implementation; preserve current capture behavior. Document targeted capture and filename migration as follow-up requiring live comparison. |
| Disk writes | State validation rewrites the same state-version marker every startup. | Skip an identical marker write. Keep corrupt-file backup and atomic replacements. |
| Duplicate logic | Audio source/sink mutations, default-device routing helpers, JSON atomic-write code and Python subprocess wrappers are repeated. | Consolidate only nonvisual integration logic. |
| UI structure | Large files are largely explicit visual declarations. Removing layouts/wrappers changes implicit size, focus, event propagation or animations. | Preserve visual object trees rather than inflate performance claims through whitespace removal. |
| Imports/assets | Seven SVGs have no literal reference; dynamic references require checking before deletion. C protocol glue is generated source. | Remove only proven unreferenced assets; replace generated C with Rust protocol definitions. |

## Implementation language inventory and migration

| Source | Existing language | Responsibility | Destination |
|---|---|---|---|
| 39 *.qml files | QML, embedded expressions | UI, bindings, interactions, service coordination | QML |
| system_helper.py (904 lines) | Python | Actions, nmcli parsing, Labwc XML, cache/state repair, screenshots, clipboard | Rust modules |
| desktop_helper.py (171 lines) | Python | Rename, move, trash, create, wallpaper | Rust filesystem/GIO integration |
| device_monitor.py (165 lines) | Python | udev event parsing and notifications | Rust in existing backend event loop |
| scripts/clipboard_capture.py (57 lines) | Python | Bounded text/image input and SHA-256 image cache | Rust one-shot subcommand |
| native/backend.c (560 lines) | C | /proc, /sys, statvfs, inotify, JSON metrics | Rust backend |
| native/preview_helper.c (179 lines) | C | Wayland toplevel discovery and grim captures | Rust preview module |
| native/generated/*.c, *.h (528 lines) | Generated C | Wayland protocol bindings | Rust interface definitions |
| native/Makefile | Make with shell recipes | Build | Cargo manifest and documented Cargo commands |
| JSON/SVG/qmldir/Markdown | Data, assets, metadata/documentation | Not executable implementation | Preserve needed files |
| Two prebuilt ELF helpers | Compiled C | Architecture-specific executables | One release Rust executable |

## Incomplete features and architecture limits

- No Labwc rc.xml/environment/autostart is included; injected key chords and
  actual workspace, lock, fullscreen and compositor support cannot be verified.
- Window screenshot mode is region selection with a second attempt after cancel.
- Workspace settings allow 16 workspaces but generated shortcuts/actions cover 9.
- GPU model, mount paths and fallback hardware labels are machine-specific.
- Calendar has demonstration data and no calendar sync or reminder scheduler.
- loginctl lock-session is a request; success does not prove a Wayland locker exists.
- Network credentials are passed to nmcli arguments; a native secrets agent would
  avoid that exposure but requires integration testing and cancellation design.
- Recorder duration counts paused time; pause state is optimistic.
- Audio deliberately propagates default/EasyEffects changes to other devices.
  This surprising behavior is part of the supplied implementation and must stay.
- Several integration commands (grim, slurp, gpu-screen-recorder, wtype, gio,
  nmcli, pactl, wpctl) do substantial protocol/policy work. Reimplementing all of
  them without a target session is a reliability risk, not a proven optimization.

## Validation plan

Compile/test Rust; compare original/new helper protocols on isolated fixtures;
compare all untouched visual sources/assets and all stored JSON byte-for-byte;
audit every diff; use a QML parser if available. Report static declaration counts
separately from instantiated objects/bindings and measure helper costs separately
from shell costs. Pixel screenshots, interaction equivalence, desktop idle
CPU/RAM/GPU, wakeups and startup latency require the original target session.
