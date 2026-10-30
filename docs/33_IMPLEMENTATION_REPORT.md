# Weylume: approved 33-item implementation and final review

30 September 2026. Baseline: delivered Weylume version 3. The original seven-section
proposal remains in `CURRENT_ROADMAP.md`; this report records the actual result.
The supplied theme and 32 font/icon/image/theme files are byte-for-byte intact.
The existing widgets keep their established paint properties. New controls live
in Settings → Integrations and in failure/pairing/confirmation dialogs. No live
Labwc or Quickshell session was available, so pixel equality and target hardware
behavior have **not** been certified.

**Status key:** I = code implemented, with target verification still needed;
T = target-session acceptance itself remains; P = partial or platform-limited.
Fixtures are deliberately named below. These marks are not claims that every
service, protocol and UX flow worked on the user's machine.

| # | Approved recommendation | What changed | Status and remaining limit |
|---:|---|---|---|
| 1 | Real-session acceptance | Native diagnostics, `/proc` sampler and a practical acceptance checklist | **T** — requires the actual Labwc desktop; see `TARGET_ACCEPTANCE.md` |
| 2 | Lock before suspend | Native logind session lookup, Lock, LockedHint wait and permission checks; suspend fails closed | **I/T** — a real Wayland locker must update LockedHint only after secure lock |
| 3 | Workspaces 10–16 | Native workspace actions and corresponding Labwc bindings; advertised windowsets used when available | **I/T** — verify Labwc XML, shortcut conflicts and protocol advertisement |
| 4 | Clipboard retention | History owns image references; pins, 128 MiB quota, capture lease, generation checks and locked cleanup | **I** — contract tests cover pins, expiry, conflicts and path safety |
| 5 | Initial state | Native repair finishes before singleton FileViews load; startup error is surfaced | **I** — missing helper watchdog and corrupt-state contract check |
| 6 | Gaming transaction | Journal previous power/tearing/output state, restore owned changes, recover on restart | **I/T** — real profile services and Labwc reload require checking |
| 7 | Audio selection | Reflect actual PipeWire defaults; migrate existing streams and reset removed/failed selections | **I/T** — test a live playback stream, unplug and migration |
| 8 | Notifications | Own live objects and release after close/eviction; action references invalidated; reload carryover deduplicated | **I/T** — Qt lifecycle fixture passes; test Quickshell notification server signals |
| 9 | Hardware discovery | Read GPU/temperature and actual mount labels, with `hardware.json` overrides and RX 590 default | **I/T** — inspect discovered hardware and mounted drives |
| 10 | Bluetooth pairing | Ephemeral BlueZ agent handles PIN, passkey, authorization, cancellation and explicit trust; adapter chooser | **I/T** — five native wire cases pass; pair a real device |
| 11 | Battery/headset power | Lazy native Quickshell UPower/Bluetooth device data in Integrations | **I/T** — test actual batteries/headsets; no new poller |
| 12 | Window screenshot | Picker uses compositor toplevel identities and an explicit cancel path | **I/T** — ext-foreign-toplevel and grim behavior must be checked on Labwc |
| 13 | Audio profiles/ports | Optional native PulseAudio card/profile and device-port operations | **I/T** — ABI layout checks pass; actual HDMI/headset routing needs checking |
| 14 | Network authentication | Native NM snapshots, saved-profile SecretAgent, VPN state and common PEAP/TTLS/TLS/PSK/WEP/OWE cases | **P/T** — ordinary cases have D-Bus fixtures; VPN plugins/OTP/browser flows vary by service |
| 15 | Calendar import/reminders | Bounded local ICS import; next-deadline timer; notification reply required before marking reminded | **I/T** — recurring events are reported and skipped; check live timezone and resume |
| 16 | Keyboard behavior | Search/focus, Escape, invoker restoration and empty-list navigation | **I/T** — on-machine input pass needed |
| 17 | Touch/pointer | Long-press context actions and drag cancellation restore | **I/T** — test touch, release outside and drag gestures |
| 18 | Multi-monitor | Own popup origin, clamp to screen and recover screen removal | **I/T** — rotated, negative-origin and mixed-DPI displays need checking |
| 19 | Accessibility | Name icon-only controls, keyboard actions and clear unavailable explanations | **I/T** — verify screen reader and keyboard on target |
| 20 | Native networking | NetworkManager D-Bus profiles/AP/IP/DNS/status replace routine `nmcli` snapshots | **I** — Unicode/colon/whitespace SSID and saved-profile wire fixture passes |
| 21 | Audio routing process work | Native default selection and stream migration avoid duplicate normal-path commands | **I/T** — `pw-cli`, `pw-metadata`, `pactl` and `wpctl` compatibility paths remain for unproven routing variants |
| 22 | Previews | Limit work to requested task group; bound captures and child timeouts | **I/T** — inspect group freshness and hover timing on the compositor |
| 23 | Large lists | Clipboard delegates use virtualized ListView/reuse; closed panels unload where safe | **I/T** — live large-list object count, frame time and scroll/focus still need profiling |
| 24 | Binary measurement | Preserve small crate set; record size, startup and isolated backend cost | **I** — actual figures below; extra features grow binary and source |
| 25 | Slow disk queries | At most one disposable bounded `statvfs` worker on drive request; stale state shown | **I/T** — a hung real network mount remains a target test |
| 26 | Preview identity | Stable compositor ID hash prevents filename/title collisions | **P/T** — identical app/title QML tasks cannot always map to a unique ext ID; show placeholder instead of the wrong image |
| 27 | Recorder | First-frame flag where supported, acknowledged pause/stop, file checks, suspend inhibitor and failure recovery | **I/T** — verify live encoder, IPC support, disk-full and suspend; file size check does not decode the media |
| 28 | Permissions/configuration | logind permissions and inhibitors, validated XML and rollback on native failure | **P/T** — Labwc reload has no application acknowledgement; final application must be checked live |
| 29 | Startup diagnostics | Native architecture/dependency report and visible missing-helper error | **I/T** — run on target architecture/services; no launch-time dependency assumptions |
| 30 | Workspace state | Quickshell windowsets when advertised; native action fallback | **I/T** — verify the compositor's actual protocol support |
| 31 | Per-game policies | Exact app-ID rules, first-match priority, prior-state journal and ownership-aware restore | **I/T** — test open/close, crash and manual override on target |
| 32 | Display profiles/VRR | Native wlr-output-management test/apply, 15-second confirmation, journal rollback and unique-match dock restore | **I/T** — seven wire scenarios pass; live output/VRR support is conditional |
| 33 | Portal sharing | Accurate status and reliable stop for Weylume's own recorder; other sessions are explained in the UI | **P** — the portable ScreenCast API has no enumeration/revoke operation for other applications' sessions; backend-specific integration would be required |

