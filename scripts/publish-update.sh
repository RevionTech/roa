#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${ROA_SPARKLE_TOOLS:?Set the Sparkle distribution directory containing bin/sign_update.}"
ACCOUNT="${ROA_SPARKLE_ACCOUNT:-roa-revion}"
VERSION="$("$ROOT/dist/roa" version)"
PACKAGE="$ROOT/dist/ROA-$VERSION-universal.pkg"
/usr/sbin/spctl --assess --type install "$PACKAGE"
EXPECTED="$(/usr/bin/plutil -extract SUPublicEDKey raw -o - "$ROOT/Resources/Info.plist")"
ACTUAL="$("$ROA_SPARKLE_TOOLS/bin/generate_keys" --account "$ACCOUNT" -p)"
[[ "$EXPECTED" == "$ACTUAL" ]] || { echo 'Sparkle signing key does not match the app.' >&2; exit 1; }
SIGNATURE="$("$ROA_SPARKLE_TOOLS/bin/sign_update" --account "$ACCOUNT" -p "$PACKAGE")"
python3 "$ROOT/tools/make-appcast.py" "$PACKAGE" "$SIGNATURE"
"$ROA_SPARKLE_TOOLS/bin/sign_update" --account "$ACCOUNT" "$ROOT/updates/appcast.xml"
"$ROA_SPARKLE_TOOLS/bin/sign_update" --account "$ACCOUNT" --verify "$ROOT/updates/appcast.xml"
echo 'Upload the package and checksum to its GitHub release, then publish updates/appcast.xml.'
