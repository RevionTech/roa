# Security policy

## Supported versions

Security fixes target the latest release and source on `main`. Published PKGs
contain company-signed, notarized universal binaries; development bundles use
ad-hoc signatures. Sparkle verifies signed update feeds/packages. Notarization
does not replace code review, failure testing or target-device acceptance.

## Reporting a vulnerability

Use [GitHub private vulnerability reporting](https://github.com/RevionTech/roa/security/advisories/new).
Do not disclose exploit details in a public issue before maintainers have
investigated. Include the affected commit, macOS version, reproduction steps,
and expected versus observed behavior. Never include passwords or access tokens.

For privileged file handling, installation, and power-control boundaries, see
[architecture](docs/ARCHITECTURE.md). A fresh ACTIVE status confirms the observed
power setting; it does not certify safe operation inside an enclosed bag.
