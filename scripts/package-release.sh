#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${ROA_INSTALLER_IDENTITY:?Set a Developer ID Installer signing identity.}"
"$ROOT/scripts/verify-release.sh"
VERSION="$("$ROOT/dist/roa" version)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/roa-package.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/payload/Applications" "$TMP/payload/Library/PrivilegedHelperTools"
/usr/bin/ditto "$ROOT/dist/ROA.app" "$TMP/payload/Applications/ROA.app"
/usr/bin/install -m 755 "$ROOT/dist/roa-service" "$TMP/payload/Library/PrivilegedHelperTools/roa-service"
/usr/bin/pkgbuild --root "$TMP/payload" --identifier net.reviontech.roa.installer \
    --component-plist "$ROOT/Resources/package-components.plist" \
    --version "$VERSION" --install-location / --ownership recommended \
    --scripts "$ROOT/scripts/pkg" --sign "$ROA_INSTALLER_IDENTITY" \
    "$ROOT/dist/ROA-$VERSION-universal.pkg"
/usr/sbin/pkgutil --check-signature "$ROOT/dist/ROA-$VERSION-universal.pkg"
echo 'Package created; notarize and staple it before publication.'
