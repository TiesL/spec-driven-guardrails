#!/usr/bin/env python3
"""Private A52 transport and reconciliation. The shell owns record semantics.

The only result is a versioned manifest and private transport files. All gh
reads, including rechecks, and all context scans share one bounded pool of 8
concurrent subprocesses and one budget. No production knobs.
"""
from concurrent.futures import ThreadPoolExecutor, wait, FIRST_EXCEPTION
import ctypes
import json
import os
from pathlib import Path
import re
import selectors
import signal
import subprocess
import sys
import tempfile
import threading
import time
from urllib.parse import quote

WORKERS = 8
CALLS = 1200            # total REST calls, including the initial detail
CHILD_CALLS = 40        # REST calls attributable to one child
CHILDREN = 100
CANDIDATES = 200
EPIC_EVENTS = 1000
COLLECTION = 1000       # closed PRs, child timeline events, comments, reviews
RESPONSE = 8 * 1024 * 1024
TOTAL_BYTES = 64 * 1024 * 1024
READ_SECONDS = 10
STAGES = ('Discovery', 'Planning', 'Test', 'Implementation')


class Incomplete(Exception):
    pass


class FetchError(Incomplete):
    def __init__(self, text):
        super().__init__(text)
        m = re.search(r'\(HTTP ([0-9]{3})\)', text)
        self.status = int(m[1]) if m else None


def child_pids(pid):
    """Enumerate direct children without a ps executable (sandboxed on macOS)."""
    if sys.platform == 'darwin':
        lib = ctypes.CDLL('/usr/lib/libproc.dylib', use_errno=True)
        listing = lib.proc_listchildpids
        listing.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_int]
        size = 32
        while True:
            buffer = (ctypes.c_int * size)()
            count = listing(pid, buffer, ctypes.sizeof(buffer))
            if count < 0:
                raise OSError(ctypes.get_errno(), 'proc_listchildpids')
            if count < size:
                return set(buffer[:count]) - {0}
            size *= 2
    # Linux lists children per thread, including subprocesses started by pool
    # threads rather than the main thread. An exited task can disappear here.
    children = set()
    for task in Path(f'/proc/{pid}/task').glob('*'):
        try:
            children.update(map(int, (task / 'children').read_text().split()))
        except FileNotFoundError:
            pass
    return children


class PipeInfo(ctypes.Structure):
    # Stable proc_pidfdinfo(PROC_PIDFDPIPEINFO) layout from sys/proc_info.h.
    _fields_ = [('file', ctypes.c_uint32 * 6), ('stat', ctypes.c_uint64 * 17),
                ('handle', ctypes.c_uint64), ('peer', ctypes.c_uint64),
                ('status', ctypes.c_int), ('reserved', ctypes.c_int)]


