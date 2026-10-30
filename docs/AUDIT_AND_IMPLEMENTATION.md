# Weylume optimization and implementation report

> Earlier optimization snapshot. See `BUGFIX_REPORT.md` for follow-up fixes and current verification. Counts and unresolved items below describe the earlier revision.

The delivered configuration replaces all four Python helpers and both C helpers
with one release Rust executable, removes redundant native-audio command spawning,
and merges device and network monitoring into the existing backend. The visual
QML, assets, saved settings and interaction timings were retained.

This is a completed source refactor with isolated regression validation, **not a
certification of pixel-for-pixel or live-session equivalence**. The supplied archive
contains no runnable Labwc session, compositor configuration, target fonts, audio
graph or reference screenshots. This environment also rejects socket creation.
Consequently, native Wayland/D-Bus integration and final desktop resource use
must still be checked on the target machine. Do not interpret passing fixture
tests as evidence that every hardware path has been exercised.

## Audit and scope

`OPTIMIZATION_AUDIT.md` records the findings before implementation.
`FILE_REVIEW.md` covers every supplied QML file, helper, timer class and dependency
group. `PERFECTION_REVIEW.md` is the separate final roadmap.

All 39 QML files, four Python files, C helpers and generated protocol definitions,
Makefile, JSON state, assets, helper commands, service coordination and existing
documentation were examined. The archive does not contain Labwc rc.xml,
environment/autostart, user service units or external application configurations;
those could not be audited. No enabled feature, visual wrapper, font, animation,
geometry value or SVG was removed merely to reduce counts.

## Implemented changes

| Area | Change and actual benefit | Preservation / remaining limit |
|---|---|---|
| Audio | Consolidated source/sink mutations. Native tracked PipeWire audio writes no longer also spawn wpctl/pactl for the same operation. | Same clamp, rounding, immediate primary write, 20 ms secondary update, default/EasyEffects propagation and OSD. CLI fallback remains for nodes without audio support. Real PipeWire behavior still needs testing. |
| Device monitoring | Removed Python + udevadm; libudev is serviced in the backend's poll loop. Native notification calls replace notify-send. | Original 3.5 s startup grace, 2 s deduplication, labels and icons. No extra daemon/thread. |
| Network events | Removed resident nmcli monitor and its QML restart timer; system D-Bus signals enter the existing backend stream. Ignore AP telemetry; retain 220 ms snapshot debounce. | Full snapshot still uses nmcli to retain its profile names, escaping, ordering and display contract. Native live signal coverage remains an acceptance test. |
| Network models | Do not reassign equal collection payloads. | JSON equality costs a serialization per refreshed collection; worthwhile for suppressing delegate/model updates, but not a measured desktop speedup. Scalar updates retain their existing path. |
| Backend sampling | Round poll deadlines upward instead of spinning at the sub-millisecond boundary. Cache sensor discovery. | Same configured 1 s active / 10 s idle defaults, metric strings and thresholds. Sampling remains necessary for counters without useful change events. |
| Desktop events | Rearm inotify when Desktop is replaced; watch parent; suppress identical desktop payloads. | Same listing/filtering/order/icon data. Event tests cover replacement and subsequent changes. |
| Tray menus | Observe QsMenuOpener children directly; remove 30 ms polling, obsolete children handler and unused anchor/import. | Rendered menu subtree and popup geometry unchanged. Empty menus no longer poll indefinitely. Test delayed/empty/dynamic menus on the actual Quickshell version. |
| Notification lifetime | Release tracked notifications once neither toast nor retained history owns them; release evicted entries. | Keep live history actions and current toast references. No rendered changes. Native object destruction/signals need live validation. |
| Clipboard | Add the missing wl-paste capability, replace the per-copy interpreter with bounded Rust capture, honor sensitive/nil/clear states. | Existing feature now starts when enabled and installed; this is a deliberate correctness fix to previously broken behavior. Hashes, ordinary payloads and limits retained. |
| Filesystem | GIO FFI for trash and cross-filesystem move, native rename/create/permissions, private atomic temporary writes, no identical state-version rewrite. | Keep existing path conventions, backups, JSON schema and action messages. No gio command process for these operations. |
| Gamma | Direct sd-bus property reads/writes replace busctl fast-path commands. | Short-lived Rust process remains; original relay startup and backlight fallback policy retained. No new resident gamma service. |
| Previews | Replace C/generated protocol code with Rust Wayland definitions. | Same toplevel discovery/capture order, grim arguments, JPEG quality and legacy filename policy. Existing long/Unicode-name issue remains in roadmap. |
| Child execution | One synchronous bounded runner, poll-based I/O and pidfd waiting, no async runtime. Timeout cleanup kills the child process group and reaps the child. | Intentional application launches and clipboard owners remain independent. This is not a proof that every external application cleans up its own descendants. |
| Packaging | One stripped release binary, Cargo.lock, build instructions, dependency/protocol notices, isolated Rust tests. | Binary is larger than the two old C binaries; it also replaces the Python helpers. |

