#!/bin/bash
set -euo pipefail
: "${RELEASE_VERSION:?Missing verified release version.}"
: "${GITHUB_SHA:?Missing immutable source commit.}"
[[ "$RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 64
PACKAGE="ROA-$RELEASE_VERSION-universal.pkg"
(cd release-files/dist && shasum -a 256 -c "$PACKAGE.sha256")
NOTES="$RUNNER_TEMP/roa-release-notes.md"
python3 - "$RELEASE_VERSION" "$NOTES" <<'PY'
import re, sys
from pathlib import Path
version, output = sys.argv[1:]
text = Path('CHANGELOG.md').read_text()
match = re.search(r'^## ' + re.escape(version) + r'(?:\s[^\n]*)?\n(.*?)(?=^## |\Z)', text, re.M | re.S)
if not match:
    raise SystemExit('Add release notes to CHANGELOG.md before publication.')
Path(output).write_text(match[1].strip() + '\n\nUniversal package signed and notarized by Revion Tech. Installation requires administrator authorization and starts ROA OFF.\n')
PY
# Never upload into an existing release or overwrite an existing tag.
python3 tools/release-preflight.py
gh release create "v$RELEASE_VERSION" "release-files/dist/$PACKAGE" \
    "release-files/dist/$PACKAGE.sha256" --repo RevionTech/roa \
    --target "$GITHUB_SHA" --title "ROA $RELEASE_VERSION" --notes-file "$NOTES" --draft
# Publishing only after all assets have uploaded avoids incomplete public releases.
gh release edit "v$RELEASE_VERSION" --repo RevionTech/roa --draft=false --latest
BRANCH="release/feed-$RELEASE_VERSION"
git switch -c "$BRANCH"
cp release-files/updates/appcast.xml updates/appcast.xml
git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
git add updates/appcast.xml
git commit -m "Publish signed ROA $RELEASE_VERSION update feed"
git push origin "$BRANCH"
BODY="$RUNNER_TEMP/roa-feed-pr.md"
cat > "$BODY" <<'BODY'
The signed, notarized package and checksum are published on GitHub. This updates the signed latest-only feed generated in the approved release run.

Approve the CI workflows if GitHub requests it, review the feed and merge after CI passes. Verify the installed update before retiring previous releases and tags. Do not edit the signed XML manually.
BODY
gh pr create --repo RevionTech/roa --base main --head "$BRANCH" \
    --title "Publish ROA $RELEASE_VERSION update feed" --body-file "$BODY"
echo 'Package published. Review and merge the feed PR to activate in-app updates.'
