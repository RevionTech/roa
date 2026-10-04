#!/bin/bash
set -euo pipefail
: "${RUNNER_TEMP:?This script requires a GitHub-hosted runner.}"
ARCHIVE="$RUNNER_TEMP/Sparkle-2.10.0.tar.xz"
curl --fail --location --proto '=https' --tlsv1.2 --retry 3 \
    https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz \
    --output "$ARCHIVE"
printf '%s  %s\n' c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c "$ARCHIVE" | shasum -a 256 -c -
mkdir -p "$RUNNER_TEMP/roa-sparkle"
tar -xf "$ARCHIVE" -C "$RUNNER_TEMP/roa-sparkle"
[[ -x "$RUNNER_TEMP/roa-sparkle/bin/sign_update" ]]
echo "ROA_SPARKLE_TOOLS=$RUNNER_TEMP/roa-sparkle" >> "$GITHUB_ENV"