## Static and measured cost

| Metric | Version 3 | This version | Interpretation |
|---|---:|---:|---|
| QML files / implementation lines | 39 / 13,895 | 51 / 14,730 | Extra settings and optional features |
| Rust implementation files / lines | 11 / 3,325 | 24 / 7,382 | Native integrations and generated Wayland metadata |
| Non-QML/Rust implementation source files | 0 | 0 | JSON, assets and documentation are data, not scripts |
| Static QML object declarations | 1,484 | 1,644 | Declarations, not instantiated objects |
| Static QML Timer declarations | 20 | 22 | Added startup watchdog and next-calendar-deadline timer; neither polls continuously |
| Static QML Process declarations | 15 | 23 | New optional/on-demand operations; not eight new resident processes |
| Direct Rust crates / resident native backend | 5 / 1 | 5 / 1 | Same package and service count |
| Stripped release executable | 992,192 B | 1,307,704 B | +315,512 B for approved features |
| Isolated backend peak RSS | 3,496 KiB | 3,540 KiB | +44 KiB in this container fixture; not idle desktop RSS |
| Native first-metrics sample | 3.25 ms | 3.42 ms | Single sample; no reliable startup delta |
| Native capability median (20 runs) | 2.75 ms | 2.86 ms | Isolated command, unavailable buses |
| 20-second backend user + system CPU | 3.17 ms | 5.31 ms | Includes startup, shutdown, test contention; too short to infer idle CPU |
| 20-second backend context switches | 4 | 8 | Not kernel CPU wakeups |

The 20-second comparison used an empty temporary Desktop, 10-second metric
interval and unavailable D-Bus/Wayland services. It omits Quickshell, the
actual devices, foreground widgets and the resident `wl-paste --watch` process.
A disk query can now spawn **one short-lived worker on demand**; previously that
query ran in the backend itself. No replacement scripting runtime or new
long-running daemon was introduced. Full-QML RAM, CPU, active bindings, IPC
volume, actual timer firings, renderer objects, gaming FPS and wakeups remain
unmeasured. The gamma regression fixture measured acknowledged writes at 3.36
ms median for the old one-shot command versus 0.335 ms for the reused backend
path, with 30 measured writes each. This path preceded the 33-item request and
is not counted as a new gain.

## Verification completed

- Rust: eight unit tests, twelve integration tests and `clippy -D warnings`
  passed; release binary was rebuilt and copied beside `shell.qml`.
- Qt: syntax checks across 51 QML files; actual Qt QML engine ran six reactive
  audio/gamma phases and ten notification lifecycle checks using production
  functions with fixture objects. Quickshell imports/rendering were not loaded.
- Native D-Bus fixture: 14 cases for NetworkManager data/secrets/cancel,
  lock-success/refusal, power profile, calendar Notify reply/error and BlueZ
  PIN/passkey/confirmation/authorization/cancel. Real sd-bus on TCP fixtures.
- Native Wayland fixture: seven cases for output snapshot, keep, explicit
  rollback, test rejection, failed apply, EOF rollback and 15-second timeout.
- Native gamma fixture: reused connection, service error, timeout, cancellation
  and 35 acknowledged-write comparison. No desktop gamma service was tested.
