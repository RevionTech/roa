# Verification

`swift test` exercises deterministic policy, persisted faults, invalid telemetry,
heartbeat freshness, file ownership/types/permissions, bounded writes and power
output parsing. Tests never install services or change power. CI runs repository
validation, XCTest, universal compilation/signature checks and CLI smoke tests.

## Manual acceptance on a MacBook

1. Install the signed PKG from GitHub; verify app/CLI/service versions match,
   both jobs run and `roa status` is OFF with `SleepDisabled 0`.
2. Enable from menu and CLI; confirm ACTIVE and `SleepDisabled 1`. Disable and
   confirm `SleepDisabled 0`. Quit ROA must confirm OFF before exiting.
3. Test lid closure on battery and AC with a timestamp-writing loop. Do not
   enclose the Mac during this test; stop the loop afterwards.
4. Restart with ON/OFF; verify owner login behavior. Log out / switch users;
   confirm release and restoration only for the installing account.
5. Naturally low battery (20% or lower) must block ON until explicitly retried
   after charging. Use injected unit samples for thermal states, not overheating.
6. Restart the helper in OFF and after a safety stop; verify persisted guards.
   Exercise failed power operations, status writes and guard persistence without
   letting a stale ON request silently re-arm after restart.
7. Use **Check for Updates…** from the prior notarized release. Install a higher
   build from the signed feed, verify relaunch, matching versions and OFF. Check
   cancellation, invalid signatures, interrupted download and failed installation.
8. Uninstall; confirm normal sleep, absent launch jobs/helper/app/CLI/state,
   cleared update preferences/caches and removed package receipt.

Universal compilation does not establish physical behavior on Intel, another
macOS version or another Mac. Record acceptance evidence privately; avoid local
machine details and internal audit reports in the public source repository.
