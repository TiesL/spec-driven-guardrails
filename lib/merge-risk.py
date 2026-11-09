#!/usr/bin/env python3
"""lib/merge-risk.py: private evaluator and collector behind merge-risk-evidence.sh.

#646, A58 D4. Read-only: it never merges, labels, comments or votes. Two
Adapters over one pure evaluation:

  evaluate --bundle <file>    judge a collected JSON bundle (tests, replays)
  collect --phase P <pr>      collect the bundle through gh, then judge it
  queue --bundle <file>       judge a queue bundle (control-issue lines)
  collect-queue               collect the queue bundle through gh, then judge
  record --bundle <file>      read one decision record (any outcome)
  completion --bundle <file>  read one completion comment against its record

Stdout first line: `merge-risk: <verdict> pr=<n> head=<H> base=<B>
diff=<sha256> config=<C>`, then one `reason: <code> <detail>` per reason and
`note:` lines. Exit 0 eligible, 1 held, 3 referred, 4 unresolved, 2 usage.
Precedence: referred, then unresolved, then held. Every `# rule:` tag below
names one veto, hold, expiry, void or revocation rule; the mutation suite
(test/fixtures/merge-risk-646.py) removes each one and shows a case fails.
The verifier proves equal bytes and recorded fields, never authorship.
"""
import hashlib
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from functools import lru_cache
from pathlib import Path

LIB = Path(__file__).resolve().parent
EXIT = {'eligible': 0, 'held': 1, 'referred': 3, 'unresolved': 4}
VOTERS = ('Product', 'Architect', 'QA', 'Reviewer', 'orchestrator')
STAGE = {'Product': 'Discovery', 'Architect': 'Planning', 'QA': 'Test', 'Reviewer': 'Review'}
POSITIONS = ('yes-if', 'yes', 'no', 'abstain')
CONFIG_KEYS = ('schema', 'repository', 'enabled', 'acceptance', 'control_issue', 'executor_host',
               'max_lines', 'max_files', 'hold_seconds', 'groups', 'reserved', 'labels', 'release_heads')
MANIFEST_KEYS = ('decision_id', 'repository', 'issue', 'pr', 'head', 'base', 'diff_sha256',
                 'config_sha256', 'config_commit', 'ac', 'design', 'class', 'reasons', 'authors',
                 'rows', 'gates', 'reviewer_assertions', 'hold_release', 'outcome', 'earliest_merge',
                 'labels', 'executor_host', 'queue_key', 'revert')
OUTCOMES = ('eligible', 'held', 'vetoed', 'unresolved', 'referred', 'failed', 'merged')
ROW_KEYS = ('role', 'source_url', 'source_sha256', 'position', 'model', 'variant', 'score', 'entry', 'date')
AUTHOR_KEYS = ('model', 'variant', 'score', 'entry', 'date')
ASSERTION_KEYS = ('semantic_disqualifiers', 'lineage', 'open_medium_high')
MANIFEST_MARK = '<!-- merge-risk-manifest v1 -->'
RECORD_LABEL = 'temporary, panel decision'
SHA40 = re.compile(r'[0-9a-f]{40}')
SHA256 = re.compile(r'[0-9a-f]{64}')
POSITION_RE = re.compile(r'merge-risk-position: role=(\S+) position=(\S+) ac=(\S+) design=(\S+) head=(\S+)[ \t]*')
QUEUE_RE = re.compile(r'merge-risk-queue: id=(\S+) pr=([0-9]+) head=([0-9a-f]{40}) state=([a-z]+) host=(\S*)[ \t]*')
MARKER_RE = re.compile(r'<!-- pre-merge-review:done sha=([0-9a-fA-F]{40}) -->')
COMMENT_URL = re.compile(r'https://github\.com/([^/\s]+/[^/\s]+)/(issues|pull)/([0-9]+)#issuecomment-([0-9]+)')
ESCAPE_HATCHES = ('CLAUDE_WORKFLOW_MERGE_GUARD_OFF', 'CLAUDE_WORKFLOW_GUARDRAILS_OFF')


class Usage(Exception):
    pass


class Result:
    def __init__(self):
        self.reasons = []
        self.notes = []

    def add(self, kind, code, detail=''):
        self.reasons.append((kind, code, str(detail)))  # rule:all-reasons

    def note(self, text):
        self.notes.append(text)

    def codes(self):
        return [c for _, c, _ in self.reasons]

    def verdict(self):
        kinds = [k for k, _, _ in self.reasons]
        for kind in ('referred', 'unresolved', 'held'):  # rule:precedence
            if kind in kinds:
                return kind
        return 'eligible'


def sha(text):
    if isinstance(text, str):
        text = text.encode('utf-8', 'surrogateescape')
    return hashlib.sha256(text).hexdigest()


