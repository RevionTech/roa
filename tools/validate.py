#!/usr/bin/env python3
"""Portable source-package validation; this does not compile or run Swift."""
import json
import os
import plistlib
import re
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
errors = []


def check(condition, message):
    if not condition:
        errors.append(message)


required = [
    'README.md', 'LICENSE', 'Package.swift', 'CONTRIBUTING.md',
    '.github/workflows/ci.yml', 'docs/ARCHITECTURE.md', 'docs/TESTING.md',
    'Assets/symbol.svg', 'Assets/symbol.pdf', 'Assets/logo.svg',
    'Assets/logo-source.png',
]
for name in required:
    check((ROOT / name).is_file(), f'Missing {name}')

products = re.findall(r'\.executable\(name: "([^"]+)"',
                      (ROOT / 'Package.swift').read_text())
check(len(products) == len({name.casefold() for name in products}),
      'Executable products collide on a case-insensitive filesystem')

version = re.search(r'version = "([\d.]+)"',
                    (ROOT / 'Sources/ROACore/Models.swift').read_text()).group(1)
plists = {}
for path in (ROOT / 'Resources').glob('*.plist'):
    with path.open('rb') as stream:
        plists[path.stem] = plistlib.load(stream)
check(plists['Info']['CFBundleShortVersionString'] == version, 'Version mismatch')
check(plists['Info']['CFBundleExecutable'] == 'ROA', 'Wrong app executable')
check(plists['Info']['LSUIElement'] is True, 'Dock icon must be disabled')
check(plists['service']['ProgramArguments'] == [
    '/Library/PrivilegedHelperTools/roa-service', '--owner-uid'
], 'Unexpected privileged executable / arguments')
check(plists['service']['KeepAlive'] is True, 'Service must restart after a crash')
check('KeepAlive' not in plists['login'], 'Quit must not relaunch the menu app')
check(plists['login']['RunAtLoad'] is False,
      'Start at login must be opt-in on a fresh installation')
check(plists['login']['ProgramArguments'] == [
    '/Applications/ROA.app/Contents/MacOS/ROA'
], 'Login agent must run only the installed app')
components = plists['package-components']
check(len(components) == 1 and
      components[0]['RootRelativeBundlePath'] == 'Applications/ROA.app' and
      components[0]['BundleIsRelocatable'] is False and
      components[0]['BundleOverwriteAction'] == 'upgrade',
      'Package must replace ROA at its fixed installation path')
check('--component-plist "$ROOT/Resources/package-components.plist"' in
      (ROOT / 'scripts/package-release.sh').read_text(),
      'Package builder must use the fixed-location component configuration')

for path in (ROOT / 'Assets').glob('*.svg'):
    svg = ET.parse(path).getroot()
    check(svg.tag.endswith('svg'), f'Invalid SVG {path.name}')
    check(len(svg.findall('{http://www.w3.org/2000/svg}path')) > 0,
          f'Empty SVG {path.name}')
for path in (ROOT / 'Assets').glob('*.pdf'):
    check(path.read_bytes().startswith(b'%PDF-'), f'Invalid PDF {path.name}')

for path in (ROOT / 'scripts').rglob('*'):
    if not path.is_file() or (path.suffix != '.sh' and path.name not in {'preinstall', 'postinstall'}):
        continue
    result = subprocess.run(['bash', '-n', str(path)], capture_output=True, text=True)
    check(result.returncode == 0, f'{path.name}: {result.stderr}')
    check(path.stat().st_mode & 0o111 != 0, f'{path.name} is not executable')
    for _, body in re.findall(r"<<'(ROOT_SCRIPT|USER_SCRIPT)'\n(.*?)\n\1", path.read_text(), re.S):
        result = subprocess.run(['bash', '-n'], input=body, capture_output=True, text=True)
        check(result.returncode == 0, f'{path.name} privileged body: {result.stderr}')

def source_files():
    # Prune generated directories before traversal, including large Swift caches.
    for directory, subdirectories, filenames in os.walk(ROOT):
        subdirectories[:] = [name for name in subdirectories
                             if name not in {'.build', '.git', '.swiftpm', 'dist', 'reports'}]
        for filename in filenames:
            yield Path(directory) / filename


paths = list(source_files())
relative_paths = [str(path.relative_to(ROOT)) for path in paths]
check(len(relative_paths) == len({name.casefold() for name in relative_paths}),
      'Source filenames collide on a case-insensitive filesystem')

for path in paths:
    if path.suffix not in {'.md', '.swift', '.sh', '.py', '.yml', '.plist'}:
        continue
    text = path.read_text()
    check(re.search(r'/Users/' + r'[^/\s]+/', text) is None and
          '/work' + 'space/' not in text,
          f'Personal/local path in {path.relative_to(ROOT)}')
    if path.suffix == '.md':
        for link in re.findall(r'\]\(([^)]+)\)', text):
            if '://' not in link and not link.startswith('#'):
                check((path.parent / link.split('#')[0]).exists(),
                      f'Broken local link in {path.name}: {link}')

result = subprocess.run(['bash', str(ROOT / 'scripts/install.sh'), '--dry-run'],
                        capture_output=True, text=True)
check(result.returncode == 0 and 'Start OFF' in result.stdout,
      'Install dry-run failed')

if errors:
    raise SystemExit('\n'.join(errors))
print(json.dumps({'result': 'passed', 'version': version,
                  'checks': ['structure', 'plists', 'versions', 'assets',
                             'shell syntax', 'permissions', 'links', 'install dry-run'],
                  'native_compilation': 'requires macOS',
                  'xctest': 'requires macOS'}, indent=2))
