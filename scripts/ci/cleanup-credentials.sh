#!/bin/bash
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "${RUNNER_ENVIRONMENT:-}" == github-hosted ]] || {
    echo 'Credential cleanup is restricted to GitHub-hosted Actions runners.' >&2; exit 64;
}
: "${RUNNER_TEMP:?This script requires a GitHub-hosted runner.}"
KEYCHAIN="$RUNNER_TEMP/roa-release.keychain-db"
if [[ -f "$KEYCHAIN" ]]; then security delete-keychain "$KEYCHAIN"; fi
rm -rf "$RUNNER_TEMP/roa-credentials"
rm -f "$RUNNER_TEMP/roa-sparkle-signing.key"
# Sparkle may explicitly store its item in the runner's login Keychain.
security delete-generic-password -s 'https://sparkle-project.org' -a roa-revion >/dev/null 2>&1 || true
