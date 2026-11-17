#!/usr/bin/env python3
"""Generate retained synthetic mode/disagreement examples through the public CLI.

No live runtime, publication, existing-file deletion or status edit. Use a fresh
output directory for regeneration, then review the generated files before copying.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
CASES = ROOT / 'test/behavior/temporary-panel-cases'
RUNNER = ROOT / 'test/behavior/temporary-panel-run.sh'
ADAPTER = Path(__file__).with_name('adapter.py')
parser = argparse.ArgumentParser(); parser.add_argument('--output-dir', required=True)
args = parser.parse_args()
output = Path(args.output_dir).resolve()
source = json.loads((CASES / 'manifest.json').read_text())


def write(name, value):
    p = CASES / name
    data = (json.dumps(value, indent=2) + '\n').encode()
    p.write_bytes(data)
    return dict(path=name, sha256=hashlib.sha256(data).hexdigest())


def cli(manifest, operation, *extra, expected=0):
    result = subprocess.run([str(RUNNER), operation, '--offline', '--exercise-file', str(CASES / manifest),
        '--output-dir', str(output), *extra], capture_output=True, text=True)
    if result.returncode != expected:
        raise SystemExit(result.stderr)
    print(operation, manifest, 'exit=' + str(result.returncode))


def sample(name, case_id, mode='lab-hook-deny', release=None):
    m = copy.deepcopy(source)
    c = copy.deepcopy(m['exercises'][0]['cases'][1])
    c.update(id=case_id, mode=mode, positive=False, repetitions=1, release=release)
    m['exercises'] = [dict(id=name, criteria=source['exercises'][0]['criteria'], cases=[c])]
    m['evidence_path'] += '/examples/' + name
    m['results_path'] = m['evidence_path'] + '/results.md'
    m['plan'] = write(name + '-plan.json', dict(version=1, name='finite-v1', rows=[
        dict(exercise=name, case=case_id, mode=mode, repetitions=1, positive=False, batch=c['batch'])]))
    filename = name + '-manifest.json'
    write(filename, m)
    return filename, m['evidence_path'] + '/' + name + '/' + case_id + '-r1.json'


manifest, primary = sample('sample-verification', 'invalid-primary')
cli(manifest, 'run', '--runtime-adapter', str(ADAPTER), expected=2)
cli(manifest, 'run', '--runtime-adapter', str(ADAPTER), '--recorder-mode', 'transcript-only', '--fallback-from', primary)
cli(manifest, 'judge', '--judge-adapter', str(ADAPTER))
cli(manifest, 'report')
manifest, _ = sample('sample-disagreement', 'refusal')
cli(manifest, 'run', '--runtime-adapter', str(ADAPTER))
cli(manifest, 'judge', '--judge-adapter', str(ADAPTER))
cli(manifest, 'report')
# The import preserves an explicitly supplied synthetic source with unknown
# original model/date and absent events. It is not a release observation.
existing = output / source['evidence_path'] / 'S590-delegation-meaning/refusal-r1.json'
record = json.loads(existing.read_text()); cap = record['capture']
cap.update(kind='release', session='synthetic-import-original-unknown', mode='observed-in-use',
    model='unknown', date='unknown', events=None,
    source=dict(url='https://example.invalid/synthetic-history',
        snapshot='Supplied synthetic history snapshot only; no actual release history or events provided.',
        snapshot_sha256=hashlib.sha256(b'Supplied synthetic history snapshot only; no actual release history or events provided.').hexdigest(),
        packet=record['packet'],
        runtime=cap['runtime'], model='unknown', date='unknown', events=None))
cap['verification'] = dict(independent='not applicable: supplied history', effective='unknown original settings',
    hook_log='not applicable: imported history', canary='not applicable: imported history', counts='not applicable: imported history')
release = write('sample-import-capture.json', cap)
manifest, _ = sample('sample-import', 'refusal', 'observed-in-use', release)
cli(manifest, 'run')
cli(manifest, 'judge', '--judge-adapter', str(ADAPTER))
cli(manifest, 'report')
