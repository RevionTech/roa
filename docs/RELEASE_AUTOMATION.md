# Release automation

The **Signed release** GitHub Actions workflow runs on standard GitHub-hosted
macOS machines. It does not require a maintainer's Mac to be online. Existing CI
still tests PRs without signing secrets. Local signing remains available as a fallback.

## One-time setup

Configure the `release` GitHub environment with a required maintainer reviewer,
administrator bypass disabled and a custom **branch** policy allowing only `main`.
A maintainer can approve their own manual run; the explicit approval separates
ordinary CI from access to signing keys. Environment and repository administrators
are trusted and can change these settings. Protect `main`, release scripts and
workflow changes through review. The official repository is configured this way.

1. Open macOS **Keychain Access → My Certificates**. Expand the company
   **Developer ID Application: Revion Tech OU (4WP3NZ2BN9)** identity. Select the
   certificate with its private key and export as `application.p12`, using a strong
   export password. Repeat for **Developer ID Installer** as `installer.p12`.
   Export only the company identities. A `.cer` without its private key is insufficient.
   Keep both files outside the repository, in a private directory.
2. In **App Store Connect → Users and Access → Integrations → App Store Connect API
   → Team Keys**, generate a dedicated `ROA Notarization` key with the **Developer**
   role. If API access has not been enabled, the Account Holder must request it.
   Download its `.p8` file once, and record its Key ID and Issuer ID. Use a team key;
   individual keys use different authentication parameters. This workflow uses the
   team issuer. The API key authorizes notarization; it does not replace signing
   certificates. Check the role against Apple's current account policy if rejected.
3. Run `python3 tools/upload-release-secrets.py` in your own interactive Terminal.
   Supply the file paths, hidden P12 passwords, Key/Issuer IDs and the directory
   containing Sparkle 2.10.0's `bin/generate_keys`. The script validates company
   identities and the existing Sparkle public key, exports the existing Sparkle key
   temporarily and sends all eight values to GitHub **environment secrets** over
   stdin. It does not print them or place them in shell arguments or history.
   Native Keychain authorization may be required. Never paste secrets into chat.
   If both Apple identities and Sparkle are already configured, use
   `python3 tools/upload-release-secrets.py --notary-only` to upload only the
   notarization API credentials without replacing existing signing secrets.
4. Keep encrypted offline backups of the Apple and Sparkle private keys. After a
   successful cloud signing test, remove temporary exports from the Mac. Keep
   the installed Keychain originals. Do not upload P12/P8 files as artifacts.

Environment secrets: `ROA_APPLICATION_P12`, `ROA_APPLICATION_P12_PASSWORD`,
`ROA_INSTALLER_P12`, `ROA_INSTALLER_P12_PASSWORD`, `ROA_NOTARY_KEY`,
`ROA_NOTARY_KEY_ID`, `ROA_NOTARY_ISSUER_ID`, `ROA_SPARKLE_KEY`.
P12 and P8 files are base64-encoded for transport; base64 is not encryption.
GitHub encrypts secrets at rest. The signing job can read them after approval.

## Run a release

In **Actions → Signed release → Run workflow**, select `main` and a mode:

| Mode | Result |
| --- | --- |
| `verify` | Validate and build both architectures; no secrets or publication. |
| `sign-only` | After environment approval, sign and notarize the current version; save public package, checksum and feed as a seven-day artifact. Publish nothing. |
| `publish` | Reject an existing version/tag; sign and notarize a new version, publish its package and open a PR for the signed update feed. |

For the first migration test, use **sign-only** for the existing version. Download
the artifact and verify package signatures/notarization. This does not replace the
already published package, change this Mac's installation or require a version bump.

For a new release, update the Swift version, both Info.plist version fields and
CHANGELOG first. Merge reviewed source changes into `main`; then use **publish**.
The workflow pins its source commit, requires increasing version/build numbers,
and publishes a draft only after its package and checksum have uploaded.
If a run fails after creating a draft or publishing the package, inspect that
state before retrying. Existing versions are deliberately blocked; never overwrite
a package users may already have downloaded.

The publisher uses the job's short-lived `GITHUB_TOKEN`, not a stored personal
token. GitHub must allow Actions to create pull requests. Approve the generated
PR's CI workflows if GitHub requests approval, then review and merge the feed PR
after CI passes. No direct push to protected `main` or automatic admin bypass is
used. Until the PR merges, installed apps continue using the previous signed feed.
Test the installed update, then retire the preceding release and tag under the
latest-only policy. Retirement stays manual so a failed installation can be recovered.

## Security and operating limits

Only manual runs on the official repository's `main` can reach signing. No fork
PR or ordinary push receives environment secrets. Signing has read-only repository
permissions; a separate Linux publication job receives only public files and
limited contents/PR write permissions. Actions and Sparkle tools are checksum/commit
pinned. Temporary Keychain and input files are deleted even after failures; the
GitHub-hosted VM is destroyed after the job. No CI artifact includes private keys
or full notarization logs. Do not enable shell tracing or debug credential output.

A compromised approved commit, dependency, account or GitHub administrator can
still compromise keys or publications. Use two-factor authentication, restrict
administrators, review executable workflow changes and revoke leaked credentials
promptly. Apple's notarization is an additional check, not a substitute for review.
Maintain certificate expiry and API-key revocation; preserve the Sparkle trust key
across releases. Apple outage/queue delays can outlast the job's timeout; inspect
the submission before retrying. CI cannot validate physical lid, battery or reboot
behavior; follow the installed-device acceptance guide.

Standard hosted runners are currently free for public repositories; Actions
artifact storage is quota-limited. Keep only seven days of CI artifacts and use
GitHub Releases for distribution. Apple Developer membership remains required.

References: [Apple certificates on GitHub runners](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications),
[environment protections](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments),
[notarization authentication](https://developer.apple.com/documentation/notaryapi/submitting-software-for-notarization-over-the-web),
[GitHub billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions).
