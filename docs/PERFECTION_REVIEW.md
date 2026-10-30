# Weylume final perfection review and roadmap

> Earlier optimization snapshot. See `CURRENT_ROADMAP.md` for current recommendations
> and `FURTHER_OPTIMIZATION_REPORT.md` for the latest verification. Counts and
> unresolved items below describe the earlier revision; several are now fixed.

The optimized current design is kept intact. These are **recommendations, not
implemented additions**. They follow a final review of the supplied configuration
and the refactor. Confirmed source defects are distinguished from missing
integration evidence and proposed features. A source refactor cannot establish
that unseen Labwc/session configuration already provides a locker, bindings,
portals or agents.

CPU/RAM effects below are **qualitative estimates, not measurements**. “Neutral”
means no intended steady-state increase; “small/event” means bounded work only on
an event; “lower” means removing an identified class of work, not a quantified
whole-desktop improvement. Difficulty: low, medium, high. “No dependency” means
no additional package beyond the refactored configuration's existing stack.
UI changes include behavior and transient dialogs, not just permanent geometry.
No recommendation requires an additional always-running daemon by default.

## 1. Must Fix

| Recommendation / status | What it improves and why | CPU impact | RAM impact | Difficulty | Implementation | Added dependency | UI change |
|---|---|---|---|---|---|---|---|
| Complete live acceptance before declaring equivalence — validation gap | Run the report's visual/input checklist, including PipeWire writes, tray children/lifetime, native Wayland previews, gamma and network D-Bus signals. These paths could not execute here. | Test-only | Test-only | Medium–high | QML + Rust tests as needed | Test tools only | None intended; reveals regressions |
| Verify a real session locker — missing evidence | loginctl lock-session only requests a lock. Confirm the session starts an ext-session-lock client and that lock-before-suspend survives shell/locker failures. Do not treat successful command exit as proof of protection. | Small/event | Existing locker, or additional locker memory while used | Medium–high | Session integration; audited QML lock UI only if replacing an existing locker | Existing locker, or one if absent; PAM integration if custom | Only lock/error path |
| Align workspace limits and bindings — confirmed mismatch | Settings accept 16 workspaces while generated/action shortcuts cover 9. Choose a complete 16-workspace action contract with the actual Labwc config; do not silently clamp the visible setting. | Neutral | Neutral | Medium | Rust XML/actions + QML state | No | Behavior for workspaces 10–16 |
| Reconcile pinned image history and cache eviction — confirmed mismatch | Capture's independent 100-file eviction can delete an image still pinned in QML history. Define one retention owner and serialize capture/delete/clear generations. Preserve pinned payloads and prevent stale queued deletes removing a fresh copy. | Small/event; fewer repeated scans possible | Small metadata; disk retention grows unless bounded | Medium | Rust cache + QML history | No | Broken-image cases and quota policy |
| Replace preview title filenames with a shared identity — confirmed mismatch | C-compatible 191-byte sanitization and QML's lookup differ for Unicode/long titles; duplicate titles collide. Use a compositor identifier and a manifest consumed by QML, migrating cached names. | Neutral to lower retries | Tiny manifest | Medium–high | Rust + QML | No | Correct thumbnails in affected cases |
| Check all external Labwc references — missing files | rc.xml/autostart/environment are outside the archive. Replace old helper invocations using README's mapping and verify exact action/schema support on the installed Labwc. | Neutral; prevents duplicate monitors | Lower if duplicate autostarts removed | Low–medium | Configuration plus existing Rust actions | No | None intended |

These items were not silently changed into new UX during this refactor. The
clipboard capability, watcher recovery and native ownership defects that could
be addressed without a new visual/action contract were fixed; the issues above
need target integration or an explicit behavior/cache migration.

## 2. Strongly Recommended

