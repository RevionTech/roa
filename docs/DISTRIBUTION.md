# Distribution

ROA releases are universal Developer ID signed, notarized PKGs. Users install
with macOS Installer and update through **Check for Updates…**. Administrator
authorization is required. Installation finishes OFF and confirms matching
app/CLI/service versions. Intel/macOS 13 and physical lid behavior require their
own acceptance testing; universal compilation alone is insufficient.

The package fixes the app location to `/Applications/ROA.app`. Bundle relocation
is disabled, so other copies (including a developer's `dist/ROA.app`) never change
the installation destination. Existing app contents are replaced atomically.

## Release maintenance

Increase `ROAConstants.version`, `CFBundleShortVersionString` and the monotonically
increasing `CFBundleVersion`. Keep the Sparkle public key and application
identifier stable across updates. Never replace an existing published artifact.

```sh
swift test
python3 tools/validate.py
ROA_SIGNING_IDENTITY="Developer ID Application: Revion Tech OU (4WP3NZ2BN9)" \
ROA_INSTALLER_IDENTITY="Developer ID Installer: Revion Tech OU (4WP3NZ2BN9)" \
ROA_NOTARY_PROFILE="roa-revion" ./scripts/notarize.sh

ROA_SPARKLE_TOOLS="/path/to/Sparkle-distribution" ./scripts/publish-update.sh
```

The first script builds both architectures, removes local debug paths from ROA
executables, signs every nested executable,
notarizes the app/binaries, staples the app, builds the signed PKG, notarizes and
staples the package, verifies Gatekeeper and writes a portable SHA-256 checksum.
Notary results/logs are generated in ignored `dist/`. Investigate failures before
publishing; interrupted submissions must be resumed/inspected with `notarytool`.

The second script uses the organization-specific Keychain account `roa-revion`
for Sparkle, checks that its public key matches the app, signs the PKG and emits
a signed latest-only `updates/appcast.xml`. Upload the PKG/checksum to the matching
GitHub release **before** publishing the feed. The public feed never contains
private keys. It must be regenerated and signed after changes; do not edit signed
XML manually. Forks must configure their own feed, update key, identifiers and
Developer ID team (`ROA_RELEASE_TEAM`).

Keep the EdDSA private key safe: package updates have no automatic fallback for
lost/rotated signing keys. Losing it may require a manually installed replacement
release. Keep Apple Application and Installer private keys outside the repository.

## Acceptance

Test a notarized installed release. Check that the app offers the next version,
verifies its package, prompts for authorization, restarts successfully and updates
all three components. Confirm OFF, then exercise ON/OFF. Delete retired releases,
assets and tags only after validating the replacement. Do not publish unsigned
CI artifacts as releases.
