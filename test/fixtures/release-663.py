"""#663 offline regressions through the existing gate CLI and fixture Adapter."""
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import time


def bundle(e):
    # Rename the empty world's epic and release; create actual children anew.
    raw = json.dumps(e.world(()))
    raw = raw.replace('608', '655').replace('648', '662').replace('inheritance', 'bundle')
    d = json.loads(raw); d['_release'] = 662
    for c in (647, 651, 660, 663):
        e.add_child(d, c, epic=655, base='release/655-bundle')
    release = d['pulls/662']
    release.update(state='open', merged=False, merged_at=None)
    release['body'] = '\n'.join(f'Closes #{c}' for c in (655, 647, 651, 660, 663))
    for c in (647, 651, 660, 663):
        d[f'issues/{c}/timeline'].append({'id': 662, 'created_at': e.STAMP,
            'event': 'cross-referenced', 'source': {'issue': dict(release,
                pull_request={'url': f'https://api.github.com/repos/{e.REPO}/pulls/662'})}})
    return d


def exercise_problems(text):
    section = text.split('### S548 ', 1)[-1].split('\n## ', 1)[0].lower()
    flat = re.sub(r'\s+', ' ', section)
    clauses = {
        'structural waiver authority': r'structural.{0,40}waiver.authority',
        'eight retained hashes': r'(?:eight|8).{0,35}(?:retained|non.gate).{0,25}hash',
        'six scopes': r'(?:six|6).{0,25}(?:override )?scopes',
        'nonblank authority': r'non.blank.{0,50}decided.by.{0,30}reason',
        'no panel authority': r'no.{0,20}panel.{0,20}authority',
    }
    problems = [name for name, pattern in clauses.items() if not re.search(pattern, flat)]
    if re.search(r'hashes.{0,90}(?:script, gate|gate and)', flat):
        problems.append('obsolete gate hash')
    return problems


