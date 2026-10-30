# Weylume: historical recommendations approved for implementation

Recorded 2026-09-29. All 33 entries below were approved later that day. See
`33_IMPLEMENTATION_REPORT.md` for their current implementation and validation
status. The text below preserves the original scope and estimated impacts.
The preceding bug fixes remain included;
this pass also fixes prototype-key taskbar grouping and implements the shared
audio models and asynchronous gamma path previously proposed in the roadmap.

CPU/RAM impacts are qualitative estimates, not measured desktop deltas.
“Event” means work on demand or on a native event; “neutral” means no intended
steady-state increase. Dependency entries describe **additional** packages.
UI changes include input, error and recovery behavior. Unseen session files
cannot be assumed to supply an integration merely because a command exists.

## 1. Must Fix

| Recommendation | Improvement and reason | CPU impact | RAM impact | Difficulty | Implementation | Extra dependency | UI change |
|---|---|---|---|---|---|---|---|
| Finish real-session acceptance | Verify rendering, native bindings, gamma/audio fallbacks and multi-monitor behavior; static tests cannot certify identical pixels or input | Test-only | Test-only | Medium | QML/Rust verification | Test tools only | None intended |
| Confirm session lock before suspend | A successful lock-session request does not prove a locker protected the session; test lock failure and shell/locker crashes | Event | Existing locker memory | Medium–high | Session integration; QML/Rust only if implementing a locker | A supported locker if absent | Lock/failure path |
| Complete workspaces 10–16 | The visible workspace setting permits 16, while shortcut/action coverage stops at 9; provide a consistent action contract without silently reducing the setting | Neutral | Neutral | Medium | Rust actions/XML plus QML state | No | Correct missing workspace actions |
| Give pinned clipboard images one retention owner | Independent 100-file eviction can remove a pinned payload; coordinate capture, clear and queued deletion with generations and an explicit quota | Event; potentially less scanning | Small index; potentially more retained disk data | Medium | Rust cache plus QML history | No | Correct broken-image/quota behavior |
| Coordinate initial state repair and loading | Native repair and singleton FileView loading can overlap; reload repaired state or order initialization deterministically | Startup-only | Neutral | Medium | Primarily QML, existing Rust repair | No | Correct missing/corrupt-state startup |

These items originally involved a target-session contract, cross-component
ownership or recovery policy. Their later implementations and remaining
target-session checks are recorded in `33_IMPLEMENTATION_REPORT.md`.
The archive does not contain the external Labwc configuration, environment or
autostart; check those references using README's helper replacement mapping.

## 2. Strongly Recommended

| Recommendation | Improvement and reason | CPU impact | RAM impact | Difficulty | Implementation | Extra dependency | UI change |
|---|---|---|---|---|---|---|---|
| Make gaming/power changes transactional | Record prior state and restore it after disable, partial failure or a crash; avoids leaving services or profiles changed | Event | Tiny saved state | Medium | Rust, existing QML status | No | Failure/restore behavior |
| Reset failed optimistic audio selection | Clear stale selected device IDs after failed actions or unplug, then show the actual default | Event | Neutral | Medium | QML plus action completion | No | Failed-selection feedback |
| Verify notification replacement and withdrawal | Reconcile application closes/replaces-id, retained actions, history eviction and reload so entries cannot hold stale objects | Event; potentially lower | Potentially lower retained objects | Medium | Pure QML | No | Incorrect notification cases |
| Make hardware labels and mounts configurable/discovered | Keep the RX 590 desktop's current defaults but avoid misleading labels or nonexistent disks elsewhere | Discovery event; neutral sampling | Tiny cache | Medium | Rust; QML only for optional settings | No | Labels on other hardware |

## 3. Useful Features to Add

