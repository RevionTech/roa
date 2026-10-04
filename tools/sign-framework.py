#!/usr/bin/env python3
"""Sign framework executables and nested bundles from the inside out."""
import subprocess
import sys
from pathlib import Path

framework = Path(sys.argv[1])
identity = sys.argv[2]
options = ['--preserve-metadata=identifier,entitlements,flags']
if identity != '-':
    options += ['--options', 'runtime', '--timestamp']
magics = {b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf', b'\xce\xfa\xed\xfe',
          b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xce', b'\xfe\xed\xfa\xcf'}
paths = list(framework.rglob('*'))
executables = []
for path in paths:
    if path.is_file() and not path.is_symlink():
        with path.open('rb') as stream:
            if stream.read(4) in magics:
                executables.append(path)
bundles = sorted((p for p in paths if p.is_dir() and not p.is_symlink()
                  and p.suffix in {'.app', '.xpc'}), key=lambda p: len(p.parts), reverse=True)
for path in executables + bundles + [framework]:
    subprocess.run(['/usr/bin/codesign', '--force', '--sign', identity, *options, str(path)], check=True)
