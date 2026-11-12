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
if [ "${PANEL_TEST_CONTENT_ONLY:-0}" != 1 ]; then
  python3 -I "$TEST_REPO_ROOT/test/fixtures/temporary-panel-680-tests.py" 631 --publication-only || fail "S631 complete-envelope publication/readability"
fi
# R7: validate the delivered tree after all examples exist, not the smaller
# intermediate main bundle that existed when its report was first generated.
if [ "${PANEL_TEST_CONTENT_ONLY:-0}" != 1 ]; then
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
fi
# Allow the delivered-tree regression and cap mutation to run independently of
# the existing, longer capture-first property suite.
if [ "${PANEL_TEST_DELIVERED_ONLY:-0}" = 1 ]; then
  test_done
fi
# R8: one content-failure property at the public judge/report/continuation Seams.
# The fixture only prints synthetic output; injected decoder faults use a private
# runner copy and exercise the same CLI, including report in a fresh process.
python3 -I - "$TEST_REPO_ROOT" "$SANDBOX" <<'R8PY' || fail "S631 completed content reportability"
import copy
import importlib.util
import json
import os
from pathlib import Path
import shutil
import shlex
import subprocess
import sys

repo, sandbox = map(Path, sys.argv[1:])
spec = importlib.util.spec_from_file_location('panel_test_fixture', repo / 'test/fixtures/temporary-panel-680-tests.py')
t = importlib.util.module_from_spec(spec); spec.loader.exec_module(t)
base_runner = Path(os.environ.get('PANEL_TEST_RUNNER', repo / 'test/behavior/temporary-panel-run.sh'))
failures = []


def nested_text(shape, depth):
    # Raw text only: no fixture parses or serializes the nested value.
    opens, closes = [], []
    for n in range(depth):
        if shape == 'arrays' or (shape == 'mixed' and n % 2):
            opens.append('['); closes.append(']')
        else:
            key = 'x' * 128 if shape == 'wide' else 'x'
            opens.append('{"' + key + '":'); closes.append((',' + ','.join('"pad' + str(k) + '":0' for k in range(256)) if n == 0 else ',"pad":0') + '}' if shape == 'wide' else '}')
    return ''.join(opens) + '"synthetic"' + ''.join(reversed(closes))


# Measure the local producer decoder transition only to choose test inputs.
# The acceptance oracle below uses the public CLI and never this decoder.
local_spec = importlib.util.spec_from_file_location('local_producer', base_runner.with_name('temporary_panel_run.py'))
producer = importlib.util.module_from_spec(local_spec); local_spec.loader.exec_module(producer)
def accepts_depth(depth):
    try:
        producer.strict_json('{"response":{"verdicts":[{"reason":' + nested_text('objects', depth) + '}]}}')
        return True
    except Exception:
        return False
low, high = 0, sys.getrecursionlimit() * 2
while low + 1 < high:
    mid = (low + high) // 2
    if accepts_depth(mid): low = mid
    else: high = mid
sweep_depths = sorted(set(range(max(1, high - 2), high + 3)) | {983, 984, 1100})
print('S631 local producer transition:', high, 'contiguous sweep + regressions:', sweep_depths, flush=True)