| Recommendation | Improvement and reason | CPU impact | RAM impact | Difficulty | Implementation | Extra dependency | UI change |
|---|---|---|---|---|---|---|---|
| Complete Bluetooth pairing prompts | Add PIN/passkey confirmation, authorization, cancel and adapter selection; connecting known devices alone is incomplete | Event | Small lazy dialog/model | Medium–high | Native Quickshell QML first; Rust only for missing BlueZ agent methods | No if BlueZ is present | Pairing dialogs |
| Battery and headset power information | Makes laptop/peripheral power status useful, using native events | Event | Small model | Low–medium | QML UPower where supported | UPower if absent | Optional power details |
| Real window screenshot selection and clean cancel | Current window-mode behavior falls back to region selection; distinguish actual window capture and stop retrying cancellation | On demand | Image buffer while active | High | QML selection; Rust capture if required | Retain current capture tools until equivalent | Selection/cancel behavior |
| Audio profiles and ports | Expose common HDMI/headset/analog choices without opening another mixer | Event | Small lazy model | Medium–high | QML where exposed; Rust only for missing operations | No additional daemon | Mixer controls |
| Network authentication and connectivity detail | Support secrets cancellation/enterprise cases and distinguish Wi-Fi association from usable internet or VPN failure | Event | Small temporary state | High | QML plus Rust NM integration where needed | No additional service beyond existing NM | Prompts/status/error paths |
| Local calendar import/reminders | Makes calendar content useful beyond the included data; schedule the next deadline instead of periodically scanning all events | Negligible idle; import/event work | Bounded event model | Medium | Rust parsing/storage, QML display | None for a limited local format; full ICS may justify a parser | Calendar content/reminders |

## 4. Polish / UX Improvements

| Recommendation | Improvement and reason | CPU impact | RAM impact | Difficulty | Implementation | Extra dependency | UI change |
|---|---|---|---|---|---|---|---|
| Consistent keyboard focus and Esc | Restore focus to the invoker, focus clipboard/start search predictably, and support empty-model navigation | Neutral | Neutral | Medium | Pure QML | No | Keyboard interaction |
| Touch/pen and pointer cancellation | Handle release outside, drag cancellation and long-press context actions without changing existing mouse geometry by default | Event | Neutral | Medium | Pure QML | No | Touch/edge interactions |
| Multi-monitor ownership and mixed-DPI pass | Clamp popups, recover removed origin screens and verify retained flyouts, rotated outputs and negative coordinates | Output/input events | Neutral or lower duplicate work | Medium | Pure QML | No | Faulty placement cases |
| Accessible names and clear unavailable states | Describe icon-only controls and explain unsupported actions through existing status surfaces | Event | Tiny temporary text/model | Low–medium | QML plus existing capabilities | No | Labels/tooltips/error states |

## 5. Performance Improvements

| Recommendation | Improvement and reason | CPU impact | RAM impact | Difficulty | Implementation | Extra dependency | UI change |
|---|---|---|---|---|---|---|---|
| Complete native NetworkManager coverage | Remove repeated nmcli snapshots only after matching escaping, profile/VPN ordering, addresses and authentication behavior | Lower spawn/parsing work | Lower transient memory; small resident model | High | Native QML first, existing Rust backend for missing methods | Potentially removes nmcli | None intended |
| Remove proven-redundant audio routing tools | Native defaults do not by themselves prove old streams migrate correctly; test that before removing compatibility commands | Lower on routing actions | Lower transient processes | High | QML first; Rust for missing native operations | Could remove wpctl/pactl/pw-cli/pw-metadata requirements | None intended |
| Capture only the requested preview group | All-window sequential capture is costly; use stable IDs and bounded work while preserving freshness, images and hover timing | Potentially much lower on hover | Lower transient capture memory | High | Rust plus QML request data | No; current capture tools may remain | None intended; freshness must be verified |
| Profile large lists on target | Virtualize clipboard/notification/app delegates only where object counts and frame timing justify it; preserve scroll and focus behavior | Lower for large models | Lower delegate count | Medium–high | Pure QML | No | None intended; scrolling risk |
| Measure before more binary/framework work | The current executable is about 969 KiB. Removing robust JSON/XML support or adding another daemon to save a small amount of code can cost more than it saves | Unknown until profiled | Unknown | Medium | Rust profiling | None required | No |

