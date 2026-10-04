"""Publication guards must fail closed before signing secrets are available."""
import os
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[1] / 'release-preflight.py'


class ReleasePreflightTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        for name in ('tools', 'Resources', 'updates', 'bin'):
            (self.root / name).mkdir()
        shutil.copyfile(SOURCE, self.root / 'tools/release-preflight.py')
        self.metadata('0.3.1', '301')
        (self.root / 'updates/appcast.xml').write_text('''<rss xmlns:s="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><s:version>300</s:version><s:shortVersionString>0.3.0</s:shortVersionString></item></channel></rss>''')
        gh = self.root / 'bin/gh'
        gh.write_text('''#!/usr/bin/env python3
import os, sys
if os.environ.get('API_FAIL'): sys.exit(1)
print(os.environ.get('TAG_REFS', '[]') if 'matching-refs' in sys.argv[-1] else os.environ.get('RELEASES', '[]'))
''')
        gh.chmod(0o755)

    def metadata(self, version, build):
        (self.root / 'Resources/Info.plist').write_bytes(plistlib.dumps({
            'CFBundleShortVersionString': version, 'CFBundleVersion': build}))

    def run_guard(self, **changes):
        env = dict(os.environ, RELEASE_MODE='publish', GITHUB_OUTPUT=str(self.root / 'output'))
        env['PATH'] = str(self.root / 'bin') + os.pathsep + env['PATH']
        env.update(changes)
        return subprocess.run(['python3', str(self.root / 'tools/release-preflight.py')],
                              env=env, capture_output=True)

    def test_new_version_is_accepted_without_changing_feed(self):
        before = (self.root / 'updates/appcast.xml').read_bytes()
        self.assertEqual(self.run_guard().returncode, 0)
        self.assertEqual((self.root / 'output').read_text(), 'version=0.3.1\n')
        self.assertEqual((self.root / 'updates/appcast.xml').read_bytes(), before)

    def test_same_build_is_rejected(self):
        self.metadata('0.3.1', '300')
        self.assertNotEqual(self.run_guard().returncode, 0)

    def test_same_version_is_rejected_even_with_new_build(self):
        self.metadata('0.3.0', '301')
        self.assertNotEqual(self.run_guard().returncode, 0)

    def test_github_api_failure_is_not_treated_as_missing_release(self):
        self.assertNotEqual(self.run_guard(API_FAIL='1').returncode, 0)
        self.assertFalse((self.root / 'output').exists())

    def test_existing_tag_is_rejected(self):
        self.assertNotEqual(self.run_guard(TAG_REFS='[{"ref":"refs/tags/v0.3.1"}]').returncode, 0)

    def test_existing_draft_is_rejected(self):
        self.assertNotEqual(self.run_guard(RELEASES='[{"tag_name":"v0.3.1","draft":true}]').returncode, 0)

    def test_sign_only_can_verify_existing_version(self):
        self.metadata('0.3.0', '300')
        self.assertEqual(self.run_guard(RELEASE_MODE='sign-only', API_FAIL='1').returncode, 0)

    def test_invalid_mode_is_rejected(self):
        self.assertNotEqual(self.run_guard(RELEASE_MODE='unexpected').returncode, 0)
