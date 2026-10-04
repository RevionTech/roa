<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Assets/logo-light.svg">
  <img src="Assets/logo.svg" alt="ROA" width="200">
</picture>

# ROA

**Run. On. Anywhere.**

A native macOS menu bar utility by **Revion Tech** that keeps your MacBook
working with the lid closed, including on battery. Left-click to toggle ROA;
right-click for controls. A solid icon indicates confirmed sleep prevention;
a faded icon with `!` indicates a safety stop or unavailable service.

## Install

Requires a MacBook running **macOS 13+** and an administrator account. Download
`ROA-<version>-universal.pkg` and its SHA-256 checksum from the
[latest release](https://github.com/RevionTech/roa/releases/latest).
Open the package and follow macOS Installer. Intel and Apple Silicon are
included; development tools are not required.

Installation adds `/Applications/ROA.app`, a root-owned power service and a
login agent for the installing account. ROA starts **OFF**. Only that account
controls the service; install/update while logged into it. **Start at Login** is
optional and initially off. Installation opens ROA once; subsequent logins follow
your choice. Updates preserve this preference.

The CLI is linked at `~/.local/bin/roa`. If needed, add
`export PATH="$HOME/.local/bin:$PATH"` to `~/.zshrc`.

## Use

```sh
roa on
roa on --minutes 30
roa on --hours 2 --charging-only
roa off
roa toggle
roa status
roa status --json
```

Choose **Turn On for…** for 15/30 minutes, 1/2 hours, or **Custom…** with a
minute/hour value from 1 minute to 24 hours. A countdown appears beside the menu
bar icon during a confirmed timed session. The service ends the session even if
the menu app stops running. Ordinary **Turn On** runs until explicitly stopped
or a guard trips. Changing the system clock does not extend a timed session.

**Only While Connected to Power** is optional and initially off: ROA supports both battery
and AC by default. With it enabled, unplugging stops the session; reconnecting
does not silently restart it. Power policy changes apply to the next session.

**Start at Login** opens the menu app without turning sleep prevention on.
After a Mac restart, ROA requires an explicit **Turn On**, even if it was ON
before shutdown or the menu app never opens. A service restart within the same
boot can continue an unexpired session; the timer is not reset.

Choose **Status & Diagnostics…** for confirmed power state, app/service versions,
battery/power source, thermal pressure, remaining time and the last stop reason.
**Copy Diagnostics** excludes account names, local paths and notification secrets.

Choose **Turn On** to retry after a safety stop. Battery cutoff is **20%** on
battery; serious/critical thermal pressure also stops sleep prevention. Safety
stops persist across service restarts until explicitly retried. Control errors
require OFF, then ON. Logout / user switching releases the hold until the
installing account is active again. **Quit ROA** confirms OFF before exiting.

ROA owns the global `pmset -a disablesleep` setting, which also blocks manual
system sleep while ON. Use one sleep-management utility at a time. Guards
reduce risk but do not make heavy workloads in an enclosed bag safe. Network
changes may interrupt connections; ROA does not reconnect applications.

## Updates and privacy

Choose **Check for Updates…** in the menu. **Automatically Check for Updates**
is optional and disabled initially. Sparkle verifies the signed update feed and
package before installation. Every update requires administrator authorization,
updates app/CLI/service together, restores normal sleep and finishes OFF.
Only the current release is offered; downloaded packages can also be installed
manually. See [distribution and release maintenance](docs/DISTRIBUTION.md).
Maintainers can build signed releases on GitHub using the protected
[release automation workflow](docs/RELEASE_AUTOMATION.md).

Power control has no network dependency. Update checks contact GitHub; macOS
may contact Apple for signature/notarization verification. ROA has no analytics,
account system or system-profile reporting. Optional **Notifications…** can
notify you about session expiry, safety stops and service problems through macOS
and Telegram. Both channels start disabled. Telegram uses your own bot; its
credentials stay in your macOS Keychain. ROA sends only short event messages to
the configured chat. Notifications require the menu app to be running and remote
delivery requires connectivity; they never control the power service. See
[notification setup and privacy](docs/NOTIFICATIONS.md).

Sparkle is the only external runtime
dependency; its license is included in [Sparkle-LICENSE.txt](Assets/Sparkle-LICENSE.txt).

## Uninstall / recover

From a source checkout, run as the installing account:

```sh
./scripts/uninstall.sh

# Emergency recovery if the service is unavailable:
sudo /usr/bin/pmset -a disablesleep 0
```

Uninstall removes the app, CLI link, launch jobs, power service, state,
preferences, update caches and package receipt. It restores normal sleep.

## Development

Requires macOS, Swift 5.9+ / Command Line Tools, and internet access to resolve
the pinned Sparkle package. Development bundles are ad-hoc signed.

```sh
swift test
ROA_UNIVERSAL=1 ./scripts/build.sh
python3 tools/validate.py
```

These commands do not install the service or change system power. Release
installation uses the signed, notarized PKG. See [architecture](docs/ARCHITECTURE.md),
[contributing](CONTRIBUTING.md), [security](SECURITY.md) and
[manual acceptance tests](docs/TESTING.md).

## License

[MIT](LICENSE) for ROA code and branding. Sparkle retains its included license.