The gamma backend path, shared audio classification/matching and common taskbar
grouping are now implemented; they are no longer open recommendations. There is
no evidence that reducing animation quality or UI timer cadence is necessary,
and doing so would change the required behavior.

## 6. Reliability / Edge-Case Fixes

| Recommendation | Improvement and reason | CPU impact | RAM impact | Difficulty | Implementation | Extra dependency | UI change |
|---|---|---|---|---|---|---|---|
| Bound slow filesystem usage queries | A stalled remote/misbehaving mount can block synchronous statvfs and thus other work in the combined backend | Prevents stalls; on-demand fallback work | Small bounded worker only if required | Medium–high | Rust | No | Unavailable/stale disk feedback |
| Use stable preview identities | Unicode/long-name compatibility is fixed, but equal or sanitized-colliding titles can still share a filename; use a shared ID/manifest | Neutral or lower retry work | Tiny manifest | Medium–high | Rust plus QML | No | Correct colliding thumbnails |
| Acknowledge recorder state and finalization | Pause timer gating is fixed; pause failure, disk full, encoder exit, suspend and incomplete output still need explicit completion/error handling | Event | Tiny state | Medium | Rust plus QML | No | Correct recorder status/errors |
| Query real power permissions and validate compositor changes | Command existence is not capability. Check logind permission/inhibitors and validate successful compositor application before declaring success | Event | Tiny state | Medium–high | Rust D-Bus/XML plus QML status | No | Permission/revert feedback |
| Verify target binary and missing dependencies | Test the actual architecture/libc, executable permissions and absent-service fallback; report failure through existing UI | Startup/event | Neutral | Low–medium | Rust packaging, QML failure surface | Build toolchain only if rebuilding | Failure path |

## 7. Optional Advanced Features

| Recommendation | Improvement and reason | CPU impact | RAM impact | Difficulty | Implementation | Extra dependency | UI change |
|---|---|---|---|---|---|---|---|
| Native workspace state and activation | Use the installed compositor's advertised workspace protocol instead of inferred shortcut actions, if fully supported | Lower action spawning; small event work | Small model | High | QML if exposed, otherwise Rust backend | No; target protocol support required | Accurate state/optional overview |
| Per-game profiles with reliable restoration | Apply explicit power/output policies on game start/exit; avoid continuous process scans and restore after a crash | Event; game effect hardware-dependent | Small rule/state model | High | Rust plus QML settings | None by default; GameMode optional | Optional settings/status |
| Output profiles, VRR and tearing controls | Restore supported monitor arrangements on docking and user-selected rendering policies; test RX 590/compositor support instead of assuming it | Hotplug/event; GPU effect workload-dependent | Small profile model | High | Rust output protocol plus optional QML editor | None if native support suffices | Intentional output/rendering changes |
| Portal-aware capture/sharing status | Show active capture and a reliable stop action across portal clients without introducing a second capture daemon | Active capture only | Active buffers/model | High | QML plus native integration where needed | Existing portal backend, or one if absent | Capture/privacy surfaces |

## Features and dependencies to reconsider

No current visual feature was removed. If you later choose to simplify the
desktop's behavior, consider all-window preview capture, unused personal
launchers and demonstration calendar data. Removing them now would violate the
preservation requirement. Native replacements for audio/network commands are
worth pursuing only after feature coverage is proven on the actual machine.

Keep file managers, terminals, the recorder and system policy daemons as focused
external programs; reimplementing them in Rust would enlarge the rice. Prefer
moving more PipeWire, Networking, Bluetooth and UPower state into native QML
services where the installed APIs cover the need. Rust remains appropriate for
cache ownership, filesystem transactions, parsing and missing native protocol
operations inside the existing backend. Check the installed Quickshell/Labwc
versions and advertised Wayland protocols before adding these integrations.
