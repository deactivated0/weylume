# Weylume: further optimization and final review

Completed 2026-09-29. Comparison baseline: the saved, already refactored bug-fix
release, version 2 of `weylume.zip`. This is an additional optimization pass, not
a comparison against the original Python/C implementation.

The updated source and stripped release executable are included. The project
still implements its own logic in QML and Rust only. No new daemon, timer, crate
or external utility was added. The visible design and timing constants were
preserved in source. A live pixel-for-pixel comparison remains unperformed.

## Measured changes

These are deliberately narrow measurements. They do not establish whole-shell
CPU, RAM, gaming performance or display latency on the target desktop.

| Measurement | Previous release | Updated release | Scope |
|---|---:|---:|---|
| Normal successful brightness/temperature write | One native helper launch per dispatched write | Zero helper launches; existing backend handles it | Fallback helpers remain available |
| Gamma request completion, median | 2.7027 ms | 0.2306 ms | 30 runs after 5 warmups, real libsystemd against a local TCP D-Bus fixture; excludes Qt/compositor rendering |
| Peak helper RAM rejecting 8 MiB of text | 11,140 KiB | 3,080 KiB | Median of 7 `wait4` measurements; about 72% lower for this input |
| Metadata calls with 80 cached images | 85 | 2 | Repeated capture; libc stat-family instrumentation, not a kernel syscall trace |
| Executable-path `readlink` calls during state validation | 12 | 1 | Immutable executable directory cached within each process |
| Audio model work, one display | 35.85 ms | 16.77 ms | 700 model revisions, 24 nodes, 8 app matches/display; median of 5 runs |
| Audio model work, two displays | 69.63 ms | 25.39 ms | Same isolated algorithm benchmark |
| Audio model work, four displays | 143.47 ms | 43.14 ms | Same isolated algorithm benchmark |

The audio benchmark executes extracted production function bodies in Node. Its
roughly 53–70% reduction describes that work, **not** idle desktop CPU. A separate
Qt QML test verifies the new model's reactive dependencies and callback behavior.
The clipboard benchmark concerns transient helper memory, **not** idle shell RAM.

## Changes made

**Shared audio and taskbar models.** `AudioService.qml` classifies PipeWire nodes
in one pass instead of four. It normalizes output-stream identifiers once per
model revision, sharing those records across application buttons and screens.
The existing Discord flavor rules, aliases, match order, device sorting and
corked-stream filtering are retained. Volume and mute remain live native values;
they are not cached. `PinnedApps.qml` now owns the common unpinned-window grouping
instead of every taskbar rebuilding it independently.

**Asynchronous gamma writes.** Brightness and night-light changes use the existing
backend input/output pipes. Rust queues a native D-Bus property write and returns
an acknowledgment. QML keeps the same per-property serialization, latest pending
value, rounding and fallback policy. A callback is retained only until its
request finishes or the backend exits; no broadcast signal or extra Connections
object is needed. Writes before the backend's `started` event use the existing
helper, preventing a startup request from getting stuck in an unopened pipe.

The native implementation uses libsystemd's asynchronous calls, the existing
`poll` loop and D-Bus deadlines. It permits two outstanding requests, enough for
one brightness and one temperature write. Message and callback-slot ownership
are explicit; completed slots are released, and disconnection/shutdown fails
pending requests. A slow service does not block metric updates. The existing
one-shot gamma commands and service-start/backlight fallbacks remain intact.

**Clipboard allocation and filesystem work.** Capture classifies the initial
bytes before choosing the existing 128 KiB text or 8 MiB image limit. Oversized
text is drained up to the original input bound without retaining the whole
payload. Accepted bytes, image hashes, privacy checks and formats are unchanged.
Directory-entry types avoid metadata calls below the 100-file cache cap.
Timestamp collection and the original sort/tie rules run only when eviction is
needed. Hidden files, directories and symlinks retain their previous treatment.

**Small native changes.** The executable directory is cached with `OnceLock`;
valid UTF-8 child output reuses its owned buffer, with the same lossy fallback for
invalid bytes. CPU/network sampling avoids temporary vectors; memory sampling
parses only the two values it actually uses. Sampling intervals and displayed
formatting remain unchanged.

**Bug fixed during review.** An unpinned application ID of `constructor` or
`__proto__` could collide with inherited object properties and break grouping.
The lookup table now has no prototype. Ordinary grouping is unchanged; affected
applications can now appear correctly instead of throwing an error.

## Static comparison and tradeoffs

| Count | Previous release | Updated release |
|---|---:|---:|
| QML files | 39 | 39 |
| QML lines | 13,844 | 13,895 |
| Rust implementation files | 11 | 11 |
| Rust implementation lines | 3,086 | 3,325 |
| Production lines, including blanks/comments | 16,930 | 17,220 |
| Rust test lines | 318 | 382 |
| Non-QML/Rust source files in the package | 0 | 0 |
| Static QML object declarations | 1,484 | 1,484 |
| QML Timer declarations | 20 | 20 |
| QML Process declarations | 15 | 15 |
| QML Connections declarations | 10 | 10 |
| Initialized QML property declarations | 418 | 425 |
| QML import statements | 161 | 160 |
| QML detached-command call sites | 56 | 56 |
| Direct Rust crates | 5 | 5 |
| Shipped Rust executables | 1 | 1 |
| Release executable bytes | 976,392 | 992,192 |

