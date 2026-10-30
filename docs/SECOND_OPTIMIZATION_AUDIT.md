# Further optimization audit — 2026-09-28

Baseline: the saved bug-fix release, version 2 of weylume.zip. Preserve visual
objects, assets, stored JSON, animation/timer cadence and user action results.
No target Labwc/Wayland session is available. Changes below require focused
regression tests and measurements before being kept.

| Remaining cost | Planned treatment | Preservation boundary |
|---|---|---|
| Each brightness/temperature write starts a native helper and opens a D-Bus connection | Send asynchronous property writes through the existing backend, with acknowledgments and existing one-shot fallbacks | Same rounded values, coalescing and failure policy; do not block metric/event processing |
| Taskbars repeat audio node string normalization per application and per screen | Prepare matching records once in AudioService, keep matching rules/order unchanged | Do not cache mute/volume or hold removed native objects beyond the current model |
| Four audio categories independently traverse all PipeWire nodes | One classification pass supplying the existing four arrays | Preserve media-class tests, corked filtering and device sorting |
| Clipboard image capture stats every cached image even when below its 100-file eviction threshold | Use directory entry file types; fetch timestamps only when eviction is required | Preserve filenames, cap, sort/tie rules and image payloads |
| Rejected large text can allocate an image-sized buffer | Bound text retention while consuming the same bounded input; preserve image limits | Same accepted/rejected payloads and no change to sensitive data handling |
| Repeated executable path discovery during native state operations | Cache the immutable executable directory within a process | No cache of mutable file contents or command availability |
| Child stdout/stderr are copied even when valid UTF-8 | Take ownership of valid output buffers; retain lossy decoding for invalid bytes | Same returned strings and status |
| Device and /proc sample parsing allocate intermediate collections | Simplify only where protocol-equivalence tests and measurements justify it | Same sampling, formatting and values |
| Network refreshes still spawn multiple nmcli queries | Keep compatibility path in this pass unless native equivalents can be validated | No guessed formatting, profile ordering or NetworkManager behavior |
| All-window preview capture remains expensive | Keep current capture policy pending live comparison | Avoid changing thumbnail freshness, capture order or hover behavior |

This pass will not claim a universal maximum or a desktop RAM/CPU reduction from
static source counts. Report measured helper/model work separately from the
unavailable complete desktop measurement. No feature removal or visual redesign.
