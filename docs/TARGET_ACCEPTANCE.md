# Weylume target-session acceptance

Run these in the real CachyOS Labwc + Quickshell 0.3.x session before treating
visual equality, security and device behavior as confirmed. Back up the prior
configuration and record which Quickshell/Labwc/output protocol versions are
advertised. The attached archive cannot inspect the user's separate Labwc
`rc.xml`, autostart, launcher, locker, permission agent or environment.

1. Build compatibility: `file weylume-native` and `ldd weylume-native`; it is x86-64
   glibc 2.39, with optional `libpulse.so.0` for audio details. In Settings →
   Integrations run **Run diagnostics**. Launch with the session's normal
   command. Deliberately temporarily make a test copy's binary non-executable
   to verify the visible startup error, then restore it.
2. Pixel/input comparison: take identical screenshots with the old and new
   configurations at native resolution and scale while animations are settled;
   compare pixels in a tool that ignores PNG metadata. Inspect Start Menu,
   taskbar, desktop, Quick Settings, sidebar, system monitor, mixer, clipboard,
   notifications, settings, wallpaper, hover and animation timing. Repeat for
   mixed DPI and negative-origin monitors. Exercise Escape, Tab, arrows,
   Return, touch/long press, click and cancel/drag-outside, then remove a screen
   while a popup is open. New Integrations controls are intentionally additive.
3. Session security: verify that Labwc actually starts a secure Wayland locker
   when logind sends `Lock` and that `LockedHint` becomes true **only after**
   lock acquisition. Test lock failure: suspend must stop. Query real logind
   permissions and inhibitors and test suspend/hibernate/shutdown/reboot as
   appropriate. Check crash behavior, restart and Polkit prompts.
4. Displays and gaming: save a profile, apply then Keep; repeat with Revert,
   no confirmation for 15 seconds, hotplug while applying and shell crash.
   Exercise scale, rotation, negative coordinates and VRR only if advertised.
   Test ambiguous dock profiles (no auto guess), game start/exit, rule edits,
   manual override, unexpected shell exit and prior power/tearing/output restore.
   Verify Labwc reconfigure applied the XML or that a restart is needed.
5. Network and Bluetooth: confirm Unicode/colon SSID, saved PSK, wrong secret,
   cancellation, EAP certificate/domain, VPN connection/failure and actual IP,
   DNS and connectivity updates. Test available adapters, PIN/passkey and code
   confirmation, cancellation, explicit trust and disappearing device. Use a
   disposable pairing target and test the backend's real challenge path.
6. Audio and media: route an already playing stream to another sink, select an
   HDMI/headset profile and input/output port, unplug and verify actual defaults.
   Verify microphone/speaker volume and mixer feedback. Record to MKV/MP4,
   pause/resume and stop, verify the container opens and contains frames. Test
   denied portal, encoder crash, disk-full and suspend inhibitor. Check screenshot
   window selection, Escape, and selected-window identity.
7. Data and resume: pin an image, fill the clipboard quota, restart and confirm
   all pinned payloads survive; confirm history eviction deletes only unowned
   data. Test duplicate/replacement/withdrawal/reload notifications and actions.
   Import calendar ICS with timezone/all-day events, unsupported RRULE and
   malformed rows. Test reminder acknowledgement, service failure, suspend and
   time-zone change. Test network mount delay and its stale-drive feedback.
8. Resource comparison: measure Quickshell plus its native backend and
   `wl-paste --watch` together at startup, several minutes idle, open panels,
   large histories and while gaming. Record per-process RSS, CPU time, actual
   wakeups and child-spawn/IPC counts on the target. `weylume-native profile PID 30`
   provides a bounded single-PID `/proc` sample; its context-switch count is
   not a wakeup counter. Repeat multiple times to avoid overinterpreting the
   small isolated sample in `33_IMPLEMENTATION_REPORT.md`.

Acceptance is complete only when these observations exist. The optional portal
backend and locker integration require access to the real user's session; the
portable portal ScreenCast interface does not expose other clients' sessions.
