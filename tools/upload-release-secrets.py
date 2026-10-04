#!/usr/bin/env python3
"""Interactive local credential upload; never print secrets or pass them as args."""
import base64
import argparse
import getpass
import os
import plistlib
import re
import subprocess
import tempfile
import uuid
from pathlib import Path

REPO = 'RevionTech/roa'
ROOT = Path(__file__).resolve().parents[1]


def secret(name, data):
    result = subprocess.run(['gh', 'secret', 'set', name, '--repo', REPO,
                             '--env', 'release'], input=data,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if result.returncode:
        raise SystemExit('Upload failed for ' + name + '. Check GitHub access and retry.')
    print('Saved:', name)


def file_input(label):
    value = input(label + ' file path: ').strip()
    path = Path(value).expanduser().resolve()
    if path.is_relative_to(ROOT):
        raise SystemExit('Keep credential files outside the repository.')
    data = path.read_bytes()
    if not data or len(base64.b64encode(data)) > 48000:
        raise SystemExit('Credential file is empty or too large.')
    return path, data


def p12(label, role):
    path, data = file_input(label)
    password = getpass.getpass(label + ' export password (hidden): ')
    if not password or '\n' in password:
        raise SystemExit('Use a nonempty single-line export password.')
    command = ['openssl', 'pkcs12', '-in', str(path), '-passin', 'stdin']
    certs = subprocess.run(command + ['-nokeys', '-clcerts'],
                           input=(password + '\n').encode(), capture_output=True)
    keys = subprocess.run(command + ['-nocerts', '-nodes'],
                          input=(password + '\n').encode(), capture_output=True)
    # Capture private material only in memory, never print or write plaintext keys.
    if certs.returncode or keys.returncode or b'PRIVATE KEY-----' not in keys.stdout:
        raise SystemExit('Could not validate the P12 password and private key.')
    blocks = re.findall(rb'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----',
                        certs.stdout, re.S)
    if len(blocks) != 1:
        raise SystemExit('Export exactly one company signing identity per P12.')
    subject = subprocess.run(['openssl', 'x509', '-noout', '-subject'],
                             input=blocks[0], capture_output=True, check=True).stdout.decode()
    if role not in subject or '4WP3NZ2BN9' not in subject or 'Revion Tech OU' not in subject:
        raise SystemExit('Wrong company or certificate type in ' + label)
    return base64.b64encode(data), password.encode()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--notary-only', action='store_true',
                        help='Upload only the team notarization API key; preserve existing signing secrets')
    args = parser.parse_args()
    if not os.isatty(0):
        raise SystemExit('Run this script yourself in an interactive Terminal.')
    os.umask(0o077)
    subprocess.run(['gh', 'api', 'repos/' + REPO], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print('Upload ROA credentials directly to the protected GitHub release environment.')
    print('Tokens and passwords will not be displayed or stored in this repository.')
    if not args.notary_only:
        app, app_pass = p12('Developer ID Application', 'Developer ID Application:')
        installer, installer_pass = p12('Developer ID Installer', 'Developer ID Installer:')
    _, notary = file_input('App Store Connect API private key (.p8)')
    if b'-----BEGIN PRIVATE KEY-----' not in notary:
        raise SystemExit('Expected an App Store Connect API private key.')
    valid = subprocess.run(['openssl', 'pkey', '-noout'], input=notary,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if valid.returncode:
        raise SystemExit('Invalid API private key.')
    key_id = input('API Key ID: ').strip()
    issuer = input('API Issuer ID: ').strip()
    if not re.fullmatch(r'[A-Z0-9]{10}', key_id):
        raise SystemExit('Invalid API Key ID.')
    issuer = str(uuid.UUID(issuer))
    notary_values = {'ROA_NOTARY_KEY': base64.b64encode(notary),
                     'ROA_NOTARY_KEY_ID': key_id.encode(),
                     'ROA_NOTARY_ISSUER_ID': issuer.encode()}
    if args.notary_only:
        for name, data in notary_values.items():
            secret(name, data)
        print('Notarization secrets uploaded. Existing signing secrets preserved.')
        return
    tools = Path(input('Sparkle signing tools directory: ').strip()).expanduser().resolve()
    expected = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())['SUPublicEDKey']
    actual = subprocess.check_output([str(tools / 'bin/generate_keys'), '--account',
                                      'roa-revion', '-p']).decode().strip()
    if actual != expected:
        raise SystemExit('Existing Sparkle key does not match ROA. Do not generate a new key.')
    with tempfile.TemporaryDirectory(prefix='roa-key-transfer-') as directory:
        key_file = Path(directory) / 'sparkle.key'
        exported = subprocess.run([str(tools / 'bin/generate_keys'), '--account',
                                   'roa-revion', '-x', str(key_file)],
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if exported.returncode:
            raise SystemExit('Sparkle key export failed. Check the native Keychain prompt.')
        sparkle = key_file.read_bytes().strip()
        if len(sparkle) not in (44, 88) or len(base64.b64decode(sparkle, validate=True)) not in (32, 64):
            raise SystemExit('Invalid Sparkle export.')
        for name, data in {
            'ROA_APPLICATION_P12': app, 'ROA_APPLICATION_P12_PASSWORD': app_pass,
            'ROA_INSTALLER_P12': installer, 'ROA_INSTALLER_P12_PASSWORD': installer_pass,
            **notary_values, 'ROA_SPARKLE_KEY': sparkle,
        }.items():
            secret(name, data)
    print('All eight release secrets uploaded. Run Signed release in sign-only mode first.')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError):
        raise SystemExit('Credential setup failed. Check paths, formats and GitHub access; no secret values are printed.')