No animation was changed. No always-running timer was added. Existing lazy
flyouts and the shared PipeWire object tracker were retained. No measured basis
justified rewriting the large visual components or replacing native Quickshell
Bluetooth, MPRIS, tray, desktop-entry and window models with Rust.

## Language boundary

The rice's implementation now contains only QML and Rust. There are zero Python,
standalone JavaScript/TypeScript, shell, Lua, Perl, Ruby, C or header source files.
QML's embedded JavaScript expressions are part of QML and remain necessary.

Two user features intentionally keep access to external interpreters: Start Menu
command mode invokes `sh -lc` for shell syntax, and Desktop “Run in Terminal” can
run a user-selected .py or .sh file with Python or sh. Removing those would change
explicit interaction behavior. They are not implementation helpers or mandatory
rice dependencies; no such script is delivered. This exception was explained
before changing the helpers. Installation command examples in Markdown and Cargo
metadata are not shipped script implementations.

## Before / after: static counts

Counts exclude docs, dependency licenses, build products and the separate Rust
integration-test file. Embedded Rust unit tests are included in production-file
line counts. Lines count physical newlines, so Rust formatting and explicit
native error/FFI handling affect the comparison. Declaration counts are lexical
approximations, not instantiated runtime objects or continuously active bindings.

| Metric | Original | Refactored | Difference |
|---|---:|---:|---:|
| QML files | 39 | 39 | 0 |
| QML lines | 14,006 | 13,838 | −168 |
| Rust production files / lines | 0 / 0 | 11 / 3,044 | +11 / +3,044 |
| Other implementation source files | 8 | 0 | −8 |
| Other implementation lines | 2,564 | 0 | −2,564 |
| Total implementation lines | 16,570 | 16,882 | +312 (+1.9%) |
| Total implementation bytes | 734,839 | 727,484 | −7,355 (−1.0%) |
| QML object-like declarations | 1,490 | 1,484 | −6 |
| QML Timer declarations | 22 | 20 | −2 |
| QML Process declarations | 17 | 15 | −2 |
| QML execDetached call sites | 80 | 56 | −24 |
| QML import statements | 163 | 161 | −2 |
| QML property declarations | 433 | 432 | −1 |
| QML property initializers/bindings (static approximation) | 418 | 417 | −1 |
| Shipped native executables | 2 | 1 | −1 |
| Shipped executable bytes | 56,840 | 974,400 | +917,560 |
| Direct Cargo dependencies | 0 | 5 | +5 |
| Other implementation runtimes required by rice helpers | Python 3 | None | Interpreter eliminated |

The codebase is not dramatically shorter. Rust replaces more implicit Python and
generated/native functionality, adding explicit error handling, bounds and FFI.
The meaningful savings here are duplicate work and interpreter/process removal,
not a misleading line-count reduction. The binary-size increase is real; neither
it nor total source size is a measurement of resident memory.

The five direct crates are libc, serde_json, xmltree, sha2 and base64. Cargo.lock
contains 24 dependency packages, including optional/target/build entries; this is
not 24 resident components. Linux shared libraries remain dynamically linked.
There is no Tokio, Node, Python package dependency or new service unit.

## Before / after: runtime evidence

Warm local one-shot tests used 15 runs per case. They exercise real helper
startup and small local operations, without a desktop session.

| Operation | Original median | Rust median | Scope |
|---|---:|---:|---|
| Capability snapshot | 41.910 ms | 3.031 ms | About 13.8× faster in this container |
| Text clipboard capture | 23.132 ms | 2.296 ms | About 10.1× faster in this container |

A 30-second backend run at a 1,000 ms interval measured 0.01184 CPU-seconds for the
original C metrics backend and 0.01627 CPU-seconds for the combined Rust backend
(0.0395% and 0.0542% of one CPU, including startup). Voluntary context switches
were 33 and 32. These tiny single-run totals do **not** establish a CPU reduction.
The Rust process performs additional monitoring work, and the removed monitor
processes could not be measured as a working desktop tree. Context switches are
not hardware wakeups. The reported 12,544 KiB peak RSS for both runs is a rusage
high-water measurement, affected by the launch environment, and cannot be used
as idle RSS or evidence of RAM savings.

In simulated tracked-native-audio graphs, a volume-plus-mute operation previously
issued 4–16 external command calls, depending on the graph and selection; it now
issues zero. These are evaluated call counts, not a PipeWire latency benchmark.
Fallback nodes and default-device/stream-routing actions still use external tools.

Source-level monitor topology changes from C backend + Python device monitor +
udevadm + nmcli monitor (four) to one native backend. Restoring the previously
broken clipboard capability also starts its enabled wl-paste watcher (one), so a
typical enabled configuration goes from four to two in these categories. This is
an inferred configuration topology, not a live process count. Quickshell, gamma
relay, compositor, audio/network daemons, application processes and transient
helpers are outside that subtotal.

