# Weylume bug-hunt fixes

> Earlier bug-fix release snapshot. See `FURTHER_OPTIMIZATION_REPORT.md` and
> `CURRENT_ROADMAP.md` for the latest implementation, measurements and open work.

This follow-up fixes ten concrete defects in the previously delivered QML/Rust
refactor. No layouts, fonts, colors, dimensions, effects or animation timings
were redesigned. Changes affect incorrect lifecycle, recovery, file handling
and preview behavior. The new release executable is included.

## Fixed

| # | Bug | Fix | Verification |
|---|---|---|---|
| 1 | Recording duration continued increasing during pause. | The existing elapsed timer runs only while the recorder is running and not paused. It also stops waking up during pause. | QML timer-state regression. Pause signaling itself still needs a real recorder. |
| 2 | Clear All could abandon a tracked transient toast because it was absent from the history map. | Include the current toast in the dismissal set, deduplicate it, release QML ownership before dismissal, and stop its expiry timer. | Transient-only and shared toast/history ownership tests. |
| 3 | Removing the current notification from history could retain a reference to the dismissed native object. | Clear the current toast/key and timer before dismissing the object; remove map/history ownership first. | Regression asserts ownership is gone when dismissal occurs. |
| 4 | Clipboard watcher crash backoff reset on every process start, keeping rapid crashes at the minimum retry delay. | Reset only after a run lasting at least 30 seconds; clear the start timestamp on exit. Rapid failures now wait 2, 4, 8 seconds, up to the existing 60-second cap. No extra timer. | Repeated short-run and stable-run simulation. |
| 5 | Rename, move and trash rejected or silently ignored dangling symlinks because existence checks followed the missing target. | Check the directory entry with symlink_metadata. Operations act on the link itself; existing destination protection remains. | Native integration test renames, moves and trashes a broken link without creating/touching its target. |
| 6 | Changing metrics from the idle interval to the active interval could retain the already scheduled ten-second deadline. | Shorten a pending deadline when a shorter interval is requested; do not postpone an already imminent sample. | Real backend stdin/stdout test switches from 10 seconds to 250 ms and receives the next sample within a bounded wait. |
| 7 | Failed native monitor descriptors could remain in poll; udev initialization failure had no recovery. Network reconnection also lacked an explicit snapshot-refresh event. | Remove descriptors on HUP/ERR/NVAL, retry missing monitors on existing sampling deadlines, and emit network-changed after reconnection. Rediscover sensors after restoring udev. | Build/lint and code-path review. Actual D-Bus/udev failure injection is unavailable in this environment. |
| 8 | QML and Rust generated different preview paths for Unicode/long titles, and combined names could exceed the usual 255-byte filename limit. | Match UTF-8 byte sanitization and the existing per-component limit in QML. When the combined filename would exceed 255 bytes, both sides shorten its components identically. Ordinary short ASCII filenames stay unchanged. | QML/native filename tests cover ASCII, accented text, Arabic/Hebrew, Japanese, emoji, empty names and oversized names. |
| 9 | The preview helper ignored toplevel closed events and could try capturing a window already reported closed during discovery. | Mark closed handles and skip them during the capture pass; preserve stable listener storage and normal handle cleanup. | Native callback-state regression; live capture remains unverified. |
| 10 | Closing a preview could still launch a queued second all-window capture. | Clear the queued request on dismiss and require the popup to remain visible before starting another capture. The already running capture is allowed to finish. | QML dismissal regression. |

## Validation

- Release build with locked dependencies: passed.
- Clippy, all targets, warnings denied: passed.
- Rust tests: **5 unit + 8 integration passed**.
- New extracted-QML/source checks: **8 passed**.
- Earlier helper compatibility suite: **83 passed** again.
- Earlier audio/notification logic checks: **17 passed** again.
- Earlier native backend comparisons: **6 passed** again.
- Syntax parsing: **all 39 QML files passed**. Quickshell modules are unavailable,
  so this is syntax-only, not full QML API/type validation.
- The affected notification and preview rendered subtrees remain byte-identical
  to the preceding release. The other two edited QML files are service logic.
- All 31 SVG assets and all 11 supplied JSON files remain byte-identical.

The eight implementation files changed are ClipboardService.qml,
NotificationService.qml, RecorderService.qml, TaskPreview.qml, and the Rust
backend, desktop, devices and preview modules. Focused Rust tests are included;
external analysis scripts are not shipped. The project remains QML + Rust only,
with no new crate, service, persistent process or QML Timer declaration.

The new stripped x86-64 GNU/Linux release binary is 976,392 bytes, versus 974,400
bytes in the preceding release. See README for target ABI/build instructions.
No new idle CPU/RAM benchmark is claimed for this patch. Existing benchmark files
and the optimization report describe the earlier optimization snapshot.

## Remaining limits and known issues

This is not a claim that the rice is bug-free. A live Labwc/Quickshell session,
PipeWire graph, recorder, D-Bus services and reference screenshots are unavailable
here. The monitor recovery changes in particular still need live disconnect and
reconnect tests. There is no certified pixel-by-pixel comparison.

The broader roadmap still contains unresolved work: workspace 10–16 action
coverage, clipboard pinned-image/cache retention and queued-delete races,
startup file-repair/loading coordination, notification replacement/withdrawal,
confirmed session-lock protection, multi-monitor ownership and precise recorder
failure/pause acknowledgment. Preview filenames now agree, but identical titles
or sanitized-name collisions still need stable compositor identifiers; this
patch does not claim to solve those collisions. A window can also close after
discovery while external captures are in progress; grim failure handling remains
necessary.

Recorder elapsed display retains one-second granularity; this patch fixes its
pause gating, not the recorder protocol or subsecond duration accounting.
These remaining issues require additional state/protocol work or target-session
evidence and are not represented as completed fixes.

The older audit/roadmap documents are retained as dated engineering snapshots.
This report and docs/verification/bughunt-* describe the follow-up fixes. Normal
installation is the same as before: replace the configuration contents, keep
weylume-native executable beside shell.qml, preserve newer personal JSON state,
and rebuild on the target if its architecture/libc differs.