def process_pipes(pid):
    """Map anonymous pipe FDs to (reader, writer) identities, without ps.

    A retained read endpoint pins its peer's identity even after a writer's
    original parent exits. Only the matching write endpoint proves ownership.
    """
    if sys.platform == 'darwin':
        lib = ctypes.CDLL('/usr/lib/libproc.dylib', use_errno=True)
        size = lib.proc_pidinfo(pid, 1, 0, None, 0)  # PROC_PIDLISTFDS, bytes
        if size <= 0:
            return {}
        rows = (ctypes.c_int32 * ((size + 256) // 4))()
        count = lib.proc_pidinfo(pid, 1, 0, rows, ctypes.sizeof(rows))
        result = {}
        for i in range(0, max(0, count) // 4, 2):
            fd, kind = rows[i:i + 2]
            if kind != 6:  # PROX_FDTYPE_PIPE
                continue
            info = PipeInfo()
            if lib.proc_pidfdinfo(pid, fd, 6, ctypes.byref(info), ctypes.sizeof(info)) != ctypes.sizeof(info):
                continue
            flags = info.file[0]  # FREAD / FWRITE, not O_RDONLY / O_WRONLY
            result[fd] = (info.peer if flags & 1 else None,
                          info.handle if flags & 2 else None)
        return result
    result = {}
    for fd in Path(f'/proc/{pid}/fd').glob('*'):
        try:
            target = os.readlink(fd)
            if not target.startswith('pipe:['):
                continue
            flags = re.search(r'^flags:\s+([0-7]+)',
                              (Path(f'/proc/{pid}/fdinfo') / fd.name).read_text(), re.M)
            access = int(flags[1], 8) & os.O_ACCMODE
            result[int(fd.name)] = (target if access != os.O_WRONLY else None,
                                    target if access != os.O_RDONLY else None)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    return result


def pipe_writers(readers):
    """Find escaped holders of private response pipes; never select readers."""
    if not readers:
        return set()
    if sys.platform == 'darwin':
        lib = ctypes.CDLL('/usr/lib/libproc.dylib', use_errno=True)
        size = max(32, lib.proc_listallpids(None, 0) + 32)
        while True:
            buffer = (ctypes.c_int * size)()
            count = lib.proc_listallpids(buffer, ctypes.sizeof(buffer))
            if count < size:
                pids = buffer[:max(0, count)]
                break
            size *= 2
    else:
        pids = [int(p.name) for p in Path('/proc').iterdir() if p.name.isdecimal()]
    return {pid for pid in pids if pid > 0 and pid != os.getpid()
            and any(writer in readers for _, writer in process_pipes(pid).values())}


def kill_descendants(roots, readers=()):
    """Freeze the owned trees before killing them, including new sessions.

    Killing only a worker's group loses gh groups when the worker exits.
    Stop parents first so they cannot fork or orphan a child during discovery;
    repeat child discovery until every discovered descendant is stopped.
    Never signal our own group: the caller and watchdog may share it.
    """
    owned = set(roots) - {os.getpid()}
    readers = set(readers) - {None}
    stopped = set()
    try:
        while True:
            pending = owned - stopped
            for pid in sorted(pending):
                try:
                    if os.getpgid(pid) == pid and pid != os.getpgrp():
                        os.killpg(pid, signal.SIGSTOP)
                    else:
                        os.kill(pid, signal.SIGSTOP)
                except ProcessLookupError:
                    pass
                stopped.add(pid)
            for pid in pending:
                readers.update(reader for reader, _ in process_pipes(pid).values() if reader is not None)
                owned.update(child_pids(pid))
            if owned - stopped:
                continue
            # A parent may already have exited. Its detached pipe holders are
            # no longer in the tree, but still own our pinned write endpoints.
            owned.update(pipe_writers(readers))
            if not owned - stopped:
                break
    finally:
        # Individual PIDs also cover descendants sharing the caller's group.
        for pid in sorted(owned - set(roots), reverse=True) + list(roots):
            try:
                if os.getpgid(pid) == pid and pid != os.getpgrp():
                    os.killpg(pid, signal.SIGKILL)
                else:
                    os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        # A recorded group can outlive its leader. getpgid(leader) then fails,
        # so signal the recorded group directly as well as the discovered PIDs.
        for group in roots:
            if group != os.getpgrp():
                try:
                    os.killpg(group, signal.SIGKILL)
                except (ProcessLookupError, PermissionError):
                    pass


class Runner:
    """Bounded subprocesses, each in its own process group, tracked under a
    lock so the main thread can kill them all on SIGTERM, deadline or the
    first failure. Counters and caches are lock-protected."""

    def __init__(self, gate, remaining):
        self.gate = gate
        self.deadline = time.monotonic() + remaining
        self.lock = threading.RLock()
        self.groups = set()
        self.readers = {}
        self.abort = threading.Event()
        self.calls = 1  # speculative detail acquisition
        self.child_calls = {}
        self.total = 0
        self.cache = {}
        self.details = {}
        self.pool = None
        if threading.current_thread() is threading.main_thread():
            signal.signal(signal.SIGTERM, self.interrupted)

    def interrupted(self, signum, frame):
        self.stop()
        raise Incomplete('evaluation interrupted')

    def stop(self):
        self.abort.set()
        with self.lock:
            groups = list(self.groups)
            readers = set().union(*self.readers.values()) if self.readers else set()
            # Keep these read FDs open until discovery finishes: pool threads
            # remove their registry entries under this same lock before close.
            kill_descendants(groups, readers)

    def all(self, fn, items):
        """Run fn over items in the pool; results in input order, never in
        completion order. The first failure cancels queued work."""
        items = list(items)
        if not items:
            return []
        if self.pool is None:
            self.pool = ThreadPoolExecutor(WORKERS)
        futures = [self.pool.submit(self.guarded, fn, x) for x in items]
        wait(futures, return_when=FIRST_EXCEPTION)
        for f in futures:
            if f.done() and not f.cancelled() and f.exception() is not None:
                self.stop()
                for g in futures:
                    g.cancel()
                raise f.exception()
        return [f.result() for f in futures]

    def settle(self, fn, items):
        """Like all(), but returns each failure as a value (legacy precedence
        decides which failure is reported)."""
        def caught(x):
            try:
                return (None, fn(x))
            except FetchError as error:
                return (error, None)
        return self.all(caught, items)

    def guarded(self, fn, x):
        if self.abort.is_set():
            raise Incomplete('aborted')
        return fn(x)

    def process(self, args, data=None, limit=READ_SECONDS):
        """Returns (returncode, stdout bytes, stderr text)."""
        if self.abort.is_set():
            raise Incomplete('aborted')
        remaining = min(limit, self.deadline - time.monotonic())
        if remaining <= 0:
            raise Incomplete('deadline')
        # A file for stdin avoids an unbounded pipe write before the read timer.
        with tempfile.TemporaryFile() as incoming:
            if data is not None:
                incoming.write(data.encode('utf-8', errors='surrogateescape'))
            incoming.seek(0)
            with self.lock:
                if self.abort.is_set():
                    raise Incomplete('aborted')
                p = subprocess.Popen(args, stdin=incoming, stdout=subprocess.PIPE,
                                     stderr=subprocess.PIPE, start_new_session=True)
                self.groups.add(p.pid)
                endpoints = process_pipes(os.getpid())
                self.readers[p.pid] = {endpoints[stream.fileno()][0]
                                       for stream in (p.stdout, p.stderr)}
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
                    if self.abort.is_set():
                        raise Incomplete('aborted')
                    for key, _ in selector.select(min(left, 1)):
                        block = os.read(key.fileobj.fileno(), 65536)
                        if not block:
                            selector.unregister(key.fileobj)
                            continue
                        result[key.data].extend(block)
                        if len(result[0]) + len(result[1]) >= RESPONSE:
                            raise Incomplete('response cap')
                p.wait(timeout=max(.001, end - time.monotonic()))
                return p.returncode, bytes(result[0]), result[1].decode('utf-8', errors='surrogateescape')
            except subprocess.TimeoutExpired:
                raise Incomplete('subprocess timeout')
            finally:
                if selector.get_map() or p.poll() is None or p.returncode:
                    kill_descendants([p.pid], self.readers[p.pid])
                try:
                    os.killpg(p.pid, signal.SIGTERM)
                except (ProcessLookupError, PermissionError):
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
                except (ProcessLookupError, PermissionError):
                    pass
                p.wait()
                with self.lock:
                    self.groups.discard(p.pid)
                    self.readers.pop(p.pid)
                selector.close()
                p.stdout.close()
                p.stderr.close()

    def count(self, child):
        with self.lock:
            self.calls += 1
            if self.calls >= CALLS:
                raise Incomplete('REST call cap')
            if child is not None:
                n = self.child_calls.get(child, 0) + 1
                self.child_calls[child] = n
                if n >= CHILD_CALLS:
                    raise Incomplete('per-child REST call cap')

    def api(self, path, child=None):
        self.count(child)
        rc, raw, err = self.process(['gh', 'api', 'repos/' + path,
                                     '-H', 'Accept: application/vnd.github+json'])
        with self.lock:
            self.total += len(raw)
            if self.total >= TOTAL_BYTES:
                raise Incomplete('aggregate byte cap')
        if rc:
            raise FetchError(err)
        return json.loads(raw.decode('utf-8'))

    def collection(self, repo, path, cap=COLLECTION, child=None):
        key = repo + '/' + path
        with self.lock:
            if key in self.cache:
                return self.cache[key]
        rows = []
        page = 1
        while True:
            sep = '&' if '?' in path else '?'
            batch = self.api(repo + '/' + path + sep + 'per_page=100&page=' + str(page), child)
            if not isinstance(batch, list) or len(batch) > 100:
                raise Incomplete('invalid collection')
            rows.extend(batch)
            if len(rows) >= cap:
                raise Incomplete('collection cap')
            if len(batch) < 100:
                with self.lock:
                    self.cache[key] = rows
                return rows
            page += 1

    def detail(self, repo, path, child=None):
        key = repo + '/' + path
        with self.lock:
            if key in self.details:
                return self.details[key]
        obj = self.api(key, child)
        validate_detail(obj, repo, path.startswith('pulls/'))
        if obj['number'] != int(path.split('/')[1]):
            raise Incomplete('detail identity')
        with self.lock:
            self.details[key] = obj
        return obj

    def shell(self, mode, data, limit=READ_SECONDS):
        rc, raw, _ = self.process(['bash', self.gate, mode], data, limit)
        if rc:
            raise Incomplete('shell ' + mode + ' failed')
        return raw.decode('utf-8', errors='surrogateescape')

    def batch(self, mode, bodies):
        """--epic-live/--epic-closing: many bodies per call, one framed result
        per body in order; a count mismatch is unchecked."""
        if not bodies:
            return []
        bundle = ''.join(b.replace('\x1e', '') + '\x1e' for b in bodies)
        parts = self.shell(mode, bundle).split('\x1e')
        if len(parts) != len(bodies) + 1 or parts[-1] != '':
            raise Incomplete('framed result count mismatch')
        return parts[:-1]

    def overrides(self, rows):
        bundle = ''.join(body.replace('\x1e', '') + '\x1e' for _, _, body in rows)
        return self.shell('--epic-overrides', bundle).splitlines()


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


def snapshot(obj):
    """Fields whose change invalidates the snapshot (A52 recheck)."""
    view = [obj.get(k) for k in ('title', 'body', 'state', 'updated_at', 'merged_at')]
    for part in ('base', 'head'):
        side = obj.get(part)
        if isinstance(side, dict):
            view += [side.get('ref'), side.get('sha'), (side.get('repo') or {}).get('full_name')]
    return view


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


def refs(r, objs):
    return [set(map(int, raw.split())) for raw in r.batch('--epic-closing', [closing(o) for o in objs])]


def events(rows):
    for event in rows:
        if not isinstance(event, dict) or not isinstance(event.get('event'), str):
            raise Incomplete('invalid timeline event')
        if event['event'] != 'cross-referenced':
            continue
        source = event.get('source')
        issue = source.get('issue') if isinstance(source, dict) else None
        if isinstance(issue, dict):
            yield issue


def encoded(body):
    return body.replace('\x1e', '').replace('\x01', ' ').replace('\n', '\x01')


def write_context(root, name, kind, detail, issues, comments, reviews, skips=()):
    target = root / name
    target.mkdir()
    (target / 'detail').write_text(detail['title'].replace('\n', ' ') + '\n' +
                                  detail['created_at'] + '\t' + encoded(detail['body']))
    descriptions = [row for row in comments if row[1] == 1]
    comments = [row for row in comments if row[1] != 1]
    for file, rows in (('issues', issues), ('comments', comments), ('reviews', reviews), ('descriptions', descriptions)):
        (target / file).write_text('\n'.join(stamp + '\t' + encoded(body) for stamp, _, body in rows))
    (target / 'kind').write_text(kind)
    (target / 'release-skips').write_text(' '.join(s[len('skip='):] for s in skips if s.startswith('skip=')))
    return name


def evaluate(r, root, names):
    return r.all(lambda name: scan(r, root / name), names)


def scan(r, context):
    rc, raw, _ = r.process(['bash', r.gate, '--epic-evaluate', str(context)])
    if rc:
        raise Incomplete('context scan failed')
    return [x for x in raw.decode('utf-8', errors='surrogateescape').split('\n') if x]


def collect(gate, number, root, remaining):
    r = Runner(gate, remaining)
    try:
        return traverse(r, number, root)
    finally:
        r.stop()
        if r.pool is not None:
            r.pool.shutdown(wait=False, cancel_futures=True)


def traverse(r, number, root):
    meta = json.loads((root / 'metadata').read_text())
    if not isinstance(meta, list) or len(meta) != 9 or not all(isinstance(x, str) for x in meta[:4]):
        raise Incomplete('invalid metadata')
    head, head_repo, base, repo = meta[:4]
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repo):
        raise Incomplete('invalid repository')
    # The initial shell read remains the snapshot for all later comparisons.
    projected = (root / 'detail').read_text()
    r.total = len(projected.encode()) + len((root / 'metadata').read_bytes())
    title, desc = projected.split('\n', 1)
    stamp, body = desc.split('\t', 1)
    detail = dict(title=title, created_at=stamp, body=body.replace('\x01', '\n'))
    m = re.fullmatch(r'release/([1-9][0-9]*)-[A-Za-z0-9][A-Za-z0-9-]*', head)
    shaped = bool(m and head_repo == repo and re.search(
        r'\bcloses\s+#' + m[1] + r'\b', closing(detail), re.I))

    # Release evidence and closing issues, read concurrently; failures are
    # reported in the legacy precedence: comments, reviews, issues by number.
    closing_issues = sorted(refs(r, [detail])[0])
    jobs = [('comments', f'issues/{number}/comments'), ('reviews', f'pulls/{number}/reviews')]
    jobs += [('issue', f'issues/{n}/comments') for n in closing_issues]
    results = r.settle(lambda job: r.collection(repo, job[1]), jobs)
    comments = reviews = None
    issues, epic_rows, notes = [], [], []
    for (kind, path), (error, rows) in zip(jobs, results):
        n = int(path.split('/')[1])
        if error is not None:
            if kind == 'issue' and error.status == 404:
                notes.append(n)
                continue
            (root / 'fetch-error').write_text(str(error))
            return {'version': 2, 'fetch_error': kind, 'issue': n if kind == 'issue' else ''}
        if kind == 'comments':
            comments = comment_rows(rows, 2)
        elif kind == 'reviews':
            reviews = comment_rows(rows, 3, True)
        else:
            rows = comment_rows(rows, 0)
            issues.extend(rows)
            if m and n == int(m[1]):
                epic_rows = rows
    pr_rows = [(stamp, 1, detail['body'])] + comments + reviews

    def legacy():
        write_context(root, 'release', 'legacy', detail, issues, comments, reviews)
        lines = ['closing reference #%d does not exist and was ignored' % n for n in notes]
        lines = ['model-record: ' + x for x in lines] + evaluate(r, root, ['release'])[0]
        return {'version': 2, 'rows': [['out', x] for x in lines]}

    if not shaped:
        return legacy()
    epic = int(m[1])
    manual, scopes = r.all(r.overrides, [epic_rows, issues + pr_rows])
    if (manual or 'single-session' in scopes) and epic not in notes:
        return legacy()
    repository = r.api(repo)
    if not isinstance(repository, dict) or repository.get('full_name') != repo or not isinstance(repository.get('default_branch'), str):
        raise Incomplete('invalid repository detail')
    if base != repository['default_branch']:
        return legacy()
    if notes:
        # An eligible release never falls back to legacy on a 404.
        return {'version': 2, 'unchecked': 'closing reference #%d on epic release PR #%d does not exist (HTTP 404)' % (min(notes), number)}
    return inherit(r, number, root, repo, head, base, meta, detail, title, stamp, body,
                   epic, issues, comments, reviews, scopes)


def inherit(r, number, root, repo, head, base, meta, detail, title, stamp, body,
            epic, issues, comments, reviews, scopes):
    findings = []

    def defect(text, child=None):
        findings.append((child or 0, text))

    release, e, timeline, merged_all = r.all(lambda f: f(), [
        lambda: r.detail(repo, f'pulls/{number}'),
        lambda: r.detail(repo, f'issues/{epic}'),
        lambda: r.collection(repo, f'issues/{epic}/timeline', EPIC_EVENTS),
        lambda: r.collection(repo, 'pulls?state=closed&base=' + quote(head, safe='')),
    ])
    # Compare the typed release detail to the first acquisition.
    if (release['title'], release['created_at'], encoded(release['body']),
        release['head']['ref'], release['head']['repo']['full_name'], release['base']['ref'], release['base']['repo']['full_name']) != (
            title, stamp, body, head, meta[1], base, repo):
        raise Incomplete('release detail changed')
    if [release.get('updated_at'), release.get('state'), release.get('merged_at'),
            release['head'].get('sha'), release['base'].get('sha')] != meta[4:]:
        raise Incomplete('release snapshot changed')

    # Candidate set K: epic timeline cross-references, Work items, and issues
    # closed by merged release-branch PRs. Never the repository issue list.
    issue_url = re.compile(r'https://api\.github\.com/repos/' + re.escape(repo) + r'/issues/([1-9][0-9]*)')
    from_timeline = set()
    for source in events(timeline):
        if 'pull_request' in source:
            continue
        link = issue_url.fullmatch(source.get('url') or '')
        if link:
            from_timeline.add(int(link[1]))
    merged = []
    for p in merged_all:
        validate_detail(p, repo, True)
        if p['merged_at'] is not None and p['base']['ref'] == head and p['base']['repo']['full_name'] == repo:
            merged.append(p)
    merged_refs = refs(r, merged)
    from_prs = set().union(*merged_refs) if merged_refs else set()

    live_epic = r.batch('--epic-live', [e['body']])[0]
    sections = re.split(r'^##[ \t]+Work items[ \t]*$', live_epic, flags=re.M)
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
    strict = set(listed) | from_prs
    candidates = sorted(from_timeline | strict)
    if len(candidates) >= CANDIDATES:
        raise Incomplete('candidate cap')

    def candidate(n):
        try:
            return r.detail(repo, f'issues/{n}', n)
        except FetchError as error:
            # A timeline-only candidate that is gone cannot carry a live field.
            if n not in strict and error.status in (404, 410):
                return None
            raise
    found = dict(zip(candidates, r.all(candidate, candidates)))
    found = {n: obj for n, obj in found.items() if obj is not None}
    numbers = sorted(found)
    fields = {}
    for n, text in zip(numbers, r.batch('--epic-live', [found[n]['body'] for n in numbers])):
        matches = re.findall(r'^[ \t]*\*\*Epic:\*\*[ \t]+#([1-9][0-9]*)[ \t]*$', text, re.M)
        field_lines = re.findall(r'^[ \t]*\*\*Epic:\*\*.*$', text, re.M)
        fields[n] = matches if len(field_lines) == len(matches) else matches + ['invalid']
    members = {n for n in numbers if str(epic) in fields[n]}
    children = set(listed) | members
    if len(children) >= CHILDREN:
        raise Incomplete('child cap')
    if not children:
        defect('empty child membership')
    for c in sorted(children):
        if fields.get(c) != [str(epic)] or c not in listed:
            defect('Epic field and Work items membership disagree', c)
    owners = {c: set() for c in children}
    for p, closed in zip(merged, merged_refs):
        if not closed & children:
            defect('merged release PR #%d closes no child' % p['number'])
        for c in sorted(closed - children):
            defect('merged release PR #%d closes a nonmember' % p['number'], c)
        for c in closed & children:
            owners[c].add(p['number'])

    ordered = sorted(children)
    for c in ordered:
        if found[c]['state'] != 'closed':
            defect('child issue is open', c)
    # Each child's timeline and comments: complete collections.
    jobs = [(c, kind) for c in ordered for kind in ('timeline', 'comments')]
    loaded = dict(zip(jobs, r.all(lambda job: r.collection(repo, f'issues/{job[0]}/{job[1]}', child=job[0]), jobs)))
    pull_url = re.compile(r'https://api\.github\.com/repos/' + re.escape(repo) + r'/pulls/([1-9][0-9]*)')
    referenced = {}
    for c in ordered:
        referenced[c] = set()
        for source in events(loaded[(c, 'timeline')]):
            link = source.get('pull_request')
            link = pull_url.fullmatch(link.get('url') or '') if isinstance(link, dict) else None
            if link:
                referenced[c].add(int(link[1]))
    # Candidate PR details, attributed to the first child that names them.
    wanted = {}
    for c in ordered:
        for pn in sorted(referenced[c] | owners[c]):
            wanted.setdefault(pn, c)
    prs = sorted(wanted)
    pr_detail = dict(zip(prs, r.all(lambda pn: r.detail(repo, f'pulls/{pn}', wanted[pn]), prs)))
    pr_refs = dict(zip(prs, refs(r, [pr_detail[pn] for pn in prs])))
    closers = {}
    for c in ordered:
        closers[c] = []
        for pn in sorted(referenced[c] | owners[c]):
            if c not in pr_refs[pn]:
                if pn in owners[c]:
                    defect('closing PR #%d no longer closes the child' % pn, c)
                continue  # a timeline reference alone is not closing evidence
            p = pr_detail[pn]
            if p['state'] != 'closed' or p['merged_at'] is None or p['base']['ref'] != head or p['base']['repo']['full_name'] != repo:
                defect('closing PR #%d is open, unmerged or on another base' % pn, c)
            closers[c].append(pn)
    evidence_jobs, seen = [], set()
    for c in ordered:
        for pn in closers[c]:
            for kind in ('comments', 'reviews'):
                if (pn, kind) not in seen:
                    seen.add((pn, kind))
                    evidence_jobs.append((c, pn, kind))
    evidence = {}
    for (c, pn, kind), rows in zip(evidence_jobs, r.all(
            lambda j: r.collection(repo, f'issues/{j[1]}/comments' if j[2] == 'comments' else f'pulls/{j[1]}/reviews', child=j[0]),
            evidence_jobs)):
        evidence[(pn, kind)] = rows

    names = [write_context(root, 'release', 'release', detail, issues, comments, reviews)]
    for c in ordered:
        local = comment_rows(loaded[(c, 'comments')], 0)
        child_comments, child_reviews = [], []
        for pn in closers[c]:
            p = pr_detail[pn]
            child_comments.append((p['created_at'], 1, p['body']))
            child_comments.extend(comment_rows(evidence[(pn, 'comments')], 2))
            child_reviews.extend(comment_rows(evidence[(pn, 'reviews')], 3, True))
        # The issue's empty pseudo description introduces no evidence.
        empty = dict(found[c], title='', body='')
        names.append(write_context(root, 'child-' + str(c), 'child' if closers[c] else 'disposition',
                                   empty, local, child_comments, child_reviews, scopes))

    # Recheck participating details and scan every context, in one pool.
    # Classification itself depends on the excluded objects' first reads too.
    participating = [f'pulls/{number}', f'issues/{epic}'] + [f'issues/{c}' for c in numbers]
    participating += [f'pulls/{pn}' for pn in prs]
    participating = list(dict.fromkeys(participating))
    owner = {f'issues/{c}': c for c in numbers}
    owner.update({f'pulls/{pn}': wanted[pn] for pn in prs})

    def recheck(path):
        before = r.details[repo + '/' + path]
        after = r.api(repo + '/' + path, owner.get(path))
        if not isinstance(after, dict) or snapshot(after) != snapshot(before):
            raise Incomplete('detail snapshot changed')
        return None
    tasks = [('recheck', x) for x in participating] + [('scan', x) for x in names]
    outputs = r.all(lambda t: recheck(t[1]) if t[0] == 'recheck' else scan(r, root / t[1]), tasks)
    scanned = dict(zip(names, outputs[len(participating):]))

    def attributed(context, lines):
        out = {'role-played': [], 'model-record': []}
        for line in lines:
            for prefix in out:
                if line.startswith(prefix + ': '):
                    out[prefix].append(f'{prefix}: epic #{epic} {context} ' + line[len(prefix) + 2:])
                    break
            else:
                raise Incomplete('unexpected context scan output')
        return out
    release_ctx = f'release PR #{number}'
    contexts = [attributed(f'child #{c}', scanned['child-' + str(c)]) for c in ordered]
    contexts.append(attributed(release_ctx, scanned['release']))
    membership = [f'role-played: epic #{epic} ' + (f'child #{c}' if c else release_ctx) + ' ' + text
                  for c, text in sorted(findings, key=lambda f: (f[0], int((re.search(r'#([0-9]+)', f[1]) or [0, 0])[1]), f[1]))]
    blocks = membership + [x for ctx in contexts for x in ctx['role-played']]
    diagnostics = [x for ctx in contexts for x in ctx['model-record']]
    if blocks:
        lines = blocks + diagnostics
    else:
        lines = diagnostics + [
            f'model-record: epic #{epic} {release_ctx} a pipeline-override waived inherited stage absence for all children: skip={s}'
            for s in STAGES if 'skip=' + s in scopes]
        lines.append(f'model-record: epic #{epic} inherited Discovery, Planning, Test and Implementation checked for {len(ordered)} children')
    return {'version': 2, 'rows': [['out', x] for x in lines]}


def manifest(root):
    value = json.loads((root / 'manifest.json').read_text())
    if not isinstance(value, dict) or value.get('version') != 2:
        raise Incomplete('manifest version')
    if value.get('fetch_error'):
        print('fetch-error|' + value['fetch_error'] + '|' + str(value.get('issue', '')))
        return
    if value.get('unchecked'):
        print('unchecked\t' + value['unchecked'])
        return
    for kind, line in value['rows']:
        if kind != 'out' or '\n' in line:
            raise Incomplete('manifest row')
        print('out\t' + line)


def supervise(gate, number, root, remaining):
    # The outer deadline covers shell parsing too. Keep every output private
    # until the worker has completed successfully. Kill all descendants on
    # timeout, including subprocesses started in their own REST groups.
    r = Runner(gate, remaining)
    rc, raw, err = r.process(['bash', gate, '--epic-worker', str(root), number, str(remaining)], limit=remaining)
    if rc:
        raise Incomplete('worker failed')
    sys.stdout.buffer.write(raw)
    sys.stderr.write(err)


def main():
    mode = sys.argv[1]
    if mode == 'initial':
        r = Runner('', READ_SECONDS)
        try:
            rc, raw, err = r.process(sys.argv[2:])
        except Incomplete as error:
            sys.stderr.buffer.write(str(error).encode('utf-8', errors='surrogateescape'))
            sys.exit(1)
        if rc:
            sys.stderr.buffer.write(err.encode('utf-8', errors='surrogateescape'))
            sys.exit(1)
        sys.stdout.buffer.write(raw)
        sys.stderr.buffer.write(err.encode('utf-8', errors='surrogateescape'))
    elif mode == 'supervise':
        supervise(sys.argv[2], sys.argv[3], Path(sys.argv[4]), float(sys.argv[5]))
    elif mode == 'collect':
        gate, number, root, remaining = sys.argv[2:]
        root = Path(root)
        value = collect(gate, int(number), root, float(remaining))
        (root / 'manifest.json').write_text(json.dumps(value))
    elif mode == 'manifest':
        manifest(Path(sys.argv[2]))
    else:
        raise Incomplete('private mode')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:  # every failure is unchecked, never a pass
        print('epic traversal incomplete: ' + str(error), file=sys.stderr)
        sys.stdout.flush()
        sys.stderr.flush()
        os._exit(1)
    sys.stdout.flush()
    sys.stderr.flush()
    os._exit(0)
