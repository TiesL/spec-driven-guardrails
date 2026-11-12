#!/usr/bin/env bash
# S631 — shared instruction exercise evidence retention (#680; A56)
# Covers: F67, F68
# Offline synthetic Adapter tests; no subscription calls or behavior claims.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test/lib.sh
. "$here/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
# R7: validate the delivered tree after all examples exist, not the smaller
# intermediate main bundle that existed when its report was first generated.
python3 -I - "$TEST_REPO_ROOT" "$SANDBOX" <<'PY' || fail "S631 complete delivered bundle"
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

repo, sandbox = map(Path, sys.argv[1:])
out = sandbox / 'delivered'
cases = out / 'test/behavior/temporary-panel-cases'
bundle_name = 'test/behavior/evidence/temporary-panel-680'
shutil.copytree(repo / 'test/behavior/temporary-panel-cases', cases)
shutil.copytree(repo / bundle_name, out / bundle_name)
result_name = 'test/behavior/temporary-panel-results.md'
shutil.copy2(repo / result_name, out / result_name)
runner = os.environ.get('PANEL_TEST_RUNNER', str(repo / 'test/behavior/temporary-panel-run.sh'))


def read(path):
    return json.loads(path.read_bytes())


def size(manifest):
    # The agreed budget counts each input/evidence/result path once. Keep this
    # independent of the implementation; do not import Store or its CAP.
    data = read(manifest)
    refs = [data['plan']]
    for exercise in data['exercises']:
        refs.extend(exercise['criteria'])
        for case in exercise['cases']:
            refs.extend([case['packet'], case['key'], *case['ground_truth']])
            if case['release'] is not None:
                refs.append(case['release'])
    inputs = {manifest} | {manifest.parent / ref['path'] for ref in refs}
    retained = {p for p in (out / data['evidence_path']).rglob('*') if p.is_file()}
    result = out / data['results_path']
    paths = inputs | retained | ({result} if result.is_file() else set())
    return sum(p.stat().st_size for p in paths)


def snapshot():
    return {str(p.relative_to(out)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in out.rglob('*') if p.is_file()}


def report(manifest):
    return subprocess.run([runner, 'report', '--offline', '--repo', str(repo),
        '--exercise-file', str(manifest), '--output-dir', str(out)], capture_output=True, text=True)


manifests = [cases / 'manifest.json'] + [cases / (name + '-manifest.json') for name in
    ('sample-verification', 'sample-disagreement', 'sample-import')]
for manifest in manifests:
    data = read(manifest)
    assert (out / data['evidence_path'] / 'index.json').is_file(), 'required example/main evidence absent'
    assert (out / data['results_path']).is_file(), 'required example/main report absent'

total = size(manifests[0])
print('S631 delivered bundle bytes:', total, '(cap 3000000)', flush=True)
assert total <= 3_000_000, 'complete delivered bundle exceeds unchanged 3000000-byte cap: ' + str(total)
before = snapshot()
indexes = {str(p.relative_to(out)): read(p) for p in (out / bundle_name).rglob('index.json')}
for manifest in manifests:
    result = out / read(manifest)['results_path']
    expected = result.read_bytes()
    p = report(manifest)
    assert p.returncode == 0, 'delivered report failed: ' + p.stderr
    assert result.read_bytes() == expected, 'delivered report does not reproduce committed bytes'
    assert size(manifest) <= 3_000_000, 'reproduced bundle exceeds unchanged cap'
after = snapshot()
for path, digest in before.items():
    if path in indexes:
        updated = read(out / path)
        assert updated.pop('reports')[:len(indexes[path]['reports'])] == indexes[path]['reports'], 'report history lost'
        original = dict(indexes[path]); original.pop('reports')
        assert updated == original, 'retained calls/usage/capture bindings changed'
    else:
        assert after.get(path) == digest, 'retained input/output/capture bytes changed: ' + path

# One byte above the real budget, counting the existing report and all nested
# examples. A raised cap must fail this assertion, even if the bundle fits it.
padding = out / bundle_name / 'over-cap-control'
padding.write_bytes(b'x' * (3_000_001 - size(manifests[0])))
assert size(manifests[0]) == 3_000_001, 'independent oversized control mismeasured'
before = snapshot()
p = report(manifests[0])
assert p.returncode != 0 and '3 MB bundle cap reached' in p.stderr, 'unchanged publication cap accepted oversized delivered tree'
assert snapshot() == before, 'oversize rejection lost retained recovery/evidence bytes'
print('S631 delivered main + 3 example reports reproduce; exact over-cap control rejected')
PY
# Allow the delivered-tree regression and cap mutation to run independently of
# the existing, longer capture-first property suite.
if [ "${PANEL_TEST_DELIVERED_ONLY:-0}" = 1 ]; then
  test_done
fi
python3 -I "$TEST_REPO_ROOT/test/fixtures/temporary-panel-680-tests.py" 631 || fail "S631 offline CLI assertions"
test_done
