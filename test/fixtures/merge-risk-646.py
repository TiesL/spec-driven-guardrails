"""Oracle for S605-S626 (#646, A58): bundles, a fake gh, and mutation checks.

Usage: python3 merge-risk-646.py <scenario number>

Every row judges the verifier only through its command-line contract: the
first stdout line, the `reason:` codes, the exit status, and (collector rows)
the fake gh call log. Every scenario first runs the unmutated base bundle and
expects `eligible`, so no row passes on an already broken bundle. Mutation
checks change exactly one rule (a `# rule:<name>` line of lib/merge-risk.py, a
statement of the skill, or a config entry) in a scratch copy and require the
named rows to fail; a surviving mutation is a defect of the suite. The
rule-to-row map is the MUTATIONS table at the end of each scenario block.
Every `# rule:` tag of lib/merge-risk.py has at least one mutation here
(`untagged_rules()` reports any that has none). Lines without a tag (parsers,
schema detail, collector plumbing) are exercised by rows but not mutated one
by one; that is the limit of this suite.

Each scratch tree is a throwaway git repository whose single commit is the
main tip B the fake gh serves, so the collector's own-checkout check (A58
addendum 3 F2) runs against real git objects; `now` comes from the fake
`Date` header of the last request (F5).

Nothing here runs a model: obedience to the skill is S624 (UNRUN, #682).
Synthetic index scores are controlled evidence, not live index observations.
"""
import atexit
import copy
import hashlib
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timedelta, timezone
from email.utils import format_datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCN = sys.argv[1] if len(sys.argv) > 1 else ''
REPO = 'TiesL/spec-driven-guardrails'
H, H2 = '1a2b3c4d' * 5, '5e6f7a8b' * 5
B, B2 = '9f8e7d6c' * 5, '0a1b2c3d' * 5
SQUASH = 'c0ffee00' * 5
DESIGN_COMMIT = '4d3c2b1a' * 5
T0 = datetime(2026, 1, 1, 12, 0, 0, tzinfo=timezone.utc)
ACC = 'https://github.com/%s/issues/646#issuecomment-111' % REPO
AC_SRC = 'https://github.com/%s/issues/701#issuecomment-222' % REPO
DESIGN_SRC = 'ARCHITECTURE.md@%s#A99' % DESIGN_COMMIT
AC_TEXT = '## Acceptance criteria\n\n- AC1 the docs page explains the guide.\n'
DESIGN_TEXT = '### A99 \u2014 sample design\n\nThe guide lives in docs/.\n\n'
VOTERS = ('Product', 'Architect', 'QA', 'Reviewer', 'orchestrator')
STAGE = {'Product': 'Discovery', 'Architect': 'Planning', 'QA': 'Test', 'Reviewer': 'Review', 'Developer': 'Implementation'}
FIRST = re.compile(r'merge-risk: (eligible|held|referred|unresolved) pr=(\S+) head=(\S+) base=(\S+) diff=(\S+) config=(\S+)')
EXIT = {'eligible': 0, 'held': 1, 'referred': 3, 'unresolved': 4}
SHA40 = re.compile(r'[0-9a-f]{40}')
OWNER_ISSUE = 'https://api.github.com/repos/%s/issues/646' % REPO
ERRORS = []
TMP = []
atexit.register(lambda: [shutil.rmtree(d, ignore_errors=True) for d in TMP])


def iso(dt):
    return dt.strftime('%Y-%m-%dT%H:%M:%SZ')


def sha(text):
    return hashlib.sha256(text.encode('utf-8')).hexdigest()


A = sha(AC_TEXT)
D = sha(DESIGN_TEXT)


class Fail(Exception):
    pass


# --- a scratch tree: verifier, its libs, a fake preflight, skill and config
FAKE_GH = r'''#!/usr/bin/env python3
import json, os, sys
world = json.load(open(os.environ['FAKE_WORLD']))
argv = sys.argv[1:]
with open(os.environ['FAKE_LOG'], 'a') as fh:
    fh.write(json.dumps({'tool': 'gh', 'argv': argv, 'env': {k: os.environ.get(k) for k in
             ('CLAUDE_WORKFLOW_MERGE_GUARD_OFF', 'CLAUDE_WORKFLOW_GUARDRAILS_OFF')}}) + '\n')
key = ' '.join(argv)
if argv[:2] == ['api', 'graphql']:
    key = 'graphql ' + ' '.join(a for a in argv if a.startswith('i='))
route = world['routes'].get(key)
if route is None:
    sys.stderr.write('gh: HTTP 404: Not Found (fake: %s)\n' % key)
    sys.exit(1)
sys.stdout.write(route.get('out', ''))
sys.stderr.write(route.get('err', ''))
sys.exit(route.get('rc', 0))
'''
FAKE_TOOL = r'''#!/usr/bin/env python3
import json, os, sys
world = json.load(open(os.environ['FAKE_WORLD']))
with open(os.environ['FAKE_LOG'], 'a') as fh:
    fh.write(json.dumps({'tool': '%s', 'argv': sys.argv[1:], 'env': {k: os.environ.get(k) for k in
             ('CLAUDE_WORKFLOW_MERGE_GUARD_OFF', 'CLAUDE_WORKFLOW_GUARDRAILS_OFF')}}) + '\n')
%s
'''
SENTINEL = '#!/bin/sh\necho SENTINEL >> "$FAKE_LOG"\nexit 1\n'


def _exe(path, text):
    path.write_text(text)
    path.chmod(0o755)


class Tree:
    count = 0

    def __init__(self, lib=None, skill=None, config=None, role_contracts=None):
        self.dir = Path(tempfile.mkdtemp(prefix='mr646-'))
        TMP.append(str(self.dir))
        (self.dir / 'lib').mkdir()
        for name in ('lib/markdown.sh', 'lib/model-record.sh'):
            shutil.copy(ROOT / name, self.dir / name)
        shutil.copy(ROOT / 'merge-risk-evidence.sh', self.dir / 'merge-risk-evidence.sh')
        (self.dir / 'lib/merge-risk.py').write_text(lib if lib is not None else (ROOT / 'lib/merge-risk.py').read_text())
        _exe(self.dir / 'merge-preflight.sh', FAKE_TOOL % ('preflight', "p = world.get('preflight', {})\n"
             "sys.stderr.write(p.get('stderr', ''))\nsys.exit(p.get('exit', 0))"))
        fake = self.dir / 'fakebin'
        fake.mkdir()
        _exe(fake / 'gh', FAKE_GH)
        _exe(fake / 'hostname', FAKE_TOOL % ('hostname', "print(world.get('host', ''))"))
        os.symlink(sys.executable, fake / 'python3')
        (self.dir / 'sentinel').mkdir()
        _exe(self.dir / 'sentinel/gh', SENTINEL)
        self.skill = skill if skill is not None else (ROOT / 'skills/merge-risk-panel/SKILL.md').read_text()
        self.config = config if config is not None else (ROOT / 'policy/merge-autonomy.json').read_text()
        self.role_contracts = role_contracts if role_contracts is not None else (ROOT / 'skills/role-contracts/SKILL.md').read_bytes()
        self.lib_text = (self.dir / 'lib/merge-risk.py').read_text()
        self.vcs('init', '-q')
        self.vcs('add', 'lib', 'merge-risk-evidence.sh', 'merge-preflight.sh')
        self.vcs('commit', '-q', '-m', 'B')
        self.B = self.vcs('rev-parse', 'HEAD').stdout.decode().strip()
        need(SHA40.fullmatch(self.B), 'scratch repository has no commit')
        Tree.count += 1
        spec = importlib.util.spec_from_file_location('merge_risk_%d' % Tree.count, self.dir / 'lib/merge-risk.py')
        self.mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.mod)
        self.n = 0

    def vcs(self, *args):
        env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
        env.update(GIT_AUTHOR_NAME='t', GIT_AUTHOR_EMAIL='t@example.invalid', GIT_COMMITTER_NAME='t',
                   GIT_COMMITTER_EMAIL='t@example.invalid', GIT_CONFIG_NOSYSTEM='1', HOME=str(self.dir))
        return subprocess.run(['git', '-C', str(self.dir)] + list(args), env=env, capture_output=True)

    def clone(self):
        """A fresh tree with the same (possibly mutated) verifier and texts."""
        return Tree(lib=self.lib_text, skill=self.skill, config=self.config, role_contracts=self.role_contracts)

    def _bundle_file(self, b):
        self.n += 1
        path = self.dir / ('bundle-%d.json' % self.n)
        path.write_text(json.dumps(b))
        return str(path)

    def cli(self, cmd, b):
        """The verifier's command-line entry, in process: (stdout, exit)."""
        return Out(*self.mod.cli([cmd, '--bundle', self._bundle_file(b)]))

    def ev(self, b):
        return self.cli('evaluate', b)

    def collector(self, world, args, env=None, cwd=None, path=None):
        wf = self.dir / ('world-%d.json' % self.n)
        self.n += 1
        log = self.dir / ('log-%d.jsonl' % self.n)
        wf.write_text(json.dumps(world))
        log.write_text('')
        e = {'PATH': path or '%s:%s:/usr/bin:/bin' % (self.dir / 'fakebin', self.dir / 'sentinel'),
             'HOME': os.environ.get('HOME', '/tmp'), 'FAKE_WORLD': str(wf), 'FAKE_LOG': str(log)}
        e.update(env or {})
        p = subprocess.run(['/bin/bash', str(self.dir / 'merge-risk-evidence.sh')] + args, env=e,
                           cwd=cwd or str(self.dir), capture_output=True)
        entries = [json.loads(x) if x.startswith('{') else {'tool': x} for x in log.read_text().splitlines() if x]
        return Out(p.stdout.decode(), p.returncode), entries


class Out:
    def __init__(self, text, rc):
        self.text, self.rc = text, rc
        lines = text.splitlines()
        self.first = lines[0] if lines else ''
        m = FIRST.fullmatch(self.first)
        self.verdict = m.group(1) if m else None
        self.ident = m.groups()[1:] if m else None
        self.reasons = [x[len('reason: '):] for x in lines if x.startswith('reason: ')]
        self.codes = [x.split()[0] for x in self.reasons]
        self.notes = [x for x in lines if x.startswith('note: ')]

    def __repr__(self):
        return '%s rc=%s reasons=%s' % (self.verdict, self.rc, self.reasons)


def expect(out, verdict=None, has=(), lacks=(), among=None, detail=None):
    problems = []
    if out.verdict is None:
        problems.append('first line malformed: %r' % out.first)
    if verdict and out.verdict != verdict:
        problems.append('verdict %s, expected %s' % (out.verdict, verdict))
    if among and out.verdict not in among:
        problems.append('verdict %s not in %s' % (out.verdict, among))
    if out.verdict in EXIT and out.rc != EXIT[out.verdict]:
        problems.append('exit %s does not match verdict %s' % (out.rc, out.verdict))
    for code in has:
        if code not in out.codes:
            problems.append('reason %s missing' % code)
    for code in lacks:
        if code in out.codes:
            problems.append('reason %s present' % code)
    if detail and not any(detail in r for r in out.reasons):
        problems.append('no reason detail contains %r' % detail)
    if problems:
        raise Fail('; '.join(problems) + ' | got %r' % out)


def need(cond, msg):
    if not cond:
        raise Fail(msg)


# --- bundles
def config_text(t, enabled=True, host='exec-host', edit=None):
    cfg = json.loads(t.config)
    cfg['enabled'] = enabled
    cfg['acceptance'] = ACC
    cfg['executor_host'] = host
    if edit:
        edit(cfg)
    return json.dumps(cfg, indent=2) + '\n'


def make_diff(files, extra=''):
    out = []
    for f in files:
        old = f.get('previous_path') or f['path']
        out += ['diff --git a/%s b/%s' % (old, f['path']), '--- a/%s' % old, '+++ b/%s' % f['path'],
                '@@ -1,%d +1,%d @@' % (f['deletions'], f['additions'])]
        out += ['-old line %d of %s' % (i, f['path']) for i in range(f['deletions'])]
        out += ['+new line %d of %s' % (i, f['path']) for i in range(f['additions'])]
    return '\n'.join(out) + '\n' + extra


def fl(path, add=5, dele=0, prev=None, binary=False):
    return {'path': path, 'previous_path': prev, 'additions': add, 'deletions': dele, 'binary': binary}


def report(role, position=None, head=None, design=None, paths='README.md docs/**.md', marker=None, lines=None):
    if position is None:
        position = 'yes' if role in ('Reviewer', 'orchestrator') else 'yes-if'
    if head is None:
        head = H if role in ('Reviewer', 'orchestrator') else 'any'
    if design is None:
        design = 'pending' if role == 'Product' else D
    out = []
    if marker is None and role in STAGE and role != 'orchestrator':
        marker = STAGE[role]
    if marker:
        out.append('<!-- model-record: stage=%s model="claude-opus-5-5" -->' % marker)
    out.append('%s report for work item #701.' % role)
    out.append('')
    if lines is None:
        lines = ['merge-risk-position: role=%s position=%s ac=%s design=%s head=%s' % (role, position, A, design, head)]
    out += lines
    out.append('conditions: scope is the docs change; any path outside it voids this position.')
    out.append('paths: ' + paths)
    return '\n'.join(out) + '\n'


def url_for(role, i):
    if role == 'Reviewer':
        return 'https://github.com/%s/pull/700#issuecomment-%d' % (REPO, 3000 + i)
    return 'https://github.com/%s/issues/701#issuecomment-%d' % (REPO, 3000 + i)


def set_report(b, role, body, keep_hash=False):
    r = b['_roles'].setdefault(role, {'url': url_for(role, len(b['_roles'])), 'position': None, 'score': 65})
    b['sources'][r['url']] = {'body': body, 'created_at': iso(T0 - timedelta(seconds=600))}
    if not keep_hash:
        r['sha'] = sha(body)
    pm = re.search(r'position=(\S+)', body)
    r['position'] = pm.group(1) if pm else r.get('position') or 'yes'


def manifest(b, head=None, base=None, diff=None, config=None, n=1, outcome='eligible', hold_release=None, roles=None):
    head = head or b['pr']['head']
    rows = []
    for role in roles or list(b['_roles']):
        r = b['_roles'][role]
        rows.append({'role': role, 'source_url': r['url'], 'source_sha256': r['sha'], 'position': r['position'],
                     'model': 'claude-opus-5-5', 'variant': 'max', 'score': r['score'], 'entry': 'Claude Opus 5.5 (max)',
                     'date': '2026-11-01'})
    return {
        'decision_id': 'MR-700-%s-%d' % (head[:7], n), 'repository': REPO, 'issue': 701, 'pr': 700,
        'head': head, 'base': base or b['main_tip'], 'diff_sha256': diff or sha(b['diff_text']),
        'config_sha256': config or sha(b['config_text']), 'config_commit': base or b['main_tip'],
        'ac': {'source': AC_SRC, 'sha256': A}, 'design': {'source': DESIGN_SRC, 'sha256': D},
        'class': ['ordinary'], 'reasons': [], 'authors': [{'model': 'claude-sonnet-5-5', 'variant': 'high', 'score': 60,
                                                         'entry': 'Claude Sonnet 5.5 (high)', 'date': '2026-11-01'}],
        'rows': rows, 'gates': {'preflight': 'exit 0, no warning', 'check_run_id': 555},
        'reviewer_assertions': {'semantic_disqualifiers': 'none', 'lineage': 'baseline: docs only', 'open_medium_high': 'none'},
        'hold_release': hold_release, 'outcome': outcome, 'earliest_merge': iso(T0 + timedelta(seconds=300)),
        'labels': [], 'executor_host': 'exec-host', 'queue_key': '%s#700@%s' % (REPO, head), 'revert': 'pending'}


