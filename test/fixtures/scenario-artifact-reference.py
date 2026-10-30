"""Fixture-only reference for A49, not a production comparator or text parser.

Inputs model fields extracted from a RAW QA comment, plus read-only git-show
results. No publication schema or new-base selection policy is invented here.
The caller selects the applicable report and base from durable records.
"""
import base64
import hashlib
import os
from pathlib import Path
import re
import subprocess
import tempfile


def digest(value):
    return hashlib.sha256(value).hexdigest()


def compare(repository, selected, head, applicable_base, reports, read_blob):
    """Return A49 status: 0 match, 1 different, 2 unusable evidence.

    read_blob(repository, revision, path) is the fixture's git-show boundary.
    git apply executes in a fresh non-repository directory, never the checkout.
    """
    try:
        report = reports[selected]
        if report.get('repository') != repository:
            return 2
        if any(r.get('supersedes') == selected for r in reports.values()):
            return 2
        original_base = report['base']
        if not all(re.fullmatch('[0-9a-f]{40}', value)
                   for value in (head, original_base, applicable_base)):
            return 2
        if report['path'] != 'TEST-SCENARIOS.md':
            return 2
        if report.get('over_limit'):
            return 2
        base = read_blob(repository, original_base, report['path'])
        if digest(base) != report['base_sha256']:
            return 2

        def apply(blob, patch):
            if not patch:
                if not report.get('empty_diff'):
                    raise ValueError('missing explicit empty diff')
                return blob
            # Restrict the fixture Interface to this one path; a diff of any
            # other file is unusable, even if the target hash happens to match.
            if (b'--- a/TEST-SCENARIOS.md\n' not in patch or
                    b'+++ b/TEST-SCENARIOS.md\n' not in patch or
                    patch.count(b'diff --git ') != 1):
                raise ValueError('wrong patch path')
            with tempfile.TemporaryDirectory(prefix='qa-artifact-') as directory:
                target = Path(directory) / 'TEST-SCENARIOS.md'
                target.write_bytes(blob)
                proc = subprocess.run(
                    ['git', 'apply', '--whitespace=nowarn', '-'],
                    cwd=directory, input=patch, capture_output=True,
                    env={'PATH': os.environ['PATH'],
                         'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': '/dev/null'})
                if proc.returncode:
                    raise ValueError('patch unusable')
                if sorted(p.name for p in Path(directory).iterdir()) != ['TEST-SCENARIOS.md']:
                    raise ValueError('unexpected output path')
                return target.read_bytes()

        patch = report.get('diff', b'')
        try:
            reconstructed = apply(base, patch)
            if digest(reconstructed) != report['result_sha256']:
                raise ValueError('result hash mismatch')
        except ValueError:
            # Same unified diff, alternate comment transport; never relax hashes.
            patch = base64.b64decode(report['diff_base64'], validate=True)
            reconstructed = apply(base, patch)
            if digest(reconstructed) != report['result_sha256']:
                return 2
        if applicable_base != original_base:
            reconstructed = apply(read_blob(repository, applicable_base, report['path']), patch)
        committed = read_blob(repository, head, report['path'])
        return 0 if committed == reconstructed else 1
    except (KeyError, ValueError, TypeError, OSError):
        return 2
