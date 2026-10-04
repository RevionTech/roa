# Contributing

Use macOS 13+ with Swift 5.9+ / Apple Command Line Tools. Open `Package.swift`
in Xcode or use `swift test` and `./scripts/build.sh`. Keep power decisions in
`ROACore`, platform APIs in `ROAMac`, UI in `ROAApp`, and privileged orchestration
in `ROAService`. Preserve the fixed-command boundary and fail-closed behavior.

Before a pull request, run the development commands in the README. Add meaningful
tests for changes to safety policy or file IPC. Test real power transitions on a
MacBook only when a change affects them; describe the Mac/OS and results. Never
add a test that changes a CI runner's system sleep state.

Keep code and documentation in English, use four-space Swift indentation, and
avoid new dependencies unless they solve a concrete problem. Explain the user
visible change and how it was verified in the pull request. Contributions are
licensed under MIT, as is the rest of the project.

Swift types and module directories use UpperCamelCase; commands, shell scripts
and tooling use lowercase names. Keep identifiers under `net.reviontech.roa` and
avoid case-only filename differences. Source assets live in `Assets/`, bundle
metadata in `Resources/`, generated output in ignored `dist/` and `.build/`.
Keep local installation logs, backups and signing credentials out of commits.

Published prereleases are immutable: describe new work in
`CHANGELOG.md`, and keep release verification and signing separate from the
ad-hoc CI bundle. Never publish ad-hoc development artifacts as production releases.

## Repository automation

Each pull request targeting `main` runs CI once. Merging runs CI again on the
integrated `main` commit. Static checks and automation tests run on Linux;
Swift tests and the universal build run on macOS when changes affect anything
other than Markdown documentation or `LICENSE`. The required `CI result` check
fails if any applicable job fails or is cancelled. Development builds are not
uploaded as artifacts.

Dependabot groups GitHub Actions updates into one weekly maintenance pull request.
These updates change build tools, not the installed ROA application. Review major
version changes and wait for CI before merging; updates are not auto-merged.
Actions are pinned to full commit hashes. External contributors' workflow runs
require maintainer approval, and pull request workflows have read-only tokens
without release secrets.

`main` requires review, resolved review conversations, passing CI and linear
history. Use squash merges. Release signing is a separate, manually dispatched
workflow with protected environment approval; a merge does not publish an update.