def ts(value):
    if not isinstance(value, str):
        return None
    try:
        return datetime.strptime(value, '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc)
    except ValueError:
        return None


def fmt(when):
    return when.strftime('%Y-%m-%dT%H:%M:%SZ')


def is_int(value):
    return isinstance(value, int) and not isinstance(value, bool)


def is_num(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool)


# --- pattern grammar (A58 D3): full path, case-sensitive; `*` within one
# segment, `**` any depth; no basename or substring match.
@lru_cache(maxsize=None)
def _pat(pattern):
    out, i = '', 0
    while i < len(pattern):
        if pattern.startswith('**', i):
            out, i = out + '.*', i + 2
        elif pattern[i] == '*':
            out, i = out + '[^/]*', i + 1
        else:
            out, i = out + re.escape(pattern[i]), i + 1
    return re.compile(out)


def path_match(path, patterns):
    return any(_pat(p).fullmatch(path) for p in patterns)


def label_match(name, patterns):
    return any(re.fullmatch('.*'.join(re.escape(x) for x in p.split('*')), name) for p in patterns)


# --- shared readers: lib/markdown.sh live_text and lib/model-record.sh rec_scan
@lru_cache(maxsize=None)
def live(text):
    p = subprocess.run(['bash', '-c', '. "$1" || exit 3; live_text "$2"', 'md',
                        str(LIB / 'markdown.sh'), text], capture_output=True)
    if p.returncode != 0:
        return None
    return p.stdout.decode('utf-8', 'surrogateescape')


@lru_cache(maxsize=None)
def marker_rows(text):
    p = subprocess.run(['bash', '-c', '. "$1" || exit 3; rec_scan model-record "$2"', 'rec',
                        str(LIB / 'model-record.sh'), text], capture_output=True)
    if p.returncode != 0:
        return None
    return [line.split('\t') for line in p.stdout.decode('utf-8', 'surrogateescape').splitlines() if line]


def _no_dupes(pairs):
    seen = {}
    for key, value in pairs:
        if key in seen:
            raise ValueError('duplicate key ' + key)
        seen[key] = value
    return seen


def strict_json(text):
    return json.loads(text, object_pairs_hook=_no_dupes)


# --- configuration (A58 D3): closed schema 1, read only from the main tip B
def _str_list(value):
    return isinstance(value, list) and all(isinstance(x, str) and x for x in value)


def config_errors(cfg):
    errs = []
    if not isinstance(cfg, dict):
        return ['top-level']
    for key in CONFIG_KEYS:
        if key not in cfg:
            errs.append('missing:' + key)
    for key in cfg:
        if key not in CONFIG_KEYS:
            errs.append('unknown:' + key)
    if errs:
        return errs
    if not is_int(cfg['schema']) or cfg['schema'] != 1:
        errs.append('schema')
    if not isinstance(cfg['repository'], str) or not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', cfg['repository']):
        errs.append('repository')
    if not isinstance(cfg['enabled'], bool):
        errs.append('enabled')
    acc = cfg['acceptance']
    if acc is not None and (not isinstance(acc, str) or not isinstance(cfg['repository'], str) or not re.fullmatch(
            r'https://github\.com/' + re.escape(cfg['repository']) + r'/issues/646#issuecomment-[0-9]+', acc)):
        errs.append('acceptance')
    if cfg['enabled'] is True and acc is None:  # rule:enabled-needs-acceptance
        errs.append('enabled-without-acceptance')
    if not is_int(cfg['control_issue']) or cfg['control_issue'] < 1:
        errs.append('control_issue')
    if not isinstance(cfg['executor_host'], str):
        errs.append('executor_host')
    for key in ('max_lines', 'max_files', 'hold_seconds'):
        if not is_int(cfg[key]) or cfg[key] < 1:  # rule:config-positive
            errs.append(key)
    groups = cfg['groups']
    if not isinstance(groups, dict) or sorted(groups) != ['adoption', 'generated', 'guard', 'ordinary']:
        errs.append('groups')
    else:
        for key in ('ordinary', 'adoption', 'guard'):
            if not _str_list(groups[key]):
                errs.append('groups.' + key)
        gen = groups['generated']
        if not isinstance(gen, dict) or sorted(gen) != ['inputs', 'outputs'] or not all(_str_list(gen[k]) for k in gen):
            errs.append('groups.generated')
    res = cfg['reserved']
    if not isinstance(res, dict) or sorted(res) != ['autonomy', 'release'] or not all(_str_list(res[k]) for k in res):
        errs.append('reserved')
    labels = cfg['labels']
    if not isinstance(labels, dict) or sorted(labels) != ['hold', 'off'] or not _str_list(labels['hold']) \
            or not isinstance(labels['off'], str) or not labels['off']:
        errs.append('labels')
    if not _str_list(cfg['release_heads']):
        errs.append('release_heads')
    return errs


def load_config(b, r):
    text = b.get('config_text')
    if not isinstance(text, str):
        r.add('unresolved', 'config-absent', 'policy/merge-autonomy.json at the main tip')
        return None
    try:
        cfg = strict_json(text)
    except ValueError as exc:
        r.add('unresolved', 'config-malformed', str(exc).splitlines()[0][:80])
        return None
    errs = config_errors(cfg)  # rule:config-closed
    for err in errs:
        r.add('unresolved', 'config-invalid', err)
    if errs:
        return None
    if cfg['repository'] != b.get('repository'):
        r.add('unresolved', 'config-repository', '%s != %s' % (cfg['repository'], b.get('repository')))
        return None
    if not cfg['enabled']:  # rule:disabled
        r.add('referred', 'autonomy-disabled', 'enabled is false at the main tip')
    elif b.get('acceptance_exists') is not True:
        r.add('unresolved', 'acceptance-unverified', cfg['acceptance'])
    return cfg


def allowed_patterns(cfg):
    g = cfg['groups']
    return g['ordinary'] + g['adoption'] + g['guard'] + g['generated']['outputs'] + g['generated']['inputs']


def group_names(cfg, path):
    g = cfg['groups']
    named = {'ordinary': g['ordinary'], 'adoption': g['adoption'], 'guard': g['guard'],
             'generated': g['generated']['outputs'] + g['generated']['inputs']}
    return [k for k, pats in named.items() if path_match(path, pats)]


# --- hard gates (A58 D4): never votes, always first
def gate_checks(b, r):
    pf = b.get('preflight')
    if not isinstance(pf, dict):
        r.add('unresolved', 'gate-preflight', 'unreadable')
    else:
        if pf.get('escape_hatch'):  # rule:escape-hatch
            r.add('unresolved', 'gate-escape-hatch', 'set in the verifier environment; removed for merge-preflight.sh')
        if pf.get('exit') != 0:
            r.add('unresolved', 'gate-preflight', 'exit=%s' % pf.get('exit'))
        if any(line.startswith('warning:') for line in str(pf.get('stderr') or '').splitlines()):  # rule:warning-line
            r.add('unresolved', 'gate-preflight-warning', 'merge-preflight.sh printed a warning: line')
    runs = b.get('checks')
    if not isinstance(runs, list):
        r.add('unresolved', 'gate-check', 'unreadable')
        return
    named = [x for x in runs if isinstance(x, dict) and x.get('name') == 'check']
    if not named:
        r.add('unresolved', 'gate-check', 'missing')
        return
    run = max(named, key=lambda x: x.get('id') if is_int(x.get('id')) else -1)
    if run.get('status') != 'completed':  # rule:pending
        r.add('unresolved', 'gates-pending', 'check status=%s' % run.get('status'))
    elif run.get('conclusion') == 'skipped':
        r.add('unresolved', 'gate-check', 'skipped')
    elif run.get('conclusion') != 'success':
        r.add('unresolved', 'gate-check', 'conclusion=%s' % run.get('conclusion'))


# --- class and disqualifiers (A58 D3/D4)
def meaning_version_touched(diff_text):
    current = None
    for line in diff_text.splitlines():
        m = re.match(r'diff --git a/(\S+) b/(\S+)', line)
        if m:
            current = (m.group(1), m.group(2))
            continue
        if current and 'CHANGES.md' in current and line[:1] in '+-' \
                and not line.startswith(('+++', '---')) and '**Meaning version:**' in line:
            return True
    return False


def class_checks(b, cfg, r, ctx):
    pr = b.get('pr') if isinstance(b.get('pr'), dict) else {}
    gate_checks(b, r)
    if pr.get('state') != 'OPEN':
        r.add('unresolved', 'pr-not-open', 'state=%s' % pr.get('state'))
    if pr.get('base') != 'main':  # rule:base-main
        r.add('referred', 'base-not-main', 'base=%s' % pr.get('base'))
    if path_match(str(pr.get('head_ref')), cfg['release_heads']):  # rule:release-head
        r.add('referred', 'release-head', 'head branch %s' % pr.get('head_ref'))
    closing = pr.get('closing_issues')
    if not isinstance(closing, list):
        r.add('unresolved', 'closing-issues', 'unreadable')
    elif len(closing) != 1:  # rule:closing-one
        r.add('referred', 'closing-issues', 'count=%d' % len(closing))
    if b.get('merge_base') != b.get('main_tip') or not b.get('main_tip'):  # rule:behind-base
        r.add('unresolved', 'behind-base', 'merge-base %s, main tip %s' % (b.get('merge_base'), b.get('main_tip')))
    files = b.get('files')
    if not isinstance(files, list):
        r.add('unresolved', 'files-unreadable', 'B...H compare')
    else:
        paths, lines = set(), 0
        for f in files:
            paths.add(f.get('path'))
            if f.get('previous_path'):
                paths.add(f['previous_path'])  # rule:rename-both
            if f.get('binary') or not is_int(f.get('additions')) or not is_int(f.get('deletions')):
                r.add('unresolved', 'binary-file', f.get('path'))
            else:
                lines += f['additions'] + f['deletions']
        reserved = cfg['reserved']['release'] + cfg['reserved']['autonomy']
        touched = set()
        for p in sorted(x for x in paths if isinstance(x, str)):
            if path_match(p, reserved):  # rule:reserved
                r.add('referred', 'reserved-path', p)
            elif not path_match(p, allowed_patterns(cfg)):  # rule:unlisted
                r.add('referred', 'unlisted-path', p)
            touched.update(group_names(cfg, p))
        ctx['paths'] = sorted(x for x in paths if isinstance(x, str))
        ctx['class'] = sorted(touched)
        if not 1 <= len(paths) <= cfg['max_files']:  # rule:cap-files
            r.add('referred', 'cap-files', 'files=%d max=%d' % (len(paths), cfg['max_files']))
        if not 1 <= lines <= cfg['max_lines']:  # rule:cap-lines
            r.add('referred', 'cap-lines', 'lines=%d max=%d' % (lines, cfg['max_lines']))
    diff_text = b.get('diff_text')
    if not isinstance(diff_text, str):
        r.add('unresolved', 'diff-unreadable', 'B...H unified diff')
    elif meaning_version_touched(diff_text):  # rule:meaning-version
        r.add('referred', 'meaning-version-line', 'CHANGES.md **Meaning version:** line changed')
    reviews = pr.get('reviews')
    if not isinstance(reviews, list):
        r.add('unresolved', 'reviews-unreadable', '')
    elif any(isinstance(x, dict) and x.get('state') == 'CHANGES_REQUESTED' for x in reviews):  # rule:changes-requested
        r.add('referred', 'changes-requested', 'a review was ever in state CHANGES_REQUESTED')
    off = cfg['labels']['off']
    hold = cfg['labels']['hold']
    issue = b.get('issue')
    items = [('pr', pr.get('labels'))]
    if isinstance(closing, list) and len(closing) == 1:
        if not isinstance(issue, dict):
            r.add('unresolved', 'issue-unreadable', closing[0])
        else:
            items.append(('issue', issue.get('labels')))
    for where, labels in items:
        if not isinstance(labels, list):
            r.add('unresolved', 'labels-unreadable', where)
            continue
        if off in labels:  # rule:label-off-item
            r.add('referred', 'label-off', where)
        for name in labels:
            if label_match(name, hold):  # rule:label-hold
                r.add('held', 'label-hold', '%s %s' % (where, name))
    control = b.get('control')
    if not isinstance(control, dict) or not isinstance(control.get('labels'), list):
        r.add('unresolved', 'control-unreadable', 'issue #%s' % cfg['control_issue'])
    else:
        if control.get('state') != 'OPEN':  # rule:control-closed
            r.add('referred', 'control-closed', 'issue #%s' % cfg['control_issue'])
        if off in control['labels']:  # rule:label-off-control
            r.add('referred', 'label-off-control', 'issue #%s' % cfg['control_issue'])
    if not any(label_match(n, hold) for _, labels in items if isinstance(labels, list) for n in labels):
        r.note('no hold or risk label is a dormant state, never evidence of safety')


# --- final phase: record, rows, hold, void, executor (A58 D4-D7)
def parse_manifest(body):
    lines = body.replace('\r\n', '\n').split('\n')
    marks = [i for i, line in enumerate(lines) if line.strip() == MANIFEST_MARK]
    if not marks:
        return None, None
    if len(marks) != 1:
        return None, 'two manifest markers'
    i = marks[0] + 1
    if i >= len(lines) or not lines[i].strip().startswith('```'):
        return None, 'no fenced block after the marker'
    out = []
    for line in lines[i + 1:]:
        if line.strip().startswith('```'):
            try:
                return strict_json('\n'.join(out)), None
            except ValueError as exc:
                return None, str(exc).splitlines()[0][:80]
        out.append(line)
    return None, 'unclosed fenced block'


def manifest_errors(m):
    if not isinstance(m, dict):
        return ['top-level']
    errs = ['missing:' + k for k in MANIFEST_KEYS if k not in m]
    errs += ['unknown:' + k for k in m if k not in MANIFEST_KEYS]
    if errs:
        return errs
    for key in ('ac', 'design'):
        v = m[key]
        if not isinstance(v, dict) or sorted(v) != ['sha256', 'source'] or not isinstance(v['source'], str):
            errs.append(key)
    if not isinstance(m['rows'], list) or not all(isinstance(x, dict) and sorted(x) == sorted(ROW_KEYS) for x in m['rows']):
        errs.append('rows')
    if not isinstance(m['authors'], list) or not all(isinstance(x, dict) and sorted(x) == sorted(AUTHOR_KEYS) for x in m['authors']):
        errs.append('authors')
    if not isinstance(m['gates'], dict) or sorted(m['gates']) != ['check_run_id', 'preflight']:
        errs.append('gates')
    if not isinstance(m['reviewer_assertions'], dict) or sorted(m['reviewer_assertions']) != sorted(ASSERTION_KEYS):
        errs.append('reviewer_assertions')
    hr = m['hold_release']
    if hr is not None and (not isinstance(hr, dict) or sorted(hr) != ['link', 'words']
                           or not all(isinstance(hr[k], str) and hr[k] for k in hr)):
        errs.append('hold_release')
    if m['outcome'] not in OUTCOMES:
        errs.append('outcome')
    if not isinstance(m['revert'], str):
        errs.append('revert')
    return errs


def records_for(b, n):
    out = []
    for c in b.get('issue_comments') or []:
        if not isinstance(c, dict) or not isinstance(c.get('body'), str):
            continue
        m, err = parse_manifest(c['body'])
        if m is None and err is None:
            continue
        if isinstance(m, dict) and m.get('pr') != n:
            continue
        out.append((c, m, err))
    return out


def floor_ok(entry):
    return all(isinstance(entry.get(k), str) and entry.get(k) for k in ('model', 'variant', 'entry', 'date')) \
        and is_num(entry.get('score'))


def position_lines(body):
    text = live(body)
    if text is None:
        return None
    return [line.strip() for line in text.split('\n') if line.strip().startswith('merge-risk-position:')]


def condition_paths(body):
    text = live(body) or ''
    lines = text.split('\n')
    for i, line in enumerate(lines):
        if line.strip().startswith('merge-risk-position:'):
            for follow in lines[i + 1:]:
                if follow.strip().startswith('paths:'):
                    return follow.strip()[len('paths:'):].split()
                if follow.strip().startswith('merge-risk-position:'):
                    break
    return None


def check_row(b, m, row, H, ctx, r):
    role = row['role']
    src = (b.get('sources') or {}).get(row['source_url'])
    body = src.get('body') if isinstance(src, dict) else None
    if not isinstance(body, str):
        r.add('unresolved', 'source-unreadable', role)
        return
    if sha(body) != row['source_sha256']:  # rule:source-hash
        r.add('unresolved', 'source-hash', role)
    found = position_lines(body)
    if found is None:
        r.add('unresolved', 'source-unreadable', role)
        return
    if len(found) != 1:  # rule:position-line
        r.add('unresolved', 'position-missing' if not found else 'position-duplicate', role)
        return
    pm = POSITION_RE.fullmatch(found[0])
    if not pm:
        r.add('unresolved', 'position-malformed', role)
        return
    p_role, p_pos, p_ac, p_design, p_head = pm.groups()
    if p_role != role:  # rule:position-role
        r.add('unresolved', 'position-role', '%s wrote role=%s' % (role, p_role))
    if p_pos != row['position']:
        r.add('unresolved', 'position-mismatch', role)
    if p_ac != m['ac']['sha256']:  # rule:ad-equal
        r.add('unresolved', 'position-digest', '%s ac' % role)
    if not (role == 'Product' and p_design == 'pending') and p_design != m['design']['sha256']:  # rule:ad-design
        r.add('unresolved', 'position-digest', '%s design' % role)
    if role in ('Reviewer', 'orchestrator'):
        if p_head != H:  # rule:position-head-final
            r.add('unresolved', 'position-head', '%s head=%s' % (role, p_head))
    elif p_head not in ('any', H):  # rule:position-head-cond
        r.add('unresolved', 'position-head', '%s head=%s' % (role, p_head))
    first = body.replace('\r\n', '\n').split('\n')[0]
    if role in STAGE:
        rows = marker_rows(first)
        if rows is None or len(rows) != 1 or rows[0][1] != 'ok' or rows[0][2] != STAGE[role]:  # rule:marker-stage
            r.add('unresolved', 'marker-stage', '%s first line is not a %s model-record marker' % (role, STAGE[role]))
    else:
        rows = marker_rows(body)
        if rows is None or rows:  # rule:orchestrator-marker-free
            r.add('unresolved', 'marker-present', 'orchestrator comment must be marker-free (OR44)')
    if row['position'] == 'yes-if':
        scope = condition_paths(body)
        if not scope:  # rule:condition-missing
            r.add('unresolved', 'condition-missing', role)
        else:
            for p in ctx.get('paths', []):
                if not path_match(p, scope):  # rule:condition-scope
                    r.add('unresolved', 'condition-scope', '%s %s' % (role, p))


def label_events(b, where):
    tl = b.get('timeline')
    return [e for e in tl.get(where) or [] if isinstance(e, dict)] if isinstance(tl, dict) else []


def final_checks(b, cfg, r, ctx, n, H, B, D, C):
    pr = b.get('pr') if isinstance(b.get('pr'), dict) else {}
    comments = pr.get('comments')
    if not isinstance(comments, list):
        r.add('unresolved', 'gate-review-marker', 'unreadable')
    else:
        shas = [x.lower() for c in comments if isinstance(c, str) for x in MARKER_RE.findall(live(c) or '')]
        if str(H).lower() not in shas:  # rule:marker-pin
            r.add('unresolved', 'gate-review-marker', 'stale' if shas else 'missing')
    if not isinstance(b.get('issue_comments'), list):
        r.add('unresolved', 'records-unreadable', 'work-item issue comments')
        return
    found = records_for(b, n)
    for c, m, err in found:
        if err:
            r.add('unresolved', 'manifest-malformed', '%s %s' % (c.get('url'), err))
    valid = []
    for c, m, err in found:
        if m is None:
            continue
        errs = manifest_errors(m)  # rule:manifest-closed
        for e in errs:
            r.add('unresolved', 'manifest-schema', '%s %s' % (c.get('url'), e))
        if not errs:
            valid.append((c, m))
    eligible = [(c, m) for c, m in valid if m['outcome'] == 'eligible']  # rule:eligible-only
    mine = sorted(((c, m) for c, m in eligible if m['head'] == H), key=lambda x: str(x[0].get('created_at')))
    if not mine:  # rule:identity-head
        r.add('unresolved', 'identity-head' if eligible else 'record-missing',
              'no eligible record for head %s' % H)
        return
    hold_pats = cfg['labels']['hold']
    off = cfg['labels']['off']

    def stops(where, ev):
        name = ev.get('label')
        if not isinstance(name, str) or ev.get('event') != 'labeled':
            return False
        return name == off or (where != 'control' and label_match(name, hold_pats))

    def _hit(ev, where):
        return stops(where, ev)
    events = [(where, ev) for where in ('pr', 'issue', 'control') for ev in label_events(b, where)]
    stop_times = [ts(ev.get('created_at')) for where, ev in events if _hit(ev, where) and ts(ev.get('created_at'))]
    # A58 addendum E4: exactly one non-superseded eligible record for H. An earlier
    # one is superseded only when a hold or off stop event at or after its T, and
    # before the newer record's T, voided it; any other second one is a duplicate.
    latest_t = ts(mine[-1][0].get('created_at'))
    superseded = all(ts(cc.get('created_at')) and latest_t and any(ts(cc.get('created_at')) <= t < latest_t for t in stop_times)
                     for cc, mm in mine[:-1])
    if len(mine) > 1 and not superseded:  # rule:single-record
        r.add('unresolved', 'record-duplicate', '%d eligible records for head %s' % (len(mine), H))
        return
    c, m = mine[-1]
    T = ts(c.get('created_at'))  # rule:record-time
    if T is None:
        r.add('unresolved', 'record-time', 'created_at unreadable')
        return
    if c.get('updated_at') != c.get('created_at'):  # rule:no-edit
        r.add('unresolved', 'record-edited', c.get('url'))
    if RECORD_LABEL not in (live(c['body']) or ''):
        r.add('unresolved', 'record-label', 'literal "%s" missing' % RECORD_LABEL)
    if not re.fullmatch(r'MR-%s-%s-[0-9]+' % (n, re.escape(str(H)[:7])), str(m['decision_id'])):
        r.add('unresolved', 'record-id', str(m['decision_id']))
    for key, want in (('repository', b.get('repository')), ('issue', ctx.get('issue'))):
        if m[key] != want:
            r.add('unresolved', 'manifest-binding', key)
    if m['base'] != B:  # rule:identity-base
        r.add('unresolved', 'identity-base', 'record %s, now %s' % (m['base'], B))
    if m['config_commit'] != B:
        r.add('unresolved', 'identity-config-commit', 'record %s, now %s' % (m['config_commit'], B))
    if m['diff_sha256'] != D:  # rule:identity-diff
        r.add('unresolved', 'identity-diff', 'record %s, now %s' % (m['diff_sha256'], D))
    if m['config_sha256'] != C:  # rule:identity-config
        r.add('unresolved', 'identity-config', 'record %s, now %s' % (m['config_sha256'], C))
    texts = b.get('texts') or {}
    for key in ('ac', 'design'):
        text = texts.get(m[key]['source'])
        if not isinstance(text, str):
            r.add('unresolved', key + '-unreadable', m[key]['source'])
        elif sha(text) != m[key]['sha256']:  # rule:ad-source
            r.add('unresolved', key + '-digest', m[key]['source'])
    rows = m['rows']
    roles = [x['role'] for x in rows]
    strangers = sorted({x for x in roles if x not in VOTERS})
    dupes = sorted({x for x in roles if x in VOTERS and roles.count(x) > 1})
    for x in strangers:  # rule:non-voter
        r.add('unresolved', 'row-not-voter', x)
    for x in dupes:  # rule:distinct-roles
        r.add('unresolved', 'row-duplicate', x)
    if not strangers and not dupes:
        for x in VOTERS:
            if x not in roles:  # rule:vote-missing
                r.add('referred', 'vote-missing', x)
    seen = set()
    for row in rows:
        if row['role'] not in VOTERS or row['role'] in seen:
            continue
        seen.add(row['role'])
        if row['position'] not in POSITIONS:
            r.add('unresolved', 'position-malformed', row['role'])
        elif row['position'] not in ('yes', 'yes-if'):  # rule:unanimity
            r.add('referred', 'vote-dissent', 'role=%s position=%s' % (row['role'], row['position']))
        check_row(b, m, row, H, ctx, r)
    authors = m['authors']
    if not authors or not all(floor_ok(a) for a in authors) or not all(floor_ok(x) for x in rows):  # rule:floor-complete
        r.add('unresolved', 'floor-evidence', 'model, variant, numeric score, entry and date for every author and voter')
    else:
        top = max(a['score'] for a in authors)
        for row in rows:
            if row['role'] in VOTERS and row['score'] < top:  # rule:floor
                r.add('referred', 'floor-below', '%s score %s, highest author %s' % (row['role'], row['score'], top))
    ra = m['reviewer_assertions']
    for key in ASSERTION_KEYS:
        v = ra.get(key)
        if not isinstance(v, str) or not v.strip():
            r.add('unresolved', 'assertion-missing', key)
        elif key != 'lineage' and v.strip() != 'none':  # rule:assertion
            r.add('referred', 'assertion', '%s: %s' % (key, v.strip()[:80]))
    tl = b.get('timeline')
    if not isinstance(tl, dict):  # rule:timeline-readable
        r.add('unresolved', 'timeline-unreadable', 'label history of PR, issue or control issue')
    now_labels = {'pr': pr.get('labels') or [], 'issue': (b.get('issue') or {}).get('labels') or [],
                  'control': (b.get('control') or {}).get('labels') or []}
    for where, ev in events:
        when = ts(ev.get('created_at'))
        if when is None:
            r.add('unresolved', 'timeline-unreadable', 'event time')
        elif when >= T and _hit(ev, where):  # rule:void
            r.add('unresolved', 'void-after-announcement', '%s %s at %s' % (where, ev.get('label'), ev.get('created_at')))  # rule:void-verdict
    earlier = [ts(cc.get('created_at')) for cc, mm in valid if ts(cc.get('created_at')) and ts(cc.get('created_at')) < T]
    T_first = min(earlier) if earlier else T
    holds = [t for t in stop_times if T_first <= t < T]
    if earlier and holds:
        hr = m['hold_release']
        if hr is None:  # rule:release-required
            r.add('held', 'hold-release-missing', 'a hold followed an earlier record; the maintainer\'s verbatim words are required')
        else:
            um = COMMENT_URL.fullmatch(hr['link'])
            if not um or um.group(1) != b.get('repository') or int(um.group(3)) not in (n, ctx.get('issue')):  # rule:release-target
                r.add('held', 'hold-release-target', hr['link'])
            else:
                src = (b.get('sources') or {}).get(hr['link'])
                body = src.get('body') if isinstance(src, dict) else None
                if not isinstance(body, str) or hr['words'] not in body:
                    r.add('held', 'hold-release-words', 'the quoted words are not in the linked comment')
                elif ts(src.get('created_at')) is None or ts(src.get('created_at')) <= max(holds):  # rule:release-stale
                    r.add('held', 'hold-release-stale', 'the linked words predate the hold')
        r.note('hold-release authorship cannot be verified on a shared login; procedure')
    earliest = T + timedelta(seconds=cfg['hold_seconds'])
    now = ts(b.get('now'))
    if now is None:
        r.add('unresolved', 'now-unreadable', '')
    elif (now - T).total_seconds() < cfg['hold_seconds']:  # rule:hold-window
        r.add('held', 'hold-window', 'earliest=%s' % fmt(earliest))
    r.note('earliest-merge=%s' % fmt(earliest))
    if cfg['executor_host'] == '':  # rule:host-empty
        r.add('unresolved', 'executor-host-empty', 'no executor configured')
    elif cfg['executor_host'] != b.get('host'):  # rule:host
        r.add('unresolved', 'executor-host-mismatch', 'this host is %s' % b.get('host'))
    r.note('the record and rows are equal bytes and recorded fields, not proof of who wrote them')


def evaluate(b):
    r = Result()
    pr = b.get('pr') if isinstance(b.get('pr'), dict) else {}
    n, H, B = b.get('pr_number'), pr.get('head'), b.get('main_tip')
    D = sha(b['diff_text']) if isinstance(b.get('diff_text'), str) else None
    C = sha(b['config_text']) if isinstance(b.get('config_text'), str) else None
    ctx = {}
    closing = pr.get('closing_issues')
    if isinstance(closing, list) and len(closing) == 1:
        ctx['issue'] = closing[0]
    cfg = load_config(b, r)
    if cfg is not None:
        class_checks(b, cfg, r, ctx)
        if b.get('phase', 'final') == 'final':
            final_checks(b, cfg, r, ctx, n, H, B, D, C)
        r.note('class=%s' % ','.join(ctx.get('class', [])))
    verdict = r.verdict()
    first = 'merge-risk: %s pr=%s head=%s base=%s diff=%s config=%s' % (
        verdict, n if n is not None else '-', H or '-', B or '-', D or '-', C or '-')
    return verdict, first, r


def render(verdict, first, r):
    out = [first]
    out += ['reason: %s %s' % (code, detail) if detail else 'reason: %s' % code for _, code, detail in r.reasons]
    out += ['note: %s' % x for x in r.notes]
    return '\n'.join(out) + '\n', EXIT[verdict]


# --- queue (A58 D7): append-only lines on the control issue
TERMINAL = ('merged', 'failed')


def evaluate_queue(b):
    r = Result()
    comments = b.get('queue_comments')
    if not isinstance(comments, list):
        r.add('unresolved', 'queue-unreadable', 'control issue comments')
        return render_queue([], r, b)
    keys, order = {}, []
    for c in sorted((x for x in comments if isinstance(x, dict)), key=lambda x: str(x.get('created_at'))):
        for line in (live(str(c.get('body') or '')) or '').split('\n'):
            qm = QUEUE_RE.fullmatch(line.strip())
            if not qm:
                continue
            ident, prn, head, state, host = qm.groups()
            key = (int(prn), head, ident)
            if key not in keys:
                keys[key] = []
                order.append(key)
            if any(s in TERMINAL for s in keys[key]) and state == 'executing':  # rule:queue-key-once
                r.add('referred', 'queue-key-repeated', 'id=%s pr=%s head=%s already executed' % (ident, prn, head))
                continue
            keys[key].append(state)
    states = b.get('pr_states') if isinstance(b.get('pr_states'), dict) else {}
    entries = []
    for key in order:
        if not keys[key] or keys[key][-1] in TERMINAL:
            continue
        prn, head, ident = key
        st = states.get(str(prn))
        if not isinstance(st, dict):
            action = 'stop-refer'
            r.add('unresolved', 'queue-outcome-unknown', 'id=%s pr=%s' % (ident, prn))
        elif st.get('state') == 'MERGED' and st.get('head') == head:  # rule:reconcile-first
            action = 'record-completion'
        else:
            action = 'refer'
        entries.append('entry: id=%s pr=%s head=%s state=%s action=%s' % (ident, prn, head, keys[key][-1], action))
    return render_queue(entries, r, b)


def render_queue(entries, r, b):
    v = r.verdict()
    code = 4 if v == 'unresolved' else 0
    out = ['merge-risk-queue: %s open=%d control=%s' % ('unresolved' if code else 'read', len(entries), b.get('control_issue', '-'))]
    out += entries
    out += ['reason: %s %s' % (c, d) for _, c, d in r.reasons]
    return '\n'.join(out) + '\n', code


# --- record and completion readers (A58 D5; S615/S616)
def read_record(b):
    r = Result()
    body = b.get('body')
    if not isinstance(body, str):
        r.add('unresolved', 'record-unreadable', '')
        return r
    if RECORD_LABEL not in (live(body) or ''):  # rule:record-label
        r.add('unresolved', 'record-label', RECORD_LABEL)
    m, err = parse_manifest(body)
    if m is None:
        r.add('unresolved', 'manifest-malformed', err or 'no manifest')
        return r
    for e in manifest_errors(m):  # rule:record-fields
        r.add('unresolved', 'manifest-schema', e)
    if isinstance(m, dict):
        if not re.fullmatch(r'MR-%s-%s-[0-9]+' % (m.get('pr'), re.escape(str(m.get('head'))[:7])), str(m.get('decision_id'))):
            r.add('unresolved', 'record-id', str(m.get('decision_id')))
        if m.get('revert') != 'pending':  # rule:revert-pending
            r.add('unresolved', 'revert-not-pending', str(m.get('revert')))
    if b.get('updated_at') != b.get('created_at'):  # rule:record-no-edit
        r.add('unresolved', 'record-edited', '')
    return r


def read_completion(b):
    rec = b.get('record') if isinstance(b.get('record'), dict) else {}
    r = read_record(rec)
    body = (b.get('completion') or {}).get('body')
    merge = b.get('merge') or {}
    S, H = merge.get('squash_sha'), merge.get('head')
    if not isinstance(body, str):
        r.add('unresolved', 'completion-unreadable', '')
        return r
    text = live(body) or ''
    if not rec.get('url') or rec['url'] not in body:
        r.add('unresolved', 'completion-unlinked', 'the record URL is not in the completion comment')
    if not isinstance(H, str) or not SHA40.fullmatch(H) or H not in text:
        r.add('unresolved', 'completion-head', 'merged head missing')
    reverts = re.findall(r'^git revert (\S+)$', md_plain(body), re.M)
    if not isinstance(S, str) or not SHA40.fullmatch(S) or reverts != [S]:  # rule:revert-exact
        r.add('unresolved', 'completion-revert', 'expected exactly the line "git revert <40-hex squash SHA>"')
    return r


def md_plain(body):
    return body.replace('\r\n', '\n')


def render_reader(kind, r):
    v = 'ok' if not r.reasons else 'invalid'
    out = ['%s: %s' % (kind, v)] + ['reason: %s %s' % (c, d) for _, c, d in r.reasons]
    return '\n'.join(out) + '\n', 0 if v == 'ok' else 4


# --- live collector: gh only, read calls only
def gh(args, raw=False):
    p = subprocess.run(['gh'] + args, capture_output=True)
    if p.returncode != 0:
        return None, p.stderr.decode('utf-8', 'replace')
    return (p.stdout if raw else p.stdout.decode('utf-8', 'surrogateescape')), ''


def gh_json(args):
    out, _ = gh(args)
    if out is None:
        return None
    try:
        return json.loads(out)
    except ValueError:
        return None


def gh_lines(args):
    out, _ = gh(args)
    if out is None:
        return None
    try:
        return [json.loads(line) for line in out.splitlines() if line.strip()]
    except ValueError:
        return None


def comment_id(url):
    um = COMMENT_URL.fullmatch(str(url))
    return um.group(4) if um else None


def a_entry(text, ident):
    lines = text.splitlines(keepends=True)
    start = next((i for i, x in enumerate(lines) if x.startswith('### %s ' % ident)), None)
    if start is None:
        return None
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith(('### ', '## '))), len(lines))
    return ''.join(lines[start:end])


