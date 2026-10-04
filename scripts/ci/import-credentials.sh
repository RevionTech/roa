#!/bin/bash
set -euo pipefail
set +x
umask 077
[[ "${GITHUB_ACTIONS:-}" == true && "${RUNNER_ENVIRONMENT:-}" == github-hosted ]] || {
    echo 'Credential import is restricted to GitHub-hosted Actions runners.' >&2; exit 64;
}
: "${RUNNER_TEMP:?This script requires a GitHub-hosted runner.}"
: "${ROA_SPARKLE_TOOLS:?Download verified Sparkle tools first.}"
for name in ROA_APPLICATION_P12 ROA_APPLICATION_P12_PASSWORD ROA_INSTALLER_P12 \
    ROA_INSTALLER_P12_PASSWORD ROA_NOTARY_KEY ROA_NOTARY_KEY_ID ROA_NOTARY_ISSUER_ID ROA_SPARKLE_KEY; do
    [[ -n "${!name:-}" ]] || { echo "Missing release environment secret: $name" >&2; exit 1; }
done
SECRET_DIR="$RUNNER_TEMP/roa-credentials"
mkdir -m 700 "$SECRET_DIR"
KEYCHAIN="$RUNNER_TEMP/roa-release.keychain-db"
KEYCHAIN_PASSWORD="$(openssl rand -hex 32)"
echo "::add-mask::$KEYCHAIN_PASSWORD"
printf '%s' "$ROA_APPLICATION_P12" | base64 --decode > "$SECRET_DIR/application.p12"
printf '%s' "$ROA_INSTALLER_P12" | base64 --decode > "$SECRET_DIR/installer.p12"
printf '%s' "$ROA_NOTARY_KEY" | base64 --decode > "$SECRET_DIR/notary.p8"
printf '%s' "$ROA_SPARKLE_KEY" > "$SECRET_DIR/sparkle.key"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security list-keychains -d user -s "$KEYCHAIN"
security default-keychain -d user -s "$KEYCHAIN"
security import "$SECRET_DIR/application.p12" -P "$ROA_APPLICATION_P12_PASSWORD" \
    -k "$KEYCHAIN" -T /usr/bin/codesign >/dev/null
security import "$SECRET_DIR/installer.p12" -P "$ROA_INSTALLER_P12_PASSWORD" \
    -k "$KEYCHAIN" -T /usr/bin/productsign -T /usr/bin/pkgbuild >/dev/null
security set-key-partition-list -S apple-tool:,apple: -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
xcrun notarytool store-credentials roa-ci --key "$SECRET_DIR/notary.p8" \
    --key-id "$ROA_NOTARY_KEY_ID" --issuer "$ROA_NOTARY_ISSUER_ID" --keychain "$KEYCHAIN" >/dev/null
"$ROA_SPARKLE_TOOLS/bin/generate_keys" --account roa-revion -f "$SECRET_DIR/sparkle.key" >/dev/null
EXPECTED="$(plutil -extract SUPublicEDKey raw -o - Resources/Info.plist)"
ACTUAL="$("$ROA_SPARKLE_TOOLS/bin/generate_keys" --account roa-revion -p)"
[[ "$EXPECTED" == "$ACTUAL" ]] || { echo 'Sparkle key does not match the installed update trust key.' >&2; exit 1; }
echo "ROA_NOTARY_KEYCHAIN=$KEYCHAIN" >> "$GITHUB_ENV"
rm -rf "$SECRET_DIR"
echo 'Release credentials imported; temporary input files removed.'
