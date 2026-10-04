# Architecture

| Module | Responsibility |
| --- | --- |
| `ROACore` | Versioned JSON models, heartbeat freshness and deterministic safety policy |
| `ROAMac` | Bounded file IPC, boot identity, power sampling, login preferences, notification transport/Keychain and fixed-argument power commands |
| `ROAApp` | AppKit menus/windows, countdown, diagnostics, optional notifications, OFF-before-quit/update coordination and Sparkle |
| `ROACLI` | Request writing, acknowledgement waiting and human/JSON status |
| `ROAService` | Root daemon, persisted safety/controller faults and power reconciliation |

Sparkle is pinned in `Package.swift` and `Package.resolved`; only the app links it.
The core policy and root service do not perform network operations. Bundle and
launchd identifiers use the company namespace `net.reviontech.roa`.

## Control and privilege boundary

The installing account atomically writes a bounded request under
`/var/db/net.reviontech.roa/<uid>/request.json`. Every explicit command creates a
new UUID. The root daemon observes the request directory for atomic file
replacements and evaluates new requests after a 50 ms event-coalescing delay.
Events are hints, never authorization: file ownership, permissions, schema and
safety policy are still validated. The once-per-second timer remains for guard
sampling, session expiry and fallback if monitoring is unavailable. The daemon publishes
root-owned status at `/var/run/net.reviontech.roa/status.json`. Clients require a
fresh heartbeat, matching component version and confirmed power state.

New requests use schema 2: old services reject them instead of silently ignoring
timer or charging restrictions. Schema 1 OFF requests remain readable for
recovery/migration; schema 1 ON is rejected. Status retains schema 1 with optional
fields and clients verify the service version before enabling a session.

The daemon's only child is `/usr/bin/pmset` with fixed arguments (`-g` or
`-a disablesleep 0/1`). It accepts no executable path or shell text from clients.
Reads reject symlinks, nonregular files, wrong ownership, writable permissions
and payloads larger than 8 KiB. Writes use exclusive temporary files, fsync and
atomic rename. A validated exclusive service lock prevents duplicate controllers.

Battery/thermal trips are persisted before enabling a hold. A new ON request
retries only when conditions permit. Control/status publication faults survive
restarts and need a new OFF request before ON. Unknown telemetry fails closed.
Power observation occurs immediately on target changes and every five seconds
while stable. Timeouts use monotonic uptime; status timestamps reject stale or
future heartbeats. Global sleep settings cannot safely be shared with another
sleep-management utility.

## Sessions, login and notifications

ON requests are bound to the current macOS boot session. The daemon releases
sleep prevention before its first evaluation and rejects ON from previous boots,
including legacy requests without a boot identity. Reboot recovery is independent
of the menu app and its launch-at-login preference. Invalid or unavailable boot
identity fails closed. OFF requests remain usable for recovery.

Timed requests carry a duration and monotonic start time. `mach_continuous_time`
includes time spent asleep and is independent of wall-clock adjustments; the
wire field `startedAtUptime` carries seconds from this continuous boot clock.
Durations must be
finite and between 60 and 86,400 seconds. The service computes remaining time;
restarting the helper within the same boot does not restart the timer. Expiry
latches a stop against the request UUID. Wall-clock changes cannot extend it.
Charging-only requests also latch a stop when AC power is removed; reconnecting
requires explicit re-arming. All existing battery and thermal guards still apply.

The user-owned login agent has no KeepAlive. Start-at-login is an explicit
preference, initially false, and changes take effect at the next login. Package
updates preserve that choice and open the app once after installing in OFF.

Notifications run in the unprivileged menu app. Opt-in macOS authorization and
optional Telegram delivery are independent of power control. Notification events
are deduplicated; normal ON/OFF commands do not generate messages. Telegram
credentials live in a namespaced Keychain item, never in request/status JSON,
diagnostics or preferences. Transport uses a fixed HTTPS host, an ephemeral
session, bounded responses/timeouts and rejects redirects. No messages are queued
for replay after a restart. See [setup and limits](NOTIFICATIONS.md).

## Installation and updates

The signed, notarized package installs `/Applications/ROA.app` and the separately
signed `/Library/PrivilegedHelperTools/roa-service`. The extensionless helper
filename is deliberate; its code identifier is `net.reviontech.roa.service`.
The CLI and matching helper also live inside the app bundle. The user CLI link
points into that bundle. Package scripts maintain user files with user credentials
and root/system files with root credentials; root never executes user-owned code.

The package serializes installation with a root lock, preserves the previous
app/helper/plist during a transaction, stops the daemon and confirms normal
sleep before replacement. It creates an OFF request, starts the new service,
verifies its version/acknowledgement and loads the login agent. Ordinary
postinstall failure attempts rollback in OFF; retained recovery data identifies
failed transactions. A crash during package extraction or failed rollback still
requires administrative recovery. Full crash durability is not guaranteed.

Sparkle downloads from a latest-only HTTPS appcast. The app embeds the public
Ed25519 key; private update keys remain in the maintainer's Keychain. Both feed
and package signatures are checked. All Sparkle nested executables/frameworks
are re-signed with the company Developer ID before notarization. PKG updates
require authorization and do not install silently. The app waits for OFF before
handing over update relaunch; package scripts independently enforce OFF.

The legacy `net.revion.roa` namespace is recognized only for removal/migration.
Installation remains limited to one active owner per Mac.

## Failure limits

SIGTERM/SIGINT attempts release; launchd restarts crashes and clears stale holds
on startup. SIGKILL, OS failure, disabled jobs or persistent launch/power errors
cannot guarantee immediate cleanup. Use the README recovery command.
Filesystem write failures prevent new holds but can prevent durable fault
recording; parent-directory crash durability is not explicitly synchronized.
Sampling/commands may be delayed by OS scheduling. Guards release the override;
they do not force sleep or guarantee enclosure thermal safety.

## References

- [Apple power sources](https://developer.apple.com/documentation/iokit/iopowersources_h)
- [Apple thermal state](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.property)
- [Apple continuous clock](https://developer.apple.com/documentation/kernel/1646199-mach_continuous_time)
- [Sparkle package updates](https://sparkle-project.org/documentation/package-updates/)

The menu app observes the root-owned status directory and refreshes when the
service publishes confirmation, avoiding a second polling delay. A pending
command displays an ellipsis immediately; active styling still requires a fresh,
compatible service confirmation. Its one-second timer remains for countdowns,
heartbeat freshness and fallback. Directory monitoring rejects symlinks, wrong
ownership and group/world-writable directories; it opens no privileged channel.