| Recommendation / status | What it improves and why | CPU impact | RAM impact | Difficulty | Implementation | Added dependency | UI change |
|---|---|---|---|---|---|---|---|
| Make hardware identity and mounts portable | Replace hardcoded GPU label and mount targets with discovered defaults plus overrides. Stops misleading metrics on other GPUs/disks without changing this machine's labels. | Small on discovery; neutral sampling | Tiny cache | Medium | Rust; QML only for optional configuration | No | Labels on different hardware |
| Confirm popup ownership when flyouts are retained | Exercise unloadClosedFlyouts=false across outputs. Gate activation and focus by the owning screen; avoid duplicate hidden work and popups attached to removed screens. | Lower off-screen work | Lower duplicate instances | Medium | Pure QML | No | Only faulty multi-monitor cases |
| Make power/gaming actions transactional | Record prior service/profile state, report partial failure and restore it after disabling gaming or a failed action. Protects desktop audio, capture and power behavior after errors. | Small/event | Tiny state | Medium | Rust + existing QML status | No | Failure/restore behavior |
| Coordinate startup state loading | Native state validation can overlap singleton FileView reads. Gate the initial read or trigger reload after repair so missing/corrupt files do not leave a singleton unloaded for the session. | Small startup work; less duplicate I/O | Neutral | Medium | Primarily QML, existing Rust repair | No | Correct startup after missing/corrupt state |
| Native Wi-Fi secrets handling | Move passwords out of nmcli argv and provide cancellation/enterprise-auth handling through a NetworkManager secrets agent. QML owns prompts; native integration owns the protocol. | Small/event | Small agent state in existing process | High | QML + Rust where Quickshell API lacks coverage | No additional service beyond NetworkManager; verify QML capabilities first | Authentication/error flows |
| Make notification replacement/closure explicit | Test replaces-id, application withdrawal, action-triggered close, reload and history eviction together. Reconcile retained objects with NotificationServer lifecycle without disabling history actions. | Small/event; prevents excess work | Lower if retained references accumulate | Medium | Pure QML | No | Only incorrect stale entries/actions |

## 3. Useful Features to Add

| Recommendation | What it improves and why | CPU impact | RAM impact | Difficulty | Implementation | Added dependency | UI change |
|---|---|---|---|---|---|---|---|
| Complete Bluetooth pairing/authorization prompts | Support PIN, passkey confirmation, trust and cancellation, including several adapters. Connecting a known device is not a complete pairing workflow. | Small/event | Small temporary dialogs | Medium–high | Native Quickshell Bluetooth where supported; Rust only for missing agent methods | BlueZ already needed; no new service intended | Pairing dialogs and adapter selection |
| Battery and peripheral power detail | Battery percentage/health/time and headset battery make the desktop usable on laptops and wireless peripherals. Keep updates event-driven. | Small/event | Small service model | Low–medium | QML Quickshell.Services.UPower | UPower if absent | Optional battery detail |
| Proper window screenshot selection | Current “window” mode falls back to region selection and retries cancellation. Introduce an actual selected-window capture and a single clear cancel path. | On-demand; potentially lower | One image buffer | High | QML selection + Rust/native capture where needed | No if target capture protocol works; otherwise retain grim | Selection/cancellation behavior |
| Audio ports/profiles and safe routing presets | Expose HDMI/headset/analog profiles and named routes so pavucontrol is not required for common tasks. Preserve existing mute/volume semantics. | Small/event | Small lazy model | Medium–high | QML if exposed; Rust for missing PipeWire/WirePlumber APIs | Existing audio stack; no new daemon | Mixer detail/preset controls |
| Calendar import and scheduled reminders | Replace demonstration-only usefulness with local ICS import first, then optional sync. Schedule the next reminder deadline rather than poll. | Negligible idle; parsing on change | Depends on bounded calendar size | Medium; sync high | Rust parsing/filesystem + QML | None for small local import; sync may justify one parser/HTTP crate | Calendar content and reminders |
| Captive-portal/VPN diagnostics | Distinguish connected Wi-Fi from usable internet, metered links and a VPN failure. Use NM connectivity state rather than periodic internet probes. | Small/event | Tiny state | Medium | QML Networking if exposed; otherwise existing Rust D-Bus | No | Contextual status/actions |
| Clipboard keyboard workflow | Add direct search focus, clear selection feedback and reliable keyboard paste/activation, respecting sensitive entries and the existing history layout. | Only while open/searching | Small filtered model | Medium | Pure QML | No | Keyboard and focus behavior |

