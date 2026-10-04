#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
team="${ROA_RELEASE_TEAM:-4WP3NZ2BN9}"
[[ "$team" =~ ^[A-Z0-9]{10}$ ]] || { echo "Invalid release Team ID." >&2; exit 64; }
requirement='=anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists'
for name in ROA.app roa roa-service; do
    case "$name" in
        ROA.app) identifier=net.reviontech.roa ;;
        roa) identifier=net.reviontech.roa.cli ;;
        roa-service) identifier=net.reviontech.roa.service ;;
    esac
    item="$ROOT/dist/$name"
    /usr/bin/codesign --verify --strict -R "$requirement and certificate leaf[subject.OU] = \"$team\" and identifier \"$identifier\"" "$item"
    if [[ "$name" == ROA.app ]]; then
        /usr/sbin/spctl --assess --type execute --verbose=2 "$item"
    else
        # spctl's execute assessment expects an app, not a standalone Mach-O tool.
        /usr/bin/codesign --verify --strict --check-notarization -R '=notarized' --verbose=2 "$item"
    fi
done
python3 - "$ROOT/dist" <<'PY'
import sys
from pathlib import Path
root = Path(sys.argv[1])
for name in ('roa', 'roa-service', 'ROA.app/Contents/MacOS/ROA'):
    data = (root / name).read_bytes()
    if b'/Users/' in data or b'/home/' in data:
        raise SystemExit(f'Local build path found in {name}; strip debug symbols before signing.')
PY
echo "Developer ID signatures and Gatekeeper assessments passed (team $team)."