**Not measured:** total shell startup, idle RSS/PSS, whole-tree idle CPU, GPU use,
hardware wakeups, actual active objects/bindings, total IPC count, real spawned
process rates or multi-monitor scaling. No percentage reduction is claimed for
these. Removing calls and merging monitors reduces the relevant work by
construction, but measuring its total desktop benefit needs the target session.

## Verification performed

| Check | Result | What it establishes |
|---|---|---|
| Release build with locked dependencies | Passed | Supplied x86-64 GNU/Linux executable compiles and links. |
| cargo fmt / Clippy all targets, warnings denied | Passed | Formatting and compiler/lint checks, including tests. |
| Rust tests | 4 unit + 6 integration passed | Parsing, filename contracts, bounds/privacy, XML preservation/backup, state repair, non-overwriting rename and EOF shutdown. |
| Original Python versus Rust fixtures | 83 checks passed | JSON/exit results and mocked command argument/order compatibility across network/actions/XML/clipboard/state repair. |
| Extracted QML logic contracts | 17 checks passed | 16 audio graph cases and notification ownership behavior; not actual Qt/PipeWire objects. |
| Original C versus Rust backend tests | 6 checks passed | Desktop data, stable metrics fields, creation events, replaced-directory recovery and process shutdown. |
| QML syntax | All 39 passed | Qt 6.4.2 qmllint parser; semantic/import checks disabled because Quickshell modules are unavailable. Not API/type certification. |
| UI source preservation | Passed | 25 QML files byte-identical; five others contain only helper command substitutions. Tray/notification rendered subtrees unchanged; shell only loses device Process. Remaining changes are service logic. |
| Assets and stored state | Passed | All 31 SVG and 11 JSON files byte-identical. |
| Live D-Bus fixture | Blocked | dbus-daemon socket creation was rejected by the environment; no live D-Bus test success claimed. |
| Screenshots / animation / input / GPU | Unavailable | Requires actual compositor, fonts, output scale and session. |

The comparison tooling ran outside the delivered project. Its results are in
`docs/verification/`; no Python/Node test scripts are shipped. Rust regression
tests are included and can be run with Cargo. Source identity is strong evidence
against accidental visual edits, but service timing, native lifetime handling
and protocol integration can still affect visible behavior.

## Live-session acceptance and measurement

1. Keep the original archive as a rollback. Build on the target if its CPU/libc
   differs. Update external Labwc/autostart references listed in README.
2. Use the same fonts, theme, wallpaper, JSON state, output order/scales, refresh
   rates and applications for original and refactored sessions. Restore identical
   state between runs; disable neither features nor effects for the comparison.
3. Capture closed desktop, every flyout/menu, hover, pressed state, notification,
   dialog, tooltip, resize/DPI condition and animation at matched frame times.
   Compare unscaled screenshots; mask only truly volatile content such as clock
   or live CPU readings. Test focus, Esc, click-away, keyboard navigation and
   drag/drop separately. A matching resting screenshot does not prove behavior.
4. Test tracked devices/streams with EasyEffects, default changes and device
   removal; verify mute and volume values including channels. Test Wi-Fi/VPN,
   adapter removal/reappearance, NM restart, Bluetooth pairing, gamma/backlight,
   clipboard copy/clear/pin, notification replacement/actions/history/DND,
   screenshots/cancel, recorder pause/stop, Polkit and all Labwc actions.
5. Measure at least several matched idle runs after warmup. Record Quickshell and
   all descendant/associated helper RSS/PSS, CPU deltas, process count and startup
   time. Use existing system tools such as /proc, pidstat or powertop when present;
   do not leave a profiler installed as an always-running rice dependency.
   Measure monitor-closed and monitor-open states separately (10 s versus 1 s).
6. Test compositor reload, suspend/resume, locked session, monitor unplug while a
   popup is open, corrupt/missing state, unavailable services and failed commands.
   Record failures before adopting the configuration as a verified replacement.

The final review found no justification for deleting enabled UI features or
changing rendering under this task's identity constraint. Known incomplete
features and unverified paths are explicitly separated in the roadmap; the
refactor should not be described as a fully certified or maximally optimized
finished desktop until the above checks are complete.

## Official API references consulted

- Quickshell PwNodeAudio: https://quickshell.org/docs/v0.3.0/types/Quickshell.Services.Pipewire/PwNodeAudio/
- Quickshell QsMenuOpener: https://quickshell.org/docs/v0.3.0/types/Quickshell/QsMenuOpener/
- Quickshell Notification: https://quickshell.org/docs/v0.3.0/types/Quickshell.Services.Notifications/Notification/
- Quickshell Retainable: https://quickshell.org/docs/v0.3.0/types/Quickshell/Retainable/
- systemd sd-bus: https://www.freedesktop.org/software/systemd/man/sd-bus.html