## 4. Polish / UX Improvements

| Recommendation | What it improves and why | CPU impact | RAM impact | Difficulty | Implementation | Added dependency | UI change |
|---|---|---|---|---|---|---|---|
| Consistent focus entry, restoration and Esc | Test all flyouts, submenus and dialogs, including empty models and close-on-click-away. Return focus predictably to the invoking control/window. | Neutral | Neutral | Medium | Pure QML | No | Keyboard focus/interaction |
| Accessible icon labels and focused tooltips | Label icon-only controls for assistive tools and keyboard users. Tooltips should be one-shot and only instantiated while needed. | Negligible/event | Small when visible | Low–medium | Pure QML | No | Optional transient hints/focus cues |
| Touch/pen and drag cancellation pass | Add long-press context menus, drag thresholds, release-outside handling and non-overlapping touch targets. Preserve existing mouse geometry by default. | Negligible/event | Neutral | Medium | Pure QML | No | Touch behavior; larger targets optional |
| Mixed-DPI and hotplug placement polish | Verify negative output coordinates, rotated screens, popup clamping and restore after removing the originating screen. Retain the existing appearance at the original scale. | Small on output change | Neutral | Medium | Pure QML | No | Only changed-output cases |
| Locale-aware dates, units and week start | Respect user locale rather than fixed English/date conventions while retaining the uploaded locale's default appearance. | Neutral | Neutral | Low–medium | Pure QML | No | Text/date layout in other locales |
| Explain unavailable controls consistently | Reuse existing error/status surfaces for missing utilities, denied permissions and unsupported compositor settings. Disable only actions proven unavailable. | Small/event | Neutral | Medium | QML + existing capability results | No | Error text/disabled state |

## 5. Performance Improvements

| Recommendation | What it improves and why | CPU impact | RAM impact | Difficulty | Implementation | Added dependency | UI change |
|---|---|---|---|---|---|---|---|
| Finish native network snapshots after parity tests | Replace roughly 6–8 nmcli queries per refresh. Prefer Quickshell.Networking for already-exposed data; use the existing Rust backend only for missing profile/VPN detail. Preserve SSID escaping, sort order and labels. | Lower spawn/parsing cost | Lower transient processes; small model cache | High | QML first, Rust as needed | Removes nmcli requirement only after actions also migrate | None intended |
| Move gamma fast-path requests into the existing backend | Eliminate one-shot native process startup while keeping the same writes. Add a small acknowledged request only if measurements justify sharing the pipe. | Lower slider process cost | Tiny state; possibly resident user-bus connection | Medium | QML + Rust | No | None intended |
| Remove remaining audio default/routing duplicate tools | Preferred native defaults already exist, but CLI helpers also move existing streams. Prove full stream migration before deleting wpctl/pactl/pw-cli/pw-metadata calls. | Lower on route/default changes | Lower transient memory | High | QML where APIs suffice; Rust only for missing operations | Can remove audio CLI dependencies if every fallback is covered | None intended |
| Capture only requested previews, with bounded concurrency | Current hover captures all windows sequentially. Capture the hovered group and coalesce repeated requests; preserve JPEG appearance and timing. Cached freshness/order must be tested before changing policy. | Potentially much lower with many windows | Lower concurrent image/process memory | High | Rust + QML request payload | No; grim may remain | None intended, freshness is behavior-sensitive |
| Profile large repeaters before virtualizing | At high notification/clipboard/app counts, use a lazy view only if object counts/frame timing show a bottleneck. Preserve implicit sizes, focus and scroll positions. | Lower large-list creation | Lower delegate count | Medium–high | Pure QML | No | None intended; scrolling risk |
| Keep application/audio matching caches revision-bound | Repeated string/icon matching can be cached per immutable identity or model revision. Avoid permanent caches holding destroyed QObject wrappers. | Slightly lower when models are large | Small bounded cache | Medium | Pure QML | No | None |
| Add opt-in profiling counters | Count process launches, model assignments, refresh events and startup milestones on target. Disable counters completely by default. | Neutral off; small during measurement | Tiny when enabled | Low–medium | QML + Rust | No | No |
| Prefer binary-size work only after process profiling | Inspect linked code and XML/JSON parser contribution before changing crates or opt-level. Avoid ad-hoc XML parsing that loses namespaces/custom keys to save bytes. | Unknown; measure | File-size savings do not imply RSS savings | Medium | Rust | Potentially fewer crates | No |