def body_at(repo, number, when):
    owner, name = repo.split('/', 1)
    q = 'query($o:String!,$n:String!,$i:Int!){repository(owner:$o,name:$n){issue(number:$i){body userContentEdits(first:100){nodes{editedAt diff}}}}}'
    data = gh_json(['api', 'graphql', '-f', 'query=' + q, '-F', 'o=' + owner, '-F', 'n=' + name, '-F', 'i=%d' % number])
    try:
        issue = data['data']['repository']['issue']
        edits = [(ts(x['editedAt']), x['diff']) for x in issue['userContentEdits']['nodes']]
    except (TypeError, KeyError):
        return None
    if not edits:
        return issue['body']
    before = [(t, d) for t, d in edits if t and t <= when and isinstance(d, str)]
    return max(before)[1] if before else None


def collect(phase, n, script_dir):
    b = {'phase': phase, 'pr_number': n, 'now': fmt(datetime.now(timezone.utc))}  # rule:read-only
    repo, _ = gh(['repo', 'view', '--json', 'nameWithOwner', '--jq', '.nameWithOwner'])
    repo = (repo or '').strip()
    b['repository'] = repo
    tip, _ = gh(['api', 'repos/%s/branches/main' % repo, '--jq', '.commit.sha'])
    B = (tip or '').strip() or None
    b['main_tip'] = B
    view = gh_json(['pr', 'view', str(n), '--repo', repo, '--json',
                    'state,baseRefName,headRefName,headRefOid,closingIssuesReferences,labels,reviews,comments'])
    pr = {}
    if isinstance(view, dict):
        pr = {'state': view.get('state'), 'base': view.get('baseRefName'), 'head_ref': view.get('headRefName'),
              'head': view.get('headRefOid'),
              'closing_issues': [x.get('number') for x in view.get('closingIssuesReferences') or []],
              'labels': [x.get('name') for x in view.get('labels') or []],
              'reviews': [{'state': x.get('state')} for x in view.get('reviews') or []],
              'comments': [x.get('body') for x in view.get('comments') or []]}
    b['pr'] = pr
    H = pr.get('head')
    cfg = None
    if B:
        raw, _ = gh(['api', '-H', 'Accept: application/vnd.github.raw', 'repos/%s/contents/policy/merge-autonomy.json?ref=%s' % (repo, B)], raw=True)  # rule:config-at-B
        if raw is not None:
            try:
                b['config_text'] = raw.decode('utf-8')
                cfg = json.loads(b['config_text'])
            except ValueError:
                pass
    if B and H:
        cmp_ = gh_json(['api', 'repos/%s/compare/%s...%s' % (repo, B, H)])  # rule:full-range
        if isinstance(cmp_, dict):
            b['merge_base'] = (cmp_.get('merge_base_commit') or {}).get('sha')
            files = []
            for f in cmp_.get('files') or []:
                binary = 'patch' not in f and not (f.get('status') == 'renamed' and f.get('changes') == 0)
                files.append({'path': f.get('filename'), 'previous_path': f.get('previous_filename'),
                              'additions': f.get('additions'), 'deletions': f.get('deletions'), 'binary': binary})
            b['files'] = files
        diff, _ = gh(['api', '-H', 'Accept: application/vnd.github.diff', 'repos/%s/compare/%s...%s' % (repo, B, H)], raw=True)
        if diff is not None:
            b['diff_text'] = diff.decode('utf-8', 'surrogateescape')
        runs = gh_json(['api', 'repos/%s/commits/%s/check-runs?per_page=100' % (repo, H)])
        if isinstance(runs, dict) and isinstance(runs.get('check_runs'), list):
            b['checks'] = [{'name': x.get('name'), 'status': x.get('status'), 'conclusion': x.get('conclusion'),
                            'id': x.get('id')} for x in runs['check_runs']]
    issue_n = pr['closing_issues'][0] if len(pr.get('closing_issues') or []) == 1 else None

    def issue(number):
        d = gh_json(['api', 'repos/%s/issues/%s' % (repo, number)])
        if isinstance(d, dict):
            return {'number': number, 'state': str(d.get('state', '')).upper(), 'labels': [x.get('name') for x in d.get('labels') or []]}
        return None
    if issue_n:
        b['issue'] = issue(issue_n)
    control_n = cfg.get('control_issue') if isinstance(cfg, dict) else None
    if is_int(control_n):
        b['control'] = issue(control_n)
    if isinstance(cfg, dict) and comment_id(cfg.get('acceptance')):
        b['acceptance_exists'] = gh_json(['api', 'repos/%s/issues/comments/%s' % (repo, comment_id(cfg['acceptance']))]) is not None
    env = {k: v for k, v in os.environ.items() if k not in ESCAPE_HATCHES}  # rule:scrub-escape-hatch
    p = subprocess.run([str(Path(script_dir) / 'merge-preflight.sh'), str(n)], capture_output=True, env=env)
    b['preflight'] = {'exit': p.returncode, 'stderr': p.stderr.decode('utf-8', 'replace'),
                      'escape_hatch': any(os.environ.get(k) for k in ESCAPE_HATCHES)}
    if phase == 'final':
        host = subprocess.run(['hostname', '-s'], capture_output=True)
        b['host'] = host.stdout.decode().strip() if host.returncode == 0 else None
        tl = {}
        for where, number in (('pr', n), ('issue', issue_n), ('control', control_n)):
            if number is None:
                continue
            ev = gh_lines(['api', '--paginate', 'repos/%s/issues/%s/timeline?per_page=100' % (repo, number), '--jq', '.[]'])
            if ev is None:
                tl = None
                break
            tl[where] = [{'event': e.get('event'), 'label': (e.get('label') or {}).get('name'), 'created_at': e.get('created_at')}
                         for e in ev if e.get('event') in ('labeled', 'unlabeled')]
        b['timeline'] = tl
        if issue_n:
            cs = gh_lines(['api', '--paginate', 'repos/%s/issues/%s/comments?per_page=100' % (repo, issue_n), '--jq', '.[]'])
            if cs is not None:
                b['issue_comments'] = [{'url': c.get('html_url'), 'body': c.get('body'), 'created_at': c.get('created_at'),
                                        'updated_at': c.get('updated_at')} for c in cs]
        sources, texts = {}, {}
        for c, m, err in records_for(b, n):
            if not isinstance(m, dict) or m.get('head') != H:
                continue
            urls = [x.get('source_url') for x in m.get('rows') or [] if isinstance(x, dict)]
            if isinstance(m.get('hold_release'), dict):
                urls.append(m['hold_release'].get('link'))
            for url in urls:
                cid = comment_id(url)
                d = gh_json(['api', 'repos/%s/issues/comments/%s' % (repo, cid)]) if cid else None
                if isinstance(d, dict):
                    sources[url] = {'body': d.get('body'), 'created_at': d.get('created_at')}
            ac = (m.get('ac') or {}).get('source') if isinstance(m.get('ac'), dict) else None
            cid = comment_id(ac)
            d = gh_json(['api', 'repos/%s/issues/comments/%s' % (repo, cid)]) if cid else None
            if isinstance(d, dict) and ts(d.get('created_at')) and issue_n:
                text = body_at(repo, issue_n, ts(d['created_at']))
                if isinstance(text, str):
                    texts[ac] = text
            ds = (m.get('design') or {}).get('source') if isinstance(m.get('design'), dict) else None
            dm = re.fullmatch(r'ARCHITECTURE\.md@([0-9a-f]{40})#(A[0-9]+[a-z]?)', str(ds))
            if dm:
                raw, _ = gh(['api', '-H', 'Accept: application/vnd.github.raw', 'repos/%s/contents/ARCHITECTURE.md?ref=%s' % (repo, dm.group(1))], raw=True)
                entry = a_entry(raw.decode('utf-8', 'surrogateescape'), dm.group(2)) if raw is not None else None
                if entry is not None:
                    texts[ds] = entry
        b['sources'], b['texts'] = sources, texts
    return b


