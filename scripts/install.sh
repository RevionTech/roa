#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for argument in "$@"; do
    case "$argument" in
        --prebuilt|--migrate-travel) ;;
        --dry-run)
            echo 'Install a signed, notarized ROA package in /Applications.'
            echo 'Install app, CLI and root service together. Start OFF.'
            exit 0 ;;
        *) echo 'Usage: ./scripts/install.sh [--prebuilt] [--migrate-travel] [--dry-run]' >&2; exit 64 ;;
    esac
done
[[ "$(uname -s)" == Darwin && "$EUID" -ne 0 ]] || exit 64
VERSION="$("$ROOT/dist/roa" version)"
PACKAGE="$ROOT/dist/ROA-$VERSION-universal.pkg"
/usr/sbin/pkgutil --check-signature "$PACKAGE"
/usr/sbin/spctl --assess --type install "$PACKAGE"
exec /usr/bin/sudo /usr/sbin/installer -pkg "$PACKAGE" -target /