def property_case(transport, ordinal, fault):
    family = fault.startswith('sweep-')
    shape, depth = (fault[6:].rsplit('-', 1) if family else (None, None))
    depth = int(depth) if family else 1100
    raw_nested = nested_text(shape or 'objects', depth)
    name = 'r8-' + transport + '-j' + str(ordinal) + '-' + fault
    f = t.Fixture(sandbox / name)
    following = copy.deepcopy(f.manifest['exercises'][0]); following['id'] = 'following'
    f.manifest['exercises'].append(following)
    f.plan['rows'].append(dict(f.plan['rows'][0], exercise='following'))
    f.plan['pilot'] = dict(exercise='generic-exercise', before=['following']); f.save()
    stderr_path = f.dir / 'completed-stderr'
    adapter_shell = f.adapter.read_text().replace('exec python3 -I ', 'python3 -I ')
    lines = adapter_shell.splitlines()
    lines[-1] += ' 2>' + shlex.quote(str(stderr_path))
    adapter_shell = '\n'.join(lines) + '\nstatus=$?\nprintf "synthetic stderr\\n" >>' + shlex.quote(str(stderr_path)) + '\ncat ' + shlex.quote(str(stderr_path)) + ' >&2\nexit "$status"\n'
    f.adapter.write_text(adapter_shell)
    extra = ('--exercise', 'generic-exercise')
    mode = '--live' if transport == 'native' else '--offline'
    t.RUNNER = base_runner
    if transport == 'native':
        f.native(primary=True, extra=extra)
    else:
        f.cli('run', mode, '--runtime-adapter', str(f.adapter), *extra)
    if not family and fault not in ('nested', 'utf8'):
        folder = f.dir / 'decoder-runner'; folder.mkdir()
        shutil.copy2(base_runner, folder / base_runner.name)
        # Inject an exception outside the JSON/ValueError family; the OSError
        # sample also distinguishes content failures from real storage errors.
        runner_source = base_runner.with_name('temporary_panel_run.py').read_text()
        error = 'OSError' if fault == 'decode-oserror' else 'LookupError'
        injection = ('    if "R8_CONTENT_FAULT" in text and "original_output" not in text:\n'
                     '        raise ' + error + '("synthetic content decoder failure")\n')
        assert runner_source.count('def strict_json(text):\n') == 1
        if fault == 'normalization-error':
            anchor = 'def encoded(obj):\n'
            injection = ('    if isinstance(obj, dict) and obj.get("kind") == "judge" and "R8_CONTENT_FAULT" in json.dumps(obj):\n'
                         '        raise OSError("synthetic content normalization failure")\n')
        elif fault == 'validation-error':
            anchor = 'def judge_verdicts(c, batch, prior_sessions, args):\n'
            injection = ('    if "R8_CONTENT_FAULT" in json.dumps(c):\n'
                         '        raise OSError("synthetic content validation failure")\n')
        elif fault == 'usage-error':
            anchor = 'def object_fields(text):\n'
        else:
            anchor = 'def strict_json(text):\n'
        assert runner_source.count(anchor) == 1
        (folder / 'temporary_panel_run.py').write_text(runner_source.replace(anchor, anchor + injection, 1))
        t.RUNNER = folder / base_runner.name
    reason = 'R8_UTF8_PLACEHOLDER' if fault == 'utf8' else 'R8_NESTED_PLACEHOLDER' if fault == 'nested' or family else 'Valid supported reason.' if fault == 'usage-error' else 'R8_CONTENT_FAULT'
    unknown_usage = fault == 'usage-error' or shape == 'usage'
    wire_expr = '.encode().replace(' + repr(b'"R8_UTF8_PLACEHOLDER"') + ', ' + repr(bytes([34, 255, 34])) + ')'
    if transport == 'native':
        # native() constructs the launcher; amend it just before its CLI call.
        cli = f.cli
        def emit(op, *args, **kw):
            launcher = f.dir / 'native-launcher.py'
            if op == 'judge':
                raw = launcher.read_text()
                replacement = 'output=json.dumps(result)+"\\n"\n'
                if fault == 'nested' or family:
                    replacement += 'if is_judge and req["ordinal"]==' + str(ordinal) + ': output=output.replace(json.dumps("R8_NESTED_PLACEHOLDER"), ' + repr(raw_nested) + ')\n'
                raw = raw.replace('output=json.dumps(result)+"\\n"\n', replacement)
                if fault == 'utf8':
                    # Emit invalid UTF-8 bytes without a producer-side decoder.
                    raw = raw.replace('print(output,end="")',
                        'sys.stdout.flush(); sys.stdout.buffer.write(output' + wire_expr + ')')
                    raw = raw.replace('(here/("completed-judge-"+str(req["ordinal"])+".txt")).write_text(',
                        '(here/("completed-judge-"+str(req["ordinal"])+".txt")).write_bytes((')
                    raw = raw.replace('for r in rows)+output)',
                        'for r in rows)+output)' + wire_expr + ')')
                if shape in ('usage', 'usage-known'):
                    usage_value = raw_nested if shape == 'usage' else '{"inputTokens":13,"cacheReadInputTokens":0,"cacheCreationInputTokens":0,"outputTokens":9,"extra":' + raw_nested + '}'
                    replacement = 'if is_judge and req["ordinal"]==' + str(ordinal) + ': result["modelUsage"]={"claude-opus-5-1":"R9_USAGE_PLACEHOLDER"}\noutput=json.dumps(result)+"\\n"\noutput=output.replace(json.dumps("R9_USAGE_PLACEHOLDER"), ' + repr(usage_value) + ')\n'
                    raw = raw.replace('output=json.dumps(result)+"\\n"\n', replacement)
                launcher.write_text(raw)
                wrapper = f.dir / 'stderr-launcher.sh'
                wrapper.write_text('#!/bin/sh\n' + shlex.quote(str(launcher)) + ' "$@" 2>' + shlex.quote(str(stderr_path)) + '\nstatus=$?\nprintf "synthetic stderr\\n" >>' + shlex.quote(str(stderr_path)) + '\ncat ' + shlex.quote(str(stderr_path)) + ' >&2\nexit "$status"\n')
                wrapper.chmod(0o755)
                args = tuple(str(wrapper) if arg == str(launcher) else arg for arg in args)
            return cli(op, *args, **kw)
        f.cli = emit
        p = f.native('judge', model='claude-opus-5-1', judgment='FAIL' if ordinal == 2 else 'PASS',
            judge_mutation=dict(path=['modelUsage'] if fault == 'usage-error' else ['structured_output', 'verdicts', 0, 'reason'], value='R8_CONTENT_FAULT' if fault == 'usage-error' else reason, ordinal=ordinal), extra=extra, ok=None)
        counter = f.dir / 'native-calls.jsonl'
    else:
        for n in (1, 2):
            c = t.fallback('judge-' + str(n))
            c.update(kind='judge', usage=dict(input=13, cache_read=0, cache_write=0, output=9),
                response=dict(verdicts=[dict(case='control', repetition=1, criterion='reason',
                    verdict='FAIL' if ordinal == 2 else 'PASS', quote=json.loads(c['events'][0]['text'])['body'],
                    reason=reason if n == ordinal else 'Valid supported reason.')]))
            if fault == 'usage-error' and n == ordinal:
                c['usage'] = 'R8_CONTENT_FAULT'
            f.data['judges'].append(c)
        if fault == 'nested' or family:
            adapter = f.dir / 'adapter_impl.py'
            adapter.write_text(adapter.read_text().replace('output=json.dumps(result)+"\\n"',
                'output=(json.dumps(result)+"\\n").replace(json.dumps("R8_NESTED_PLACEHOLDER"), ' + repr(raw_nested) + ')'))
        if fault == 'utf8':
            adapter = f.dir / 'adapter_impl.py'
            raw = adapter.read_text().replace('output=json.dumps(result)+"\\n"',
                'output=(json.dumps(result)+"\\n")' + wire_expr)
            raw = raw.replace('.write_text(output)', '.write_bytes(output)').replace('print(output,end="")', 'sys.stdout.buffer.write(output)')
            adapter.write_text(raw)
        if shape in ('usage', 'usage-known'):
            for c in f.data['judges']:
                if c['session'] == 'judge-' + str(ordinal):
                    c['usage'] = 'R9_USAGE_PLACEHOLDER'
            usage_value = raw_nested if shape == 'usage' else '{"input":13,"cache_read":0,"cache_write":0,"output":9,"extra":' + raw_nested + '}'
            adapter = f.dir / 'adapter_impl.py'
            raw = adapter.read_text().replace('print(output,end="")',
                'output=output.replace(json.dumps("R9_USAGE_PLACEHOLDER"), ' + repr(usage_value) + '); (here/("completed-judge-"+str(request["ordinal"])+".txt")).write_text(output); print(output,end="")')
            adapter.write_text(raw)
        p = f.cli('judge', mode, '--judge-adapter', str(f.adapter), *extra, ok=None)
        counter = f.dir / 'calls.jsonl'
    index = json.loads((f.out / 'evidence/682/index.json').read_text()); call = index['calls'][-1]
    assert p.returncode != 0 and call['completed'] and 'error_capture' in call, name + ' discarded completed attempt: ' + p.stderr
    attempt_path = f.out / call['error_capture']; before_attempt = attempt_path.read_bytes()
    # Strings are opaque; inspect structural depth before any recursive reader.
    level = maximum = 0; quoted = escaped = False
    for ch in before_attempt.decode():
        if quoted:
            if escaped: escaped = False
            elif ch == '\\': escaped = True
            elif ch == '"': quoted = False
        elif ch == '"': quoted = True
        elif ch in '[{': level += 1; maximum = max(maximum, level)
        elif ch in ']}': level -= 1
    assert maximum <= 4, name + ' payload-independent envelope/reportability: nested decoded content'
    a = json.loads(before_attempt)
    expected_fields = {'version', 'kind', 'usable', 'work_item', 'exercise', 'batch', 'ordinal', 'cases', 'call_id', 'transport', 'original_output', 'original_output_encoding', 'original_sha256', 'original_bytes', 'stderr', 'stderr_encoding', 'stderr_sha256', 'stderr_bytes', 'usage', 'raw_usage', 'session', 'runtime', 'model', 'errors'}
    assert set(a) == expected_fields and a['session'] == 'unknown' and a['model'] == 'unknown', name + ' payload-independent envelope/reportability: untrusted fields'
    assert a['original_bytes'] == len(a['original_output'].encode(a['original_output_encoding'])), name + ' stdout length changed'
    original_stderr = stderr_path.read_bytes()
    assert a['stderr'].encode(a['stderr_encoding']) == original_stderr and a['stderr_bytes'] == len(original_stderr) and a['stderr_sha256'] == t.sha(original_stderr), name + ' stderr bytes/hash/length changed'
    original = (f.dir / ('completed-judge-' + str(ordinal) + '.txt')).read_bytes()
    assert a['original_output'].encode(a.get('original_output_encoding', 'utf-8')) == original and a['original_sha256'] == t.sha(original), name + ' original-output/evidence-loss'
    assert a['usable'] is False and a['call_id'] == len(index['calls']) and a['work_item'] == 682, name + ' call identity lost'
    assert (a['exercise'], a['batch'], a['ordinal'], a['cases']) == ('generic-exercise', 'one', ordinal, [dict(case='control', repetition=1)]), name + ' request binding lost'
    judge_calls = [c for c in index['calls'] if c['kind'] == 'judge']
    assert len(judge_calls) == ordinal and sum(c.get('attempt_capture') == call['attempt_capture'] for c in judge_calls) == 1, name + ' completed call counted more than once'
    assert call['attempt_capture'] == call['error_capture'] and call['usage'] == a['usage'] and call['session'] == a['session'], name + ' ledger binding lost'
    r = f.cli('report', mode, ok=None)
    assert r.returncode == 0, name + ' content failure is not reportable: ' + r.stderr
    assert a['errors'] == ['CONTENT_INVALID'] and (a['raw_usage'] is None or isinstance(a['raw_usage'], str)), name + ' payload-independent envelope/reportability: decoded usage or diagnostic'
    text = (f.out / 'results-682.md').read_text()
    assert a['errors'][0] in text and 'awaiting qualification' not in text, name + ' missing flat content failure code'
    assert 'Original completed output:' in text and 'LAB: PASS' not in text, name + ' erased unusable output'
    if unknown_usage:
        assert all(v is None for v in a['usage'].values()) and ('R8_CONTENT_FAULT' in a['original_output'] or isinstance(a['raw_usage'], str)), name + ' unrecoverable usage fabricated zero or lost raw evidence'
        assert 'unknown_calls' in text and '"input": null' in text, name + ' report did not identify unknown usage'
    else:
        assert a['usage'] == dict(input=13, cache_read=0, cache_write=0, output=9), name + ' recoverable usage lost'
    assert not (f.out / 'STOP').exists() and not list((f.out / '.private-recovery').glob('call-*')), name + ' unrelated permanent publication stop'
    before = counter.read_bytes(); records = copy.deepcopy(index['records'])
    if transport == 'native':
        f.native('judge', model='claude-opus-5-1', extra=extra, ok=False)
        f.native(primary=True, extra=('--exercise', 'following'), ok=False)
    else:
        f.cli('judge', mode, '--judge-adapter', str(f.adapter), *extra, ok=False)
        f.cli('run', mode, '--runtime-adapter', str(f.adapter), '--exercise', 'following', ok=False)
    assert counter.read_bytes() == before and json.loads((f.out / 'evidence/682/index.json').read_text())['records'] == records, name + ' retry/continuation started calls or observations'
    assert attempt_path.read_bytes() == before_attempt, name + ' unusable attempt replaced'
    if transport == 'offline' and ordinal == 1 and fault == 'nested':
        # The trusted reader rejects structural envelope tampering before its
        # recursive decoder; opaque bracket text above must still report.
        tampered = before_attempt.rstrip()[:-1] + b',"untrusted":' + nested_text('objects', sys.getrecursionlimit() + 100).encode() + b'}'
        attempt_path.write_bytes(tampered)
        bad = f.cli('report', mode, ok=None)
        assert bad.returncode == 2 and 'JSON structural limit exceeded' in bad.stderr and 'RecursionError' not in bad.stderr, name + ' trusted envelope depth guard failed'
        assert counter.read_bytes() == before, name + ' tampered envelope started calls'
        attempt_path.write_bytes(before_attempt)
    print(name + ': reportable, byte-exact, usage available/unknown, zero retry/continuation', flush=True)


