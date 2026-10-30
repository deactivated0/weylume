# Approved roadmap implementation: completed source pass

The user approved all 33 recommendations on 2026-09-29. Preserve the established
visual style while adding the specifically requested controls and recovery
behavior. Keep implementation in QML/Rust, bounded native operations and lazy
optional features. Baseline: delivered version 3.

1. Target acceptance: native preflight/profiling and a reproducible visual/input checklist; actual target results must not be invented.
2. Lock/suspend: require acknowledged locking, query logind, fail closed.
3. Workspaces 10–16: complete native activation and fallback actions/bindings.
4. Clipboard: one retention owner, pin protection, quota and generation-safe cleanup.
5. State loading: repair before singleton FileView loads.
6. Gaming/power: journal previous state, rollback and recovery.
7. Audio selection: actual defaults and completion/removal reset.
8. Notifications: replacement/withdrawal/expiry and stale-action ownership.
9. Hardware: discovered metrics and configured mount/label overrides.
10. Bluetooth: PIN/passkey/authorization/cancel/trust, adapter choice.
11. Battery: native UPower and peripheral details.
12. Screenshots: actual window selection and single cancellation path.
13. Audio profiles/ports: on-demand native controls.
14. Networking: native secrets/authentication, connectivity and VPN state.
15. Calendar: local import and deadline-driven reminders.
16. Keyboard: focus, search, Escape and restoration.
17. Touch/pointer: long-press, cancellation and drag safety.
18. Outputs: ownership, hotplug and mixed-DPI clamping.
19. Accessibility: names and clear unavailable states.
20. Native networking: remove routine nmcli snapshots with equivalent native data/actions.
21. Audio commands: remove redundant normal-path CLI work; retain only justified compatibility paths.
22. Previews: capture the requested group, bounded work and stable identities.
23. Large lists: profile/virtualize where justified, preserve focus and scroll.
24. Binary/framework: measure size and runtime; keep robust parsers.
25. Filesystem metrics: isolate and bound slow usage queries.
26. Preview identity: avoid title/filename collisions.
27. Recorder: acknowledge pause/exit/finalization and handle failures/suspend.
28. Capabilities/configuration: native permissions/inhibitors and transactional compositor writes.
29. Portability: dependency diagnostics and actionable startup failure.
30. Workspace state: native advertised protocol with fallback.
31. Per-game policies: event-driven allowlist, restoration and crash recovery.
32. Output profiles: native hotplug profiles and supported VRR/tearing policy.
33. Portal sharing: actual portal session lifecycle and reliable stop controls.

Implementation and validation status is recorded in `33_IMPLEMENTATION_REPORT.md`.
The on-machine checks are in `TARGET_ACCEPTANCE.md`. Hardware, compositor
protocol support and live service behavior remain target-validation gates, not
presumed successes. Portable cross-application portal revocation is a documented
platform limit and was not replaced by unsafe process termination.