def record_body(m, raw_json=None):
    js = raw_json if raw_json is not None else json.dumps(m, indent=1)
    return ('temporary, panel decision %s\nQuestion: may PR #700 merge into main at %s under the #646 delegation?\n'
            'Vote: 5-0, dissent: none; outcome: %s\n\n<!-- merge-risk-manifest v1 -->\n```json\n%s\n```\n'
            % (m.get('decision_id'), m.get('head'), m.get('outcome'), js))


def add_record(b, m=None, created=T0, edited=False, raw_json=None, cid=None):
    m = m if m is not None else manifest(b)
    cid = cid or 5000 + len(b['issue_comments'])
    b['issue_comments'].append({'url': 'https://github.com/%s/issues/701#issuecomment-%d' % (REPO, cid),
                                'body': record_body(m, raw_json), 'created_at': iso(created),
                                'updated_at': iso(created + timedelta(seconds=60 if edited else 0))})
    return m


def base(t, phase='final', cfg=None, files=None):
    files = files if files is not None else [fl('README.md', 10, 2), fl('docs/guide.md', 20)]
    b = {'phase': phase, 'pr_number': 700, 'repository': REPO, 'now': iso(T0 + timedelta(seconds=400)),
         'host': 'exec-host', 'config_text': cfg if cfg is not None else config_text(t), 'main_tip': t.B, 'merge_base': t.B,
         'verifier': {'head': t.B, 'base_present': True, 'mismatches': []},
         'acceptance': {'issue_url': OWNER_ISSUE, 'html_url': ACC, 'login': REPO.split('/')[0]},
         'config_commit_date': iso(T0 - timedelta(days=10)),
         'pr': {'state': 'OPEN', 'base': 'main', 'head_ref': 'feature/701-docs', 'head': H, 'closing_issues': [701],
                'labels': [], 'reviews': [{'state': 'APPROVED'}], 'created_at': iso(T0 - timedelta(seconds=5000)),
                'comments': ['Review done.\n<!-- pre-merge-review:done sha=%s -->' % H]},
         'files': files, 'diff_text': make_diff(files),
         'preflight': {'exit': 0, 'stderr': '', 'escape_hatch': False},
         'checks': [{'name': 'check', 'status': 'completed', 'conclusion': 'success', 'id': 555}],
         'issue': {'number': 701, 'state': 'OPEN', 'labels': []},
         'control': {'number': 607, 'state': 'OPEN', 'labels': []},
         'timeline': {'pr': [], 'issue': [], 'control': []},
         'texts': {AC_SRC: AC_TEXT, DESIGN_SRC: DESIGN_TEXT}, 'sources': {}, 'issue_comments': [], '_roles': {}}
    for role in VOTERS:
        set_report(b, role, report(role))
    add_record(b)
    return b


def refresh(b, **kw):
    """Recompute the diff from the file list and re-post one fresh record."""
    b['diff_text'] = make_diff(b['files'])
    b['issue_comments'] = []
    add_record(b, manifest(b, **kw))
    return b


def ev_label(where, label, when, event='labeled'):
    return {'event': event, 'label': label, 'created_at': iso(when)}


