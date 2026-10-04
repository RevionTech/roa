# Architecture

| Module | Responsibility |
| --- | --- |
| `ROACore` | Versioned JSON models, heartbeat freshness and deterministic safety policy |
| `ROAMac` | Bounded file IPC, battery/thermal sampling, console-user checks and fixed-argument power commands |
| `ROAApp` | AppKit menu, confirmed status, OFF-before-quit/update coordination and Sparkle |
| `ROACLI` | Request writing, acknowledgement waiting and human/JSON status |
| `ROAService` | Root daemon, persisted safety/controller faults and power reconciliation |

Sparkle is pinned in `Package.swift` and `Package.resolved`; only the app links it.
The core policy and root service do not perform network operations. Bundle and
launchd identifiers use the company namespace `net.reviontech.roa`.

## Control and privilege boundary

The installing account atomically writes a bounded request under
`/var/db/net.reviontech.roa/<uid>/request.json`. Every explicit command creates a
new UUID. The root daemon samples once per second, evaluates guards and publishes
root-owned status at `/var/run/net.reviontech.roa/status.json`. Clients require a
fresh heartbeat, matching component version and confirmed power state.

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
- [Sparkle package updates](https://sparkle-project.org/documentation/package-updates/)
