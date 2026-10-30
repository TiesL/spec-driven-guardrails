"""Independent byte oracles for the text-only comparison Interface (A49)."""
import base64
import importlib.util
from pathlib import Path
import subprocess
import sys
from unittest.mock import patch

sys.dont_write_bytecode = True
root = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('reference', Path(__file__).with_name('scenario-artifact-reference.py'))
ref = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ref)

# Literal expected bytes, not output calculated by the reconstruction algorithm.
old = b'p1\np2\np3\ntitle\nremove me\nexpected: old\nkeep\nfooter\n'
new = b'p1\np2\np3\ntitle\nexpected: new \t\nkeep\nfooter\n'
new_base = b'upstream\np2\np3\ntitle\nremove me\nexpected: old\nkeep\nfooter\n'
rebased = b'upstream\np2\np3\ntitle\nexpected: new \t\nkeep\nfooter\n'
diff = (b'diff --git a/TEST-SCENARIOS.md b/TEST-SCENARIOS.md\n'
        b'index ' + b'1' * 40 + b'..' + b'2' * 40 + b' 100644\n'
        b'--- a/TEST-SCENARIOS.md\n+++ b/TEST-SCENARIOS.md\n'
        b'@@ -4,4 +4,3 @@\n title\n-remove me\n-expected: old\n+expected: new \t\n keep\n')
base, head, later = '1' * 40, '2' * 40, '3' * 40
report = dict(repository='owner/repo', base=base, path='TEST-SCENARIOS.md',
              base_sha256=ref.digest(old), result_sha256=ref.digest(new), diff=diff)
blobs = {base: old, head: new, later: new_base}
reads = []


def read_blob(repository, revision, path):
    assert repository == 'owner/repo' and path == 'TEST-SCENARIOS.md'
    reads.append(revision)
    return blobs[revision]


# Snapshot worktree + git index; fixture git apply must never touch either.
protected = [root / name for name in ('PRD.md', 'ARCHITECTURE.md', 'TEST-SCENARIOS.md')]
gitdir = subprocess.check_output(['git', 'rev-parse', '--absolute-git-dir'], cwd=root).decode().strip()
protected.append(Path(gitdir) / 'index')
before = {p: p.read_bytes() for p in protected if p.exists()}
real_run = subprocess.run
calls = []


def guarded_run(argv, **kwargs):
    location = Path(kwargs['cwd']).resolve()
    assert location != root and root not in location.parents, 'git apply entered repository'
    assert not (location / '.git').exists(), 'git apply entered fixture repository'
    assert argv == ['git', 'apply', '--whitespace=nowarn', '-']
    calls.append(location)
    return real_run(argv, **kwargs)


def expect(label, expected, reports=None, selected='qa1', applicable=base):
    actual = ref.compare('owner/repo', selected, head, applicable,
                         {'qa1': report} if reports is None else reports, read_blob)
    assert actual == expected, f'{label}: expected {expected}, got {actual}'
    print('PASS reference/' + label)


with patch.object(ref.subprocess, 'run', guarded_run):
    expect('equal-with-deletion-and-whitespace', 0)
    for label, value in [('one-byte', new.replace(b'new', b'now')),
                         ('crlf', new.replace(b'\n', b'\r\n')),
                         ('whitespace', new.replace(b' \t', b'  ')),
                         ('outside-hunk', new.replace(b'title', b'Title'))]:
        blobs[head] = value
        expect(label, 1)
    blobs[head] = new
    expect('missing-report', 2, {})
    broken = dict(report, diff=diff[:-8])
    expect('truncated-diff', 2, {'qa1': broken})
    expect('bad-base-hash', 2, {'qa1': dict(report, base_sha256='0' * 64)})
    expect('bad-result-hash', 2, {'qa1': dict(report, result_sha256='0' * 64)})
    expect('corruption', 2, {'qa1': dict(report, diff=diff.replace(b'new', b'now'))})
    expect('base64-recovery', 0, {'qa1': dict(broken, diff_base64=base64.b64encode(diff))})
    expect('base64-still-verifies-hash', 2, {'qa1': dict(broken, diff_base64=base64.b64encode(diff), result_sha256='0' * 64)})
    expect('over-limit-unresolved', 2, {'qa1': dict(report, over_limit=True)})
    blobs[head] = old
    empty = dict(report, diff=b'', empty_diff=True, result_sha256=ref.digest(old))
    expect('explicit-empty', 0, {'qa1': empty})
    expect('implicit-empty-refused', 2, {'qa1': dict(empty, empty_diff=False)})
    blobs[head] = new
    second = dict(report, supersedes='qa1')
    expect('superseded-refused', 2, {'qa1': report, 'qa2': second})
    expect('selected-latest', 0, {'qa1': report, 'qa2': second}, selected='qa2')
    expect('missing-latest-not-local-fallback', 2, {'qa1': report}, selected='qa2')
    blobs[head] = rebased
    expect('main-merge-reapply', 0, applicable=later)
    blobs[head] = rebased.replace(b'upstream', b'Upstream')
    expect('main-merge-outside-hunk', 1, applicable=later)
    blobs[later] = b'conflicting base\n'
    expect('main-merge-apply-conflict', 2, applicable=later)
    blobs[head] = new
    expect('foreign-repository', 2, {'qa1': dict(report, repository='other/repo')})

assert calls, 'no reconstruction executed'
assert all(not p.exists() for p in calls), 'temporary reconstruction leaked'
assert before == {p: p.read_bytes() for p in before}, 'repository bytes changed'
# Mutation controls: equality must discriminate a single byte, a stripped
# whitespace result and newline normalization, as demonstrated above. The
# caller checks all three exit classes against literal expected statuses.
print('PASS reference/no-repository-writes')