def collect_queue():
    repo, _ = gh(['repo', 'view', '--json', 'nameWithOwner', '--jq', '.nameWithOwner'])
    repo = (repo or '').strip()
    tip, _ = gh(['api', 'repos/%s/branches/main' % repo, '--jq', '.commit.sha'])
    raw, _ = gh(['api', '-H', 'Accept: application/vnd.github.raw',
                 'repos/%s/contents/policy/merge-autonomy.json?ref=%s' % (repo, (tip or '').strip())])
    try:
        control = strict_json(raw)['control_issue']
    except (TypeError, ValueError, KeyError):
        return {'queue_comments': None}
    b = {'control_issue': control}
    cs = gh_lines(['api', '--paginate', 'repos/%s/issues/%s/comments?per_page=100' % (repo, control), '--jq', '.[]'])
    b['queue_comments'] = None if cs is None else [{'body': c.get('body'), 'created_at': c.get('created_at')} for c in cs]
    states = {}
    for c in cs or []:
        for line in str(c.get('body') or '').split('\n'):
            qm = QUEUE_RE.fullmatch(line.strip())
            if qm and qm.group(2) not in states:
                d = gh_json(['pr', 'view', qm.group(2), '--repo', repo, '--json', 'state,headRefOid'])
                if isinstance(d, dict):
                    states[qm.group(2)] = {'state': d.get('state'), 'head': d.get('headRefOid')}
    b['pr_states'] = states
    return b