tasks = [(transport, ordinal, fault)
         for transport in ('native', 'offline') for ordinal in (1, 2)
         for fault in (['nested', 'decode-error', 'decode-oserror', 'usage-error', 'normalization-error', 'validation-error', 'utf8'] + ['sweep-' + shape + '-' + str(depth) for shape in ('objects', 'arrays', 'mixed', 'wide', 'usage', 'usage-known') for depth in sweep_depths])
         if not os.environ.get('PANEL_TEST_CONTENT_PROBE') or os.environ['PANEL_TEST_CONTENT_PROBE'] == 'r8-' + transport + '-j' + str(ordinal) + '-' + fault]
# Each worker has its own fixture and runner binding. Parallel processes keep
# the full sweep affordable without sharing mutable Adapter/runner state.
if len(tasks) == 1:
    try:
        property_case(*tasks[0])
    except AssertionError as exc:
        failures.append(str(exc)); print('FAIL: ' + str(exc), flush=True)
else:
    import multiprocessing
    with multiprocessing.get_context('fork').Pool(4) as pool:
        results = [pool.apply_async(property_case, task) for task in tasks]
        for result in results:
            try:
                result.get()
            except AssertionError as exc:
                failures.append(str(exc)); print('FAIL: ' + str(exc), flush=True)