- Assets and theme: all 32 comparable files have identical bytes; the original
  layout constants in normal desktop conditions were intentionally retained.

Fixture results are in `docs/verification/`. Static declarations and isolated
native figures should never be presented as pixel, FPS or desktop wakeup
measurements. The acceptance list identifies each remaining real-session check.

## Final perfection review: recommendations after implementation

The original 33 recommendations were authorized and have the statuses above.
The following actions are a **separate roadmap**; they are not silently added.
CPU/RAM are expected steady-state effects, not measured improvements. "Event"
means no new idle loop; "neutral" means no predicted material change.

### 1. Must Fix

| Recommendation and benefit | CPU / RAM | Difficulty | QML or Rust; new dependency; UI change |
|---|---|---|---|
| Complete the target acceptance list: establish exact rendering and controls before deploying as the primary shell | Test-only / test-only | Medium | QML/Rust verification; no permanent dependency; none |
| Configure a trusted locker that sets LockedHint after acquiring the Wayland session lock: makes suspend usable without bypassing the guard | Event / existing locker | Medium | External Labwc/logind session contract; locker if absent; only failure flow |

### 2. Strongly Recommended

| Recommendation and benefit | CPU / RAM | Difficulty | QML or Rust; new dependency; UI change |
|---|---|---|---|
| Validate Labwc keyboard/output/tearing changes after reload or a deliberate restart: distinguish accepted config from applied config | Event / neutral | Medium | QML with native check if compositor exposes state; none; accurate status |
| Prove stream migration for each installed PipeWire setup, then remove any redundant `pw-cli`/`pactl`/`wpctl` fallback: fewer action spawns | Lower action CPU / neutral | Medium | QML/PipeWire where possible, small Rust gap; may remove utilities; none intended |

### 3. Useful Features to Add

| Recommendation and benefit | CPU / RAM | Difficulty | QML or Rust; new dependency; UI change |
|---|---|---|---|
| Optional search and automation over saved output/game rules: useful when many docks or games accumulate | Event / small model | Low–medium | QML; none; adds controls |
| Optional notification/clipboard history export with private atomic files: better backup/migration | On demand / transient buffer | Medium | QML UI + Rust file operation; none; adds an explicit export action |

### 4. Polish / UX Improvements

| Recommendation and benefit | CPU / RAM | Difficulty | QML or Rust; new dependency; UI change |
|---|---|---|---|
| Exercise keyboard, screen reader, touch and mouse with every popup on both displays; refine focus and labels found by actual usage | Neutral / neutral | Medium | QML; no dependency; only corrective input/labels |
| Offer a concise, on-demand explanation when a hardware control is unsupported instead of a silent disabled action | Event / tiny text | Low | QML; none; extra status text |

### 5. Performance Improvements

| Recommendation and benefit | CPU / RAM | Difficulty | QML or Rust; new dependency; UI change |
|---|---|---|---|
| Profile clipboard/notifications under a genuinely large history; optimize delegates only if object count or frame time warrants it | Potentially lower / potentially lower | Medium | QML; profiler only; none intended |
| Measure foreground, idle and gaming FPS/CPU/RSS/wakeups on the real Labwc desktop; then address the largest measured consumer | Unknown / unknown | Medium | Profile first, QML or Rust depending on cause; measurement tool only; none intended |

### 6. Reliability / Edge-Case Fixes

| Recommendation and benefit | CPU / RAM | Difficulty | QML or Rust; new dependency; UI change |
|---|---|---|---|
| Check actual disk-full, revoked portal, hot-unplug and encoder-crash cases; these can still fail despite the bounded native fixtures | Event / neutral | Medium | QML/Rust fixes as findings dictate; no known new dependency; clearer failure status |
| Inspect enterprise/VPN authentication with the actual NM plugins, CA rules and MFA: avoid claiming unsupported mechanisms work | Event / transient prompt | High | Rust/NetworkManager integration or plugin UI; plugin-dependent; added prompts only where needed |
| Resolve equal app/title to distinct ext-toplevel identities only if Quickshell exposes a stable cross-protocol handle; avoids wrong previews | Event / small index | High | QML/Rust protocol bridge; compositor support, no crate; correct thumbnail |

### 7. Optional Advanced Features

| Recommendation and benefit | CPU / RAM | Difficulty | QML or Rust; new dependency; UI change |
|---|---|---|---|
| Integrate a specific portal backend's session registry, if it offers one, to show other apps' shares and revoke them safely | Event / small model | High | Rust adapter + QML status; backend-specific; privacy controls |
| Support bounded ICS recurrence expansion only if local calendar subscriptions require it; shows recurring appointments | On import / bounded event model | High | Rust parser; perhaps a calendar crate; calendar entries |

These recommendations cover window/workspace controls, networking and
Bluetooth, audio, screenshots/recording, notifications and clipboard, power and
gaming, keyboard/pointer access and displays. No extra settings or UI redesign
was applied merely to pursue the optional roadmap.
