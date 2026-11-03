#!/usr/bin/env python3
"""Private A52 transport and reconciliation. The shell owns record semantics.

The only result is a versioned manifest and private transport files. All gh
reads, including rechecks, share one bounded budget. No production knobs.
"""
import json
import os
from pathlib import Path
import re
import selectors
import signal
import subprocess
import sys
import time
from urllib.parse import quote


class Incomplete(Exception):
    pass


class FetchError(Incomplete):
    pass


class Reader:
    def __init__(self, gate, remaining):
        self.gate = gate
        self.deadline = time.monotonic() + remaining
        self.calls = 1  # speculative detail acquisition
        self.total = 0
        self.cache = {}
        self.details = {}

    def process(self, args, data=None, limit=10, bytes_output=False):
        remaining = min(limit, self.deadline - time.monotonic())
        if remaining <= 0:
            raise Incomplete('deadline')
        # A file for stdin avoids an unbounded pipe write before the read timer.
        import tempfile
        with tempfile.TemporaryFile() as incoming:
            if data is not None:
                incoming.write(data.encode())
            incoming.seek(0)
            p = subprocess.Popen(args, stdin=incoming, stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE, start_new_session=True)
            def interrupted(signum, frame):
                try:
                    os.killpg(p.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                raise Incomplete('evaluation interrupted')
            previous = signal.signal(signal.SIGTERM, interrupted)
            result = [bytearray(), bytearray()]
            selector = selectors.DefaultSelector()
            for i, stream in enumerate((p.stdout, p.stderr)):
                os.set_blocking(stream.fileno(), False)
                selector.register(stream, selectors.EVENT_READ, i)
            end = time.monotonic() + remaining
            try:
                while selector.get_map():
                    left = end - time.monotonic()
                    if left <= 0:
                        raise Incomplete('subprocess timeout')
                    for key, _ in selector.select(left):
                        block = os.read(key.fileobj.fileno(), 65536)
                        if not block:
                            selector.unregister(key.fileobj)
                            continue
                        result[key.data].extend(block)
                        if sum(map(len, result)) >= 8 * 1024 * 1024:
                            raise Incomplete('response cap')
                p.wait(timeout=max(.001, end - time.monotonic()))
                if p.returncode:
                    raise FetchError(result[1].decode(errors='surrogateescape'))
                self.last_error = result[1].decode('utf-8', errors='surrogateescape')
                return bytes(result[0]) if bytes_output else result[0].decode('utf-8')
            finally:
                signal.signal(signal.SIGTERM, previous)
                try:
                    os.killpg(p.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                # Allow nested workers to reap their own subprocess groups.
                if p.poll() is None:
                    try:
                        p.wait(timeout=.2)
                    except subprocess.TimeoutExpired:
                        pass
                # Kill the group even if its leader exited leaving pipe holders.
                try:
                    os.killpg(p.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                p.wait()
                selector.close()
                p.stdout.close()
                p.stderr.close()

    def api(self, path):
        self.calls += 1
        if self.calls >= 1200:
            raise Incomplete('REST call cap')
        raw = self.process(['gh', 'api', 'repos/' + path,
                            '-H', 'Accept: application/vnd.github+json'])
        self.total += len(raw.encode())
        if self.total >= 64 * 1024 * 1024:
            raise Incomplete('aggregate byte cap')
        return json.loads(raw)

    def collection(self, repo, path, cap=1000):
        key = repo + '/' + path
        if key in self.cache:
            return self.cache[key]
        rows = []
        page = 1
        while True:
            sep = '&' if '?' in path else '?'
            batch = self.api(repo + '/' + path + sep + 'per_page=100&page=' + str(page))
            if not isinstance(batch, list) or len(batch) > 100:
                raise Incomplete('invalid collection')
            rows.extend(batch)
            if len(rows) >= cap:
                raise Incomplete('collection cap')
            if len(batch) < 100:
                self.cache[key] = rows
                return rows
            page += 1

    def detail(self, repo, path):
        key = repo + '/' + path
        if key not in self.details:
            obj = self.api(key)
            validate_detail(obj, repo, path.startswith('pulls/'))
            if obj['number'] != int(path.split('/')[1]):
                raise Incomplete('detail identity')
            self.details[key] = obj
        return self.details[key]

    def live(self, text):
        return self.process(['bash', self.gate, '--epic-live'], text)

    def overrides(self, rows):
        bundle = ''.join(body.replace('\x1e', '') + '\x1e' for _, _, body in rows)
        return self.process(['bash', self.gate, '--epic-overrides'], bundle).splitlines()


def integer(n):
    return type(n) is int and n > 0


def validate_detail(obj, repo, pull=False):
    if not isinstance(obj, dict) or not integer(obj.get('number')) or not integer(obj.get('id')):
        raise Incomplete('invalid issue/PR identity')
    for field in ('body', 'title', 'created_at', 'updated_at', 'state', 'url'):
        if not isinstance(obj.get(field), str):
            raise Incomplete('invalid detail ' + field)
    prefix = 'https://api.github.com/repos/' + repo + '/'
    expected = [prefix + 'issues/' + str(obj['number'])]
    if pull:
        expected.append(prefix + 'pulls/' + str(obj['number']))
    if obj['url'] not in expected:
        raise Incomplete('repository identity')
    if obj['state'] not in ('open', 'closed'):
        raise Incomplete('issue state')
    if pull:
        for part in ('base', 'head'):
            side = obj.get(part)
            if not isinstance(side, dict) or not isinstance(side.get('ref'), str):
                raise Incomplete('invalid PR ref')
            if not isinstance(side.get('repo'), dict) or not isinstance(side['repo'].get('full_name'), str):
                raise Incomplete('invalid PR repository')
            if not isinstance(side.get('sha'), str):
                raise Incomplete('invalid PR sha')
        if obj.get('merged_at') is not None and not isinstance(obj['merged_at'], str):
            raise Incomplete('invalid merge time')


def comment_rows(items, rank, review=False):
    rows = []
    for obj in items:
        if not isinstance(obj, dict) or not integer(obj.get('id')):
            raise Incomplete('invalid comment identity')
        stamp = obj.get('submitted_at' if review else 'created_at')
        body = obj.get('body')
        if not isinstance(stamp, str) or not stamp or not isinstance(body, str):
            raise Incomplete('invalid comment body/time')
        rows.append((stamp, rank, body))
    return rows


def closing(obj):
    # This is transport to the gate's existing closing-reference parser,
    # selected by a private reader mode, not a second closing grammar.
    return obj['title'] + ' ' + obj['body']


def refs(reader, obj):
    raw = reader.process(['bash', reader.gate, '--epic-closing'], closing(obj))
    return set(map(int, raw.split()))


def write_context(root, name, kind, detail, issues, comments, reviews, skips=()):
    target = root / name
    target.mkdir()
    def encoded(body):
        return body.replace('\x1e', '').replace('\x01', ' ').replace('\n', '\x01')
    (target / 'detail').write_text(detail['title'].replace('\n', ' ') + '\n' +
                                  detail['created_at'] + '\t' + encoded(detail['body']))
    descriptions = [row for row in comments if row[1] == 1]
    comments = [row for row in comments if row[1] != 1]
    for file, rows in (('issues', issues), ('comments', comments), ('reviews', reviews), ('descriptions', descriptions)):
        (target / file).write_text('\n'.join(stamp + '\t' + encoded(body) for stamp, _, body in rows))
    (target / 'kind').write_text(kind)
    (target / 'release-skips').write_text(' '.join(s.removeprefix('skip=') for s in skips if s.startswith('skip=')))
    return name


def collect(gate, number, root, remaining):
    r = Reader(gate, remaining)
    meta = json.loads((root / 'metadata').read_text())
    if not isinstance(meta, list) or len(meta) != 9 or not all(isinstance(x, str) for x in meta[:4]):
        raise Incomplete('invalid metadata')
    head, head_repo, base, repo = meta[:4]
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repo):
        raise Incomplete('invalid repository')
    # Fetch the projected detail as a typed object once; the initial shell
    # read remains the snapshot used for all later comparisons.
    projected = (root / 'detail').read_text()
    r.total = len(projected.encode()) + len((root / 'metadata').read_bytes())
    title, desc = projected.split('\n', 1)
    stamp, body = desc.split('\t', 1)
    detail = dict(title=title, created_at=stamp, body=body.replace('\x01', '\n'))
    m = re.fullmatch(r'release/([1-9][0-9]*)-[A-Za-z0-9][A-Za-z0-9-]*', head)
    eligible = bool(m and head_repo == repo and re.search(
        r'\bcloses\s+#' + m[1] + r'\b', closing(detail), re.I))
    for suffix, review in (('comments', False), ('reviews', True)):
        path = f'pulls/{number}/reviews' if review else f'issues/{number}/comments'
        try:
            rows = comment_rows(r.collection(repo, path), 3 if review else 2, review)
        except FetchError as error:
            (root / 'fetch-error').write_text(str(error))
            return {'version': 1, 'fetch_error': suffix}
        if review:
            reviews = rows
        else:
            comments = rows
    issues = []
    epic_rows = []
    notes = []
    for n in sorted(refs(r, detail)):
        try:
            rows = comment_rows(r.collection(repo, f'issues/{n}/comments'), 0)
        except FetchError as error:
            if '(HTTP 404)' not in str(error):
                (root / 'fetch-error').write_text(str(error))
                return {'version': 1, 'fetch_error': 'issue', 'issue': n}
            notes.append(n)
            continue
        issues.extend(rows)
        if m and n == int(m[1]):
            epic_rows = rows
    pr_rows = [(stamp, 1, detail['body'])] + comments + reviews
    scopes = r.overrides(issues + pr_rows)
    if notes or r.overrides(epic_rows) or 'single-session' in scopes:
        eligible = False
    if eligible:
        repository = r.api(repo)
        if not isinstance(repository, dict) or repository.get('full_name') != repo or not isinstance(repository.get('default_branch'), str):
            raise Incomplete('invalid repository detail')
        eligible = base == repository['default_branch']
    if not eligible:
        write_context(root, 'release', 'legacy', detail, issues, comments, reviews)
        return {'version': 1, 'contexts': [['release', '']], 'findings': [], 'notes': notes}
    epic = int(m[1])
    # Cache the full release snapshot; compare its projected fields to the
    # first acquisition before trusting this typed identity.
    release = r.detail(repo, f'pulls/{number}')
    if (release['title'], release['created_at'], release['body'].replace('\x1e', '').replace('\x01', ' ').replace('\n', '\x01'),
        release['head']['ref'], release['head']['repo']['full_name'], release['base']['ref'], release['base']['repo']['full_name']) != (
        title, stamp, body, head, head_repo, base, repo):
        raise Incomplete('release detail changed')
    if [release.get('updated_at'), release.get('state'), release.get('merged_at'),
        release['head'].get('sha'), release['base'].get('sha')] != meta[4:]:
        raise Incomplete('release snapshot changed')
    e = r.detail(repo, f'issues/{epic}')
    findings = []
    def defect(text, child=None, pull=None):
        findings.append({'epic': epic, 'child': child, 'pull': pull, 'detail': text})
    all_issues = r.collection(repo, 'issues?state=all', 5000)
    members = {}
    fields = {}
    enumerated = {}
    for obj in all_issues:
        validate_detail(obj, repo)
        if 'pull_request' in obj:
            continue
        c = obj['number']
        enumerated[c] = obj
        if c in fields:
            raise Incomplete('duplicate issue identity')
        text = r.live(obj['body'])
        matches = re.findall(r'^[ \t]*\*\*Epic:\*\*[ \t]+#([1-9][0-9]*)[ \t]*$', text, re.M)
        field_lines = re.findall(r'^[ \t]*\*\*Epic:\*\*.*$', text, re.M)
        fields[c] = matches if len(field_lines) == len(matches) else matches + ['invalid']
        if str(epic) in matches:
            members[c] = obj
    if len(members) >= 100:
        raise Incomplete('child cap')
    # Parse one live Work items section and reject malformed checklist rows.
    text = r.live(e['body'])
    sections = re.split(r'^##[ \t]+Work items[ \t]*$', text, flags=re.M)
    listed = []
    if len(sections) != 2:
        defect('missing or ambiguous Work items section')
    else:
        section = re.split(r'^#{1,2}[ \t]+', sections[1], maxsplit=1, flags=re.M)[0]
        for line in section.splitlines():
            if not line.strip() or not re.match(r'^[ \t]*[-*][ \t]+', line):
                continue
            match = re.fullmatch(r'[ \t]*[-*][ \t]+\[[ xX]\][ \t]+#([1-9][0-9]*)(?:[ \t]+.*)?[ \t]*', line)
            if not match:
                mentioned = re.search(r'#([1-9][0-9]*)\b', line)
                defect('malformed Work items row', int(mentioned[1]) if mentioned else None)
                continue
            c = int(match[1])
            if c in listed:
                defect('duplicate Work items row', c)
            listed.append(c)
    children = set(listed) | set(members)
    if len(children) >= 100:
        raise Incomplete('child cap')
    if not children:
        defect('empty child membership')
    for c in sorted(children):
        if fields.get(c) != [str(epic)] or c not in listed:
            defect('Epic field and Work items membership disagree', c)
    merged = r.collection(repo, 'pulls?state=closed&base=' + quote(head, safe=''))
    candidates = {c: set() for c in children}
    for p in merged:
        validate_detail(p, repo, True)
        if p['merged_at'] is None or p['base']['ref'] != head or p['base']['repo']['full_name'] != repo:
            continue
        closed = refs(r, p)
        if not closed & children:
            defect('merged release PR closes no child', pull=p['number'])
        for c in closed - children:
            defect('merged release PR closes a nonmember', c, p['number'])
        for c in closed & children:
            candidates[c].add(p['number'])
    contexts = [['release', '']]
    write_context(root, 'release', 'release', detail, issues, comments, reviews)
    for c in sorted(children):
        if c not in fields:
            continue  # complete enumeration already proves the missing member
        obj = r.detail(repo, f'issues/{c}')
        # Enumeration is also a snapshot. A changed first issue detail is
        # unchecked, not a membership guess.
        if c in enumerated and obj != enumerated[c]:
            raise Incomplete('enumerated issue changed')
        if obj['state'] != 'closed':
            defect('child issue is open', c)
        events = r.collection(repo, f'issues/{c}/timeline')
        for event in events:
            if not isinstance(event, dict) or not integer(event.get('id')) or not isinstance(event.get('event'), str) or not isinstance(event.get('created_at'), str):
                raise Incomplete('invalid timeline event')
            if event['event'] != 'cross-referenced':
                continue
            source = event.get('source', {}).get('issue', {})
            if not isinstance(source, dict):
                raise Incomplete('invalid timeline source')
            link = source.get('pull_request', {}).get('url', '')
            match = re.fullmatch(r'https://api.github.com/repos/' + re.escape(repo) + r'/pulls/([1-9][0-9]*)', link)
            if not match:
                continue
            validate_detail(source, repo)
            if source['number'] != int(match[1]):
                raise Incomplete('timeline source identity')
            p = r.detail(repo, 'pulls/' + match[1])
            if c in refs(r, p):
                candidates[c].add(p['number'])
        local = comment_rows(r.collection(repo, f'issues/{c}/comments'), 0)
        child_comments, child_reviews = [], []
        for pn in sorted(candidates[c]):
            p = r.detail(repo, f'pulls/{pn}')
            if c not in refs(r, p):
                defect('closing PR no longer closes child', c, pn)
                continue
            if p['state'] != 'closed' or p['merged_at'] is None or p['base']['ref'] != head or p['base']['repo']['full_name'] != repo:
                defect('closing PR is open, unmerged or on another base', c, pn)
            child_comments.append((p['created_at'], 1, p['body']))
            child_comments.extend(comment_rows(r.collection(repo, f'issues/{pn}/comments'), 2))
            child_reviews.extend(comment_rows(r.collection(repo, f'pulls/{pn}/reviews'), 3, True))
        # Descriptions are rank 1, followed by comments/reviews; sort only
        # on time/source/sequence in the gate. Use the issue's empty pseudo
        # description so no fabricated evidence is introduced.
        empty = dict(obj, title='', body='')
        name = 'child-' + str(c)
        write_context(root, name, 'child' if candidates[c] else 'disposition', empty,
                      local, child_comments, child_reviews, scopes)
        contexts.append([name, str(c)])
    for key, before in r.details.items():
        after = r.api(key)
        if after != before:
            raise Incomplete('detail snapshot changed')
    return {'version': 1, 'epic': epic, 'contexts': contexts, 'findings': findings}


def manifest(root):
    value = json.loads((root / 'manifest.json').read_text())
    if not isinstance(value, dict) or value.get('version') != 1:
        raise Incomplete('manifest version')
    if value.get('fetch_error'):
        print('fetch-error|' + value['fetch_error'] + '|' + str(value.get('issue', '')))
        return
    for issue in value.get('notes', []):
        if not integer(issue):
            raise Incomplete('manifest note identity')
        print('note\t' + str(issue))
    for name, child in value['contexts']:
        if not re.fullmatch(r'release|child-[1-9][0-9]*', name) or not re.fullmatch(r'[0-9]*', child):
            raise Incomplete('manifest context')
        print('context\t' + name + '\t' + child + '\t' + str(value.get('epic', '')))
    for finding in value['findings']:
        print('finding\t' + str(finding['epic']) + '\t' + str(finding['child'] or '') + '\t' +
              str(finding['pull'] or '') + '\t' + finding['detail'])


def supervise(gate, number, root, remaining):
    # The outer deadline covers shell parsing too. Keep every output private
    # until the worker has completed successfully. Kill all descendants on
    # timeout, including subprocesses started in their own REST groups.
    r = Reader(gate, remaining)
    raw = r.process(['bash', gate, '--epic-worker', str(root), number, str(remaining)], limit=remaining)
    sys.stdout.write(raw)
    sys.stderr.write(r.last_error)


def main():
    mode = sys.argv[1]
    if mode == 'initial':
        r = Reader('', 10)
        try:
            sys.stdout.buffer.write(r.process(sys.argv[2:], bytes_output=True))
            sys.stderr.buffer.write(r.last_error.encode('utf-8', errors='surrogateescape'))
        except Incomplete as error:
            sys.stderr.buffer.write(str(error).encode('utf-8', errors='surrogateescape'))
            sys.exit(1)
    elif mode == 'supervise':
        supervise(sys.argv[2], sys.argv[3], Path(sys.argv[4]), float(sys.argv[5]))
    elif mode == 'collect':
        gate, number, root, remaining = sys.argv[2:]
        root = Path(root)
        value = collect(gate, int(number), root, float(remaining))
        (root / 'manifest.json').write_text(json.dumps(value))
    elif mode == 'findings':
        value = json.loads((Path(sys.argv[2]) / 'manifest.json').read_text())
        if value.get('version') != 1:
            raise Incomplete('manifest version')
        for f in value.get('findings', []):
            print('|'.join(map(str, (f['epic'], f['child'] or '', f['pull'] or '', f['detail']))))
    elif mode == 'manifest':
        manifest(Path(sys.argv[2]))
    else:
        raise Incomplete('private mode')


if __name__ == '__main__':
    try:
        main()
    except (Incomplete, ValueError, KeyError, TypeError, OSError, subprocess.SubprocessError) as error:
        print('epic traversal incomplete: ' + str(error), file=sys.stderr)
        sys.exit(1)