# --- the fake gh world for the live collector, built from a bundle
def http_head(now):
    """`gh api --include` output head; the Date header carries the bundle's now."""
    lines = ['HTTP/2.0 200 OK', 'Content-Type: application/json; charset=utf-8']
    if now is not None:
        when = datetime.strptime(now, '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc)
        lines.append('Date: ' + format_datetime(when, usegmt=True))
    return '\r\n'.join(lines) + '\r\n\r\n'


def world(b, cand_config=None, overrides=None):
    R, Hh, Bb = REPO, b['pr']['head'], b['main_tip']
    raw = 'api -H Accept: application/vnd.github.raw repos/%s/contents/' % R
    routes = {
        'repo view --json nameWithOwner --jq .nameWithOwner': {'out': R + '\n'},
        'api repos/%s/branches/main --jq .commit.sha' % R: {'out': Bb + '\n'},
        raw + 'policy/merge-autonomy.json?ref=%s' % Bb: {'out': b['config_text']},
        'pr view 700 --repo %s --json state,baseRefName,headRefName,headRefOid,closingIssuesReferences,labels,reviews,comments' % R: {
            'out': json.dumps({'state': b['pr']['state'], 'baseRefName': b['pr']['base'], 'headRefName': b['pr']['head_ref'],
                               'headRefOid': Hh, 'closingIssuesReferences': [{'number': x} for x in b['pr']['closing_issues']],
                               'labels': [{'name': x} for x in b['pr']['labels']], 'reviews': b['pr']['reviews'],
                               'comments': [{'body': x} for x in b['pr']['comments']]})},
        'api repos/%s/compare/%s...%s' % (R, Bb, Hh): {'out': json.dumps({
            'merge_base_commit': {'sha': b['merge_base']},
            'files': [dict({'filename': f['path'], 'status': 'renamed' if f['previous_path'] else 'modified',
                            'additions': f['additions'], 'deletions': f['deletions'],
                            'changes': f['additions'] + f['deletions']},
                           **({'previous_filename': f['previous_path']} if f['previous_path'] else {}),
                           **({} if f['binary'] else {'patch': '@@'})) for f in b['files']]})},
        'api -H Accept: application/vnd.github.diff repos/%s/compare/%s...%s' % (R, Bb, Hh): {'out': b['diff_text']},
        'api repos/%s/commits/%s/check-runs?per_page=100' % (R, Hh): {'out': json.dumps({'check_runs': b['checks']})},
        'api repos/%s/issues/701' % R: {'out': json.dumps({'state': b['issue']['state'].lower(), 'labels': [{'name': x} for x in b['issue']['labels']]})},
        'api repos/%s/issues/607' % R: {'out': json.dumps({'state': b['control']['state'].lower(), 'labels': [{'name': x} for x in b['control']['labels']]})},
        'api repos/%s/issues/comments/111' % R: {'out': json.dumps({
            'id': 111, 'created_at': iso(T0 - timedelta(days=30)), 'html_url': ACC,
            'issue_url': (b.get('acceptance') or {}).get('issue_url', OWNER_ISSUE),
            'user': {'login': (b.get('acceptance') or {}).get('login', REPO.split('/')[0])}})},
        'api repos/%s/commits?sha=%s&path=policy/merge-autonomy.json&per_page=1' % (R, Bb): {'out': json.dumps(
            [{'sha': Bb, 'commit': {'committer': {'date': b.get('config_commit_date')}}}])},
        'api --include repos/%s/branches/main' % R: {'out': http_head(b.get('now')) + json.dumps({'commit': {'sha': Bb}})},
        'api repos/%s/issues/comments/222' % R: {'out': json.dumps({'id': 222, 'created_at': iso(T0 - timedelta(seconds=5000))})},
        'graphql i=701': {'out': json.dumps({'data': {'repository': {'issue': {'body': AC_TEXT, 'userContentEdits': {
            'nodes': [{'editedAt': iso(T0 - timedelta(seconds=9000)), 'diff': AC_TEXT}]}}}}})},
        raw + 'ARCHITECTURE.md?ref=%s' % DESIGN_COMMIT: {'out': '# Architecture\n\n' + DESIGN_TEXT + '### A100 \u2014 next\n\nOther.\n'},
        'api --paginate repos/%s/issues/701/comments?per_page=100 --jq .[]' % R: {'out': ''.join(
            json.dumps({'html_url': c['url'], 'body': c['body'], 'created_at': c['created_at'], 'updated_at': c['updated_at']}) + '\n'
            for c in b['issue_comments'])},
    }
    for where, number in (('pr', 700), ('issue', 701), ('control', 607)):
        routes['api --paginate repos/%s/issues/%d/timeline?per_page=100 --jq .[]' % (R, number)] = {'out': ''.join(
            json.dumps({'event': e['event'], 'label': {'name': e['label']}, 'created_at': e['created_at']}) + '\n'
            for e in b['timeline'][where])}
    for url, src in b['sources'].items():
        cid = url.rsplit('-', 1)[1]
        routes['api repos/%s/issues/comments/%s' % (R, cid)] = {'out': json.dumps({'body': src['body'], 'created_at': src['created_at']})}
    if cand_config is not None:
        routes[raw + 'policy/merge-autonomy.json?ref=%s' % Hh] = {'out': cand_config}
    routes.update(overrides or {})
    return {'routes': routes, 'host': b['host'], 'preflight': {'exit': b['preflight']['exit'], 'stderr': b['preflight']['stderr']}}


def writes(log):
    bad = []
    for e in log:
        if e.get('tool') == 'SENTINEL':
            bad.append('a call reached a gh later on PATH')
        if e.get('tool') != 'gh':
            continue
        a = e['argv']
        if a[:1] == ['pr'] and a[1:2] != ['view'] or a[:1] == ['issue'] and a[1:2] not in (['view'], ['list']) \
                or a[:1] == ['label'] or a[:1] == ['api'] and (
                    any(x in ('-X', '--method', '--input') for x in a)
                    or a[1:2] != ['graphql'] and any(x in ('-f', '-F', '--field', '--raw-field') for x in a)
                    or a[1:2] == ['graphql'] and any(x.startswith('query=') and not x.startswith('query=query') for x in a)):
            bad.append(' '.join(a))
    return bad


# --- registry
ROWS = {}
MUTATIONS = {}


def row(scn, name):
    def deco(fn):
        ROWS.setdefault(scn, []).append((name, fn))
        return fn
    return deco


def mutation(scn, label, rows, lib=None, skill=None, config=None, role_contracts=None, exact=False):
    MUTATIONS.setdefault(scn, []).append((label, rows, lib, skill, config, role_contracts, exact))


def mutate_lib(text, spec):
    kind, rule = spec[0], spec[1]
    tag = re.compile(r'# rule:%s(\s|$)' % re.escape(rule))
    lines = text.split('\n')
    hits = [i for i, x in enumerate(lines) if tag.search(x)]
    if len(hits) != 1:
        raise Fail('rule %s tagged on %d lines' % (rule, len(hits)))
    i = hits[0]
    line = lines[i]
    if kind == 'drop':
        m = re.match(r'(\s*)(if|elif) .*:(\s*#.*)$', line)
        f = re.match(r'(\s*)for (.+?) in .*:(\s*#.*)$', line)
        if m:
            lines[i] = '%s%s False:%s' % m.groups()
        elif f:
            lines[i] = '%sfor %s in []:%s' % f.groups()
        else:
            raise Fail('rule %s cannot be dropped generically' % rule)
    else:
        old, new = spec[2], spec[3]
        if line.count(old) != 1:
            raise Fail('rule %s: %r occurs %d times on its line' % (rule, old, line.count(old)))
        lines[i] = line.replace(old, new)
    return '\n'.join(lines)


def sub_once(text, old, new):
    if text.count(old) != 1:
        raise Fail('mutation anchor occurs %d times: %r' % (text.count(old), old[:60]))
    return text.replace(old, new)


def run_rows(t, rows):
    failed = {}
    for name, fn in rows:
        try:
            fn(t)
        except Fail as exc:
            failed[name] = str(exc)
    return failed


def main():
    scn = SCN
    if scn not in ROWS:
        print('unknown scenario %s' % scn)
        return 1
    real = Tree()
    rows = ROWS[scn]
    failed = run_rows(real, rows)
    for name, msg in failed.items():
        ERRORS.append('S%s %s: %s' % (scn, name, msg))
    killed = 0
    for label, names, lib, skill, config, rc, exact in MUTATIONS.get(scn, []):
        try:
            t = Tree(lib=mutate_lib(real_lib(), lib) if lib else None,
                     skill=skill(real.skill) if skill else None,
                     config=config(real.config) if config else None,
                     role_contracts=rc(real.role_contracts) if rc else None)
        except Fail as exc:
            ERRORS.append('S%s mutation %s: %s' % (scn, label, exc))
            continue
        except SyntaxError as exc:
            ERRORS.append('S%s mutation %s broke the source: %s' % (scn, label, exc))
            continue
        chosen = [(n, f) for n, f in rows if n in names] if not exact else rows
        missing = set(names) - {n for n, _ in rows}
        if missing:
            ERRORS.append('S%s mutation %s names unknown rows %s' % (scn, label, sorted(missing)))
        got = run_rows(t, chosen)
        if not set(names) & set(got):
            ERRORS.append('S%s mutation %s survived: rows %s stayed green' % (scn, label, ', '.join(names)))
        elif exact and set(got) != set(names):
            ERRORS.append('S%s mutation %s failed other rows too: %s' % (scn, label, sorted(set(got) - set(names))))
        else:
            killed += 1
    for line in ERRORS:
        print('FAIL: ' + line)
    print('S%s: %d rows, %d failed; %d mutations killed of %d' % (scn, len(rows), len(failed), killed, len(MUTATIONS.get(scn, []))))
    return 1 if ERRORS else 0


def untagged_rules():
    """Rule tags of lib/merge-risk.py that no mutation of any scenario changes."""
    tags = set(re.findall(r'# rule:([A-Za-z0-9-]+)', real_lib()))
    used = {spec[2][1] for muts in MUTATIONS.values() for spec in muts if spec[2]}
    return sorted(tags - used)


@row('605', 'every-rule-tag-mutated')
def _(t):
    need(not untagged_rules(), 'rule tags without a mutation: %s' % untagged_rules())


def real_lib():
    return (ROOT / 'lib/merge-risk.py').read_text()


def class_base(t, **kw):
    return base(t, phase='class', **kw)


# =========================================================================
# S605 hard gates come first and are never votes
@row('605', 'base-class')
def _(t):
    expect(t.ev(class_base(t)), 'eligible')


@row('605', 'base-final')
def _(t):
    expect(t.ev(base(t)), 'eligible')


def gate(t, phase, fn):
    b = base(t, phase=phase)
    fn(b)
    return t.ev(b)


@row('605', 'a-preflight-exit')
def _(t):
    expect(gate(t, 'class', lambda b: b['preflight'].update(exit=2)), 'unresolved', has=['gate-preflight'])


@row('605', 'b-warning-line')
def _(t):
    o = gate(t, 'class', lambda b: b['preflight'].update(stderr='warning: merge-guard couldn\'t consult the CI status\n'))
    expect(o, 'unresolved', has=['gate-preflight-warning'])


@row('605', 'c-escape-hatch')
def _(t):
    expect(gate(t, 'class', lambda b: b['preflight'].update(escape_hatch=True)), 'unresolved', has=['gate-escape-hatch'])


@row('605', 'c-escape-hatch-collector')
def _(t):
    b = base(t, phase='class')
    o, log = t.collector(world(b), ['--phase', 'class', '700'], env={'CLAUDE_WORKFLOW_MERGE_GUARD_OFF': '1'})
    expect(o, 'unresolved', has=['gate-escape-hatch'])
    pf = [e for e in log if e.get('tool') == 'preflight']
    need(len(pf) == 1, 'merge-preflight.sh ran %d times' % len(pf))
    need(pf[0]['env']['CLAUDE_WORKFLOW_MERGE_GUARD_OFF'] is None, 'the escape hatch reached merge-preflight.sh')
    need(not writes(log), 'write calls: %s' % writes(log))


@row('605', 'collector-green')
def _(t):
    b = base(t, phase='class')
    o, log = t.collector(world(b), ['--phase', 'class', '700'])
    expect(o, 'eligible')
    need(not writes(log), 'write calls: %s' % writes(log))


@row('605', 'd-pending')
def _(t):
    expect(gate(t, 'class', lambda b: b['checks'][0].update(status='in_progress', conclusion=None)), 'unresolved', has=['gates-pending'])


@row('605', 'e-skipped')
def _(t):
    expect(gate(t, 'class', lambda b: b['checks'][0].update(conclusion='skipped')), 'unresolved', has=['gate-check'], detail='skipped')


@row('605', 'f-red')
def _(t):
    expect(gate(t, 'class', lambda b: b['checks'][0].update(conclusion='failure')), 'unresolved', has=['gate-check'], detail='failure')


@row('605', 'g-unreadable')
def _(t):
    expect(gate(t, 'class', lambda b: b.update(checks=None)), 'unresolved', has=['gate-check'])


@row('605', 'g-collector-403-and-malformed')
def _(t):
    b = base(t, phase='class')
    key = 'api repos/%s/commits/%s/check-runs?per_page=100' % (REPO, H)
    for route in ({'rc': 1, 'err': 'gh: HTTP 403: Forbidden\n'}, {'out': '{not json'}):
        o, _ = t.collector(world(b, overrides={key: route}), ['--phase', 'class', '700'])
        expect(o, 'unresolved', has=['gate-check'])


@row('605', 'h-marker-older-head')
def _(t):
    o = gate(t, 'final', lambda b: b['pr'].update(comments=['<!-- pre-merge-review:done sha=%s -->' % H2]))
    expect(o, 'unresolved', has=['gate-review-marker'], detail='stale')


@row('605', 'i-no-marker')
def _(t):
    expect(gate(t, 'final', lambda b: b['pr'].update(comments=[])), 'unresolved', has=['gate-review-marker'], detail='missing')


@row('605', 'five-voters-no-gate-row')
def _(t):
    b = base(t)
    m = json.loads(re.search(r'```json\n(.*)\n```', b['issue_comments'][0]['body'], re.S).group(1))
    need(sorted(x['role'] for x in m['rows']) == sorted(VOTERS), 'base rows are not the five voters')
    set_report(b, 'gate:check', report('orchestrator'))
    refresh(b)
    expect(t.ev(b), 'unresolved', has=['row-not-voter'])


@row('605', 'j-check-missing')
def _(t):
    o = gate(t, 'class', lambda b: b.update(checks=[{'name': 'lint', 'status': 'completed', 'conclusion': 'success', 'id': 556}]))
    expect(o, 'unresolved', has=['gate-check'], detail='missing')


mutation('605', 'check-missing', ['j-check-missing'], lib=('drop', 'check-missing'))
mutation('605', 'warning-line', ['b-warning-line'], lib=('drop', 'warning-line'))
mutation('605', 'escape-hatch-reason', ['c-escape-hatch'], lib=('drop', 'escape-hatch'))
mutation('605', 'escape-hatch-scrub', ['c-escape-hatch-collector'],
         lib=('sub', 'scrub-escape-hatch', 'if k not in ESCAPE_HATCHES', 'if k'))
mutation('605', 'pending-check', ['d-pending'], lib=('drop', 'pending'))
mutation('605', 'marker-pin', ['h-marker-older-head', 'i-no-marker'], lib=('drop', 'marker-pin'))


# =========================================================================
# S606 votes expire on any head change, update-branch included
@row('606', 'f-control')
def _(t):
    expect(t.ev(base(t)), 'eligible')


def moved_head(b):
    b['pr']['head'] = H2
    b['pr']['comments'] = ['<!-- pre-merge-review:done sha=%s -->' % H2]


@row('606', 'a-new-commit')
def _(t):
    b = base(t)
    moved_head(b)
    expect(t.ev(b), 'unresolved', has=['identity-head'])


@row('606', 'b-update-branch-merge')
def _(t):
    b = base(t)
    moved_head(b)
    b['pr']['parents'] = [H, B]  # the one merge commit gh pr update-branch makes
    expect(t.ev(b), 'unresolved', has=['identity-head'])


@row('606', 'c-base-moved')
def _(t):
    b = base(t)
    b['main_tip'] = B2
    expect(t.ev(b), 'unresolved', has=['identity-base'])


@row('606', 'd-diff-bytes')
def _(t):
    b = base(t)
    b['diff_text'] += ' '
    expect(t.ev(b), 'unresolved', has=['identity-diff'])


@row('606', 'e-config-digest')
def _(t):
    b = base(t)
    b['config_text'] += '\n'
    expect(t.ev(b), 'unresolved', has=['identity-config'])


mutation('606', 'identity-head', ['a-new-commit', 'b-update-branch-merge'], lib=('sub', 'identity-head', 'if not mine:', 'if False:'))
mutation('606', 'identity-base', ['c-base-moved'], lib=('drop', 'identity-base'))
mutation('606', 'identity-diff', ['d-diff-bytes'], lib=('drop', 'identity-diff'))
mutation('606', 'identity-config', ['e-config-digest'], lib=('drop', 'identity-config'))


# =========================================================================
# S607 unanimity: 5-0 only
@row('607', 'h-five-zero')
def _(t):
    expect(t.ev(base(t)), 'eligible')


def with_rows(t, edit):
    b = base(t)
    edit(b)
    refresh(b)
    return t.ev(b)


@row('607', 'a-four-one')
def _(t):
    o = with_rows(t, lambda b: set_report(b, 'QA', report('QA', position='no')))
    expect(o, 'referred', has=['vote-dissent'], detail='role=QA position=no')


@row('607', 'b-abstain')
def _(t):
    o = with_rows(t, lambda b: set_report(b, 'Architect', report('Architect', position='abstain')))
    expect(o, 'referred', has=['vote-dissent'], detail='position=abstain')


@row('607', 'c-missing-role')
def _(t):
    o = with_rows(t, lambda b: b['_roles'].pop('QA'))
    expect(o, 'referred', has=['vote-missing'], detail='QA')


@row('607', 'd-six-rows-duplicate')
def _(t):
    b = base(t)
    m = manifest(b)
    m['rows'].append(dict(m['rows'][1]))
    b['issue_comments'] = []
    add_record(b, m)
    expect(t.ev(b), 'unresolved', has=['row-duplicate'])


@row('607', 'e-developer-instead')
def _(t):
    b = base(t)
    set_report(b, 'Developer', report('Developer', position='yes', head=H))
    b['_roles'].pop('orchestrator')
    refresh(b)
    o = t.ev(b)
    expect(o, among=('unresolved', 'referred'), has=['row-not-voter'], detail='Developer')


@row('607', 'f-two-same-one-absent')
def _(t):
    b = base(t)
    m = manifest(b)
    m['rows'][2] = dict(m['rows'][1])
    b['issue_comments'] = []
    add_record(b, m)
    expect(t.ev(b), 'unresolved', has=['row-duplicate'])


@row('607', 'g-developer-sixth')
def _(t):
    b = base(t)
    set_report(b, 'Developer', report('Developer', position='yes', head=H))
    refresh(b)
    o = t.ev(b)
    expect(o, among=('unresolved', 'referred'), has=['row-not-voter'])


mutation('607', 'unanimity', ['a-four-one', 'b-abstain'], lib=('drop', 'unanimity'))
mutation('607', 'majority', ['a-four-one'], lib=('sub', 'unanimity', "not in ('yes', 'yes-if')", "== 'never'"))
mutation('607', 'distinct-roles', ['d-six-rows-duplicate', 'f-two-same-one-absent'], lib=('drop', 'distinct-roles'))
mutation('607', 'count-developer', ['e-developer-instead', 'g-developer-sixth'], lib=('drop', 'non-voter'))
mutation('607', 'vote-missing', ['c-missing-role'], lib=('drop', 'vote-missing'))


# =========================================================================
# S608 a marker alone is never a yes; the position line binds
@row('608', 'h-base')
def _(t):
    expect(t.ev(base(t)), 'eligible')


def with_report(t, role, body, keep_hash=False):
    b = base(t)
    set_report(b, role, body, keep_hash=keep_hash)
    refresh(b)
    return t.ev(b)


@row('608', 'a-marker-no-position')
def _(t):
    expect(with_report(t, 'Product', report('Product', lines=['I agree with the plan.'])), 'unresolved', has=['position-missing'], detail='Product')


@row('608', 'b-position-twice')
def _(t):
    line = 'merge-risk-position: role=Architect position=yes-if ac=%s design=%s head=any' % (A, D)
    expect(with_report(t, 'Architect', report('Architect', lines=[line, line])), 'unresolved', has=['position-duplicate'])


@row('608', 'c-role-mismatch')
def _(t):
    line = 'merge-risk-position: role=Architect position=yes-if ac=%s design=%s head=any' % (A, D)
    expect(with_report(t, 'QA', report('QA', lines=[line])), 'unresolved', has=['position-role'])


@row('608', 'd-hash-mismatch')
def _(t):
    b = base(t)
    url = b['_roles']['QA']['url']
    b['sources'][url]['body'] += 'edited after the record\n'
    expect(t.ev(b), 'unresolved', has=['source-hash'], detail='QA')


@row('608', 'e-first-line-not-marker')
def _(t):
    body = 'Architect notes first.\n' + report('Architect')
    expect(with_report(t, 'Architect', body), 'unresolved', has=['marker-stage'], detail='Architect')


@row('608', 'e-marker-wrong-stage')
def _(t):
    expect(with_report(t, 'QA', report('QA', marker='Planning')), 'unresolved', has=['marker-stage'], detail='QA')


@row('608', 'f-orchestrator-marker')
def _(t):
    expect(with_report(t, 'orchestrator', report('orchestrator', marker='Review')), 'unresolved', has=['marker-present'])


@row('608', 'g-reviewer-head-any')
def _(t):
    expect(with_report(t, 'Reviewer', report('Reviewer', head='any')), 'unresolved', has=['position-head'], detail='Reviewer')


@row('608', 'i-ac-digest-differs')
def _(t):
    line = 'merge-risk-position: role=Architect position=yes-if ac=%s design=%s head=any' % (sha('other ACs'), D)
    expect(with_report(t, 'Architect', report('Architect', lines=[line])), 'unresolved', has=['position-digest'], detail='Architect ac')


@row('608', 'i-design-digest-differs')
def _(t):
    expect(with_report(t, 'QA', report('QA', design=sha('other design'))), 'unresolved', has=['position-digest'], detail='QA design')


@row('608', 'collector-serves-bodies')
def _(t):
    b = base(t)
    o, log = t.collector(world(b), ['700'])
    expect(o, 'eligible')
    url = b['_roles']['Product']['url']
    b['sources'][url]['body'] = b['sources'][url]['body'].replace('report for', 'report (edited) for')
    o, _ = t.collector(world(b), ['700'])
    expect(o, 'unresolved', has=['source-hash'], detail='Product')


@row('608', 'i-position-value-differs')
def _(t):
    for said, recorded in (('no', 'yes'), ('yes-if', 'yes')):
        b = base(t)
        set_report(b, 'QA', report('QA', position=said))
        b['_roles']['QA']['position'] = recorded
        refresh(b)
        expect(t.ev(b), 'unresolved', has=['position-mismatch'], detail='QA')


mutation('608', 'position-mismatch', ['i-position-value-differs'], lib=('drop', 'position-mismatch'))
mutation('608', 'position-line',['a-marker-no-position', 'b-position-twice'], lib=('drop', 'position-line'))
mutation('608', 'source-hash', ['d-hash-mismatch'], lib=('drop', 'source-hash'))
mutation('608', 'position-role', ['c-role-mismatch'], lib=('drop', 'position-role'))
mutation('608', 'marker-stage', ['e-first-line-not-marker', 'e-marker-wrong-stage'], lib=('drop', 'marker-stage'))
mutation('608', 'orchestrator-marker-free', ['f-orchestrator-marker'], lib=('drop', 'orchestrator-marker-free'))
mutation('608', 'reviewer-head', ['g-reviewer-head-any'], lib=('drop', 'position-head-final'))
mutation('608', 'ac-equality', ['i-ac-digest-differs'], lib=('drop', 'ad-equal'))
mutation('608', 'design-equality', ['i-design-digest-differs'], lib=('drop', 'ad-design'))


# =========================================================================
# S609 the manifest binds all five rows to the same identities
@row('609', 'control')
def _(t):
    o = t.ev(base(t))
    expect(o, 'eligible')
    need(not re.search(r'authentic|verified author|proves? who', o.text, re.I), 'output claims authenticity')
    need(any('not proof of who wrote' in n for n in o.notes), 'the equal-bytes limitation note is missing')


@row('609', 'a-scope-excludes-path')
def _(t):
    o = with_report(t, 'Architect', report('Architect', paths='README.md'))
    expect(o, 'unresolved', has=['condition-scope'], detail='Architect docs/guide.md')


@row('609', 'a-paths-line-missing')
def _(t):
    body = '\n'.join(x for x in report('Architect').split('\n') if not x.startswith('paths: '))
    o = with_report(t, 'Architect', body)
    expect(o, 'unresolved', has=['condition-missing'], lacks=['condition-scope'], detail='Architect')


@row('609', 'b-row-head-differs')
def _(t):
    expect(with_report(t, 'QA', report('QA', head=H2)), 'unresolved', has=['position-head'], detail='QA')


def edit_manifest(t, fn, raw=None):
    b = base(t)
    m = manifest(b)
    fn(m)
    b['issue_comments'] = []
    add_record(b, m, raw_json=raw)
    return t.ev(b)


@row('609', 'c-ac-digest')
def _(t):
    b = base(t)
    b['texts'][AC_SRC] = AC_TEXT + 'edited later\n'
    expect(t.ev(b), 'unresolved', has=['ac-digest'])


@row('609', 'd-design-digest')
def _(t):
    b = base(t)
    b['texts'][DESIGN_SRC] = DESIGN_TEXT + 'edited later\n'
    expect(t.ev(b), 'unresolved', has=['design-digest'])


@row('609', 'e-missing-key')
def _(t):
    expect(edit_manifest(t, lambda m: m.pop('gates')), 'unresolved', has=['manifest-schema'], detail='missing:gates')


@row('609', 'e-unknown-key')
def _(t):
    expect(edit_manifest(t, lambda m: m.update(approved_by='maintainer')), 'unresolved', has=['manifest-schema'], detail='unknown:approved_by')


@row('609', 'e-malformed-json')
def _(t):
    expect(edit_manifest(t, lambda m: None, raw='{"decision_id": "MR-700-1a2b3c4-1",'), 'unresolved', has=['manifest-malformed'])


@row('609', 'f-two-records')
def _(t):
    b = base(t)
    add_record(b, manifest(b, n=2), created=T0 + timedelta(seconds=5))
    expect(t.ev(b), 'unresolved', has=['record-duplicate'])


@row('609', 'control-earlier-non-eligible-record')
def _(t):
    for outcome in ('held', 'unresolved'):
        b = base(t)
        b['issue_comments'] = []
        add_record(b, manifest(b, n=1, outcome=outcome), created=T0 - timedelta(seconds=60))
        add_record(b, manifest(b, n=2), created=T0)
        o = t.ev(b)
        expect(o, 'eligible', lacks=['record-duplicate'], detail=None)


@row('609', 'g-edited')
def _(t):
    b = base(t)
    b['issue_comments'] = []
    add_record(b, edited=True)
    expect(t.ev(b), 'unresolved', has=['record-edited'])


@row('609', 'reviewer-asserts-disqualifier')
def _(t):
    o = edit_manifest(t, lambda m: m['reviewer_assertions'].update(semantic_disqualifiers='new permission in hooks/x'))
    expect(o, 'referred', has=['assertion'], detail='semantic_disqualifiers')


@row('609', 'reviewer-assertion-missing')
def _(t):
    expect(edit_manifest(t, lambda m: m['reviewer_assertions'].update(lineage='')), 'unresolved', has=['assertion-missing'], detail='lineage')


@row('609', 'h-config-commit-not-B')
def _(t):
    o = edit_manifest(t, lambda m: m.update(config_commit=B2))
    expect(o, 'unresolved', has=['identity-config-commit'], lacks=['identity-base'])


mutation('609', 'identity-config-commit', ['h-config-commit-not-B'], lib=('drop', 'identity-config-commit'))
mutation('609', 'reviewer-assertion',['reviewer-asserts-disqualifier'], lib=('drop', 'assertion'))
mutation('609', 'schema-closed', ['e-missing-key', 'e-unknown-key'], lib=('sub', 'manifest-closed', 'manifest_errors(m)', '[]'))
mutation('609', 'single-record', ['f-two-records'], lib=('drop', 'single-record'))
mutation('609', 'no-edit', ['g-edited'], lib=('drop', 'no-edit'))
mutation('609', 'digest-sources', ['c-ac-digest', 'd-design-digest'], lib=('drop', 'ad-source'))
mutation('609', 'condition-scope', ['a-scope-excludes-path'], lib=('drop', 'condition-scope'))
mutation('609', 'condition-missing', ['a-paths-line-missing'], lib=('drop', 'condition-missing'))
mutation('609', 'count-every-outcome', ['control-earlier-non-eligible-record'],
         lib=('sub', 'eligible-only', "if m['outcome'] == 'eligible'", 'if True'))
mutation('609', 'row-head', ['b-row-head-differs'], lib=('drop', 'position-head-cond'))


# =========================================================================
# S610 a voter below the floor is not activated
def floor_case(t, score=65, author_edit=None, row_edit=None):
    b = base(t)
    b['_roles']['QA']['score'] = score
    m = manifest(b)
    if author_edit:
        author_edit(m)
    if row_edit:
        row_edit(m)
    b['issue_comments'] = []
    add_record(b, m)
    return t.ev(b)


@row('610', 'base')
def _(t):
    expect(floor_case(t), 'eligible')


@row('610', 'a-one-below')
def _(t):
    expect(floor_case(t, 59), 'referred', has=['floor-below'], detail='QA')


@row('610', 'b-equal')
def _(t):
    expect(floor_case(t, 60), 'eligible')


@row('610', 'c-above')
def _(t):
    expect(floor_case(t, 61), 'eligible')


@row('610', 'd-no-variant')
def _(t):
    expect(floor_case(t, row_edit=lambda m: m['rows'][2].update(variant='')), 'unresolved', has=['floor-evidence'])


@row('610', 'd-no-date')
def _(t):
    expect(floor_case(t, author_edit=lambda m: m['authors'][0].update(date='')), 'unresolved', has=['floor-evidence'])


@row('610', 'e-no-authors')
def _(t):
    expect(floor_case(t, author_edit=lambda m: m.update(authors=[])), 'unresolved', has=['floor-evidence'])


@row('610', 'f-non-numeric')
def _(t):
    expect(floor_case(t, row_edit=lambda m: m['rows'][2].update(score='65')), 'unresolved', has=['floor-evidence'])


@row('610', 'g-voter-between-two-authors')
def _(t):
    def two(m):
        m['authors'] = [dict(m['authors'][0], score=50), dict(m['authors'][0], model='claude-opus-5-5', score=70)]
    expect(floor_case(t, 65, author_edit=two), 'referred', has=['floor-below'], detail='highest author 70')


mutation('610', 'floor-min', ['g-voter-between-two-authors'], lib=('sub', 'floor-max', 'max(', 'min('))
mutation('610', 'strictly-greater',['b-equal'], lib=('sub', 'floor', "row['score'] < top", "row['score'] <= top"))
mutation('610', 'lower-passes', ['a-one-below'], lib=('sub', 'floor', "row['score'] < top", "row['score'] > top"))
mutation('610', 'completeness', ['d-no-variant', 'd-no-date', 'e-no-authors', 'f-non-numeric'], lib=('drop', 'floor-complete'))


# =========================================================================
# S611 four verdicts, every reason, read-only
@row('611', 'eligible')
def _(t):
    o = t.ev(base(t))
    expect(o, 'eligible')
    need(o.rc == 0, 'exit %s' % o.rc)
    need(o.ident == ('700', H, t.B, sha(base(t)['diff_text']), sha(base(t)['config_text'])), 'first-line identities differ')


@row('611', 'held')
def _(t):
    b = class_base(t)
    b['pr']['labels'] = ['hold']
    o = t.ev(b)
    expect(o, 'held', has=['label-hold'])
    need(o.rc == 1, 'exit %s' % o.rc)


@row('611', 'referred')
def _(t):
    b = class_base(t, files=[fl('README.md'), fl('merge-preflight.sh')])
    b['diff_text'] = make_diff(b['files'])
    o = t.ev(b)
    expect(o, 'referred', has=['reserved-path'])
    need(o.rc == 3, 'exit %s' % o.rc)


@row('611', 'unresolved')
def _(t):
    b = class_base(t)
    b['files'] = None
    o = t.ev(b)
    expect(o, 'unresolved', has=['files-unreadable'])
    need(o.rc == 4, 'exit %s' % o.rc)


@row('611', 'mixed-precedence-all-reasons')
def _(t):
    b = class_base(t, files=[fl('README.md'), fl('merge-preflight.sh')])
    b['diff_text'] = make_diff(b['files'])
    b['pr']['labels'] = ['hold']
    b['checks'] = None
    expect(t.ev(b), 'referred', has=['label-hold', 'reserved-path', 'gate-check'])


@row('611', 'usage-and-crash')
def _(t):
    b = base(t)
    for args in (['--bogus'], [], ['--phase', 'sideways', '700'], ['--queue', '700'], ['700', '701'], ['0']):
        o, _ = t.collector(world(b), args)
        need(o.rc == 2, 'args %s exit %s, expected 2' % (args, o.rc))
    b['files'] = ['not a file object']
    o = t.ev(b)
    expect(o, 'unresolved', has=['verifier-crash'])


@row('611', 'missing-gh-or-python')
def _(t):
    nogh = t.dir / 'nogh'
    nogh.mkdir(exist_ok=True)
    if not (nogh / 'python3').exists():
        os.symlink(sys.executable, nogh / 'python3')
    o, _ = t.collector(world(base(t)), ['700'], path=str(nogh))
    expect(o, 'unresolved', has=['gh-missing'])
    empty = t.dir / 'empty'
    empty.mkdir(exist_ok=True)
    o, _ = t.collector(world(base(t)), ['700'], path=str(empty))
    expect(o, 'unresolved', has=['python3-missing'])


@row('611', 'read-only-call-log-and-tree')
def _(t):
    repo = t.dir / ('checkout-%d' % t.n)
    repo.mkdir()
    env = dict(os.environ, GIT_AUTHOR_NAME='t', GIT_AUTHOR_EMAIL='t@example.invalid', GIT_COMMITTER_NAME='t', GIT_COMMITTER_EMAIL='t@example.invalid')
    for cmd in (['init', '-q', '-b', 'main'], ['add', '.'], ['commit', '-q', '--allow-empty', '-m', 'x']):
        subprocess.run(['git', '-C', str(repo)] + cmd, env=env, capture_output=True)
    (repo / 'file.txt').write_text('x\n')
    before = subprocess.run(['git', '-C', str(repo), 'status', '--porcelain'], capture_output=True).stdout
    index = (repo / '.git/index').read_bytes() if (repo / '.git/index').exists() else b''
    for args in (['--phase', 'class', '700'], ['700']):
        o, log = t.collector(world(base(t)), args, cwd=str(repo))
        expect(o, 'eligible')
        need(not writes(log), 'write calls: %s' % writes(log))
    after = subprocess.run(['git', '-C', str(repo), 'status', '--porcelain'], capture_output=True).stdout
    need(before == after, 'working tree changed')
    need(index == ((repo / '.git/index').read_bytes() if (repo / '.git/index').exists() else b''), 'index changed')


def class_edit(t, fn):
    b = class_base(t)
    fn(b)
    return t.ev(b)


@row('611', 'a-pr-not-open')
def _(t):
    for state in ('CLOSED', 'MERGED'):
        expect(class_edit(t, lambda b: b['pr'].update(state=state)), 'unresolved', has=['pr-not-open'], detail=state)


@row('611', 'b-closing-unreadable')
def _(t):
    expect(class_edit(t, lambda b: b['pr'].update(closing_issues=None)), 'unresolved', has=['closing-issues'], detail='unreadable')


@row('611', 'c-issue-unreadable')
def _(t):
    expect(class_edit(t, lambda b: b.update(issue=None)), 'unresolved', has=['issue-unreadable'], detail='701')


@row('611', 'd-labels-unreadable')
def _(t):
    for where, fn in (('pr', lambda b: b['pr'].update(labels=None)), ('issue', lambda b: b['issue'].update(labels=None)),
                      ('control', lambda b: b['control'].update(labels=None))):
        expect(class_edit(t, fn), 'unresolved', has=['labels-unreadable'], lacks=['verifier-crash'], detail=where)


mutation('611', 'pr-not-open', ['a-pr-not-open'], lib=('drop', 'pr-not-open'))
mutation('611', 'closing-unreadable', ['b-closing-unreadable'], lib=('drop', 'closing-unreadable'))
mutation('611', 'issue-unreadable', ['c-issue-unreadable'], lib=('drop', 'issue-unreadable'))
mutation('611', 'labels-unreadable', ['d-labels-unreadable'], lib=('drop', 'labels-unreadable'))
mutation('611', 'control-labels-unreadable', ['d-labels-unreadable'], lib=('drop', 'control-labels-unreadable'))
mutation('611', 'precedence',['mixed-precedence-all-reasons'],
         lib=('sub', 'precedence', "('referred', 'unresolved', 'held')", "('held', 'unresolved', 'referred')"))
mutation('611', 'first-reason-only', ['mixed-precedence-all-reasons'],
         lib=('sub', 'all-reasons', 'self.reasons.append((kind, code, str(detail)))',
              'self.reasons[:] = self.reasons or [(kind, code, str(detail))]'))
mutation('611', 'write-call', ['read-only-call-log-and-tree'],
         lib=('sub', 'read-only', "'now': None}", "'now': None}; gh(['issue', 'comment', '701', '--body', 'x'])"))


# =========================================================================
# S612 caps are inclusive; both counts positive
def lines_case(t, total, nfiles=2, extra_cfg=None):
    per = [total // nfiles + (1 if i < total % nfiles else 0) for i in range(nfiles)]
    files = [fl('docs/page-%d.md' % i, per[i]) for i in range(nfiles)]
    b = class_base(t, files=files, cfg=config_text(t, edit=extra_cfg) if extra_cfg else None)
    return t.ev(b)


@row('612', 'base')
def _(t):
    expect(t.ev(class_base(t)), 'eligible')


@row('612', 'lines-299')
def _(t):
    expect(lines_case(t, 299), 'eligible')


@row('612', 'lines-300')
def _(t):
    expect(lines_case(t, 300), 'eligible')


@row('612', 'lines-301')
def _(t):
    expect(lines_case(t, 301), 'referred', has=['cap-lines'])


@row('612', 'files-7')
def _(t):
    expect(lines_case(t, 14, 7), 'eligible')


@row('612', 'files-8')
def _(t):
    expect(lines_case(t, 16, 8), 'eligible')


@row('612', 'files-9-incl-generated')
def _(t):
    files = [fl('docs/page-%d.md' % i) for i in range(8)] + [fl('WORKFLOW.md')]
    expect(t.ev(class_base(t, files=files)), 'referred', has=['cap-files'])


@row('612', 'zero-lines-one-file')
def _(t):
    expect(t.ev(class_base(t, files=[fl('docs/empty.md', 0)])), 'referred', has=['cap-lines'])


@row('612', 'zero-files')
def _(t):
    expect(t.ev(class_base(t, files=[])), 'referred', has=['cap-files'])


@row('612', 'rename-counts-both')
def _(t):
    files = [fl('docs/page-%d.md' % i) for i in range(7)] + [fl('docs/new.md', 1, 1, prev='docs/old.md')]
    expect(t.ev(class_base(t, files=files)), 'referred', has=['cap-files'], detail='files=9')


@row('612', 'rename-at-cap')
def _(t):
    files = [fl('docs/page-%d.md' % i) for i in range(6)] + [fl('docs/new.md', 1, 1, prev='docs/old.md')]
    expect(t.ev(class_base(t, files=files)), 'eligible')


@row('612', 'docs-tests-generated-count')
def _(t):
    files = [fl('docs/a.md', 100), fl('test/cases/s1.sh', 100), fl('WORKFLOW.md', 101)]
    expect(t.ev(class_base(t, files=files)), 'referred', has=['cap-lines'], detail='lines=301')


@row('612', 'binary')
def _(t):
    expect(t.ev(class_base(t, files=[fl('docs/a.md'), fl('test/fixtures/img.png', binary=True)])), 'unresolved', has=['binary-file'])


@row('612', 'full-range-collector')
def _(t):
    b = class_base(t, files=[fl('docs/a.md', 150), fl('docs/b.md', 151)])
    b['diff_text'] = make_diff(b['files'])
    o, log = t.collector(world(b), ['--phase', 'class', '700'])
    expect(o, 'referred', has=['cap-lines'], detail='lines=301')
    need(any(e.get('argv') == ['api', 'repos/%s/compare/%s...%s' % (REPO, t.B, H)] for e in log), 'the B...H compare was not read')


for _key, _val, _ok in (('max_lines', 0, False), ('max_lines', -1, False), ('max_files', 0, False),
                        ('max_files', -1, False), ('hold_seconds', 0, False), ('hold_seconds', 1, True)):
    def _make(key=_key, val=_val, ok=_ok):
        def fn(t):
            b = class_base(t, cfg=config_text(t, edit=lambda c: c.update({key: val})))
            if ok:
                expect(t.ev(b), 'eligible')
            else:
                expect(t.ev(b), 'unresolved', has=['config-invalid'], detail=key)
        return fn
    row('612', 'config-%s-%s' % (_key, _val))(_make())

mutation('612', 'lines-exclusive', ['lines-300'], lib=('sub', 'cap-lines', "lines <= cfg['max_lines']", "lines < cfg['max_lines']"))
mutation('612', 'lines-plus-one', ['lines-301'], lib=('sub', 'cap-lines', "lines <= cfg['max_lines']", "lines <= cfg['max_lines'] + 1"))
mutation('612', 'files-exclusive', ['files-8'], lib=('sub', 'cap-files', "len(paths) <= cfg['max_files']", "len(paths) < cfg['max_files']"))
mutation('612', 'files-plus-one', ['files-9-incl-generated'], lib=('sub', 'cap-files', "len(paths) <= cfg['max_files']", "len(paths) <= cfg['max_files'] + 1"))
mutation('612', 'empty-lines-accepted', ['zero-lines-one-file'], lib=('sub', 'cap-lines', '1 <= lines', '0 <= lines'))
mutation('612', 'empty-files-accepted', ['zero-files'], lib=('sub', 'cap-files', '1 <= len(paths)', '0 <= len(paths)'))
mutation('612', 'rename-once', ['rename-counts-both'], lib=('sub', 'rename-both', "paths.add(f['previous_path'])", 'pass'))
mutation('612', 'last-commit-only', ['full-range-collector'],
         lib=('sub', 'full-range', "'repos/%s/compare/%s...%s' % (repo, B, H)", "'repos/%s/compare/%s~1...%s' % (repo, H, H)"))
mutation('612', 'accept-zero', ['config-max_lines-0', 'config-hold_seconds-0'], lib=('sub', 'config-positive', 'cfg[key] < 1', 'cfg[key] < 0'))


# =========================================================================
# S613 each disqualifier alone; look-alikes stay eligible
def one_path(t, path, extra=''):
    b = class_base(t, files=[fl('README.md', 3), fl(path, 2)])
    b['diff_text'] = make_diff(b['files'], extra)
    return t.ev(b)


RESERVED_PAIRS = [
    ('CHANGELOG.md', 'CHANGELOG.md'), ('VERSION', 'VERSION'), ('package.json', 'package.json'),
    ('skills/release-branch-workflow/x', 'skills/release-branch-workflow/**'),
    ('merge-preflight.sh', 'merge-preflight.sh'), ('hooks/git-guardrails', 'hooks/git-guardrails'),
    ('skills/pre-merge-review/x', 'skills/pre-merge-review/**'), ('lib/model-record.sh', 'lib/model-record**'),
    ('lib/model-records-note.md', 'lib/model-record**'),
    ('pipeline-override.sh', 'pipeline-override.sh'), ('skills/role-contracts/x', 'skills/role-contracts/**'),
    ('skills/merge-risk-panel/SKILL.md', 'skills/merge-risk-panel/**'),
    ('policy/merge-autonomy.json', 'policy/merge-autonomy.json'), ('merge-risk-evidence.sh', 'merge-risk-evidence.sh'),
    ('lib/merge-risk.py', 'lib/merge-risk**'), ('test/cases/s610_merge_risk_x.sh', 'test/cases/**merge_risk**'),
    ('test/fixtures/merge-risk-646.py', 'test/fixtures/merge-risk**'),
    ('test/fixtures/merge-risk/x.py', 'test/fixtures/merge-risk**'),
    ('test/behavior/merge-risk-scenarios.md', 'test/behavior/merge-risk**')]
RESERVED_ROWS = [p for p, _ in RESERVED_PAIRS]
RESERVED_PATTERN = dict(RESERVED_PAIRS)
for _p in RESERVED_ROWS:
    def _mk(p=_p):
        def fn(t):
            expect(one_path(t, p), 'referred', has=['reserved-path'], detail=p)
        return fn
    row('613', 'reserved ' + _p)(_mk())


@row('613', 'base')
def _(t):
    expect(t.ev(class_base(t)), 'eligible')


@row('613', 'unlisted')
def _(t):
    expect(one_path(t, 'foo/bar.txt'), 'referred', has=['unlisted-path'])


@row('613', 'case-sensitive')
def _(t):
    o = one_path(t, 'changelog.md')
    expect(o, 'referred', has=['unlisted-path'], lacks=['reserved-path'])


@row('613', 'star-one-segment')
def _(t):
    expect(one_path(t, 'lib/sub/adopt-x.sh'), 'referred', has=['unlisted-path'])


@row('613', 'double-star-depth')
def _(t):
    expect(one_path(t, 'docs/a/b/c.md'), 'eligible')


@row('613', 'meaning-version-line')
def _(t):
    hunk = 'diff --git a/CHANGES.md b/CHANGES.md\n--- a/CHANGES.md\n+++ b/CHANGES.md\n@@ -1 +1 @@\n-**Meaning version:** 3\n+**Meaning version:** 4\n'
    b = class_base(t, files=[fl('README.md', 3), fl('CHANGES.md', 1, 1)])
    b['diff_text'] = make_diff(b['files'][:1]) + hunk
    expect(t.ev(b), 'referred', has=['meaning-version-line'])


@row('613', 'release-head')
def _(t):
    b = class_base(t)
    b['pr']['head_ref'] = 'release/x'
    expect(t.ev(b), 'referred', has=['release-head'])


@row('613', 'base-not-main')
def _(t):
    b = class_base(t)
    b['pr']['base'] = 'release/607-panel-mechanisms'
    expect(t.ev(b), 'referred', has=['base-not-main'])


@row('613', 'changes-requested-ever')
def _(t):
    b = class_base(t)
    b['pr']['reviews'] = [{'state': 'CHANGES_REQUESTED'}, {'state': 'DISMISSED'}, {'state': 'APPROVED'}]
    expect(t.ev(b), 'referred', has=['changes-requested'])


def label_case(t, where, label):
    b = class_base(t)
    (b['pr'] if where == 'pr' else b[where])['labels'] = [label]
    return t.ev(b)


@row('613', 'risk-high-pr')
def _(t):
    expect(label_case(t, 'pr', 'risk:high'), 'held', has=['label-hold'])


@row('613', 'hold-pr')
def _(t):
    expect(label_case(t, 'pr', 'hold'), 'held', has=['label-hold'])


@row('613', 'hold-issue')
def _(t):
    expect(label_case(t, 'issue', 'hold'), 'held', has=['label-hold'], detail='issue hold')


@row('613', 'off-pr')
def _(t):
    expect(label_case(t, 'pr', 'merge-autonomy:off'), 'referred', has=['label-off'], detail='pr')


@row('613', 'off-issue')
def _(t):
    expect(label_case(t, 'issue', 'merge-autonomy:off'), 'referred', has=['label-off'], detail='issue')


@row('613', 'off-control')
def _(t):
    expect(label_case(t, 'control', 'merge-autonomy:off'), 'referred', has=['label-off-control'])


@row('613', 'closing-zero')
def _(t):
    b = class_base(t)
    b['pr']['closing_issues'] = []
    expect(t.ev(b), 'referred', has=['closing-issues'], detail='count=0')


@row('613', 'closing-two')
def _(t):
    b = class_base(t)
    b['pr']['closing_issues'] = [701, 702]
    expect(t.ev(b), 'referred', has=['closing-issues'], detail='count=2')


@row('613', 'behind-base')
def _(t):
    b = class_base(t)
    b['merge_base'] = B2
    expect(t.ev(b), 'unresolved', has=['behind-base'])


@row('613', 'control-tag-version-prose')
def _(t):
    b = class_base(t)
    b['diff_text'] = b['diff_text'].replace('+new line 0 of README.md', '+Tag the version in the release notes.')
    expect(t.ev(b), 'eligible')


@row('613', 'control-changes-md-other-line')
def _(t):
    hunk = 'diff --git a/CHANGES.md b/CHANGES.md\n--- a/CHANGES.md\n+++ b/CHANGES.md\n@@ -1 +1 @@\n-An old sentence.\n+A new sentence; **Meaning version:** unchanged below.\n'
    b = class_base(t, files=[fl('README.md', 3), fl('CHANGES.md', 1, 1)])
    b['diff_text'] = make_diff(b['files'][:1]) + hunk.replace('; **Meaning version:** unchanged below', '')
    expect(t.ev(b), 'eligible')


@row('613', 'control-lookalike-docs')
def _(t):
    expect(one_path(t, 'docs/merge-preflight.sh.md'), 'eligible')


@row('613', 'control-lookalike-version-under-test')
def _(t):
    expect(one_path(t, 'test/VERSION'), 'eligible')


@row('613', 'control-lookalike-test-lib-model-record')
def _(t):
    expect(one_path(t, 'test/lib/model-record.sh'), 'eligible')


NESTED_GROUP_CONTROLS = ['.github/ISSUE_TEMPLATE/bug.md', 'adapters/codex/INSTRUCTIONS.md', 'skills/adopt-workflow/SKILL.md']
for _p in NESTED_GROUP_CONTROLS:
    def _mk(p=_p):
        def fn(t):
            expect(one_path(t, p), lacks=['unlisted-path', 'reserved-path'])
        return fn
    row('613', 'control-nested ' + _p)(_mk())


for _p in RESERVED_ROWS:
    def _cfg_drop(text, p=_p):
        cfg = json.loads(text)
        pat = RESERVED_PATTERN[p]
        for k in ('release', 'autonomy'):
            if pat in cfg['reserved'][k]:
                cfg['reserved'][k].remove(pat)
        return json.dumps(cfg)
    _others = [x for x in RESERVED_ROWS if RESERVED_PATTERN[x] == RESERVED_PATTERN[_p]]
    mutation('613', 'delete reserved entry ' + RESERVED_PATTERN[_p], ['reserved ' + x for x in _others], config=_cfg_drop, exact=True)
mutation('613', 'reserved-rule', ['reserved ' + x for x in RESERVED_ROWS], lib=('drop', 'reserved'))


def _one_segment(text, group, pat):
    cfg = json.loads(text)
    lst = cfg['groups'][group]
    lst[lst.index(pat + '/**')] = pat + '/*'
    return json.dumps(cfg)


# Only .github/ISSUE_TEMPLATE/bug.md depends on `/**` alone: adapters/codex/INSTRUCTIONS.md is
# also a generated input, and skills/adopt-workflow/SKILL.md is a direct child.
mutation('613', 'one-segment star .github', ['control-nested .github/ISSUE_TEMPLATE/bug.md'], exact=True,
         config=lambda s: _one_segment(s, 'guard', '.github'))
mutation('613', 'delete label hold', ['hold-pr', 'hold-issue'], exact=True,
         config=lambda s: json.dumps(dict(json.loads(s), labels={'hold': ['risk:*'], 'off': 'merge-autonomy:off'})))
mutation('613', 'delete label risk', ['risk-high-pr'], exact=True,
         config=lambda s: json.dumps(dict(json.loads(s), labels={'hold': ['hold'], 'off': 'merge-autonomy:off'})))
mutation('613', 'change label off', ['off-pr', 'off-issue', 'off-control'], exact=True,
         config=lambda s: json.dumps(dict(json.loads(s), labels={'hold': ['hold', 'risk:*'], 'off': 'autonomy:other'})))
mutation('613', 'changes-requested-rule', ['changes-requested-ever'], lib=('drop', 'changes-requested'), exact=True)
mutation('613', 'meaning-version-rule', ['meaning-version-line'], lib=('drop', 'meaning-version'), exact=True)
mutation('613', 'release-head-rule', ['release-head'], lib=('drop', 'release-head'), exact=True)
mutation('613', 'base-main-rule', ['base-not-main'], lib=('drop', 'base-main'), exact=True)
mutation('613', 'closing-one-rule', ['closing-zero', 'closing-two'], lib=('drop', 'closing-one'), exact=True)
mutation('613', 'behind-base-rule', ['behind-base'], lib=('drop', 'behind-base'), exact=True)
mutation('613', 'unlisted-rule', ['unlisted', 'case-sensitive', 'star-one-segment'], lib=('drop', 'unlisted'), exact=True)
mutation('613', 'label-off-item-rule', ['off-pr', 'off-issue'], lib=('drop', 'label-off-item'), exact=True)
mutation('613', 'label-hold-rule', ['risk-high-pr', 'hold-pr', 'hold-issue'], lib=('drop', 'label-hold'), exact=True)


# =========================================================================
# S614 the config is read at the main tip; a candidate cannot widen itself
CANDIDATES = {
    'raise-max-lines': lambda c: c.update(max_lines=3000),
    'own-path-in-group': lambda c: c['groups']['ordinary'].append('policy/merge-autonomy.json'),
    'clear-reserved': lambda c: c['reserved'].update(autonomy=[], release=[]),
    'enable-with-link': lambda c: c.update(enabled=True, acceptance=ACC.replace('111', '999')),
    'change-hold': lambda c: c.update(hold_seconds=1),
}


def candidate_bundle(t):
    files = [fl('docs/a.md', 150), fl('docs/b.md', 150), fl('policy/merge-autonomy.json', 1, 1)]
    b = base(t, phase='class', files=files)
    return b


for _name, _edit in CANDIDATES.items():
    def _mk(edit=_edit):
        def fn(t):
            b = candidate_bundle(t)
            cand = json.loads(t.config)
            edit(cand)
            o, log = t.collector(world(b, cand_config=json.dumps(cand)), ['--phase', 'class', '700'])
            expect(o, 'referred', has=['reserved-path'], detail='policy/merge-autonomy.json')
            need(o.ident and o.ident[4] == sha(b['config_text']), 'config digest is not the SHA-256 of the main-tip bytes')
            need(not any('ref=%s' % H in ' '.join(e.get('argv', [])) for e in log), 'the candidate head config was read')
        return fn
    row('614', 'candidate ' + _name)(_mk())


@row('614', 'control-enabled-valid')
def _(t):
    o = t.ev(class_base(t))
    expect(o, 'eligible')
    need(o.ident[4] == sha(class_base(t)['config_text']), 'config= is not the digest of the exact bytes')


INVALID = {
    'unknown-key': lambda c: c.update(extra=1),
    'missing-key': lambda c: c.pop('labels'),
    'wrong-type': lambda c: c.update(max_lines='300'),
    'enabled-null-acceptance': lambda c: c.update(acceptance=None),
    'acceptance-wrong-shape': lambda c: c.update(acceptance='https://github.com/%s/issues/645#issuecomment-1' % REPO),
    'repository-differs': lambda c: c.update(repository='Other/repo', acceptance='https://github.com/Other/repo/issues/646#issuecomment-1'),
}
for _name, _edit in INVALID.items():
    def _mk(edit=_edit):
        def fn(t):
            for files in (None, [fl('README.md'), fl('merge-preflight.sh')]):
                b = class_base(t, cfg=config_text(t, edit=edit), files=files)
                o = t.ev(b)
                expect(o, 'unresolved', lacks=['reserved-path'])
                need(any(c.startswith('config-') for c in o.codes), 'no config-* reason: %r' % o)
        return fn
    row('614', 'invalid ' + _name)(_mk())


@row('614', 'invalid malformed-and-absent')
def _(t):
    for text in ('{"schema": 1,', None, '{"schema": 1, "schema": 1}'):
        b = class_base(t)
        b['config_text'] = text
        expect(t.ev(b), 'unresolved', has=['config-absent'] if text is None else ['config-malformed'])


@row('614', 'shipped-disabled')
def _(t):
    for phase in ('class', 'final'):
        b = base(t, phase=phase, cfg=t.config)
        o = t.ev(b)
        expect(o, among=('referred', 'unresolved'), has=['autonomy-disabled'])
        need(o.ident[4] == sha(t.config), 'config= is not the digest of the shipped bytes')


ACCEPTANCE = {
    'a-missing': (lambda a: None, 'missing'),
    'b-other-issue': (lambda a: dict(a, issue_url='https://api.github.com/repos/%s/issues/1' % REPO), 'issue'),
    'c-other-author': (lambda a: dict(a, login='someone-else'), 'author'),
}
for _name, (_edit, _detail) in ACCEPTANCE.items():
    def _mk(edit=_edit, detail=_detail):
        def fn(t):
            b = class_base(t)
            b['acceptance'] = edit(b['acceptance'])
            o = t.ev(b)
            expect(o, 'unresolved', has=['acceptance-unverified'], lacks=['verifier-crash'])
            need(any(r.startswith('acceptance-unverified ' + detail) for r in o.reasons), 'no acceptance-unverified %s: %r' % (detail, o))
        return fn
    row('614', 'acceptance ' + _name)(_mk())


@row('614', 'acceptance collector reads issue and login')
def _(t):
    b = class_base(t)
    o, _ = t.collector(world(b), ['--phase', 'class', '700'])
    expect(o, 'eligible')
    b['acceptance'] = dict(b['acceptance'], login='someone-else', issue_url='https://api.github.com/repos/%s/issues/1' % REPO)
    o, _ = t.collector(world(b), ['--phase', 'class', '700'])
    expect(o, 'unresolved', has=['acceptance-unverified'])
    need(len([r for r in o.reasons if r.startswith('acceptance-unverified ')]) == 2, 'issue and author not both reported: %r' % o)


VERIFIER = {
    'd-head-not-B': (lambda v: dict(v, head=B2), 'head '),
    'e-reserved-byte-differs': (lambda v: dict(v, mismatches=['lib/merge-risk.py']), 'bytes lib/merge-risk.py'),
    'f-B-absent': (lambda v: dict(v, base_present=False), 'base-absent'),
    'g-field-missing': (lambda v: None, 'field missing'),
}
for _name, (_edit, _detail) in VERIFIER.items():
    def _mk(edit=_edit, detail=_detail):
        def fn(t):
            for phase in ('class', 'final'):
                b = base(t, phase=phase)
                b['verifier'] = edit(b['verifier'])
                expect(t.ev(b), 'unresolved', has=['verifier-not-at-base'], lacks=['verifier-crash'], detail=detail)
        return fn
    row('614', 'verifier ' + _name)(_mk())


@row('614', 'verifier collector control at B')
def _(t):
    o, log = t.collector(world(class_base(t)), ['--phase', 'class', '700'])
    expect(o, 'eligible', lacks=['verifier-not-at-base'])
    need(not writes(log), 'write calls: %s' % writes(log))


@row('614', 'verifier collector head moved')
def _(t):
    c = t.clone()
    c.vcs('commit', '-q', '--allow-empty', '-m', 'candidate')
    o, _ = c.collector(world(class_base(c)), ['--phase', 'class', '700'])
    expect(o, 'unresolved', has=['verifier-not-at-base'], detail='head ')


@row('614', 'verifier collector one byte differs')
def _(t):
    c = t.clone()
    (c.dir / 'lib/model-record.sh').write_bytes((c.dir / 'lib/model-record.sh').read_bytes() + b'#')
    c.vcs('update-index', '--assume-unchanged', 'lib/model-record.sh')
    o, _ = c.collector(world(class_base(c)), ['--phase', 'class', '700'])
    expect(o, 'unresolved', has=['verifier-not-at-base'], detail='bytes lib/model-record.sh')


@row('614', 'verifier collector B absent')
def _(t):
    b = class_base(t)
    b['main_tip'] = b['merge_base'] = 'abcdef12' * 5
    o, _ = t.collector(world(b), ['--phase', 'class', '700'])
    expect(o, 'unresolved', has=['verifier-not-at-base'], detail='base-absent')


mutation('614', 'acceptance-exists', ['acceptance a-missing'], lib=('drop', 'acceptance-exists'))
mutation('614', 'acceptance-issue', ['acceptance b-other-issue'], lib=('drop', 'acceptance-issue'))
mutation('614', 'acceptance-author', ['acceptance c-other-author'], lib=('drop', 'acceptance-author'))
mutation('614', 'verifier-field', ['verifier g-field-missing'], lib=('drop', 'verifier-field'))
mutation('614', 'verifier-base-present', ['verifier f-B-absent', 'verifier collector B absent'], lib=('drop', 'verifier-base-present'))
mutation('614', 'verifier-head', ['verifier d-head-not-B', 'verifier collector head moved'], lib=('drop', 'verifier-head'))
mutation('614', 'verifier-bytes', ['verifier e-reserved-byte-differs', 'verifier collector one byte differs'], lib=('drop', 'verifier-bytes'))
mutation('614', 'read-config-from-H',['candidate raise-max-lines'], lib=('sub', 'config-at-B', '% (repo, B)', '% (repo, H)'))
mutation('614', 'schema-not-closed', ['invalid unknown-key', 'invalid missing-key'], lib=('sub', 'config-closed', 'config_errors(cfg)', '[]'))
mutation('614', 'enabled-acceptance-pairing', ['invalid enabled-null-acceptance'], lib=('drop', 'enabled-needs-acceptance'))


# =========================================================================
# S615 records: complete, on the work-item issue, never edited
def template(skill):
    lines = skill.split('\n')
    start = next(i for i, x in enumerate(lines) if x.strip().endswith('Template:'))
    out = []
    for x in lines[start + 1:]:
        if x.startswith('    ') or not x.strip():
            out.append(x[4:])
        else:
            break
    return '\n'.join(out).strip('\n') + '\n'


def filled_record(t, outcome):
    tpl = template(t.skill)
    js = re.search(r'```json\n(.*?)\n```', tpl, re.S)
    need(js and MANIFEST_LINE in tpl, 'the skill template lacks the manifest block')
    m = json.loads(js.group(1))
    b = base(t)
    real = manifest(b, outcome=outcome)
    need(sorted(m) == sorted(real), 'template keys differ from the record schema: %s' % sorted(set(m) ^ set(real)))
    body = tpl.replace(js.group(1), json.dumps(real, indent=1)).replace('MR-<pr>-<short H>-<n>', real['decision_id'])
    return body, real


MANIFEST_LINE = '<!-- merge-risk-manifest v1 -->'


def reader(t, body, edited=False):
    return t.cli('record', {'body': body, 'created_at': iso(T0), 'updated_at': iso(T0 + timedelta(seconds=9 if edited else 0))})


def reader_ok(o):
    need(o.first == 'record: ok' and o.rc == 0, 'record reader: %s' % o.text.strip())


def reader_bad(o, code):
    need(o.first == 'record: invalid' and o.rc == 4 and code in o.codes, 'record reader accepted or wrong code: %s' % o.text.strip())


for _outcome in ('eligible', 'held', 'vetoed', 'unresolved', 'referred', 'failed', 'merged'):
    def _mk(outcome=_outcome):
        def fn(t):
            body, _ = filled_record(t, outcome)
            reader_ok(reader(t, body))
        return fn
    row('615', 'template ' + _outcome)(_mk())

for _key in ('decision_id', 'repository', 'issue', 'pr', 'head', 'base', 'diff_sha256', 'config_sha256', 'config_commit',
             'ac', 'design', 'class', 'reasons', 'authors', 'rows', 'gates', 'reviewer_assertions', 'hold_release',
             'outcome', 'earliest_merge', 'labels', 'executor_host', 'queue_key', 'revert'):
    def _mk(key=_key):
        def fn(t):
            body, m = filled_record(t, 'eligible')
            m.pop(key)
            body = record_body(m)
            reader_bad(reader(t, body), 'manifest-schema')
        return fn
    row('615', 'missing ' + _key)(_mk())


@row('615', 'missing literal label')
def _(t):
    body, _ = filled_record(t, 'eligible')
    reader_bad(reader(t, body.replace('temporary, panel decision', 'panel decision')), 'record-label')


@row('615', 'edited record')
def _(t):
    body, _ = filled_record(t, 'eligible')
    reader_bad(reader(t, body, edited=True), 'record-edited')


@row('615', 'revert not pending')
def _(t):
    body, m = filled_record(t, 'eligible')
    m['revert'] = 'git revert ' + SQUASH
    reader_bad(reader(t, record_body(m)), 'revert-not-pending')


@row('615', 'template fields and disclosure')
def _(t):
    tpl = template(t.skill)
    for field in ('temporary, panel decision', 'Question:', 'Delegation:', 'configuration revision', 'Positions:',
                  'Vote:', 'dissent:', 'outcome:', 'Rationale:', 'reservation status:', 'limit/risk flag:', 'T:',
                  'earliest merge:'):
        need(field in tpl, 'template lacks %r' % field)
    flat = ' '.join(t.skill.split())
    for sentence in ('ordinary comment on the work-item issue, never only on the PR',
                     'The PR description links it beside `Closes #<work-item>`',
                     'merge-risk records are listed in their own 5-0 group',
                     'dissent and unresolved records stay visible', 'never invent a 3-0 or 2-1 vote'):
        need(sentence in flat, 'skill lacks %r' % sentence)


@row('615', 'final control')
def _(t):
    expect(t.ev(base(t)), 'eligible')


@row('615', 'final a-label-absent')
def _(t):
    b = base(t)
    b['issue_comments'][0]['body'] = b['issue_comments'][0]['body'].replace('temporary, panel decision', 'panel decision')
    expect(t.ev(b), 'unresolved', has=['record-label'])


@row('615', 'final b-id-wrong')
def _(t):
    for ident in ('MR-700-5e6f7a8-1', 'MR-699-1a2b3c4-1', 'decision-1'):
        expect(edit_manifest(t, lambda m: m.update(decision_id=ident)), 'unresolved', has=['record-id'], detail=ident)


@row('615', 'final c-other-repository')
def _(t):
    expect(edit_manifest(t, lambda m: m.update(repository='Other/repo')), 'unresolved', has=['manifest-binding'], detail='repository')


@row('615', 'final d-other-issue')
def _(t):
    expect(edit_manifest(t, lambda m: m.update(issue=702)), 'unresolved', has=['manifest-binding'], detail='issue')


mutation('615', 'final-label', ['final a-label-absent'], lib=('drop', 'record-label-final'))
mutation('615', 'final-id', ['final b-id-wrong'], lib=('drop', 'record-id-final'))
mutation('615', 'manifest-binding', ['final c-other-repository', 'final d-other-issue'], lib=('drop', 'manifest-binding'))
mutation('615', 'manifest-binding-repository', ['final c-other-repository'],
         lib=('sub', 'manifest-binding', 'if m[key] != want:', "if m[key] != want and key != 'repository':"))
mutation('615', 'manifest-binding-issue', ['final d-other-issue'],
         lib=('sub', 'manifest-binding', 'if m[key] != want:', "if m[key] != want and key != 'issue':"))
mutation('615', 'reader-fields',['missing gates', 'missing revert', 'missing rows'], lib=('sub', 'record-fields', 'manifest_errors(m)', '[]'))
mutation('615', 'reader-label', ['missing literal label'], lib=('drop', 'record-label'))
mutation('615', 'reader-edit', ['edited record'], lib=('drop', 'record-no-edit'))
mutation('615', 'reader-revert', ['revert not pending'], lib=('drop', 'revert-pending'))
mutation('615', 'skill-closes-link', ['template fields and disclosure'],
         skill=lambda s: sub_once(s, 'The PR\ndescription links it beside `Closes #<work-item>`. ', ''))
mutation('615', 'skill-disclosure', ['template fields and disclosure'],
         skill=lambda s: sub_once(s, 'never invent a 3-0 or 2-1 vote', 'list votes as usual'))


# =========================================================================
# S616 completion is a new linked comment with the exact revert command
def completion_bundle(t, text=None, edited=False):
    body, m = filled_record(t, 'eligible')
    url = 'https://github.com/%s/issues/701#issuecomment-5000' % REPO
    if text is None:
        text = 'Completion of %s\nMerged head: %s at %s, squash %s.\n\ngit revert %s\n' % (url, H, iso(T0 + timedelta(seconds=400)), SQUASH, SQUASH)
    return {'record': {'url': url, 'body': body, 'created_at': iso(T0), 'updated_at': iso(T0 + timedelta(seconds=30 if edited else 0))},
            'completion': {'body': text}, 'merge': {'squash_sha': SQUASH, 'head': H}}


@row('616', 'before-completion')
def _(t):
    body, m = filled_record(t, 'eligible')
    need(m['revert'] == 'pending' and SQUASH not in body, 'the record carries a SHA before the merge')
    reader_ok(reader(t, body))


@row('616', 'completion-valid')
def _(t):
    o = t.cli('completion', completion_bundle(t))
    need(o.first == 'completion: ok', o.text)


@row('616', 'completion-guessed-sha')
def _(t):
    b = completion_bundle(t)
    b['completion']['body'] = b['completion']['body'].replace('git revert ' + SQUASH, 'git revert ' + 'ab' * 20)
    o = t.cli('completion', b)
    need(o.first == 'completion: invalid' and 'completion-revert' in o.codes, o.text)


@row('616', 'completion-short-sha')
def _(t):
    b = completion_bundle(t)
    b['completion']['body'] = b['completion']['body'].replace('git revert ' + SQUASH, 'git revert ' + SQUASH[:7])
    o = t.cli('completion', b)
    need(o.first == 'completion: invalid' and 'completion-revert' in o.codes, o.text)


@row('616', 'record-edited-in-place')
def _(t):
    o = t.cli('completion', completion_bundle(t, edited=True))
    need(o.first == 'completion: invalid' and 'record-edited' in o.codes, o.text)


@row('616', 'reversal-not-autonomous')
def _(t):
    flat = ' '.join(t.skill.split())
    for s in ('Completion is a new comment linking the record', 'the exact line `git revert <S>`',
              'Reversal is a normal maintainer-confirmed revert PR, never autonomous'):
        need(s in flat, 'skill lacks %r' % s)


mutation('616', 'allow-edit', ['record-edited-in-place'], lib=('drop', 'record-no-edit'))
mutation('616', 'allow-short-sha', ['completion-short-sha'],
         lib=('sub', 'revert-exact', 'reverts != [S]', 'not any(S.startswith(x) for x in reverts)'))
mutation('616', 'skill-autonomous-revert', ['reversal-not-autonomous'],
         skill=lambda s: sub_once(s, 'Reversal is a normal maintainer-confirmed revert PR, never autonomous.', 'Reversal is automatic.'))


# =========================================================================
# S617 the hold: 299 s waits, 300 s may proceed
def at(t, seconds, hold=None):
    b = base(t, cfg=config_text(t, edit=(lambda c: c.update(hold_seconds=hold)) if hold else None))
    b['now'] = iso(T0 + timedelta(seconds=seconds))
    return t.ev(b)


@row('617', 'base')
def _(t):
    expect(at(t, 400), 'eligible')


@row('617', 't-plus-0')
def _(t):
    expect(at(t, 0), 'held', has=['hold-window'], detail='earliest=%s' % iso(T0 + timedelta(seconds=300)))


@row('617', 't-plus-299')
def _(t):
    o = at(t, 299)
    expect(o, 'held', has=['hold-window'], detail='earliest=%s' % iso(T0 + timedelta(seconds=300)))
    need(any('earliest-merge=%s' % iso(T0 + timedelta(seconds=300)) in n for n in o.notes), 'earliest merge time not printed')


@row('617', 't-plus-300')
def _(t):
    expect(at(t, 300), 'eligible')


@row('617', 't-plus-301')
def _(t):
    expect(at(t, 301), 'eligible')


@row('617', 'hold-1-t0')
def _(t):
    expect(at(t, 0, hold=1), 'held', has=['hold-window'])


@row('617', 'hold-1-t1')
def _(t):
    expect(at(t, 1, hold=1), 'eligible')


@row('617', 'config-changed-after-T')
def _(t):
    b = base(t)
    b['config_text'] = config_text(t, edit=lambda c: c.update(hold_seconds=1))
    expect(t.ev(b), 'unresolved', has=['identity-config'])


@row('617', 'now-missing')
def _(t):
    b = base(t)
    b['now'] = None
    expect(t.ev(b), 'unresolved', has=['now-unreadable'], lacks=['verifier-crash'])


@row('617', 'collector-date-header-missing-or-bad')
def _(t):
    b = base(t)
    key = 'api --include repos/%s/branches/main' % REPO
    for out in ('HTTP/2.0 200 OK\r\nContent-Type: application/json\r\n\r\n{}', 'HTTP/2.0 200 OK\r\nDate: not a date\r\n\r\n{}'):
        o, _ = t.collector(world(b, overrides={key: {'out': out}}), ['700'])
        expect(o, 'unresolved', has=['now-unreadable'], lacks=['verifier-crash'])


@row('617', 'collector-date-header-decides')
def _(t):
    # the header says T+100; the local clock (any real date after 2026-01-01) would say eligible
    b = base(t)
    b['now'] = iso(T0 + timedelta(seconds=100))
    o, log = t.collector(world(b), ['700'])
    expect(o, 'held', has=['hold-window'])
    calls = [e.get('argv') for e in log if e.get('tool') == 'gh']
    need(calls and calls[-1] == ['api', '--include', 'repos/%s/branches/main' % REPO], 'the Date request is not the last gh call: %s' % calls[-1:])
    b['now'] = iso(T0 + timedelta(seconds=300))
    o, _ = t.collector(world(b), ['700'])
    expect(o, 'eligible')


mutation('617', 'now-unreadable', ['now-missing'], lib=('drop', 'now-unreadable'))
mutation('617', 'local-clock', ['collector-date-header-decides', 'collector-date-header-missing-or-bad'],
         lib=('sub', 'server-now', 'server_now(head)', 'fmt(datetime.now(timezone.utc))'))
mutation('617', 'strict-greater',['t-plus-300'], lib=('sub', 'hold-window', "< cfg['hold_seconds']", "<= cfg['hold_seconds']"))
mutation('617', 'fixed-300', ['hold-1-t1'], lib=('sub', 'hold-window', "< cfg['hold_seconds']", '< 300'))
mutation('617', 'T-from-PR', ['t-plus-0', 't-plus-299'], lib=('sub', 'record-time', "c.get('created_at')", "pr.get('created_at')"))


# =========================================================================
# S618 a hold or risk label stops every merge and voids the record
def timeline_case(t, events, labels=None):
    b = base(t)
    for where, ev in events:
        b['timeline'][where].append(ev)
    for where, names in (labels or {}).items():
        (b['pr'] if where == 'pr' else b[where])['labels'] = names
    return t.ev(b)


@row('618', 'h-no-label-anywhere')
def _(t):
    o = t.ev(base(t))
    expect(o, 'eligible')
    need(any('dormant' in n for n in o.notes) and not any('dormant' in r for r in o.reasons),
         'the dormant state must be a note, not a reason')


@row('618', 'a-hold-on-pr-after-T')
def _(t):
    o = timeline_case(t, [('pr', ev_label('pr', 'hold', T0 + timedelta(seconds=10)))], {'pr': ['hold']})
    expect(o, 'unresolved', has=['void-after-announcement', 'label-hold'])
    need(o.rc == 4, 'exit %s, expected 4' % o.rc)


@row('618', 'b-risk-on-issue-after-T')
def _(t):
    for label in ('risk:high', 'risk:low'):
        o = timeline_case(t, [('issue', ev_label('issue', label, T0 + timedelta(seconds=10)))], {'issue': [label]})
        expect(o, 'unresolved', has=['void-after-announcement', 'label-hold'], detail='issue %s' % label)
        need(o.rc == 4, 'exit %s, expected 4' % o.rc)


@row('618', 'c-off-on-control-after-T')
def _(t):
    o = timeline_case(t, [('control', ev_label('control', 'merge-autonomy:off', T0 + timedelta(seconds=10)))],
                      {'control': ['merge-autonomy:off']})
    expect(o, 'referred', has=['void-after-announcement', 'label-off-control'])
    need(o.rc == 3, 'exit %s, expected 3' % o.rc)


@row('618', 'd-added-then-removed')
def _(t):
    o = timeline_case(t, [('pr', ev_label('pr', 'hold', T0 + timedelta(seconds=10))),
                          ('pr', ev_label('pr', 'hold', T0 + timedelta(seconds=20), 'unlabeled'))])
    expect(o, 'unresolved', has=['void-after-announcement'], lacks=['label-hold'])
    need(o.rc == 4, 'exit %s, expected 4' % o.rc)


@row('618', 'e-same-second')
def _(t):
    o = timeline_case(t, [('pr', ev_label('pr', 'hold', T0 + timedelta(seconds=10))),
                          ('pr', ev_label('pr', 'hold', T0 + timedelta(seconds=10), 'unlabeled'))])
    expect(o, 'unresolved', has=['void-after-announcement'], lacks=['label-hold'])
    need(o.rc == 4, 'exit %s, expected 4' % o.rc)


@row('618', 'f-timeline-unreadable')
def _(t):
    b = base(t)
    b['timeline'] = None
    expect(t.ev(b), 'unresolved', has=['timeline-unreadable'])


PRE_HOLD = [('pr', ev_label('pr', 'hold', T0 - timedelta(seconds=100))),
            ('pr', ev_label('pr', 'hold', T0 - timedelta(seconds=50), 'unlabeled'))]


@row('618', 'g-before-T-needs-release')
def _(t):
    o = timeline_case(t, PRE_HOLD)
    expect(o, 'held', has=['hold-release-missing'])
    need(o.rc == 1, 'exit %s, expected 1' % o.rc)


@row('618', 'g-before-T-off-on-issue')
def _(t):
    o = timeline_case(t, [('issue', ev_label('issue', 'merge-autonomy:off', T0 - timedelta(seconds=100))),
                          ('issue', ev_label('issue', 'merge-autonomy:off', T0 - timedelta(seconds=50), 'unlabeled'))])
    expect(o, 'held', has=['hold-release-missing'])


@row('618', 'g2-released-after-the-hold')
def _(t):
    b = base(t)
    b['timeline']['pr'] += [ev for _, ev in PRE_HOLD]
    b['sources'][MAINT] = {'body': 'TiesL: release the hold on #700, merge it.', 'created_at': iso(T0 - timedelta(seconds=40))}
    b['issue_comments'] = []
    add_record(b, manifest(b, hold_release=GOOD))
    expect(t.ev(b), 'eligible')


@row('618', 'i-stop-exactly-at-T')
def _(t):
    for where, label in (('pr', 'hold'), ('issue', 'merge-autonomy:off')):
        o = timeline_case(t, [(where, ev_label(where, label, T0)), (where, ev_label(where, label, T0 + timedelta(seconds=1), 'unlabeled'))])
        expect(o, 'unresolved', has=['void-after-announcement'], detail='%s %s at %s' % (where, label, iso(T0)))


mutation('618', 'ignore-after-T', ['d-added-then-removed', 'e-same-second'], lib=('drop', 'void'))
mutation('618', 'honour-removal', ['d-added-then-removed'],
         lib=('sub', 'void', '_hit(ev, where)', "_hit(ev, where) and ev.get('label') in now_labels[where]"))
mutation('618', 'unreadable-as-empty', ['f-timeline-unreadable'], lib=('drop', 'timeline-readable'))
mutation('618', 'void-mapped-to-held', ['a-hold-on-pr-after-T', 'b-risk-on-issue-after-T', 'd-added-then-removed',
                                        'e-same-second', 'i-stop-exactly-at-T'], exact=True,
         lib=('sub', 'void-verdict', "r.add('unresolved', 'void-after-announcement'", "r.add('held', 'void-after-announcement'"))
mutation('618', 'void-strictly-after-T', ['i-stop-exactly-at-T'], lib=('sub', 'void', 'when >= T', 'when > T'))
mutation('618', 'release-only-after-earlier-record', ['g-before-T-needs-release', 'g-before-T-off-on-issue'],
         lib=('sub', 'release-any-time', 't < T]', 't < T and len(valid) > 1]'))

# =========================================================================
# S619 a new record after a hold needs the maintainer's own words
T2 = T0 + timedelta(seconds=100)
MAINT = 'https://github.com/%s/pull/700#issuecomment-7001' % REPO


def released(t, hold_release, now=T2 + timedelta(seconds=400), src=None):
    b = base(t)
    b['timeline']['pr'] += [ev_label('pr', 'hold', T0 + timedelta(seconds=10)),
                            ev_label('pr', 'hold', T0 + timedelta(seconds=50), 'unlabeled')]
    b['sources'][MAINT] = src or {'body': 'TiesL: release the hold on #700, merge it.', 'created_at': iso(T0 + timedelta(seconds=40))}
    if hold_release and hold_release.get('link') not in b['sources'] and hold_release.get('link') != MAINT:
        b['sources'][hold_release['link']] = {'body': 'TiesL: release the hold on #700, merge it.', 'created_at': iso(T0 + timedelta(seconds=40))}
    add_record(b, manifest(b, n=2, hold_release=hold_release), created=T2)
    b['now'] = iso(now)
    return t.ev(b)


GOOD = {'link': MAINT, 'words': 'release the hold on #700, merge it.'}


@row('619', 'base')
def _(t):
    expect(t.ev(base(t)), 'eligible')


@row('619', 'a-null')
def _(t):
    expect(released(t, None), 'held', has=['hold-release-missing'])


@row('619', 'b-verbatim-full-window')
def _(t):
    o = released(t, GOOD)
    expect(o, 'eligible')
    need(any('authorship' in n for n in o.notes), 'the authorship limitation note is missing')


@row('619', 'b-window-too-short')
def _(t):
    expect(released(t, GOOD, now=T2 + timedelta(seconds=299)), 'held', has=['hold-window'])


@row('619', 'c-other-pr')
def _(t):
    expect(released(t, {'link': 'https://github.com/%s/pull/699#issuecomment-7001' % REPO, 'words': GOOD['words']}),
           'held', has=['hold-release-target'])


@row('619', 'd-paraphrase')
def _(t):
    expect(released(t, {'link': MAINT, 'words': 'the maintainer says go ahead in general'}), 'held', has=['hold-release-words'])


@row('619', 'e-predates-hold')
def _(t):
    src = {'body': 'TiesL: release the hold on #700, merge it.', 'created_at': iso(T0 + timedelta(seconds=5))}
    expect(released(t, GOOD, src=src), 'held', has=['hold-release-stale'])


def pre_record(t, words_at, now=T0 + timedelta(seconds=400)):
    """A hold added and removed before the first and only record (no void record)."""
    b = base(t)
    b['timeline']['pr'] += [ev_label('pr', 'hold', T0 - timedelta(seconds=100)),
                            ev_label('pr', 'hold', T0 - timedelta(seconds=50), 'unlabeled')]
    b['sources'][MAINT] = {'body': 'TiesL: release the hold on #700, merge it.', 'created_at': iso(words_at)}
    b['issue_comments'] = []
    add_record(b, manifest(b, hold_release=GOOD))
    b['now'] = iso(now)
    return t.ev(b)


@row('619', 'f-pre-record-hold-released')
def _(t):
    expect(pre_record(t, T0 - timedelta(seconds=40)), 'eligible')
    expect(pre_record(t, T0 - timedelta(seconds=40), now=T0 + timedelta(seconds=299)), 'held', has=['hold-window'])


@row('619', 'g-words-at-the-hold')
def _(t):
    expect(pre_record(t, T0 - timedelta(seconds=100)), 'held', has=['hold-release-stale'])


@row('619', 'h-words-before-the-hold')
def _(t):
    expect(pre_record(t, T0 - timedelta(seconds=200)), 'held', has=['hold-release-stale'])


def control_off(t, at, config_at=T0 - timedelta(days=10)):
    b = base(t)
    b['timeline']['control'] += [ev_label('control', 'merge-autonomy:off', at),
                                 ev_label('control', 'merge-autonomy:off', at + timedelta(seconds=30), 'unlabeled')]
    b['config_commit_date'] = iso(config_at) if config_at else None
    return t.ev(b)


@row('619', 'i-off-after-config-commit')
def _(t):
    expect(control_off(t, T0 - timedelta(days=1)), 'referred', has=['off-since-config'])


@row('619', 'j-off-before-config-commit')
def _(t):
    expect(control_off(t, T0 - timedelta(days=20)), 'eligible', lacks=['off-since-config'])


@row('619', 'config-date-unreadable')
def _(t):
    expect(control_off(t, T0 - timedelta(days=20), config_at=None), 'unresolved', has=['config-date-unreadable'], lacks=['verifier-crash'])


mutation('619', 'stale-boundary', ['g-words-at-the-hold'], lib=('sub', 'release-stale', '<= max(holds)', '< max(holds)'))
mutation('619', 'off-since-config', ['i-off-after-config-commit'], lib=('drop', 'off-since-config'))
mutation('619', 'off-before-config', ['j-off-before-config-commit'], lib=('sub', 'off-since-config', 't > cd', 't != cd'))
mutation('619', 'config-date', ['config-date-unreadable'], lib=('drop', 'config-date'))
mutation('619', 'accept-null',['a-null'], lib=('drop', 'release-required'))
mutation('619', 'shorten-window', ['b-window-too-short'], lib=('sub', 'hold-window', '(now - T).total_seconds()', '(now - T).total_seconds() + 100'))
mutation('619', 'any-target', ['c-other-pr'], lib=('drop', 'release-target'))
mutation('619', 'stale-words', ['e-predates-hold'], lib=('drop', 'release-stale'))


# =========================================================================
# S620 the maintainer's own approval overrides; relays count only verbatim
STATEMENTS_620 = {
    'a-human-path': 'An explicit maintainer approval of an in-class PR is a human-path merge, recorded as such; the panel record is linked but not required.',
    'bcd-verbatim-only': 'Relays and wakes count only his verbatim words about that exact PR and decision; a paraphrase, a general go-ahead or an approval of another PR neither releases a hold nor authorizes a merge.',
    'e-outside-class': 'A 5-0 vote outside the class does not merge.',
    'fg-release': 'A work item into a release branch keeps the release workflow\'s own path and a release branch into `main` keeps the maintainer\'s confirmation; both are referred here.',
    'h-own-pr': '#646\'s own PR touches reserved paths and cannot merge under its delegation.',
    'step4-lapse': 'today\'s rule applies with every lapse rule of WORKFLOW.md step 4.',
}
for _name, _text in STATEMENTS_620.items():
    def _mk(text=_text):
        def fn(t):
            need(text in ' '.join(t.skill.split()), 'skill lacks %r' % text)
        return fn
    row('620', 'text ' + _name)(_mk())
    mutation('620', 'delete ' + _name, ['text ' + _name],
             skill=lambda s, text=_text: ' '.join(s.split()).replace(text, ''))


@row('620', 'e-five-zero-outside-class')
def _(t):
    files = [fl('docs/page-%d.md' % i) for i in range(9)]
    b = base(t, files=files)
    refresh(b)
    expect(t.ev(b), 'referred', has=['cap-files'])


@row('620', 'f-into-release-branch')
def _(t):
    b = class_base(t)
    b['pr']['base'] = 'release/607-panel-mechanisms'
    expect(t.ev(b), 'referred', has=['base-not-main'])


@row('620', 'g-release-into-main')
def _(t):
    b = class_base(t)
    b['pr']['head_ref'] = 'release/607-panel-mechanisms'
    expect(t.ev(b), 'referred', has=['release-head'])


@row('620', 'h-own-pr')
def _(t):
    files = [fl('skills/merge-risk-panel/SKILL.md'), fl('lib/merge-risk.py'), fl('policy/merge-autonomy.json'), fl('README.md')]
    expect(t.ev(class_base(t, files=files)), 'referred', has=['reserved-path'])


mutation('620', 'release-head-rule', ['g-release-into-main'], lib=('drop', 'release-head'))


# =========================================================================
# S621 one executor, one literal merge command, recheck of main
LITERAL = '`gh pr merge <n> --repo TiesL/spec-driven-guardrails --squash --delete-branch --match-head-commit <H>`'


def steps(skill):
    sec = skill.split('## Executor sequence', 1)[1].split('\n## ', 1)[0]
    found = re.findall(r'^(\d)\. (.*(?:\n   .*)*)', sec, re.M)
    return [(int(n), ' '.join(body.split())) for n, body in found], ' '.join(sec.split())


@row('621', 'sequence-order-and-literal')
def _(t):
    got, flat = steps(t.skill)
    need([n for n, _ in got] == [1, 2, 3, 4, 5, 6], 'steps are %s' % [n for n, _ in got])
    want = {1: '`merge-risk-evidence.sh --phase final <n>`', 2: 'state=executing host=<host>',
            3: '`merge-preflight.sh <n>` fresh: exit 0 without warnings', 4: LITERAL,
            5: '`gh pr view <n> --json state,mergeCommit,headRefOid`', 6: '`git fetch origin`, then step 1'}
    for n, body in got:
        need(want[n] in body, 'step %d lacks %r' % (n, want[n]))
    need('It must not be wrapped in a script' in got[3][1], 'step 4 does not forbid wrapping the command in a script')
    need('One PR at a time' in flat, 'one PR at a time is not stated')
    need('state=failed' in got[4][1] and 'state=merged' in got[4][1], 'step 5 lacks the queue outcomes')


@row('621', 'host-equal')
def _(t):
    expect(t.ev(base(t)), 'eligible')


@row('621', 'host-other')
def _(t):
    b = base(t)
    b['host'] = 'second-machine'
    expect(t.ev(b), 'unresolved', has=['executor-host-mismatch'])


@row('621', 'host-empty')
def _(t):
    b = base(t, cfg=config_text(t, host=''))
    refresh(b)
    expect(t.ev(b), 'unresolved', has=['executor-host-empty'])


@row('621', 'host-collector')
def _(t):
    b = base(t)
    o, log = t.collector(world(b), ['700'])
    expect(o, 'eligible')
    need(any(e.get('tool') == 'hostname' and e.get('argv') == ['-s'] for e in log), 'hostname -s was not asked')
    need(not writes(log), 'the verifier made a write call: %s' % writes(log))
    b['host'] = 'second-machine'
    o, _ = t.collector(world(b), ['700'])
    expect(o, 'unresolved', has=['executor-host-mismatch'])


@row('621', 'second-item-old-base')
def _(t):
    b = base(t)
    b['main_tip'] = B2  # the first merge moved main; the second item is not updated
    expect(t.ev(b), 'unresolved', has=['identity-base', 'behind-base'])


mutation('621', 'drop-match-head-commit', ['sequence-order-and-literal'],
         skill=lambda s: sub_once(s, ' --match-head-commit <H>`.', '`.'))
mutation('621', 'skip-refetch', ['sequence-order-and-literal'],
         skill=lambda s: re.sub(r'\n6\. Before the next item:.*?\n(?=\n)', '\n', s, flags=re.S))
mutation('621', 'skip-host-check', ['host-other', 'host-collector'], lib=('drop', 'host'))
mutation('621', 'skip-empty-host', ['host-empty'], lib=('drop', 'host-empty'))


# =========================================================================
# S622 crash or duplicate wake neither drops nor double-merges
def qline(state, pr=700, head=H, ident='MR-700-1a2b3c4-1', host='exec-host'):
    return 'merge-risk-queue: id=%s pr=%d head=%s state=%s host=%s' % (ident, pr, head, state, host)


def queue(t, lines, states):
    comments = [{'body': x, 'created_at': iso(T0 + timedelta(seconds=i))} for i, x in enumerate(lines)]
    return t.cli('queue', {'control_issue': 607, 'queue_comments': comments, 'pr_states': states})


def entries(o):
    return [x for x in o.text.splitlines() if x.startswith('entry: ')]


@row('622', 'a-merged-reconciled')
def _(t):
    o = queue(t, [qline('executing')], {'700': {'state': 'MERGED', 'head': H}})
    need(o.rc == 0 and len(entries(o)) == 1 and entries(o)[0].endswith('action=record-completion'), o.text)


@row('622', 'b-still-open-refer')
def _(t):
    o = queue(t, [qline('executing')], {'700': {'state': 'OPEN', 'head': H}})
    need(o.rc == 0 and entries(o) and entries(o)[0].endswith('action=refer'), o.text)


@row('622', 'c-unreadable-stop')
def _(t):
    o = queue(t, [qline('executing')], {})
    need(o.rc == 4 and entries(o) and entries(o)[0].endswith('action=stop-refer'), o.text)


@row('622', 'd-duplicate-wake-once')
def _(t):
    o = queue(t, [qline('executing'), qline('executing')], {'700': {'state': 'OPEN', 'head': H}})
    need(len(entries(o)) == 1, 'a key is listed %d times' % len(entries(o)))


@row('622', 'e-stray-after-merged')
def _(t):
    o = queue(t, [qline('executing'), qline('merged'), qline('executing')], {'700': {'state': 'MERGED', 'head': H}})
    need(not entries(o) and 'queue-key-repeated' in o.codes, o.text)


@row('622', 'f-pending-never-started')
def _(t):
    o = queue(t, [qline('merged', pr=699, head=H2, ident='MR-699-5e6f7a8-1')], {})
    need(o.rc == 0 and not entries(o) and not o.codes, o.text)
    expect(t.ev(base(t)), 'eligible')  # its own record still answers eligible: step 1 runs it once


@row('622', 'collector-queue')
def _(t):
    b = base(t)
    w = world(b, overrides={
        'api --paginate repos/%s/issues/607/comments?per_page=100 --jq .[]' % REPO: {
            'out': json.dumps({'body': qline('executing'), 'created_at': iso(T0)}) + '\n'},
        'pr view 700 --repo %s --json state,headRefOid' % REPO: {'out': json.dumps({'state': 'MERGED', 'headRefOid': H})}})
    o, log = t.collector(w, ['--queue'])
    need(o.rc == 0 and entries(o) and entries(o)[0].endswith('action=record-completion'), o.text)
    need(not writes(log), 'write calls: %s' % writes(log))


mutation('622', 'no-reconcile-first', ['a-merged-reconciled'], lib=('drop', 'reconcile-first'))
mutation('622', 'repeat-key', ['e-stray-after-merged'], lib=('drop', 'queue-key-once'))


# =========================================================================
# S623 revocation stops everything and does not revive
def two_items(t, edit=None):
    out = []
    for pr, issue, head in ((700, 701, H), (702, 703, H2)):
        b = base(t)
        b['pr_number'] = pr
        b['pr'].update(head=head, closing_issues=[issue], comments=['<!-- pre-merge-review:done sha=%s -->' % head])
        b['issue']['number'] = issue
        for role in ('Reviewer', 'orchestrator'):
            set_report(b, role, report(role, head=head))
        b['issue_comments'] = []
        m = manifest(b)
        m.update(pr=pr, issue=issue, decision_id='MR-%d-%s-1' % (pr, head[:7]),
                 queue_key='%s#%d@%s' % (REPO, pr, head))
        add_record(b, m)
        if edit:
            edit(b, pr)
        out.append(t.ev(b))
    return out


@row('623', 'base-both-eligible')
def _(t):
    for o in two_items(t):
        expect(o, 'eligible')


@row('623', 'a-off-on-control')
def _(t):
    for o in two_items(t, lambda b, pr: b['control'].update(labels=['merge-autonomy:off'])):
        expect(o, 'referred', has=['label-off-control'])


@row('623', 'b-enabled-false')
def _(t):
    for o in two_items(t, lambda b, pr: b.update(config_text=config_text(t, enabled=False))):
        expect(o, among=('referred', 'unresolved'), has=['autonomy-disabled'])


@row('623', 'c-control-closed')
def _(t):
    for o in two_items(t, lambda b, pr: b['control'].update(state='CLOSED')):
        expect(o, 'referred', has=['control-closed'])


@row('623', 'd-config-digest')
def _(t):
    for o in two_items(t, lambda b, pr: b.update(config_text=b['config_text'] + ' ')):
        expect(o, 'unresolved', has=['identity-config'])


@row('623', 'e-off-one-pr')
def _(t):
    a, c = two_items(t, lambda b, pr: b['pr'].update(labels=['merge-autonomy:off']) if pr == 700 else None)
    expect(a, 'referred', has=['label-off'])
    expect(c, 'eligible')


@row('623', 'f-off-one-issue')
def _(t):
    a, c = two_items(t, lambda b, pr: b['issue'].update(labels=['merge-autonomy:off']) if pr == 700 else None)
    expect(a, 'referred', has=['label-off'])
    expect(c, 'eligible')


@row('623', 're-enable-label-removed')
def _(t):
    def edit(b, pr):
        b['timeline']['control'] += [ev_label('control', 'merge-autonomy:off', T0 + timedelta(seconds=20)),
                                      ev_label('control', 'merge-autonomy:off', T0 + timedelta(seconds=90), 'unlabeled')]
    for o in two_items(t, edit):
        # label removal does not re-enable (A58 addendum 3 F3): void, and referred off-since-config
        expect(o, 'referred', has=['void-after-announcement', 'off-since-config'])


@row('623', 're-enable-same-bytes-new-tip')
def _(t):
    def edit(b, pr):
        b['main_tip'] = b['merge_base'] = B2  # the re-enabling config PR is a new main commit
    for o in two_items(t, edit):
        expect(o, 'unresolved', has=['identity-base'])


@row('623', 'incident-text')
def _(t):
    flat = ' '.join(t.skill.split())
    for s in ('An incident (an incorrect autonomous merge, an ignored hold, suspected forgery) disables autonomy: add the off label to the control issue, record the incident there, refer.',
              'Only the maintainer re-enables', 'old records do not revive'):
        need(s in flat, 'skill lacks %r' % s)


mutation('623', 'global-off-label', ['a-off-on-control'], lib=('drop', 'label-off-control'))
mutation('623', 'global-enabled', ['b-enabled-false'], lib=('drop', 'disabled'))
mutation('623', 'global-closed', ['c-control-closed'], lib=('drop', 'control-closed'))
mutation('623', 'global-config-digest', ['d-config-digest'], lib=('drop', 'identity-config'))
mutation('623', 'incident-statement', ['incident-text'],
         skill=lambda s: ' '.join(s.split()).replace('disables autonomy: add the off label to the control issue, record the incident there, refer.', ''))


# =========================================================================
# S625 live narrow start: shipped disabled, no shadow phase
@row('625', 'shipped-config')
def _(t):
    cfg = json.loads(t.config)
    want = {'enabled': False, 'acceptance': None, 'executor_host': '', 'max_lines': 300, 'max_files': 8,
            'hold_seconds': 300, 'control_issue': 607, 'schema': 1, 'repository': REPO}
    for key, value in want.items():
        need(key in cfg and cfg[key] == value and type(cfg[key]) is type(value), '%s is %r, expected %r' % (key, cfg.get(key), value))


@row('625', 'skill-statements')
def _(t):
    flat = ' '.join(t.skill.split())
    for s in ('no shadow phase, no 40-case sample and no first-ten maintainer review',
              "Enabling happens only by a change that links the maintainer's recorded acceptance of #646",
              '22 of 80 (27.5%)', 'cited from A55 on `feature/646-merge-risk-panel` 9621de6, not re-run',
              'fully evidenced eligibility is unknown',
              'candidates, each veto reason, eligible 5-0, holds, referrals and dissent, merges, failures, reverts, incidents, time to merge and actual token usage (`n/a` when unavailable)',
              'Widening only through a reserved, maintainer-approved config PR', 'a success streak never changes defaults',
              'Token cost is not a gate'):
        need(s in flat, 'skill lacks %r' % s)
    need(not re.search(r'cash|pays? (for )?itself|payback(?! claim)', flat, re.I), 'the skill makes a payback claim')


mutation('625', 'flip-enabled', ['shipped-config'], config=lambda s: sub_once(s, '"enabled": false', '"enabled": true'))
mutation('625', 'delete-shadow-statement', ['skill-statements'],
         skill=lambda s: ' '.join(s.split()).replace('no shadow phase, ', ''))


# =========================================================================
# S626 the skill lives in its own file and survives compaction
CAP = 16000
ORDER = ['Applicability', 'Hard gates', 'Class and disqualifiers', 'Position line', 'Manifest and decision record',
         'Hold', 'Executor sequence', 'Revocation and recovery', 'Human-path interaction', 'Statistics', 'Residual risks']
ALLOWED_NAMES = {'merge-preflight.sh', 'merge-risk-evidence.sh', 'policy/merge-autonomy.json', 'ARCHITECTURE.md',
                 'CHANGES.md', 'WORKFLOW.md', 'check'}  # commands and files the procedure names, not a path list


def within_cap(data):
    return len(data) <= CAP


@row('626', 'size-cap')
def _(t):
    data = t.skill.encode('utf-8')
    need(within_cap(b'x' * CAP) and not within_cap(b'x' * (CAP + 1)), 'the threshold function is wrong')
    need(within_cap(data), 'skill is %d bytes, cap %d' % (len(data), CAP))


@row('626', 'frontmatter')
def _(t):
    m = re.match(r'---\nname: (.+)\ndescription: (.+)\n---\n', t.skill)
    need(m and m.group(1) == 'merge-risk-panel', 'frontmatter name')
    d = m.group(2) if m else ''
    for s in ('`policy/merge-autonomy.json`', '`"enabled": true`', 'an `acceptance` link', "this repository's name", 'inert'):
        need(s in d, 'description lacks %r' % s)
    need('every adopted project included, it is inert' in d, 'description does not say it is inert in adopted projects')


@row('626', 'heading-order')
def _(t):
    got = re.findall(r'^## (.+)$', t.skill, re.M)
    need(got == ORDER, 'headings are %s' % got)


@row('626', 'no-second-list')
def _(t):
    cfg = json.loads(t.config)
    pats = cfg['groups']['ordinary'] + cfg['groups']['adoption'] + cfg['groups']['guard'] + \
        cfg['groups']['generated']['outputs'] + cfg['groups']['generated']['inputs'] + \
        cfg['reserved']['release'] + cfg['reserved']['autonomy'] + cfg['release_heads'] + \
        [x for x in cfg['labels']['hold'] if '*' in x]
    for p in pats:
        if '*' in p or p in cfg['reserved']['release']:
            need(p not in t.skill, 'the skill restates %r' % p)
        elif re.search(r'(?<![\w./-])%s(?![\w/-])' % re.escape(p), t.skill):
            need(p in ALLOWED_NAMES, 'the skill names config path %r' % p)
    need(not re.search(r'\b(300|%d)\b' % cfg['max_lines'], t.skill), 'the skill restates a cap or hold value')
    need(not re.search(r'\b%d (changed )?files\b' % cfg['max_files'], t.skill), 'the skill restates the file cap')


@row('626', 'role-contracts-unchanged')
def _(t):
    p = subprocess.run(['git', '-C', str(ROOT), 'show', '2cfba6a:skills/role-contracts/SKILL.md'], capture_output=True)
    need(p.returncode == 0, 'base 2cfba6a is not readable')
    need(t.role_contracts == p.stdout, 'skills/role-contracts/SKILL.md differs from the release base 2cfba6a')
    need(b'merge-risk-panel' not in t.role_contracts, 'role-contracts points at the skill')


@row('626', 'installer')
def _(t):
    project = t.dir / ('project-%d' % t.n)
    t.n += 1
    project.mkdir()
    env = dict(os.environ, HOME=str(t.dir / 'home'), SPEC_DRIVEN_GUARDRAILS_DIR=str(ROOT))
    (t.dir / 'home').mkdir(exist_ok=True)
    subprocess.run(['git', 'init', '-q', '-b', 'main', str(project)], capture_output=True)
    p = subprocess.run([str(ROOT / 'adopt.sh'), str(project)], env=env, capture_output=True)
    link = project / '.claude/skills/merge-risk-panel'
    need(p.returncode == 0 and link.is_symlink() and Path(os.readlink(link)).resolve() == (ROOT / 'skills/merge-risk-panel').resolve(),
         'adopt.sh did not link the skill: %s' % p.stderr.decode()[-300:])
    p = subprocess.run([str(ROOT / 'adopt.sh'), '--runtime', 'codex', str(project)], env=env, capture_output=True)
    gi = (project / '.gitignore').read_text() if (project / '.gitignore').exists() else ''
    need('/.agents/skills/merge-risk-panel' in gi, 'codex installer .gitignore block lacks the skill: %s' % p.stderr.decode()[-300:])
    own = (ROOT / '.gitignore').read_text()
    block = own.split('# spec-driven-guardrails: begin', 1)[-1].split('# spec-driven-guardrails: end', 1)[0]
    need('/.agents/skills/merge-risk-panel\n' in block, "this repository's own managed .gitignore block lacks the skill")


@row('626', 'inert-statement')
def _(t):
    flat = ' '.join(t.skill.split())
    need('in an adopted project, or with the shipped file' in flat and 'it is inert' in flat, 'inert statement missing')


mutation('626', 'over-cap', ['size-cap'], skill=lambda s: s + 'x' * (CAP + 1 - len(s.encode('utf-8'))))
mutation('626', 'copy-reserved-list', ['no-second-list'],
         skill=lambda s: s + '\nReserved: ' + ', '.join(json.loads((ROOT / 'policy/merge-autonomy.json').read_text())['reserved']['autonomy']) + '\n')
mutation('626', 'edit-role-contracts', ['role-contracts-unchanged'], role_contracts=lambda b: b + b'\nSee merge-risk-panel.\n')
mutation('626', 'heading-moved', ['heading-order'], skill=lambda s: sub_once(s, '## Hold\n', '## Holding\n'))


if __name__ == '__main__':
    sys.exit(main())