Do not reduce the retained metric interval, media progress cadence, hover delay,
animation duration or frame quality as a hidden optimization. These are visible
behavior. The original hidden flyouts already unload by default; preserving that
policy is more valuable than constructing a replacement UI framework.

## 6. Reliability / Edge-Case Fixes

| Recommendation / status | What it improves and why | CPU impact | RAM impact | Difficulty | Implementation | Added dependency | UI change |
|---|---|---|---|---|---|---|---|
| Recorder pause/time and finalization — observed weakness | Elapsed time continues while paused and pause state is optimistic. Track acknowledged state and active elapsed time; handle disk full, encoder exit, suspend and graceful stop before declaring completion. | Neutral | Tiny state | Medium | QML + Rust process status | No | Correct timer/error behavior |
| Backoff only after sustained recovery — observed weakness | Clipboard restart delay resets when the process starts, so rapid start/exit failures can keep retrying at the minimum. Reset after useful data or a stable run; retain bounded retries. | Lower during failure loops | Neutral | Low | Pure QML | No | Faster trustworthy recovery; failure timing only |
| Recover failed native monitor subscriptions | An initial unavailable bus/udev monitor can leave that source disabled until backend restart. Reconnect on bounded failure deadlines or service events; never poll a broken fd in a tight loop. | Small on failure; no normal polling | Tiny retry state | Medium | Rust | No | Restores updates after failure |
| Prevent problematic mounts blocking metrics | Synchronous statvfs on a stuck network/filesystem mount can block the combined backend. Classify mount types and give slow/remote usage a bounded on-demand path. | Lower stalls; extra work only when requested | Small worker/process only if needed | Medium–high | Rust | No | Stale/unavailable disk state may need labeling |
| Validate session capabilities beyond command presence | systemctl existence does not prove suspend permission; /sys/power/state existence does not prove hibernate support. Query actual logind capabilities/inhibitors and handle denial. | Small/event | Tiny model | Medium | Rust D-Bus + QML | Existing logind | Correct disabled/error states |
| Reset failed optimistic audio selections | selectedSinkId/selectedSourceId clear when a matching default event arrives; failure or unplug can leave a stale optimistic selection. Clear from completion/removal and show the actual default. | Small/event | Neutral | Medium | Pure QML plus helper completion | No | Only failed selection feedback |
| Atomic compositor validation/rollback | Existing backups protect the file, but successful write/reload invocation does not guarantee the desired option took effect. Validate supported schema and preserve custom bindings; restore on a confirmed failure. | Small on edits | Tiny transaction state | High | Rust + existing QML error surface | No | Error/revert flow |
| Bound clipboard storage by bytes and generation | 100 files at up to 8 MiB each can be substantial. Use a byte budget that also respects pinned ownership; guard clear/delete races and test concurrent captures. | Small/event; possible lower I/O | Tiny index; less disk | Medium | Rust + QML policy | No | Quota/eviction behavior |
| Notification persistence privacy | Persisted bodies remain readable to the user account. Offer session-only history or clear-on-lock before considering encryption/key management. Do not silently delete uploaded history. | Lower I/O with persistence off | Similar live model | Low–medium | Pure QML | No | Optional privacy setting |
| Target binary portability and dependency absence | Rebuild for architecture/libc, check dynamic library availability, preserve executable permissions after extraction, and report helper failure clearly. Single-binary consolidation broadens its shared-library requirements. | Startup-only | Neutral | Low–medium | Cargo build + QML failure surface | Build toolchain only when rebuilding | Error path only |

## 7. Optional Advanced Features