assert not failures, '\n'.join(failures)
# These mutants change only the named guard. Each must fail at its behavioral
# reportability/retention assertion, never merely at setup or syntax.
if not os.environ.get('PANEL_TEST_CONTENT_ONLY') and not os.environ.get('PANEL_TEST_SKIP_MUTATIONS'):
    original_source = base_runner.with_name('temporary_panel_run.py').read_text()
    for name, old, new, probe, diagnostic in (
        ('decoded-envelope-reinsertion',
         '            attempt["errors"] = ["CONTENT_INVALID"]',
         '            attempt["capture"] = c\n            attempt["errors"] = ["CONTENT_INVALID"]',
         'r8-offline-j1-validation-error', 'payload-independent envelope/reportability'),
        ('remove-usage-containment',
         '    except Exception:\n        return dict.fromkeys(USAGE), raw',
         '    except (Invalid, ValueError):\n        return dict.fromkeys(USAGE), raw',
         'r8-native-j1-usage-error', 'content failure is not reportable'),
        ('depth-only-containment',
         '    except Exception as exc:\n        if not enabled or isinstance(exc, Invalid):',
         '    except RecursionError as exc:\n        if not enabled or isinstance(exc, Invalid):',
         'r8-native-j1-decode-oserror', 'content failure is not reportable'),
        ('swallow-storage-failure',
         '    def put(self, name, obj):\n',
         '    def put(self, name, obj):\n        try:\n            self._put(name, obj)\n        except OSError:\n            pass\n\n    def _put(self, name, obj):\n',
         None, 'storage/publication failure claimed successful retention')):
        folder = sandbox / ('mutant-' + name); folder.mkdir()
        shutil.copy2(base_runner, folder / base_runner.name)
        assert original_source.count(old) == 1, name + ' mutation anchor not unique'
        (folder / 'temporary_panel_run.py').write_text(original_source.replace(old, new, 1))
        env = dict(os.environ, PANEL_TEST_RUNNER=str(folder / base_runner.name), PANEL_TEST_SKIP_MUTATIONS='1')
        if probe:
            env.update(PANEL_TEST_CONTENT_ONLY='1', PANEL_TEST_CONTENT_PROBE=probe)
            cmd = ['bash', str(repo / 'test/cases/s631_exercise_evidence_retention.sh')]
        else:
            cmd = [sys.executable, '-I', str(repo / 'test/fixtures/temporary-panel-680-tests.py'), '631', '--chronology-probe', 'r6-private-storage']
        p = subprocess.run(cmd, capture_output=True, text=True, env=env)
        assert p.returncode != 0 and diagnostic in p.stdout + p.stderr, name + ' survived or failed for an unrelated reason: ' + p.stdout + p.stderr
        print('S631: killed ' + name + ' at ' + diagnostic, flush=True)
R8PY
if [ "${PANEL_TEST_CONTENT_ONLY:-0}" = 1 ]; then
  test_done
fi
python3 -I "$TEST_REPO_ROOT/test/fixtures/temporary-panel-680-tests.py" 631 || fail "S631 offline CLI assertions"
test_done
