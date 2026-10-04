"""Require successful main push CI for the exact release commit before signing."""
import json
import os
import re
import subprocess
import time


def select_run(runs, sha):
    matches = [run for run in runs if run['head_sha'] == sha
               and run['head_branch'] == 'main' and run['event'] == 'push']
    return max(matches, key=lambda run: (run['id'], run.get('run_attempt', 1)), default=None)


def main():
    sha = os.environ['GITHUB_SHA']
    if not re.fullmatch(r'[0-9a-f]{40}', sha) or os.environ['GITHUB_REPOSITORY'] != 'RevionTech/roa':
        raise ValueError('Unexpected release repository or commit')
    endpoint = f'repos/RevionTech/roa/actions/workflows/ci.yml/runs?event=push&branch=main&head_sha={sha}&per_page=100'
    deadline = time.monotonic() + 600
    while True:
        data = json.loads(subprocess.check_output(['gh', 'api', endpoint]))
        run = select_run(data['workflow_runs'], sha)
        if run and run['status'] == 'completed':
            if run['conclusion'] != 'success':
                raise RuntimeError(f"Main CI did not succeed: {run['conclusion']}")
            print(f"Verified main CI: {run['html_url']}")
            return
        if time.monotonic() >= deadline:
            raise TimeoutError('No successful main CI within 10 minutes')
        print('Waiting for main CI on the exact release commit...', flush=True)
        time.sleep(15)


if __name__ == '__main__':
    main()
