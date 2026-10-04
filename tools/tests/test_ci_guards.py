"""Docs optimizations and release CI reuse must fail closed."""
import importlib.util
import unittest
from unittest.mock import patch
import json
import subprocess
from pathlib import Path


def load(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).resolve().parents[1] / f'{name}.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CIGuardTests(unittest.TestCase):
    def test_docs_only_skip_native(self):
        self.assertFalse(load('ci-changes').needs_native(['README.md', 'docs/INSTALL.md', 'LICENSE']))

    def test_unknown_empty_and_mixed_changes_require_native(self):
        for paths in ([], ['updates/appcast.xml'], ['.github/workflows/ci.yml'], ['README.md', 'Sources/App.swift']):
            self.assertTrue(load('ci-changes').needs_native(paths))

    def test_only_exact_main_push_is_accepted(self):
        select = load('wait-for-ci').select_run
        run = dict(id=1, head_sha='a' * 40, head_branch='main', event='push', run_attempt=1)
        self.assertEqual(select([run], 'a' * 40), run)
        for changes in ({'head_sha': 'b' * 40}, {'head_branch': 'feature'}, {'event': 'pull_request'}):
            self.assertIsNone(select([dict(run, **changes)], 'a' * 40))

    def test_newest_run_is_required_even_when_old_run_succeeded(self):
        select = load('wait-for-ci').select_run
        old = dict(id=1, head_sha='a' * 40, head_branch='main', event='push', conclusion='success')
        new = dict(old, id=2, conclusion='failure')
        self.assertEqual(select([old, new], 'a' * 40), new)

    def test_release_rejects_unsuccessful_or_missing_ci(self):
        module = load('wait-for-ci')
        env = {'GITHUB_SHA': 'a' * 40, 'GITHUB_REPOSITORY': 'RevionTech/roa'}
        for conclusion in ('failure', 'cancelled', 'timed_out', 'skipped'):
            run = dict(id=1, head_sha='a' * 40, head_branch='main', event='push', status='completed', conclusion=conclusion)
            with patch.dict(module.os.environ, env), patch.object(module.subprocess, 'check_output', return_value=json.dumps({'workflow_runs': [run]}).encode()):
                with self.assertRaises(RuntimeError):
                    module.main()
        with patch.dict(module.os.environ, env), patch.object(module.subprocess, 'check_output', return_value=b'{"workflow_runs": []}'), patch.object(module.time, 'monotonic', side_effect=[0, 601]):
            with self.assertRaises(TimeoutError):
                module.main()

    def test_release_rejects_api_errors(self):
        module = load('wait-for-ci')
        with patch.dict(module.os.environ, {'GITHUB_SHA': 'a' * 40, 'GITHUB_REPOSITORY': 'RevionTech/roa'}), patch.object(module.subprocess, 'check_output', side_effect=subprocess.CalledProcessError(1, 'gh')):
            with self.assertRaises(subprocess.CalledProcessError):
                module.main()