def dependency_hang(t, e, missing):
    clone = t.sandbox / ('hung-' + missing)
    (clone / 'skills/pre-merge-review').mkdir(parents=True)
    (clone / 'lib').mkdir()
    for lib in (t.root / 'lib').iterdir():
        if missing == 'helper' and lib.name == 'model-record-epic.py':
            continue
        (clone / 'lib' / lib.name).symlink_to(lib)
    gate = clone / 'skills/pre-merge-review/model-record-gate.sh'
    shutil.copyfile(t.root / 'skills/pre-merge-review/model-record-gate.sh', gate)
    saved = t.env['PATH']
    if missing == 'python':
        no_python = t.sandbox / 'hung-no-python'; no_python.mkdir()
        script = no_python / 'python3'; script.write_text('#!/bin/sh\nexit 127\n'); script.chmod(0o755)
        t.env['PATH'] = str(no_python) + os.pathsep + saved
    # The 10s watchdog plus 2s grace may legitimately leave the child alive
    # within that bound. Schedule its witness strictly after 12s, never at 6s.
    marker_after = 12.5
    d = e.world(); d['_fault'] = {'key': 'pulls/648', 'mode': 'hung-descendant',
                                'marker_after': marker_after}
    Path(t.env['EPIC_DATA']).write_text(json.dumps(d))
    receipt = Path(t.env['EPIC_LOG'] + '.pids')
    survived = Path(t.env['EPIC_LOG'] + '.orphan-survived')
    ready = Path(t.env['EPIC_LOG'] + '.orphan-ready')
    for path in (receipt, survived, ready):
        path.unlink(missing_ok=True)
    start = time.monotonic()
    p = subprocess.Popen(['bash', str(gate), '648'], cwd=t.sandbox / 'project', env=t.env,
                         text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
    t.arms += 1
    try:
        try:
            out, err = p.communicate(timeout=14)  # 12s contract + 2s scheduling tolerance
            elapsed = time.monotonic() - start
            if p.returncode or not e.accepts(out, err, 'unchecked'):
                t.failures.append(f'{missing} hung initial: expected unchecked without block; {out!r} {err!r}')
            if elapsed > 14:
                t.failures.append(f'{missing} hung initial exceeded bound: {elapsed:.2f}s')
        except subprocess.TimeoutExpired:
            t.failures.append(f'{missing} hung initial exceeded 12s + 2s tolerance')
        if not receipt.exists():
            t.failures.append(f'{missing}: hung initial injection not reached')
        else:
            record = json.loads(receipt.read_text())
            if not ready.exists():
                t.failures.append(f'{missing}: child did not reach marker delay')
            else:
                # Observe past the witness even if the gate returned quickly.
                time.sleep(max(0, float(ready.read_text()) + marker_after + 0.5 - time.time()))
            for pid in record['pids']:
                try:
                    os.kill(pid, 0)
                    t.failures.append(f'{missing}: descendant {pid} survived')
                except ProcessLookupError:
                    pass
            if survived.exists():
                t.failures.append(f'{missing}: orphan survival marker written')
    finally:
        groups = [p.pid]
        if receipt.exists():
            record = json.loads(receipt.read_text()); groups += [record['pgid'], record['child_pgid']]
        for group in set(groups):
            assert group != os.getpgrp()
            try: os.killpg(group, signal.SIGKILL)
            except ProcessLookupError: pass
        p.communicate()
        t.env['PATH'] = saved


def scenario(n, t, e):
    if n in (579, 580, 581):
        t.pr_number = 662
        if n == 579:
            d = bundle(e)
            final = 'model-record: epic #655 inherited Discovery, Planning, Test and Implementation checked for 4 children\n'
            control = json.loads(json.dumps(d))
            for c in (647, 651, 660, 663):
                control[f'issues/{c}/timeline'] = control[f'issues/{c}/timeline'][:1]
            t.run(control, label='control: complete bundle without self events', exact=final)
            assert e.accepts(final, '', 'pass', attributed=True, exact=final)
            assert not e.accepts(final.replace('4 children', '3 children'), '', 'pass', exact=final)
            t.run(d, label='actual bundle self references', exact=final)
            for c in (647, 651, 660, 663):
                d[f'issues/{c}/comments'] = e.comments(*(e.marker(s) for s in e.STAGES if s != 'Test'))
            d['issues/647/comments'].append(e.comments(e.skip('skip=Test'))[0])
            # Pin the complete release-wide skip output, not just absence of blocks.
            expected = ('model-record: epic #655 release PR #662 a pipeline-override waived inherited stage absence for all children: skip=Test\n' + final)
            control = json.loads(json.dumps(d))
            for c in (647, 651, 660, 663):
                control[f'issues/{c}/timeline'] = control[f'issues/{c}/timeline'][:1]
            t.run(control, label='control: release-wide skip without self events', exact=expected)
            assert e.accepts(expected, '', 'pass', attributed=True, exact=expected)
            assert not e.accepts(final, '', 'pass', exact=expected)
            t.run(d, label='actual bundle release-wide Test skip', exact=expected)
        elif n == 580:
            for kind in ('open', 'wrong-base', 'merged-elsewhere'):
                d = bundle(e)
                # Isolate invalid-closer detection from F1: remove only self events.
                for c in (647, 651, 660, 663):
                    d[f'issues/{c}/timeline'] = d[f'issues/{c}/timeline'][:1]
                p = e.pr(9000, 647, 'release/655-bundle')
                if kind == 'open': p.update(state='open', merged_at=None, merged=False)
                elif kind == 'wrong-base': p['base']['ref'] = 'trunk'
                else: p['base']['ref'] = 'release/999-elsewhere'
                d['pulls/9000'] = p; d['issues/9000/comments'] = []; d['pulls/9000/reviews'] = []
                d['issues/647/timeline'].append({'id': 9000, 'created_at': e.STAMP,
                    'event': 'cross-referenced', 'source': {'issue': dict(p,
                        pull_request={'url': f'https://api.github.com/repos/{e.REPO}/pulls/9000'})}})
                t.run(d, 'block', ('child #647', 'closing PR #9000'), kind)
        else:
            d = bundle(e); d['pulls/662/reviews'] = []
            t.run(d, 'block', ('release PR #662', 'Review'), 'release Review still required')
            # A different PR with the release head/base is still a child closer;
            # exclusion must use identity, not merely branch shape.
            d = bundle(e)
            for c in (647, 651, 660, 663):
                d[f'issues/{c}/timeline'] = d[f'issues/{c}/timeline'][:1]
            other = e.pr(9001, 647, 'trunk')
            other.update(state='open', merged=False, merged_at=None)
            other['head']['ref'] = 'release/655-bundle'
            d['pulls/9001'] = other
            d['issues/9001/comments'] = []; d['pulls/9001/reviews'] = []
            d['issues/647/timeline'].append({'id': 9001, 'created_at': e.STAMP,
                'event': 'cross-referenced', 'source': {'issue': dict(other,
                    pull_request={'url': f'https://api.github.com/repos/{e.REPO}/pulls/9001'})}})
            t.run(d, 'block', ('child #647', 'closing PR #9001'), 'same shape, different PR identity')
    elif n == 582:
        e.scenario(565, t)
    elif n in (583, 584):
        dependency_hang(t, e, 'helper' if n == 583 else 'python')
    elif n == 587:
        good = ('### S548 — authority\nStructural waiver-authority oracle; eight retained hashes. '
                'Exactly six override scopes, non-blank decided-by and reason guards, no panel authority.\n')
        assert not exercise_problems(good)
        for clause in ('Structural waiver-authority oracle;', 'eight retained hashes.', 'six override scopes,',
                       'non-blank decided-by and reason guards,', 'no panel authority.'):
            assert exercise_problems(good.replace(clause, ''))
        assert exercise_problems(good + ' Retain hashes: core, script, gate and readers.')
        text = (t.root / 'test/behavior/stage-selection-scenarios.md').read_text()
        t.failures += ['S548 exercise: ' + x for x in exercise_problems(text)]
        # Existing S548 executes the structural oracle and all eight hashes/controls.
        p = subprocess.run(['bash', str(t.root / 'test/cases/s548_stage_selection.sh')], capture_output=True, text=True)
        if p.returncode: t.failures.append('S548 mechanical oracle failed: ' + p.stdout + p.stderr)
    elif n == 588:
        baseline = (t.root / 'test/fixtures/baseline/CHANGES.md.snapshot').read_text()
        section = baseline.split('## process-multi-agent-roles\n', 1)[1].split('\n## ', 1)[0]
        assert '**Meaning version:** 3' in section
        assert 'stage-selection' in section and 'epic stage inheritance' in section
        current = (t.root / 'CHANGES.md').read_text()
        assert baseline.split('## release-branch-workflow\n')[1] == current.split('## release-branch-workflow\n')[1]
        if baseline != current: t.failures.append('CHANGES.md must match approved Meaning v3 snapshot')
