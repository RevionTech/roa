#!/usr/bin/env python3
"""Reject stale or inconsistent publication without access to signing secrets."""
import json
import os
import plistlib
import re
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path

root = Path(__file__).resolve().parents[1]
info = plistlib.loads((root / 'Resources/Info.plist').read_bytes())
version = info['CFBundleShortVersionString']
build = info['CFBundleVersion']
assert re.fullmatch(r'\d+\.\d+\.\d+', version), 'Invalid semantic version'
assert re.fullmatch(r'[1-9]\d*', build), 'Invalid build number'
mode = os.environ.get('RELEASE_MODE', 'verify')
assert mode in ('verify', 'sign-only', 'publish'), 'Invalid release mode'
if mode == 'publish':
    feed = ET.parse(root / 'updates/appcast.xml')
    ns = {'s': 'http://www.andymatuschak.org/xml-namespaces/sparkle'}
    previous = feed.find('./channel/item')
    assert previous is not None, 'Missing current feed version'
    assert int(build) > int(previous.find('s:version', ns).text), 'Increase build number'
    old = previous.find('s:shortVersionString', ns).text
    assert tuple(map(int, version.split('.'))) > tuple(map(int, old.split('.'))), 'Increase version'
    # A failed API call is a failure, never evidence that a tag does not exist.
    refs = json.loads(subprocess.check_output([
        'gh', 'api', 'repos/RevionTech/roa/git/matching-refs/tags/v' + version]))
    assert not any(r['ref'] == 'refs/tags/v' + version for r in refs), 'Tag already exists'
    releases = json.loads(subprocess.check_output([
        'gh', 'api', 'repos/RevionTech/roa/releases?per_page=100']))
    assert not any(r['tag_name'] == 'v' + version for r in releases), 'Release already exists'
if os.environ.get('GITHUB_OUTPUT'):
    with open(os.environ['GITHUB_OUTPUT'], 'a') as stream:
        stream.write('version=' + version + '\n')
print('Release preflight passed:', mode, version, 'build', build)
