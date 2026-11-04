#!/usr/bin/env python3
"""Offline REST adapter and CLI assertions for A52. No production imports."""
import fcntl
import json
import shutil
import signal
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from urllib.parse import parse_qs

STAMP = '2026-11-03T00:00:00Z'
REPO = 'fixture/project'
STAGES = ('Discovery', 'Planning', 'Test', 'Implementation')


def marker(stage):
    basis = ' floor-basis="stronger model than Implementation"' if stage == 'Review' else ''
    return '<!-- model-record: stage=' + stage + ' model="opus"' + basis + ' -->'


def skip(stage):
    return '<!-- pipeline-override: decided-by="maintainer" scope="' + stage + '" reason="standing class decision" -->'


def comments(*bodies):
    return [dict(id=i + 1, body=b, created_at=STAMP, updated_at=STAMP, submitted_at=STAMP)
            for i, b in enumerate(bodies)]


def issue(n, body):
    return dict(number=n, id=n, title='Work', body=body, state='closed',
                created_at=STAMP, updated_at=STAMP, url=f'https://api.github.com/repos/{REPO}/issues/{n}',
                html_url=f'https://github.com/{REPO}/issues/{n}')


def pr(n, child, base):
    p = issue(n, f'Closes #{child}')
    p.update(merged_at=STAMP, merged=True, head={'ref': f'feature/{child}-work', 'sha': 'a' * 40,
             'repo': {'full_name': REPO}}, base={'ref': base, 'sha': 'b' * 40, 'repo': {'full_name': REPO}})
    return p


def add_child(d, c, epic=608, base='release/608-inheritance', records=True, with_pr=True, listed=True):
    """One member: live field, epic timeline event (stale embedded copy), list row, closing PR."""
    d[f'issues/{c}'] = issue(c, f'**Epic:** #{epic}')
    d[f'issues/{c}/comments'] = comments(*(marker(s) for s in STAGES)) if records else []
    d[f'issues/{c}/timeline'] = []
    d[f'issues/{epic}/timeline'].append({'id': c, 'created_at': STAMP, 'event': 'cross-referenced',
        'source': {'type': 'issue', 'issue': issue(c, f'stale copy mentions #{epic}')}})
    if listed:
        d[f'issues/{epic}']['body'] += f'- [x] #{c} work\n'
    if with_pr:
        p = pr(c + 1000, c, base)
        d['pulls'].append(p)
        d[f'pulls/{c + 1000}'] = p
        d[f'issues/{c + 1000}/comments'] = []
        d[f'pulls/{c + 1000}/reviews'] = []
        d[f'issues/{c}/timeline'].append({'id': c, 'created_at': STAMP, 'event': 'cross-referenced', 'source': {'issue': dict(p, pull_request={
            'url': f'https://api.github.com/repos/{REPO}/pulls/{c + 1000}'})}})


def plain(d, n):
    """An issue that carries no Epic field (a listed or closed-by-PR non-member), readable in full."""
    d[f'issues/{n}'] = issue(n, 'no Epic field')
    d[f'issues/{n}/comments'] = []
    d[f'issues/{n}/timeline'] = []


def mention(d, n, body='unrelated', epic=608):
    """A timeline-only candidate: it mentions the epic but carries no Epic field."""
    d[f'issues/{n}'] = issue(n, body)
    d[f'issues/{n}/comments'] = []
    d[f'issues/{epic}/timeline'].append({'id': n, 'created_at': STAMP, 'event': 'cross-referenced',
        'source': {'type': 'issue', 'issue': issue(n, '**Epic:** #' + str(epic) if body == 'embedded' else 'mentions')}})


def world(children=(609, 610)):
    # No issue collection exists: the repository's issue list must never be read.
    data = {'': {'full_name': REPO, 'default_branch': 'trunk'}, 'pulls': []}
    data['pulls/648'] = pr(648, 608, 'trunk')
    data['pulls/648']['head']['ref'] = 'release/608-inheritance'
    data['issues/648/comments'] = []
    data['compare/trunk...' + 'a' * 40] = {'behind_by': 0}
    data['pulls/648/commits'] = []
    data['pulls/648/reviews'] = comments(marker('Review'))
    data['issues/608'] = issue(608, '## Work items\n')
    data['issues/608/comments'] = []
    # Epic timeline noise that is never a candidate: a PR source, a foreign
    # repository source, a label and a source-less event.
    pr_src = dict(issue(4001, 'mentions #608'), pull_request={'url': f'https://api.github.com/repos/{REPO}/pulls/4001'})
    foreign = dict(issue(4002, 'mentions #608'), url='https://api.github.com/repos/other/project/issues/4002')
    data['issues/608/timeline'] = [
        {'id': 1, 'created_at': STAMP, 'event': 'labeled'},
        {'id': 2, 'created_at': STAMP, 'event': 'cross-referenced', 'source': {'type': 'issue', 'issue': pr_src}},
        {'id': 3, 'created_at': STAMP, 'event': 'cross-referenced', 'source': {'type': 'issue', 'issue': foreign}},
        {'id': 4, 'created_at': STAMP, 'event': 'cross-referenced'}]
    for c in children:
        add_child(data, c)
    return data


def violate(message):
    """Record a forbidden read where the gate cannot swallow it, then fail the call."""
    with open(os.environ['EPIC_LOG'] + '.viol', 'a') as f:
        f.write(message + '\n')
    sys.exit(message)


class Locked:
    def __init__(self, path):
        self.path = path

    def __enter__(self):
        self.f = open(self.path + '.lock', 'a+')
        fcntl.flock(self.f, fcntl.LOCK_EX)
        return self

    def __exit__(self, *exc):
        self.f.close()


def concurrency(delta):
    path = os.environ['EPIC_LOG'] + '.conc'
    with Locked(path):
        try:
            state = json.loads(Path(path).read_text())
        except (OSError, ValueError):
            state = {'active': 0, 'max': 0}
        state['active'] += delta
        state['max'] = max(state['max'], state['active'])
        Path(path).write_text(json.dumps(state))


def serve():
    args = sys.argv[2:]
    if args[:2] == ['pr', 'view']:
        print(json.dumps({'headRefOid': '1' * 40, 'comments': [
            {'body': '<!-- pre-merge-review:done sha=' + '1' * 40 + ' -->'}]}))
        return
    if args[:2] == ['pr', 'checks']:
        print('[{"bucket":"pass","name":"check"}]'); return
    if not args or args.pop(0) != 'api':
        sys.exit('unexpected non-REST call')
    endpoint = args.pop(0)
    pending = list(args)
    while pending:
        flag = pending.pop(0)
        if flag in ('--jq', '-q', '-H', '--header'):
            if not pending: sys.exit('missing CLI flag argument')
            pending.pop(0)
        elif flag == '--method':
            if not pending or pending.pop(0) != 'GET': sys.exit('non-read REST request refused')
        elif flag != '--paginate':
            sys.exit('unexpected CLI argument: ' + flag)
    with open(os.environ['EPIC_DATA']) as f:
        data = json.load(f)
    with open(os.environ['EPIC_LOG'], 'a') as f:
        f.write(json.dumps([endpoint, args]) + '\n')
    concurrency(1)
    try:
        respond(data, endpoint, args)
    finally:
        concurrency(-1)


