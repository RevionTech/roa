#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${ROA_SIGNING_IDENTITY:?Set a Developer ID Application signing identity.}"
: "${ROA_INSTALLER_IDENTITY:?Set a Developer ID Installer signing identity.}"
[[ "$ROA_SIGNING_IDENTITY" != - ]] || exit 64
PROFILE="${ROA_NOTARY_PROFILE:-roa-revion}"
ROA_UNIVERSAL=1 "$ROOT/scripts/build.sh"
ZIP="$ROOT/dist/ROA-notarize.zip"
rm -f "$ZIP"
/usr/bin/ditto -c -k --keepParent "$ROOT/dist/ROA.app" "$ZIP"
/usr/bin/zip -j "$ZIP" "$ROOT/dist/roa" "$ROOT/dist/roa-service"
submit() {
    local file="$1" result="$2"
    echo "Waiting for Apple notarization: $(basename "$file")"
    /usr/bin/xcrun notarytool submit "$file" --keychain-profile "$PROFILE" --wait --output-format json > "$result"
    local id status
    id="$(/usr/bin/plutil -extract id raw -o - "$result")"
    status="$(/usr/bin/plutil -extract status raw -o - "$result")"
    /usr/bin/xcrun notarytool log "$id" --keychain-profile "$PROFILE" "$result.log"
    [[ "$status" == Accepted ]] || { echo "Notarization failed: $status; see $result.log" >&2; exit 1; }
}
submit "$ZIP" "$ROOT/dist/notary-binaries.json"
/usr/bin/xcrun stapler staple "$ROOT/dist/ROA.app"
/usr/bin/xcrun stapler validate "$ROOT/dist/ROA.app"
"$ROOT/scripts/package-release.sh"
VERSION="$("$ROOT/dist/roa" version)"
PACKAGE="$ROOT/dist/ROA-$VERSION-universal.pkg"
submit "$PACKAGE" "$ROOT/dist/notary-package.json"
/usr/bin/xcrun stapler staple "$PACKAGE"
/usr/bin/xcrun stapler validate "$PACKAGE"
/usr/sbin/spctl --assess --type install --verbose=2 "$PACKAGE"
(cd "$ROOT/dist" && /usr/bin/shasum -a 256 "$(basename "$PACKAGE")" > "$(basename "$PACKAGE").sha256")
echo "Signed, notarized universal release: $PACKAGE"