| Recommendation | What it improves and why | CPU impact | RAM impact | Difficulty | Implementation | Added dependency | UI change |
|---|---|---|---|---|---|---|---|
| Native workspace state and activation | Use ext-workspace only when the installed Labwc advertises the needed capabilities. Improves active-workspace truth and avoids inferred keyboard actions; retain fallback where needed. | Lower action spawning; small events | Small model | High | QML if Quickshell exposes it; otherwise Rust backend | No new daemon; target protocol support required | Accurate status; optional overview |
| Automatic per-game policy with restoration | Apply an explicit allowlist on game start/exit, record previous state and restore after crash. Avoid scanning the process table every second. | Small/event; game-side effect hardware-dependent | Small rules/state | High | Rust integration + QML settings | None by default; GameMode optional | Optional policy editor/status |
| Per-game VRR/tearing/output profiles | Apply only supported settings and restore the original output mode. Do not imply enabling HDR/VRR always reduces latency or preserves colors. | Hardware/content-dependent | Neutral | High | Rust compositor/output integration + QML | No if compositor supports required controls | Optional settings and intentional rendering changes |
| Portal-aware capture/sharing controls | Make permission, selection, active recording and stop state clear across screenshot/screencast clients. Prefer existing portals/PipeWire over a new capture daemon. | Active capture cost; neutral when unused | Capture buffers only while active | High | QML + Rust where needed | Existing portal backend; install one if absent | Permission/recording surfaces |
| Event-driven output profiles | Restore monitor arrangement on docking using output-management events. A tiny native profile evaluator can avoid another daemon; first assess whether an existing output manager already owns this policy. | Small on hotplug | Small profile model | High | Rust + QML if an editor is wanted | None in native approach; kanshi is optional alternative | Output arrangement changes when enabled |
| Remote sharing privacy controls | If remote desktop is used, show sharing state and a reliable stop action. Do not add remote access merely to make the shell appear complete. | None when absent; variable during sharing | None when absent; service-dependent | High | QML + Rust integration | Remote desktop service only if chosen | Sharing indicator/control |
| Controller navigation | Optional gamepad focus/activation for couch use, suspended when not needed. Keyboard/mouse behavior stays the default. | Small input events | Small input mapping | High | QML if input module available; otherwise Rust events | Possibly gamepad input support | Controller focus/behavior |

## Features and dependencies worth removing

No further enabled visual feature was removed in this task. The best candidates
for an explicit future removal decision are all-window preview capture, unused
machine-specific application launchers, demo calendar content and redundant
audio-routing fallbacks **after** coverage is proven. Each removal either changes
behavior or needs target evidence. Do not delete dynamically named SVGs based on
literal-reference searches alone.

External applications listed in capability detection are optional launch targets,
not automatically resident dependencies. Rewriting a file manager, recorder,
terminal, network policy daemon or audio policy manager in Rust would expand the
rice and risk reliability. Retain grim/slurp/gpu-screen-recorder for their current
capture features until native replacements demonstrate equivalent output.

The strongest move **back into QML** is completing existing native Networking,
PipeWire and Bluetooth coverage, followed by UPower integration. The strongest
additional **Rust** work is cache ownership, filesystem transactions and missing
native protocol actions inside the existing backend. Avoid a Rust helper for
ordinary bindings, visual selection state, layout or existing native service
properties.

## Documentation basis and version limits

The Quickshell 0.3.0 module listing includes Networking, Bluetooth, UPower,
PipeWire, Wayland and WindowManager. Availability of a module does not guarantee
it exposes every operation proposed above:
https://quickshell.org/docs/v0.3.0/types/

Labwc's integration documentation describes layer-shell, foreign-toplevel,
screenshot and session-lock integration. Its current configuration manual lists
protocol interfaces including ext-workspace and image capture sources. These are
opportunities to investigate on the installed version, not proof of support in
the user's unseen session:
https://labwc.github.io/integration.html
https://labwc.github.io/labwc-config.5.html

All remaining recommendations are project-specific engineering judgments from
the source review. CPU/RAM estimates require measurement before implementation
is called an optimization. Optional UX and feature work requires a separate
change from this preserved-design refactor.
