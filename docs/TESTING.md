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
4. Restart with ON/OFF; verify sleep prevention stays OFF until explicitly enabled,
   with Start at Login both checked and unchecked. Log out / switch users;
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
   cleared update preferences/caches, Telegram credentials and package receipt.
9. Start preset and custom timed sessions in minutes and hours. Confirm the
   countdown uses service-confirmed time, reaches zero and releases sleep. Stop
   the menu app unexpectedly while timing; expiry must still release the hold.
   Restart only the helper; an unexpired session must retain its original end.
   Change wall-clock time and verify the duration is unchanged. Unit tests cover
   the 1-minute/24-hour boundaries and malformed requests.
10. Confirm charging-only defaults off and supports ON on battery. Enable it,
    start on AC and unplug: sleep prevention must stop, and replug must not
    re-arm it. Retry explicitly on AC. Existing low-battery guards still apply.
11. Toggle Start at Login, quit/reopen, update and log in again. The choice must
    persist. Installation opens the app once even when login launch is disabled.
12. Compare Status & Diagnostics with `roa status --json`; copy diagnostics and
    verify no account names, paths, IDs or secrets. Check stale/version-mismatch
    reporting and countdown behavior while a menu/window is open.
13. Enable macOS notifications explicitly, including denial/revocation. Configure
    your Telegram bot in-app and press Test. Confirm expiry/guard/fault alerts are
    deduplicated and ordinary ON/OFF is silent. Exercise loss of network, provider
    rejection, redirect and timeout using mocks; none may change power control.
    Do not put a live bot token in tests, logs or issue reports.

Universal compilation does not establish physical behavior on Intel, another
macOS version or another Mac. Record acceptance evidence privately; avoid local
machine details and internal audit reports in the public source repository.