def respond(data, endpoint, args):
    path, _, query = endpoint.partition('?')
    match = re.fullmatch(r'repos/(?:fixture/project|\{owner\}/\{repo\})(?:/(.*))?', path)
    if not match:
        violate('unexpected endpoint: ' + endpoint)
    key = match[1] or ''
    if key == 'issues':
        violate('forbidden repository issue scan: ' + endpoint)
    if key in data.get('_forbidden', ()):
        violate('forbidden read of unrelated object: ' + endpoint)
    if key == 'pulls/648': Path(os.environ['EPIC_LOG'] + '.detail').touch()
    q = parse_qs(query)
    page = int(q.get('page', ['1'])[0])
    counter = Path(os.environ['EPIC_LOG'] + '.counts')
    with Locked(str(counter)):
        counts = json.loads(counter.read_text()) if counter.exists() else {}
        counts[key] = counts.get(key, 0) + 1
        counter.write_text(json.dumps(counts))
    if data.get('_delay'):
        time.sleep(data['_delay'])
    fault = data.get('_fault', {})
    active = key == fault.get('key') and page == fault.get('page', 1) and counts[key] >= fault.get('after', 1)
    if active:
        mode = fault.get('mode', 'error')
        if mode == 'hung-descendant':
            # Runner starts gh in a separate session/group from the worker.
            # Its child also owns a separate group and must not outlive the gate.
            child = subprocess.Popen([sys.executable, '-c',
                'import pathlib,time; pathlib.Path(' +
                repr(os.environ['EPIC_LOG'] + '.orphan-ready') +
                ').write_text(str(time.time())); time.sleep(6); pathlib.Path(' +
                repr(os.environ['EPIC_LOG'] + '.orphan-survived') +
                ').touch(); time.sleep(20)'], start_new_session=True, stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            Path(os.environ['EPIC_LOG'] + '.pids').write_text(json.dumps(
                {'pids': [os.getpid(), child.pid], 'pgid': os.getpgrp(),
                 'child_pgid': os.getpgid(child.pid)}))
            time.sleep(30)
        elif mode == 'delay':
            time.sleep(11)
        elif mode == 'error':
            sys.exit('gh: injected failure (HTTP ' + str(fault.get('status', 500)) + ')')
        elif mode == 'malformed':
            print('{broken'); return
        elif mode == 'oversize':
            sys.stdout.write('[' + ' ' * (8 * 1024 * 1024 - 2) + ']'); return
    if any(re.fullmatch(r'(?:issues|pulls)/' + m + r'(?:/.*)?', key) for m in data.get('_missing', ())):
        sys.exit('gh: Not Found (HTTP 404)')
    if key not in data and re.fullmatch(r'issues/\d+', key) and key + '/comments' in data:
        data[key] = issue(int(key.split('/')[1]), '')  # a PR or closing issue read as an issue object
    if key not in data:
        violate('unexpected endpoint: ' + endpoint)
    value = data[key]
    if isinstance(value, dict) and '_pad' in value:
        value = dict(value, body=value['body'] + 'x' * value['_pad'])
    if active and fault.get('mode') == 'changed':
        value = json.loads(json.dumps(value))
        change = fault.get('change', 'updated_at')
        if change == 'body': value['body'] = fault.get('body', value['body'] + '\nchanged')
        elif change == 'state': value['state'] = 'open'
        elif change == 'base': value['base']['ref'] = 'different-base'
        elif change == 'head': value['head']['sha'] = 'c' * 40
        elif change == 'merged_at': value['merged_at'] = None
        else: value['updated_at'] = '2026-11-03T00:01:00Z'
    if isinstance(value, list) and ('page' in q):
        if q.get('per_page') != ['100']:
            sys.exit('collection must request per_page=100')
        value = value[(page - 1) * 100:page * 100]
    if key == 'pulls' and q.get('base') != [data['pulls/648']['head']['ref']]:
        sys.exit('release ref missing or incorrectly encoded')
    raw = json.dumps(value)
    expr = None
    for flag in ('--jq', '-q'):
        if flag in args:
            expr = args[args.index(flag) + 1]
    if expr:
        p = subprocess.run(['jq', '-r', expr], input=raw, text=True)
        sys.exit(p.returncode)
    print(raw)


ATTRIBUTED = re.compile(r'(?:role-played|model-record): epic #\d+ (?:release PR #\d+|child #\d+) |'
                        r'model-record: epic #\d+ inherited Discovery, Planning, Test and Implementation checked for \d+ children$')


def accepts(out, err, kind, names=(), absent=(), attributed=False, exact=None, line=None):
    blocks = '\n'.join(x for x in out.splitlines() if x.startswith('role-played: '))
    if attributed and kind != 'unchecked':
        if 'no record found' in out or any(x and not ATTRIBUTED.match(x) for x in out.splitlines()):
            return False
    if exact is not None and out != exact:
        return False
    if any(x in out for x in absent):
        return False
    if kind == 'pass':
        return not blocks and 'role-play-unchecked:' not in out and not err
    if kind == 'unchecked':
        return ('role-play-unchecked: ' in out and not blocks and (line is None or line in out.splitlines())
                and 'warning:' in err)
    return bool(blocks) and all(x in blocks for x in names) and 'role-play-unchecked:' not in out


class Check:
    def __init__(self, root, sandbox):
        self.root, self.sandbox = Path(root), Path(sandbox)
        self.env = dict(os.environ, EPIC_DATA=str(self.sandbox / 'world.json'), EPIC_LOG=str(self.sandbox / 'calls'))
        self.failures = []
        self.arms = 0
        # Independent compliant controls, then output mutations.
        assert accepts('', '', 'pass')
        assert accepts('role-played: epic #608 child #609 Test\n', '', 'block', ('#609', 'Test'))
        assert accepts('role-play-unchecked: failed read\n', 'warning: read failed', 'unchecked')
        # Independent output mutations: pass/block/unchecked and erased child/stage.
        assert not accepts('role-played: epic #608 child #609 Test\n', '', 'pass')
        assert not accepts('', '', 'block', ('#609', 'Test'))
        assert not accepts('role-played: epic #608 Test\n', '', 'block', ('#609', 'Test'))
        assert not accepts('role-played: epic #608 child #609\n', '', 'block', ('#609', 'Test'))
        assert not accepts('', '', 'unchecked')
        assert not accepts('role-play-unchecked: error\nrole-played: stale\n', '', 'unchecked')
        # Output-shape controls: attribution, literal pass line, absent text, exact unchecked line.
        final = 'model-record: epic #608 inherited Discovery, Planning, Test and Implementation checked for 19 children\n'
        assert accepts(final, '', 'pass', attributed=True, exact=final)
        assert not accepts('model-record: no record found for stage Test (missing model-choice marker)\n' + final, '', 'pass', attributed=True)
        assert not accepts('model-record: child #609 near-miss\n' + final, '', 'pass', attributed=True)
        assert not accepts('model-record: epic #608 child #609 waived stage absence\n' + final, '', 'pass', exact=final)
        assert not accepts(final.replace('19', '18'), '', 'pass', exact=final)
        assert accepts('role-played: epic #608 child #617 stages missing: Test\nmodel-record: epic #608 release PR #648 near-miss\n', '', 'block', ('#617',), attributed=True)
        assert not accepts('role-played: epic #608 child #617 stages missing: Test\nmodel-record: no record found for stage Test\n', '', 'block', ('#617',), attributed=True)
        assert not accepts('role-played: epic #608 child #609 Test\nrole-played: epic #608 child #610 Test\n', '', 'block', ('#609',), absent=('#610',))
        wanted = 'role-play-unchecked: closing reference #9999 on epic release PR #648 does not exist (HTTP 404)'
        assert accepts(wanted + '\n', 'warning: x', 'unchecked', line=wanted)
        assert not accepts(wanted.replace('9999', '9998') + '\n', 'warning: x', 'unchecked', line=wanted)
        assert not accepts(wanted + '\n', '', 'unchecked', line=wanted)
        assert not accepts(wanted + '\nrole-played: stages missing: Test\n', 'warning: x', 'unchecked', line=wanted)

    def run(self, d, kind='pass', names=(), label='', gate=None, attributed=True, absent=(), exact=None, line=None):
        self.arms += 1
        Path(self.env['EPIC_DATA']).write_text(json.dumps(d))
        for suffix in ('', '.counts', '.detail', '.slow', '.viol', '.conc', '.counts.lock', '.conc.lock'):
            Path(self.env['EPIC_LOG'] + suffix).unlink(missing_ok=True)
        cmd = ['bash', str(gate or self.root / 'skills/pre-merge-review/model-record-gate.sh'), '648']
        try:
            p = subprocess.run(cmd, cwd=self.sandbox / 'project', env=self.env, text=True,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=135)
            ok = p.returncode == 0 and accepts(p.stdout, p.stderr, kind, names, absent, attributed, exact, line)
            if not ok:
                self.failures.append(f'{label}: expected {kind} {names}; exit={p.returncode}; stdout={p.stdout[:1500]!r}; stderr={p.stderr[:600]!r}')
            viol = Path(self.env['EPIC_LOG'] + '.viol')
            if viol.exists():
                self.failures.append(f'{label}: forbidden REST read: ' + '; '.join(sorted(set(viol.read_text().splitlines()))[:3]))
            return p
        except subprocess.TimeoutExpired:
            self.failures.append(label + ': external 135s watchdog fired; gate did not bound traversal')
            return None

    def concurrent(self):
        try:
            return json.loads(Path(self.env['EPIC_LOG'] + '.conc').read_text())['max']
        except (OSError, ValueError, KeyError):
            return 0

    def doc(self, path, groups):
        text = (self.root / path).read_text()
        flat = re.sub(r'\s+', ' ', text).lower()
        control = (
            'Normalize Epic fields and Work items before release. Record child count and epic ledger complete: yes. '
            'The ledger is a view. An open child gives no. Late Epic fields count. Unchecked cannot justify yes. '
            'Any closing issue skip waives the whole release. The A18 override amendment and membership amendment '
            'require maintainer acceptance.'
            if 'release-branch' in path else
            'Any session can forge model-records and human overrides. This does not authenticate authorship. '
            'Limits: 100 children; 200 candidates; 40 calls for one child; 1200 calls; 8 concurrent reads; '
            '120 seconds; 64 MiB; 10 seconds; 1000 comments or reviews per collection; 1000 timeline events. '
            'A cap yields role-play-unchecked. A closing reference with HTTP 404 on an epic release PR is unchecked. '
            'Residual gap: a missing or delayed cross-referenced timeline event hides an unlisted member. '
            'Discovery never reads every issue in the repository.'
        ).lower()
        for group in groups:
            assert re.search(group, control), 'compliant documentation control failed: ' + group
            assert not re.search(group, re.sub(group, '', control)), 'clause deletion survived'
            if not re.search(group, flat):
                self.failures.append(f'{path}: missing policy clause /{group}/')
            # Clause deletion must defeat the exact same content check.
            assert not re.search(group, re.sub(group, '', flat))
        if path.startswith('skills/'):
            import difflib
            old = subprocess.run(['git', 'show', 'HEAD:' + path], cwd=self.root,
                                 text=True, capture_output=True, check=True).stdout
            added = [line[2:] for line in difflib.ndiff(old.splitlines(), text.splitlines())
                     if line.startswith('+ ')]
            if any('TiesL' in line for line in added):
                self.failures.append(path + ': new skill text must say maintainer')


def disposition(d, c):
    d['pulls'] = [p for p in d['pulls'] if p['number'] != c + 1000]
    d[f'issues/{c}/timeline'] = []
    d[f'issues/{c}/comments'] = comments(*(skip('skip=' + s) for s in STAGES))


def context_problems(gate_out, hook_err):
    """The hook shows all role-played lines first and only model-record lines for the release PR
    or a child named in a role-played line; a missing child is never behind other children's context."""
    problems = []
    named = set(re.findall(r'role-played: epic #\d+ child #(\d+) ', gate_out))
    shown = [x.strip() for x in hook_err.splitlines()]
    for line in gate_out.splitlines():
        if line.startswith('role-played: ') and line not in shown:
            problems.append('role-played line missing from the hook message: ' + line)
    for line in gate_out.splitlines():
        m = re.match(r'model-record: epic #\d+ (release PR #\d+|child #(\d+)) ', line)
        if not m: continue
        wanted = m[1].startswith('release') or m[2] in named
        if wanted and line not in shown: problems.append('context line dropped: ' + line)
        if not wanted and line in shown: problems.append('context line for an unnamed child leaked: ' + line)
    return problems


def hook_filter(t, gate_out, hook_err):
    gate_context = [x for x in gate_out.splitlines() if x.startswith('model-record: epic #608 child #610 ')]
    release_context = [x for x in gate_out.splitlines() if x.startswith('model-record: epic #608 release PR #648 ')]
    if not gate_context or not release_context:
        t.failures.append('hook-filter fixture ineffective: the gate printed no attributed near-miss for child #610 and the release PR')
    problems = context_problems(gate_out, hook_err)
    t.failures.extend('hook context filter: ' + x for x in problems)
    # Controls: the same inputs with a leaked unnamed-child line, or a dropped release line, are rejected.
    sample = ('role-played: epic #608 child #609 stages missing: Test\n'
              'model-record: epic #608 child #610 near-miss\nmodel-record: epic #608 release PR #648 near-miss\n')
    good = 'role-played: epic #608 child #609 stages missing: Test\nmodel-record: epic #608 release PR #648 near-miss\n'
    assert not context_problems(sample, good)
    assert context_problems(sample, sample)
    assert context_problems(sample, good.replace('model-record: epic #608 release PR #648 near-miss\n', ''))
    assert context_problems(sample, good.split('\n', 1)[1])


def normalized_608():
    children = tuple(range(609, 626)) + (643, 649)
    d = world(children)
    waived = (609, 611, 613, 614, 619, 622, 623, 624, 643, 649)
    implemented = (610, 612, 615, 616, 618, 620, 621)
    assert len(set(children)) == 19 and len(implemented) + len(waived) + 2 == 19
    for c in implemented:
        d[f'issues/{c}/comments'] = comments(*(marker(s) for s in STAGES[:3]))
        d[f'issues/{c+1000}/comments'] = comments(marker('Implementation'))
    for c in waived:
        d[f'issues/{c}/comments'] = comments(*(marker(s) for s in STAGES[:3]), skip('skip=Implementation'))
    for c in (617, 625):
        disposition(d, c)
    return d


def scenario(n, t):
    d = world()
    if n == 549:
        d = normalized_608()
        final = 'model-record: epic #608 inherited Discovery, Planning, Test and Implementation checked for 19 children\n'
        t.run(d, label='normalized 7 implemented + 10 waived + 2 dispositions: literal one-line pass', exact=final)
        d['issues/617/comments'] = []
        p = t.run(d, 'block', ('epic #608', 'child #617', 'Implementation'), 'one of all 19 uncovered',
                  absent=('child #609', 'child #625', 'no record found'))
        if p and 'role-played: epic #608 child #617 stages missing: Discovery, Planning, Test, Implementation\n' not in p.stdout:
            t.failures.append('removal block lacks the attributed legacy stages-missing text for child #617')
    elif n == 550:
        for source in ('issue', 'description', 'comment', 'review'):
            a = world()
            if source != 'issue':
                a['issues/609/comments'] = []
                p = a['pulls/1609']
                if source == 'description':
                    p['body'] += '\n' + marker('Discovery')
                    a['issues/1609/comments'] = comments(*(marker(s) for s in STAGES[1:]))
                else:
                    a['issues/1609/comments' if source == 'comment' else 'pulls/1609/reviews'] = comments(*(marker(s) for s in STAGES))
            t.run(a, label=source)
        for body in ('> ' + marker('Test'), '```\n' + marker('Test') + '\n```', 'inline ' + marker('Test')):
            a = world()
            a['issues/609/comments'] = comments(*(marker(s) for s in STAGES if s != 'Test'), body)
            p = t.run(a, 'block', ('child #609', 'Test'), 'quoted or inline child marker')
            if body.startswith('inline') and p and 'near-miss' not in p.stdout:
                t.failures.append('inline child marker lost near-miss context')
    elif n == 551:
        for c in (609, 610):
            disposition(d, c)
        t.run(d, label='all four child skips; no PRs')
    elif n == 552:
        for c in (609, 610):
            for s in STAGES:
                a = world()
                a[f'issues/{c}/comments'] = comments(*(marker(x) for x in STAGES if x != s))
                a['issues/648/comments'] = comments(*(marker(x) for x in STAGES))
                t.run(a, 'block', ('epic #608', f'child #{c}', s), f'no quorum {c}/{s}')
    elif n == 553:
        for c in (609, 610):
            d[f'issues/{c}/comments'] = comments('recorded: https://example.invalid/no-marker')
        d['issues/608/comments'] = comments('Ledger: child #609 recorded all stages https://example.invalid/record')
        t.run(d, 'block', ('child #609', 'child #610'), 'ledger is not evidence')
    elif n == 554:
        d['pulls/648/reviews'] = []
        d['issues/608/comments'] = comments(marker('Review'))
        d['pulls/1609/reviews'] = comments(marker('Review'))
        t.run(d, 'block', ('Review',), 'epic/child review cannot replace release review')
        d['pulls/648/reviews'] = comments('<!-- model-record: stage=Review model="opus" -->')
        p = t.run(d, label='Review floor basis')
        if p and 'no floor-basis' not in p.stdout:
            t.failures.append('Review without floor basis must retain diagnostic')
    elif n == 555:
        disposition(d, 609)
        t.run(d, label='disposition with four skips')
        for bodies in (('closed by disposition',), tuple(marker(s) for s in STAGES)):
            d['issues/609/comments'] = comments(*bodies)
            t.run(d, 'block', ('child #609',), 'no-PR requires skips, not prose or records')
    elif n == 556:
        for body in ('', '**Epic:** #999', '**Epic:** #608\n**Epic:** #608', '**Epic:** #608\n**Epic:** #999', '> **Epic:** #608', '```\n**Epic:** #608\n```'):
            a = world(); a['issues/609']['body'] = body
            t.run(a, 'block', ('#609',), 'missing/conflicting/repeated/quoted field ' + repr(body))
    elif n == 557:
        for arm in ('extra-list', 'extra-field', 'timeline-only-member', 'duplicate', 'foreign', 'missing-section', 'ambiguous-section', 'malformed-row'):
            a = world()
            if arm == 'extra-field':
                a['issues/608']['body'] = '## Work items\n- [x] #609'
            elif arm == 'timeline-only-member':
                # Field present and discoverable only through the epic timeline: not listed, no closing PR.
                add_child(a, 611, listed=False, with_pr=False)
            elif arm == 'extra-list':
                a['issues/608']['body'] += '- [x] #611\n'; plain(a, 611)
            elif arm == 'duplicate':
                a['issues/608']['body'] += '- [x] #609\n'
            elif arm == 'foreign':
                a['issues/608']['body'] = '## Work items\n- [x] other/repo#609\n- [x] #610'
            elif arm == 'missing-section':
                a['issues/608']['body'] = 'Ledger #609 #610'
            elif arm == 'ambiguous-section':
                a['issues/608']['body'] += '\n## Work items\n- [x] #609'
            else:
                a['issues/608']['body'] += '- [maybe] #611\n'; plain(a, 611)
            names = ('epic #608', '#611') if arm == 'timeline-only-member' else ('epic #608',)
            t.run(a, 'block', names, arm)
        # Timeline candidates without a live field are not members, whatever the stale embedded copy says.
        a = world(); mention(a, 4100); mention(a, 4101, 'embedded')
        t.run(a, label='mentions and stale embedded field copies are not members')
        # A same-repository issue with a live field and no timeline event is the documented residual gap.
    elif n == 558:
        for body in ('Closes #611', 'Closes #609\nCloses #611', 'mentions #609', 'Closes other/repo#609'):
            a = world(); a['pulls/1609']['body'] = body
            if '#611' in body: plain(a, 611)
            t.run(a, 'block', ('#1609',), body)
    elif n == 559:
        for state in ('open-child', 'open-pr', 'unmerged', 'wrong-base'):
            a = world()
            if state == 'open-child': a['issues/609']['state'] = 'open'
            elif state == 'open-pr': a['pulls/1609']['state'] = 'open'; a['pulls/1609']['merged_at'] = None
            elif state == 'unmerged': a['pulls/1609']['merged_at'] = None
            else: a['pulls/1609']['base']['ref'] = 'trunk'
            t.run(a, 'block', ('#609',), state)
    elif n == 560:
        extra = pr(1709, 609, 'release/608-inheritance')
        d['pulls/1709'] = extra; d['pulls'].append(extra)
        d['issues/1709/comments'] = []; d['pulls/1709/reviews'] = []
        t.run(d, label='two valid closing PRs')
        a = world()
        foreign = pr(9999, 609, 'trunk')
        foreign.update(url='https://api.github.com/repos/other/project/issues/9999',
                       html_url='https://github.com/other/project/pull/9999')
        foreign['pull_request'] = {'url': 'https://api.github.com/repos/other/project/pulls/9999'}
        a['issues/609/timeline'].append({'id': 9999, 'created_at': STAMP, 'event': 'cross-referenced', 'source': {'issue': foreign}})
        t.run(a, label='foreign timeline sources are ignored without a fetch')
        mentioned = pr(1809, 609, 'trunk'); mentioned['body'] = 'mentionss #609'
        a = world(); a['pulls/1809'] = mentioned
        a['issues/609/timeline'].append({'id': 1809, 'created_at': STAMP, 'event': 'cross-referenced',
            'source': {'issue': dict(mentioned, pull_request={'url': f'https://api.github.com/repos/{REPO}/pulls/1809'})}})
        t.run(a, label='timeline mention is not a wrong-base closing PR')
        extra['base']['ref'] = 'trunk'
        d['issues/609/timeline'].append({'id': 1709, 'created_at': STAMP, 'event': 'cross-referenced', 'source': {'issue': dict(extra, pull_request={'url': f'https://api.github.com/repos/{REPO}/pulls/1709'})}})
        t.run(d, 'block', ('#609', '#1709'), 'second closing PR wrong base')
    elif n == 561:
        d['issues/609']['updated_at'] = '2026-11-03T00:01:00Z'
        d['issues/609']['body'] = ' \t**Epic:** #608\r\n'
        d['issues/608']['body'] = '## Work items\n* [X] #609 late\n- [ ] #610\n## Other\n- [x] #999 ignored'
        t.run(d, label='late membership and live structural normalization')
        late = world(); add_child(late, 611)
        t.run(late, label='member whose field arrives later is found through its epic timeline event')
        t.run(world(()), 'block', ('epic #608',), 'empty cannot pass vacuously')
    elif n == 562:
        for body in (skip('skip=Test').replace('maintainer', ' '), skip('skip=Test').replace('standing class decision', ' '), '> ' + skip('skip=Test'), '```\n' + skip('skip=Test') + '\n```', skip('skip=Planning'), skip('skip=Test').replace(' -->', ' broken -->'), 'panel voted to skip Test'):
            a = world(); a['issues/609/comments'] = comments(*(marker(s) for s in STAGES if s != 'Test'), body)
            a['issues/610/comments'].append(comments(skip('skip=Test'))[0])
            t.run(a, 'block', ('child #609', 'Test'), 'invalid or wrong-child waiver ' + repr(body))
        a = world(); a['issues/609/comments'] = comments(*(marker(s) for s in STAGES if s != 'Test'))
        a['pulls/1609']['body'] += '\nCloses #999'; plain(a, 999); a['issues/999/comments'] = comments(skip('skip=Test'))
        # #999 is a membership defect too; it must never supply #609's Test.
        t.run(a, 'block', ('#999',), 'no recursive waiver laundering')
        # Valid membership, valid skip=Test, wrong source: the child stays blocked for Test.
        for source in ('description', 'comment', 'review'):
            a = world(); a['issues/609/comments'] = comments(*(marker(s) for s in STAGES if s != 'Test'))
            if source == 'description': a['pulls/1609']['body'] += '\n' + skip('skip=Test')
            elif source == 'comment': a['issues/1609/comments'] = comments(skip('skip=Test'))
            else: a['pulls/1609/reviews'] = comments(skip('skip=Test'))
            t.run(a, 'block', ('child #609', 'Test'), 'skip on the child own closing PR ' + source, absent=('child #610',))
        a = world(); a['issues/609/comments'] = comments(*(marker(s) for s in STAGES if s != 'Test'))
        a['pulls/1609']['body'] = 'Closes #609\nCloses #610'
        a['issues/610/comments'] = comments(*(marker(s) for s in STAGES if s != 'Test'), skip('skip=Test'))
        t.run(a, 'block', ('child #609', 'Test'), 'skip on another listed child closed by the same PR', absent=('child #610',))
    elif n == 563:
        d['issues/609/comments'] = comments(marker('Discovery'), marker('Implementation'), skip('skip=Planning'), skip('skip=Test'))
        t.run(d, label='Abbreviated standing human class')
        d['issues/609/comments'] = comments(marker('Discovery'), marker('Planning'), marker('Test'), skip('skip=Implementation'))
        t.run(d, label='test-only standing human class')
    elif n == 564:
        d['issues/609/comments'] = comments(skip('single-session'))
        t.run(d, 'block', ('child #609', 'Implementation'), 'child single-session supplies no stages')
        d['issues/609/comments'] = comments('\n'.join(marker(s) for s in STAGES), *(skip('skip=' + s) for s in STAGES))
        t.run(d, 'block', ('child #609', 'stages in one text'), 'stage skips cannot waive multi-stage body')
        d['issues/609/comments'].append(comments(skip('single-session'))[0])
        t.run(d, label='child single-session waives only one-text finding with records present')
    elif n == 565:
        # Literal complete legacy stdout/stderr, including missing-stage lines.
        for manual in (False, True):
            a = world()
            if not manual: a['pulls/648']['head']['ref'] = 'feature/651-work'
            else: a['issues/608/comments'] = comments(skip('skip=Implementation'))
            p = t.run(a, 'block', ('Planning',), 'legacy byte contract', attributed=False)
            expected = ''.join(f'model-record: no record found for stage {s} (missing model-choice marker)\n' for s in STAGES)
            expected += 'role-played: stages missing: Discovery, Planning, Test' + ('' if manual else ', Implementation') + '\n'
            if manual: expected += 'model-record: a pipeline-override waived stage absence: skip=Implementation\n'
            if p and (p.stdout != expected or p.stderr): t.failures.append('legacy stdout/stderr differs byte for byte')
        base = '626694237d1dc6dfe9b99d8838fba4c7f75f843f'
        old = t.sandbox / 'baseline'
        (old / 'skills/pre-merge-review').mkdir(parents=True)
        (old / 'lib').symlink_to(t.root / 'lib', target_is_directory=True)
        old_gate = old / 'skills/pre-merge-review/model-record-gate.sh'
        old_gate.write_bytes(subprocess.run(['git', 'show', base + ':skills/pre-merge-review/model-record-gate.sh'],
                                           cwd=t.root, capture_output=True, check=True).stdout)
        for manual in (False, True):
            for arm in ('clean', 'near-miss', '404', '404-other', '404-single', 'comments-fail', 'reviews-fail', 'detail-fail', 'release-single'):
                if arm == '404-single' and manual: continue
                a = world()
                if arm == '404-single': pass  # eligible release, no epic override
                elif not manual: a['pulls/648']['head']['ref'] = 'feature/651-work'
                else: a['issues/608/comments'] = comments(skip('skip=Implementation'))
                if arm == 'near-miss': a['issues/648/comments'] = comments('inline ' + marker('Test'))
                elif arm == '404' and manual: continue  # a 404 on the epic itself is unchecked (S571)
                elif arm == '404': a['_fault'] = {'key': 'issues/608/comments', 'status': 404}
                elif arm in ('404-other', '404-single'):
                    # An ordinary PR, a manual epic override and an eligible release-wide single-session all
                    # keep the legacy path and its 404 note for a nonexistent closing reference.
                    a['pulls/648']['body'] += '\nCloses #9999'; a['_missing'] = ['9999']
                    if arm == '404-single': a['issues/648/comments'] = comments(skip('single-session'))
                elif arm in ('comments-fail', 'reviews-fail', 'detail-fail'):
                    key = {'comments-fail': 'issues/648/comments', 'reviews-fail': 'pulls/648/reviews', 'detail-fail': 'pulls/648'}[arm]
                    a['_fault'] = {'key': key}
                elif arm == 'release-single': a['issues/648/comments'] = comments(skip('single-session'))
                Path(t.env['EPIC_DATA']).write_text(json.dumps(a))
                results = []
                for gate in (old_gate, t.root / 'skills/pre-merge-review/model-record-gate.sh'):
                    results.append(subprocess.run(['bash', str(gate), '648'], cwd=t.sandbox / 'project',
                                                  env=t.env, capture_output=True, timeout=135))
                t.arms += 2
                if (results[0].returncode, results[0].stdout, results[0].stderr) != (results[1].returncode, results[1].stdout, results[1].stderr):
                    t.failures.append(f'base {base} legacy byte comparison manual={manual}/{arm}: differs')

    elif n == 566:
        d['pulls/648']['body'] += '\nCloses #651\nCloses #647'
        d['issues/651/comments'] = []; d['issues/647/comments'] = comments(skip('skip=Test'))
        for c in (609, 610): d[f'issues/{c}/comments'] = comments(*(marker(s) for s in STAGES if s != 'Test'))
        t.run(d, label='any Closes issue skip waives inherited Test release-wide')
        d['issues/609']['state'] = 'open'
        t.run(d, 'block', ('#609',), 'release-wide skip cannot waive membership')
        a = world()
        a['issues/655'] = issue(655, a.pop('issues/608')['body'])
        a['issues/655/comments'] = a.pop('issues/608/comments')
        a['issues/655/timeline'] = a.pop('issues/608/timeline')
        a['pulls/648']['body'] = 'Closes #655\nCloses #651\nCloses #647'
        a['pulls/648']['head']['ref'] = 'release/655-bundle'
        a['issues/651/comments'] = []; a['issues/647/comments'] = comments(skip('skip=Test'))
        for c in (609, 610):
            a[f'issues/{c}']['body'] = '**Epic:** #655'
            a[f'pulls/{c+1000}']['base']['ref'] = 'release/655-bundle'
            a[f'issues/{c}/comments'] = comments(*(marker(s) for s in STAGES if s != 'Test'))
        t.run(a, label='exact bundle Closes #655 #651 #647 and Test waived release-wide')

    elif n == 567:
        for arm in ('default', 'case', 'nonrelease', 'foreign', 'wrong-target', 'no-closes'):
            a = world()
            if arm == 'case': a['pulls/648']['body'] = 'cLoSeS #608'
            elif arm == 'nonrelease': a['pulls/648']['head']['ref'] = 'feature/608-tracking'
            elif arm == 'foreign': a['pulls/648']['head']['repo']['full_name'] = 'other/project'
            elif arm == 'wrong-target': a['pulls/648']['base']['ref'] = 'main'
            elif arm == 'no-closes': a['pulls/648']['body'] = 'See #608'
            t.run(a, 'pass' if arm in ('default', 'case') else 'block', () if arm in ('default', 'case') else ('stages missing:',), arm,
                  attributed=arm in ('default', 'case'))
    elif n == 568:
        for key in ('issues/608/timeline', 'pulls', 'issues/609/timeline', 'issues/609/comments', 'pulls/1609/reviews', 'issues/648/comments', 'pulls/648/reviews'):
            a = world()
            if key == 'pulls':
                a[key] = [pr(3000+i, 609, 'elsewhere') for i in range(100)] + a[key]
            elif key.endswith('timeline'):
                a[key] = [{'id': 1, 'created_at': STAMP, 'event': 'labeled'} for _ in range(100)] + a[key]
            else:
                a[key] = comments(*(['noise'] * 100)) + a[key]
                if key == 'issues/609/comments':
                    a[key] = comments(*(['noise'] * 100), *(marker(s) for s in STAGES))
            p = t.run(a, label='page 2 ' + key)
            log = Path(t.env['EPIC_LOG']).read_text()
            if not any(key in ep and 'page=2' in ep for ep, _ in map(json.loads, log.splitlines())):
                t.failures.append(key + ': no explicit page 2; collection completeness unproved')
        # A member discoverable only on epic timeline page 2 cannot be ignored.
        a = world(); add_child(a, 611, listed=False)
        a['issues/608/timeline'] = [{'id': 1, 'created_at': STAMP, 'event': 'labeled'} for _ in range(100)] + a['issues/608/timeline']
        t.run(a, 'block', ('epic #608', '#611'), 'unlisted member on epic timeline page 2')
        log = list(map(json.loads, Path(t.env['EPIC_LOG']).read_text().splitlines()))
        if not any('issues/608/timeline' in ep and 'page=2' in ep for ep, _ in log):
            t.failures.append('epic timeline page 2 was not read')
        for ep, args in log:
            if '--paginate' in args:
                t.failures.append('inheritance collection used unbounded --paginate: ' + ep)
    elif n == 569:
        for key, count in (('pulls', 1000), ('issues/609/timeline', 1000), ('issues/609/comments', 1000), ('pulls/1609/reviews', 1000), ('issues/648/comments', 1000), ('pulls/648/reviews', 1000)):
            a = world()
            if key == 'pulls': a[key] += [pr(3000+i, 609, 'elsewhere') for i in range(count-len(a[key]))]
            elif key.endswith('timeline'): a[key] += [{'id': 1, 'created_at': STAMP, 'event': 'labeled'} for _ in range(count-len(a[key]))]
            else: a[key] = comments(*(['noise'] * count))
            t.run(a, 'unchecked', label=f'exact cap {key}={count}')
        # Epic timeline events: 1,000 is unchecked (a full final page cannot prove completeness), 999 is not.
        for count, kind in ((1000, 'unchecked'), (999, 'pass')):
            a = world(); a['issues/608/timeline'] += [{'id': 1, 'created_at': STAMP, 'event': 'labeled'} for _ in range(count-len(a['issues/608/timeline']))]
            t.run(a, kind, label=f'epic timeline events={count}')
        # Membership candidates (field-bearing or not): 200 is unchecked, 199 is not.
        for count, kind in ((200, 'unchecked'), (199, 'pass')):
            a = world()
            for i in range(count - 2): mention(a, 4200 + i)
            t.run(a, kind, label=f'candidates={count}')
        t.run(world(tuple(range(609, 709))), 'unchecked', label='exact child cap 100')
        # Calls attributable to one child: 40 REST calls (detail, timeline, comments, candidate-PR details, closing-PR evidence).
        for extra, kind in ((20, 'unchecked'), (5, 'pass')):
            a = world()
            for i in range(extra):
                p = pr(5000 + i, 609, 'release/608-inheritance'); a['pulls'].append(p); a[f'pulls/{5000+i}'] = p
                a[f'issues/{5000+i}/comments'] = []; a[f'pulls/{5000+i}/reviews'] = []
                a['issues/609/timeline'].append({'id': 5000 + i, 'created_at': STAMP, 'event': 'cross-referenced',
                    'source': {'issue': dict(p, pull_request={'url': f'https://api.github.com/repos/{REPO}/pulls/{5000+i}'})}})
            t.run(a, kind, label=f'calls for one child with {extra} extra closing PRs')
        a = world(); a['_fault'] = {'key': 'issues/608/timeline', 'mode': 'oversize'}
        t.run(a, 'unchecked', label='8 MiB response cap')
        a = world(tuple(range(609, 708)))
        for c in range(609, 708):
            a[f'issues/{c}/timeline'] += [{'id': 1, 'created_at': STAMP, 'event': 'labeled'} for _ in range(998)]
        t.run(a, 'unchecked', label='1200 aggregate REST-call budget')
        calls = Path(t.env['EPIC_LOG']).read_text().splitlines()
        if len(calls) > 1200: t.failures.append('aggregate REST budget exceeded 1200 calls')
        a = world()
        for i in range(10):
            mention(a, 4300 + i); a[f'issues/{4300+i}']['_pad'] = 7500000
        t.run(a, 'unchecked', label='64 MiB aggregate response budget; each response under 8 MiB')

    elif n == 570:
        d['_fault'] = {'key': 'issues/609/timeline', 'mode': 'delay'}
        start = time.monotonic(); t.run(d, 'unchecked', label='10s subprocess timeout')
        if time.monotonic() - start > 14: t.failures.append('10s subprocess was not killed promptly')
        # Use the existing copied-gate seam (S572) to shorten only the
        # deadline expression; exercise the unchanged production supervisor.
        short = t.sandbox / 'short-deadline'
        (short / 'skills/pre-merge-review').mkdir(parents=True)
        (short / 'lib').symlink_to(t.root / 'lib', target_is_directory=True)
        gate = short / 'skills/pre-merge-review/model-record-gate.sh'
        source = (t.root / 'skills/pre-merge-review/model-record-gate.sh').read_text()
        deadline = 'remaining=$((120 - SECONDS + started))'
        assert source.count(deadline) == 1, 'deadline injection seam moved'
        watchdog = '( sleep "$remaining" ||'
        assert source.count(watchdog) == 1, 'watchdog injection seam moved'
        # Fire SIGTERM before the collector's own deadline, so cleanup cannot
        # race with its normal per-call timeout and hide the supervisor defect.
        gate.write_text(source.replace(deadline, 'remaining=$((8 - SECONDS + started))')
                        .replace(watchdog, '( sleep 3 ||'))
        a = world(); a['_fault'] = {'key': 'issues/609/timeline', 'mode': 'hung-descendant'}
        receipt = Path(t.env['EPIC_LOG'] + '.pids')
        orphan = Path(t.env['EPIC_LOG'] + '.orphan-survived')
        ready = Path(t.env['EPIC_LOG'] + '.orphan-ready')
        receipt.unlink(missing_ok=True); orphan.unlink(missing_ok=True); ready.unlink(missing_ok=True)
        groups = []
        try:
            t.run(a, 'unchecked', label='hung-call descendant cleanup', gate=gate)
            if not receipt.exists():
                t.failures.append('hung-call descendant cleanup: injection not reached')
            else:
                record = json.loads(receipt.read_text())
                groups = [record['pgid'], record['child_pgid']]
                assert groups == record['pids'] and groups[0] != groups[1]
                assert os.getpgrp() not in groups, 'fixture must own separate groups'
                # Wall time crosses process boundaries on older macOS Python too.
                # Wait past the child's write time, even if the gate returned early.
                if not ready.exists():
                    t.failures.append('hung-call descendant cleanup: child did not reach delay')
                else:
                    time.sleep(max(0, float(ready.read_text()) + 6.5 - time.time()))
                alive = []
                for pid in record['pids']:
                    try:
                        os.kill(pid, 0)
                        alive.append(pid)
                    except ProcessLookupError:
                        pass
                live_groups = []
                for group in groups:
                    try:
                        os.killpg(group, 0)
                        live_groups.append(group)
                    except ProcessLookupError:
                        pass
                if alive or live_groups:
                    t.failures.append(f'hung-call descendant cleanup: surviving pids {alive}; '
                                      f'pgids {live_groups}')
                if orphan.exists():
                    t.failures.append('hung-call descendant cleanup: orphan-survived marker written')
        finally:
            # A RED regression must not leak its deliberately hung processes.
            if receipt.exists() and not groups:
                record = json.loads(receipt.read_text())
                groups = [record['pgid'], record['child_pgid']]
            for group in groups:
                try:
                    os.killpg(group, signal.SIGKILL)
                except ProcessLookupError:
                    pass

        # A shell scan blocks after detail acquisition: the whole-evaluation
        # watchdog must cover this, independently of Python REST timeouts.
        slow = t.sandbox / 'slow-scan'; slow.mkdir()
        awk = slow / 'awk'
        t.env['EPIC_REAL_AWK'] = shutil.which('awk')
        awk.write_text('''#!/usr/bin/env bash
if [ -f "$EPIC_LOG.detail" ] && [ ! -f "$EPIC_LOG.slow" ]; then
  : > "$EPIC_LOG.slow"
  sleep 121
fi
exec "$EPIC_REAL_AWK" "$@"
''')
        awk.chmod(0o755)
        saved = t.env['PATH']; t.env['PATH'] = str(slow) + os.pathsep + saved
        start = time.monotonic()
        t.run(world(), 'unchecked', label='120s whole-evaluation watchdog includes shell scans')
        if time.monotonic() - start > 130:
            t.failures.append('whole evaluation exceeded 120s plus watchdog cleanup allowance')
        if not Path(t.env['EPIC_LOG'] + '.slow').exists():
            t.failures.append('shell-scan timeout injection was never reached')
        t.env['PATH'] = saved
        # Scale arm: the normalized 19-child fixture, 300 unrelated issues and 0.8 s per gh call
        # finishes checked inside the 120 s deadline, never reads an unrelated issue and overlaps its reads.
        a = normalized_608()
        unrelated = [f'issues/{6000+i}' for i in range(300)]
        for key in unrelated:
            a[key] = issue(int(key.split('/')[1]), 'unrelated'); a[key + '/comments'] = []
        a['_forbidden'] = unrelated + [k + '/comments' for k in unrelated]; a['_delay'] = 0.8
        start = time.monotonic()
        t.run(a, label='scale: 19 children, 300 unrelated issues, 0.8 s per gh call')
        elapsed = time.monotonic() - start
        if elapsed >= 120: t.failures.append(f'scale arm took {elapsed:.0f}s, not under the 120s deadline')
        peak = t.concurrent()
        if not 1 < peak <= 8: t.failures.append(f'scale arm observed {peak} concurrent gh calls; expected more than 1 and at most 8')
        print(f'S570 scale arm: {elapsed:.0f}s, peak {peak} concurrent gh calls')

    elif n == 571:
        for key in ('', 'issues/608', 'issues/608/comments', 'issues/608/timeline', 'issues/609', 'pulls', 'issues/609/timeline', 'pulls/1609', 'issues/609/comments', 'issues/1609/comments', 'pulls/1609/reviews', 'issues/648/comments', 'pulls/648/reviews', 'pulls/648'):
            for status in (404, 500):
                a = world(); a['_fault'] = {'key': key, 'status': status}
                t.run(a, 'unchecked', label=f'{key} HTTP {status}')
        # A timeline-only candidate that is gone (404/410) cannot carry a live field; any other failure is unchecked.
        for status, kind in ((404, 'pass'), (410, 'pass'), (500, 'unchecked')):
            a = world(); mention(a, 4400); a['_fault'] = {'key': 'issues/4400', 'status': status}
            t.run(a, kind, label=f'timeline-only candidate HTTP {status}')
        # An eligible release PR whose closing reference does not exist is unchecked, never the legacy path.
        wanted = 'role-play-unchecked: closing reference #9999 on epic release PR #648 does not exist (HTTP 404)'
        a = world(); a['pulls/648']['body'] += '\nCloses #9999'; a['_missing'] = ['9999']
        t.run(a, 'unchecked', label='eligible release, covered children, Closes #9999 is 404', line=wanted)
        a = world(); a['pulls/648']['body'] += '\nCloses #9999\nCloses #9998'; a['_missing'] = ['9998', '9999']
        p = t.run(a, 'unchecked', label='lowest nonexistent closing reference first',
                  line=wanted.replace('9999', '9998'))
        if p and not p.stdout.startswith(wanted.replace('9999', '9998') + '\n'):
            t.failures.append('lowest nonexistent closing reference is not reported first: ' + repr(p.stdout))
        a = world(); a['pulls/648']['body'] += '\nCloses #9999'; a['_missing'] = ['9999']; a['issues/609/comments'] = []
        t.run(a, 'unchecked', label='404 closing reference wins over a missing-child block', line=wanted)
    elif n == 572:
        for key in ('issues/608/timeline', 'pulls', 'issues/609/comments', 'pulls/1609/reviews', 'issues/609/timeline', 'issues/608', 'issues/609', 'pulls/1609'):
            a = world(); a['_fault'] = {'key': key, 'mode': 'malformed'}
            t.run(a, 'unchecked', label='malformed JSON ' + key)
        for key, value in (('issues/608/timeline', {}), ('issues/609/comments', [{'body': 42, 'created_at': STAMP}]), ('pulls/1609', dict(d['pulls/1609'], number='1609'))):
            a = world(); a[key] = value
            t.run(a, 'unchecked', label='wrong JSON type ' + key)
        # Missing helper at the existing public CLI; all shared readers preserved.
        clone = t.sandbox / 'missing-helper'
        (clone / 'skills/pre-merge-review').mkdir(parents=True)
        (clone / 'lib').mkdir()
        for lib in (t.root / 'lib').glob('*.sh'):
            (clone / 'lib' / lib.name).symlink_to(lib)
        gate = clone / 'skills/pre-merge-review/model-record-gate.sh'
        shutil.copyfile(t.root / 'skills/pre-merge-review/model-record-gate.sh', gate)
        t.run(world(), 'unchecked', label='private helper missing', gate=gate)
        no_python = t.sandbox / 'no-python'; no_python.mkdir()
        script = no_python / 'python3'; script.write_text('#!/bin/sh\nexit 127\n'); script.chmod(0o755)
        saved_path = t.env['PATH']; t.env['PATH'] = str(no_python) + os.pathsep + saved_path
        t.run(world(), 'unchecked', label='Python interpreter unavailable')
        t.env['PATH'] = saved_path

    elif n == 573:
        for key in ('issues/608', 'issues/609', 'pulls/1609', 'pulls/648'):
            changes = ('updated_at', 'body', 'state') + (('base', 'head', 'merged_at') if key.startswith('pulls/') else ())
            for change in changes:
                # A52: every participating detail is read once (cached) and re-read once before
                # publishing, so the changed object must appear from the second read on.
                a = world(); a['_fault'] = {'key': key, 'after': 2, 'mode': 'changed', 'change': change}
                t.run(a, 'unchecked', label='snapshot changed ' + key + '/' + change)
        # Excluded candidates participated in classification too. Their second
        # read must be checked even though they supplied no inherited evidence.
        a = world(); mention(a, 4400)
        t.run(a, label='control: unchanged discovered nonmember passes')
        a['_fault'] = {'key': 'issues/4400', 'after': 2, 'mode': 'changed',
                       'change': 'body', 'body': '**Epic:** #608'}
        t.run(a, 'unchecked', label='excluded nonmember gains Epic field before publication')
        for base in ('elsewhere', 'release/608-inheritance'):
            a = world(); p = pr(4500, 999, base)
            a['pulls/4500'] = p
            a['issues/4500/comments'] = []; a['pulls/4500/reviews'] = []
            a['issues/609/timeline'].append({'id': 4500, 'created_at': STAMP,
                'event': 'cross-referenced', 'source': {'issue': dict(p,
                    pull_request={'url': f'https://api.github.com/repos/{REPO}/pulls/4500'})}})
            t.run(a, label='control: unchanged mentioned noncloser passes on ' + base)
            a['_fault'] = {'key': 'pulls/4500', 'after': 2, 'mode': 'changed',
                           'change': 'body', 'body': 'Closes #609'}
            t.run(a, 'unchecked', label='excluded noncloser becomes child closer on ' + base)
        # Control: a change visible from the first read is a genuinely open child, not a
        # snapshot change, so the gate blocks on it (the recheck cannot see a difference).
        a = world(); a['_fault'] = {'key': 'issues/609', 'after': 1, 'mode': 'changed', 'change': 'state'}
        t.run(a, 'block', ('#609',), 'control: child open from the first read blocks')
    elif n == 574:
        d['issues/609/comments'] = []
        d['_fault'] = {'key': 'pulls/1610/reviews', 'status': 404}
        t.run(d, 'unchecked', label='late failure discards missing-child and legacy findings')
    elif n == 575:
        t.doc('skills/release-branch-workflow/SKILL.md', (r'epic ledger complete: (?:`)?yes', r'child count', r'ledger.{0,200}(?:view|not evidence|never.{0,30}evidence)', r'open.{0,160}(?:no|refus|cannot)', r'(?:late|gain).{0,100}(?:epic|field|member)', r'(?:unchecked).{0,100}(?:yes|complete)', r'(?:normaliz|normalis).{0,200}(?:field|work items)'))
    elif n == 576:
        t.doc('skills/pre-merge-review/SKILL.md', (r'(?:forge).{0,160}(?:override|model.record)', r'(?:not|cannot|does not).{0,60}authenticat', r'100.{0,30}children', r'200.{0,40}candidates', r'40.{0,60}(?:calls|requests|reads).{0,30}child|child.{0,60}40.{0,30}(?:calls|requests|reads)', r'1[,.]?200.{0,50}(?:calls|requests)', r'(?:8|eight).{0,40}concurrent', r'120.{0,30}seconds', r'64.{0,15}(?:mib|megabytes)', r'10.{0,30}seconds', r'1[,.]?000.{0,40}(?:comments|reviews)', r'1[,.]?000.{0,30}timeline', r'(?:cap|limit).{0,160}role-play-unchecked', r'closing reference.{0,160}404.{0,100}unchecked', r'(?:residual|gap).{0,200}(?:timeline|cross-referenced)', r'(?:never|not|no).{0,60}(?:every|all) (?:the )?(?:repository )?issues?'))
    elif n == 577:
        t.doc('skills/release-branch-workflow/SKILL.md', (r'(?:any|each).{0,100}(?:closes|closing).{0,160}(?:whole|release.wide)', r'(?:a18|override amendment)', r'(?:membership).{0,100}(?:amendment|maintainer acceptance)'))
        prd = (t.root / 'PRD.md').read_text()
        section = prd.split('### F65 ', 1)[-1].split('### F66 ', 1)[0]
        control = '**Epic:** #655 merges after #647 F64–F66 A52–A53 S549–S578 A18 membership-freeze maintainer acceptance'
        for literal in ('**Epic:** #655', 'merges after #647', 'F64–F66', 'A52–A53', 'S549–S578', 'A18', 'membership-freeze', 'maintainer acceptance'):
            assert literal in control
            assert literal not in control.replace(literal, '')
            if literal not in section:
                t.failures.append('PRD F65 bundle metadata missing ' + literal)
    elif n == 578:
        # Real merge hook; its other gates have the established v2 fixture inputs.
        hook = t.root / 'hooks/git-guardrails'
        text = hook.read_text().lower()
        for clause in ('child', 'epic', 'pipeline-override'):
            if clause not in text: t.failures.append('merge-hook block remedy omits ' + clause)
        for broken in (False, True):
            a = world()
            if broken:
                # Child #609 is missing; child #610 and the release PR carry kept near-miss diagnostics.
                a['issues/609/comments'] = []
                a['issues/610/comments'] = comments(*(marker(s) for s in STAGES), 'inline ' + marker('Test'))
                a['issues/648/comments'] = comments('inline ' + marker('Review'))
            p = t.run(a, 'block' if broken else 'pass', ('epic #608', 'child #609') if broken else (),
                      'real CLI missing child' if broken else 'real CLI positive')
            payload = json.dumps({'tool_name': 'Bash', 'cwd': str(t.sandbox / 'project'),
                                  'tool_input': {'command': 'gh pr merge 648'}})
            h = subprocess.run(['bash', str(hook)], input=payload, cwd=t.sandbox / 'project',
                               env=t.env, text=True, capture_output=True, timeout=135)
            want = 2 if broken else 0
            if 'unexpected' in h.stderr or 'skips the' in h.stderr:
                t.failures.append('real hook fixture did not establish its other gates: ' + h.stderr)
            if h.returncode != want:
                t.failures.append(f'real hook broken={broken}: exit={h.returncode}, expected {want}: {h.stderr}')
            if broken:
                hook_filter(t, p.stdout if p else '', h.stderr)
    else:
        raise AssertionError(n)


def main():
    if sys.argv[1] == 'serve': serve(); return
    n, root, sandbox = int(sys.argv[1]), sys.argv[2], sys.argv[3]
    t = Check(root, sandbox)
    scenario(n, t)
    for failure in t.failures:
        print(f'FAIL S{n}: {failure}')
    print(f'S{n}: {t.arms} CLI arms; output/doc mutation controls passed; ' + ('RED' if t.failures else 'GREEN'))
    sys.exit(bool(t.failures))


if __name__ == '__main__': main()
