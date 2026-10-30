# Weylume — QML + Rust refactor

The supplied Weylume design is retained. The rice's own implementation is QML
and Rust; there are no Python, standalone JavaScript, shell, C or C-header source
files in this package. QML's embedded expressions remain part of QML.

**Validation status:** release build, Rust tests, QML syntax checks and native
D-Bus/Wayland protocol fixtures passed. The 33 approved additions and their
remaining target checks are in `docs/33_IMPLEMENTATION_REPORT.md`. The supplied
assets and theme are byte-identical to the previous archive. Pixel-for-pixel
rendering and live interaction still require verification on your Labwc session.

## Install

1. Back up your current `~/.config/quickshell/weylume` directory.
2. Copy the contents of this `weylume` directory into its place. Keep the supplied
   JSON files if you want the uploaded state; preserve newer local JSON files
   if you have changed settings since making the archive.
3. Ensure `weylume-native` is executable and sits beside `shell.qml`.
4. Reload with the command normally used by your Labwc session.

The included release executable targets **x86-64 GNU/Linux** and was built on
Ubuntu 24.04 (glibc 2.39). Rebuild on the target machine if its ABI differs.
It dynamically links systemd, udev, GLib/GIO and Wayland client libraries.
The optional audio profile/port editor loads `libpulse.so.0` only when opened.
These normally already exist on the intended Arch/CachyOS desktop.

To rebuild from the included Rust source, run from this directory:

```sh
cargo build --release --locked --manifest-path native/Cargo.toml
cp native/target/release/weylume-native ./weylume-native
chmod +x ./weylume-native
```

These are installation commands, not shipped shell scripts. Cargo/Rust and a
system linker are build requirements; no compiler is required at runtime.
The binary must be copied beside `shell.qml`: state-file paths are resolved
relative to the executable, just as the old helpers used their script directory.

Run the isolated Rust tests with:

```sh
cargo test --locked --manifest-path native/Cargo.toml
```

The configuration still targets the original Quickshell 0.3.x APIs and Labwc.
The archive does not include your Labwc `rc.xml`, environment, menu or autostart.
If those files refer to the removed helpers, update those external references:

| Original invocation | Replacement |
|---|---|
| `python3 system_helper.py ARGS` | `weylume-native ARGS` |
| `python3 desktop_helper.py ARGS` | `weylume-native desktop ARGS` |
| `weylume_backend` | `weylume-native backend` |
| `weylume_previews` | `weylume-native previews` |
| `python3 scripts/clipboard_capture.py` | `weylume-native clipboard-capture` |
| `python3 device_monitor.py` | Remove that separate autostart entry; monitoring is inside the backend. |

Use the actual absolute configuration path in external compositor bindings.
All references inside the supplied QML have already been updated.

## Runtime scope

- One resident native backend handles metrics, desktop filesystem events,
  udev device events, NetworkManager signals and asynchronous gamma writes.
  Gamma writes use the existing one-shot fallback until the backend is ready
  or when the service fails. No extra service unit is added.
- Clipboard history uses the existing `wl-paste --watch` architecture and a
  compiled one-shot encoder. Its previously missing capability is now detected.
- Native Quickshell PipeWire objects handle ordinary volume/mute writes.
- NetworkManager snapshots, saved Wi-Fi/VPN authentication, power profiles,
  output management and calendar parsing use bounded native calls. Audio
  profile/port details are loaded on demand. Existing audio routing fallbacks,
  screenshots, recording and user-selected applications retain their utilities.
- Start Menu command mode still invokes `sh -lc`. Desktop “Run in Terminal”
  still uses Python or sh for a **user-selected external script**. These are
  preserved user features, not implementation helpers; installing Python is no
  longer required to run the rice itself.

## Reports

- `docs/FURTHER_OPTIMIZATION_REPORT.md`: latest optimization, measurements,
  regression results and explicit validation limits.
- `docs/33_IMPLEMENTATION_REPORT.md`: all 33 items, measured changes, evidence,
  known limits and the final seven-category review.
- `docs/TARGET_ACCEPTANCE.md`: reproducible on-machine acceptance checklist.
- `docs/CURRENT_ROADMAP.md`: historical recommendations that prompted this work.
- `docs/SECOND_OPTIMIZATION_AUDIT.md`: audit before this optimization pass.
- `docs/BUGFIX_REPORT.md`: preceding bug-hunt fixes and validation.

- `docs/OPTIMIZATION_AUDIT.md`: audit recorded before source modifications.
- `docs/AUDIT_AND_IMPLEMENTATION.md`: changes, exact metrics, verification and
  live-session acceptance steps.
- `docs/PERFECTION_REVIEW.md`: separate seven-category roadmap; additions were
  not automatically implemented.
- `docs/FILE_REVIEW.md`: per-file disposition, dependency inventory and timer review.
- `docs/verification/`: machine-readable results and checksums.