This pass favors measured runtime savings over line count. Production source
grew by 290 lines, principally for asynchronous completion, cancellation and
fallback handling. The binary grew by 15,800 bytes, about 1.6%. A small current
audio-match cache and a lazily opened session-bus connection trade some retained
memory for less repeated work and fewer transient processes. No whole-shell net
RAM saving is claimed.

QML's 20 Timer declarations are not 20 constantly running timers. Their blocks
are unchanged, including existing one-shot UI delays and gated timers. The 15
Process objects likewise do not imply 15 resident processes. The one existing
native backend remains resident; clipboard watching and optional external
services retain their previous lifecycle. Animation timing, metric intervals,
hover delays and recorder/media cadence were not reduced.

Each gamma write still needs a D-Bus property call. The new path adds a small
request/acknowledgment on the existing pipes while avoiding process creation and
a fresh bus connection for each normal write. Total runtime IPC, live object
counts and continuously active bindings require a target-session trace; static
declaration counts cannot provide them.

## Verification

| Check | Result |
|---|---|
| Locked, stripped, optimized Rust release build | Passed |
| Formatting and Clippy, all targets, warnings denied | Passed |
| Rust release tests | 5 unit + 10 integration passed |
| QML syntax parsing | All 39 files passed with Qt 6.4.2; unresolved Quickshell semantics excluded |
| Old/new audio and grouping comparisons | 6,348 passed |
| Brightness/temperature queue comparisons | 29,400 passed, including failed writes and backend-unavailable fallback |
| Native clipboard/state/backend checks | 19 passed |
| Native gamma protocol/lifecycle checks | 11 passed, including delayed replies, rejection, reconnect, saturation and shutdown |
| Actual default D-Bus timeout | Failed the request after approximately 25 seconds while metrics continued |
| Qt QML reactive fixture | Passed identifier/name, corked-state, class, sorting and removal updates; cross-object callbacks and cancellation also passed |
| Assets and saved state | All 31 SVGs and 11 root JSON files byte-identical |
| Timers and animations | Blocks textually unchanged |
| Taskbar visual source | Unchanged after accounting for relocated functions and equivalent service references |

Thirty-three QML files are completely unchanged. The six edited QML files are
AudioService, PinnedApps, Taskbar, SystemData, ShellState and NightLightService.
Four Rust implementation modules changed: backend, bus, clipboard and util.
The regression fixture now uses an immutable executable hard link where
possible, avoiding flaky executable-copy races on copy-on-write test mounts.

The native backend's isolated six-second check received five additional metric
messages in both versions, with nine voluntary context switches each. CPU time
including startup/exit was about 4.6 versus 5.0 ms; first-metric samples were
3.53 versus 4.06 ms. These small single-sample differences are not evidence of an
idle or startup improvement. With the gamma fixture connected, the new backend
used about 5.7 ms total CPU over six seconds, with 3,652 KiB peak RSS and ten
voluntary context switches including setup and the write. This checks against a
busy loop; it does not measure desktop power wakeups.

Detailed evidence is in `docs/verification/second-*`. Earlier verification files
remain historical snapshots. Python, JavaScript, C and C++ test tools ran outside
the project and are not shipped; QML's embedded expressions remain part of QML.

## Final review and remaining limits

The final source/diff review covered the changed call paths, callback lifetimes,
request ownership, fallback sequencing, cache eviction and module dependencies.
No new always-running timer, worker thread, external process or crate was found.
Native callback ownership is bounded, and pending references are cleared on
completion or backend exit. This is not a claim that every possible leak or
failure in the entire desktop has been eliminated.

The target Quickshell/Labwc session, PipeWire graph, actual gamma service,
reference screenshots and input devices were unavailable. Therefore neither
pixel-for-pixel equivalence nor full live interaction equivalence is certified.
Native calls were exercised against a controlled protocol fixture; QML bindings
used mock QtObject nodes. Complete startup, idle RAM/CPU and idle wakeups remain
unmeasured on the real desktop.

The next acceptance pass should compare the same panels/popups before and after,
with the same fonts, scale, outputs and saved state; drag brightness and night
light rapidly; unplug audio devices; exercise duplicate app groups across
outputs; and test backend/service restarts. Keep the previous archive until that
comparison is complete. Installation and target ABI/rebuild instructions are in
README; the included binary is stripped x86-64 GNU/Linux built on Ubuntu 24.04.

Further removal of nmcli queries, audio-routing compatibility utilities or
all-window preview captures needs target evidence to preserve formatting,
routing and thumbnail behavior. Changing refresh cadence, frame quality,
retention policy or available features would violate the preservation boundary.
Those decisions and the remaining correctness/integration work are documented
separately in `CURRENT_ROADMAP.md`; optional recommendations were not implemented.