def load_bundle(path):
    with open(path, encoding='utf-8') as fh:
        return json.load(fh)


def main(argv):
    if not argv:
        raise Usage()
    cmd, rest = argv[0], argv[1:]
    if cmd in ('evaluate', 'queue', 'record', 'completion'):
        if len(rest) != 2 or rest[0] != '--bundle':
            raise Usage()
        b = load_bundle(rest[1])
        if cmd == 'evaluate':
            return render(*evaluate(b))
        if cmd == 'queue':
            return evaluate_queue(b)
        return render_reader(cmd, read_record(b) if cmd == 'record' else read_completion(b))
    if cmd == 'collect':
        if len(rest) != 4 or rest[0] != '--phase' or rest[1] not in ('class', 'final') or not re.fullmatch(r'[1-9][0-9]*', rest[2]):
            raise Usage()
        return render(*evaluate(collect(rest[1], int(rest[2]), rest[3])))
    if cmd == 'collect-queue':
        if rest:
            raise Usage()
        return evaluate_queue(collect_queue())
    raise Usage()


USAGE = 'usage: merge-risk.py evaluate|queue|record|completion --bundle <file> | collect --phase class|final <pr> <script-dir> | collect-queue\n'


def cli(argv):
    """Returns (stdout, exit code) exactly as the command line gives them."""
    try:
        return main(argv)
    except Usage:
        sys.stderr.write(USAGE)
        return '', 2
    except Exception as exc:  # any crash reads as unresolved, never as eligible or held
        return ('merge-risk: unresolved pr=- head=- base=- diff=- config=-\n'
                'reason: verifier-crash %s\n' % type(exc).__name__), 4


if __name__ == '__main__':
    out, status = cli(sys.argv[1:])
    sys.stdout.write(out)
    sys.exit(status)
