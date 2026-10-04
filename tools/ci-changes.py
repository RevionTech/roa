"""Conservatively identify changes that need the native macOS build."""
import json
import os
import re
import subprocess
from pathlib import Path


def needs_native(paths):
    return not paths or any(not (p.endswith('.md') or p == 'LICENSE') for p in paths)


def main():
    event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
    if 'pull_request' in event:
        base, head = (event['pull_request'][key]['sha'] for key in ('base', 'head'))
    elif os.environ.get('GITHUB_EVENT_NAME') == 'workflow_dispatch':
        base = subprocess.check_output(['git', 'rev-parse', 'origin/main']).decode().strip()
        head = os.environ['GITHUB_SHA']
    else:
        base, head = event['before'], event['after']
    if not all(re.fullmatch(r'[0-9a-f]{40}', ref) for ref in (base, head)):
        raise ValueError('Invalid event commit')
    if base == '0' * 40:
        paths = []  # Initial pushes require the native build.
    else:
        paths = subprocess.check_output(['git', 'diff', '--no-renames', '--name-only', '-z', base, head, '--']).decode().split('\0')
        paths = [p for p in paths if p]
    required = str(needs_native(paths)).lower()
    with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
        output.write(f'native={required}\n')
    print(f'Native build required: {required}')


if __name__ == '__main__':
    main()
