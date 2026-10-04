#!/bin/bash
set -euo pipefail
[[ "$(uname -s)" == Darwin && "$EUID" -ne 0 ]] || exit 64
OWNER_UID="$(id -u)"
for base in /var/db/net.reviontech.roa /var/db/net.revion.roa; do
    if [[ -f "$base/owner" && "$(cat "$base/owner")" != "$OWNER_UID" ]]; then
        echo 'Uninstall from the account that controls ROA.' >&2; exit 1
    fi
done
if [[ -x "$HOME/.local/bin/roa" ]]; then "$HOME/.local/bin/roa" off || true; fi
/usr/bin/sudo -v
/usr/bin/sudo /bin/bash -s -- "$OWNER_UID" <<'ROOT_SCRIPT'
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
owner="$1"
[[ "$owner" =~ ^[0-9]+$ && "$owner" -ge 501 ]] || exit 64
lock=/var/run/net.reviontech.roa.install-lock
mkdir -m 700 "$lock" || exit 1
trap 'rmdir "$lock"' EXIT
for base in /var/db/net.reviontech.roa /var/db/net.revion.roa; do
    [[ ! -L "$base" && ! -L "$base/owner" ]] || exit 1
    if [[ -f "$base/owner" ]]; then [[ "$(cat "$base/owner")" == "$owner" ]] || exit 1; fi
done
for label in net.reviontech.roa.service net.revion.roa.service; do
    launchctl bootout "system/$label" 2>/dev/null || true
done
/usr/bin/pmset -a disablesleep 0
rm -f /Library/LaunchDaemons/net.reviontech.roa.service.plist /Library/LaunchDaemons/net.revion.roa.service.plist
rm -f /Library/PrivilegedHelperTools/roa-service /Library/PrivilegedHelperTools/net.revion.roa.service
rm -rf /Applications/ROA.app /var/db/net.reviontech.roa /var/db/net.revion.roa /var/run/net.reviontech.roa /var/run/net.revion.roa
pkgutil --forget net.reviontech.roa.installer 2>/dev/null || true
ROOT_SCRIPT
for label in net.reviontech.roa.menubar net.revion.roa.menubar; do
    /bin/launchctl bootout "gui/$OWNER_UID/$label" 2>/dev/null || true
    rm -f "$HOME/Library/LaunchAgents/$label.plist"
done
/usr/bin/pkill -u "$OWNER_UID" -x ROA 2>/dev/null || true
# Delete only ROA's optional notification credential, using the user's Keychain.
/usr/bin/security delete-generic-password -s net.reviontech.roa.notifications -a telegram 2>/dev/null || true
rm -f "$HOME/.local/bin/roa"
rm -rf "$HOME/Applications/ROA.app" "$HOME/Applications/ROA.app.previous"
for identifier in net.reviontech.roa net.revion.roa; do
    /usr/bin/defaults delete "$identifier" 2>/dev/null || true
    rm -rf "$HOME/Library/Caches/$identifier" "$HOME/Library/Saved Application State/$identifier.savedState" "$HOME/Library/HTTPStorages/$identifier"
done
echo 'ROA removed completely. Normal sleep restored.'
