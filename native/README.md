# Native helper

`weylume-native` is one release Rust executable with subcommands, not a new
resident service. The existing event-driven backend remains the sole native
backend process. Its Linux `poll` loop handles stdin, D-Bus, udev, inotify,
gamma replies and metric deadlines. A one-shot worker isolates slow filesystem
queries only when the disk view requests them. Optional output, pairing,
network-secret, calendar and audio operations run on explicit actions.

The five direct crates remain `libc`, `serde_json`, `xmltree`, `sha2` and
`base64`. No async runtime, interpreter or generated C source ships. On-demand
modules are `audio.rs` (PulseAudio profiles and ports), `bluetooth.rs` and
`network_agent.rs` (temporary D-Bus authentication agents), `calendar.rs`,
`disk_worker.rs`, `diagnostics.rs`, `outputs.rs`/`output_protocol.rs` and
`wayland.rs`. The existing backend and system/desktop/preview/clipboard modules
remain focused on their original work and the approved improvements.

Build from the parent directory using the commands in the main README. The
release profile uses optimization level 3, LTO, one codegen unit, stripped
symbols and abort-on-panic. The supplied executable targets generic x86-64
GNU/Linux; its highest glibc symbol requirement is 2.39. It dynamically links
`libsystemd.so.0`, GLib/GIO/GObject, `libudev.so.1` and
`libwayland-client.so.0`. `libpulse.so.0` is loaded only when the optional
audio detail editor is invoked. Capture and launch tools are feature-specific
external dependencies, not shipped implementation languages.

Linux 5.3+ is required for pidfd child waiting. Bounded child output is capped
at 4 MiB per stream; timed-out process groups are killed and reaped. User
applications and clipboard owners remain independent. The Wayland protocol
license is in `PROTOCOL_LICENSE.md`; crate licenses are in `LICENSES/`.

Run `weylume-native diagnostics` for on-demand capabilities and
`weylume-native profile PID SECONDS` for a single-process `/proc` sample on the
target. That sample reports context switches, not kernel CPU wakeups. Target
hardware and Quickshell rendering remain unverified by the packaged tests.
