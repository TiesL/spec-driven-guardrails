"""#594 public adoption/guard tests. All mutations stay in SANDBOX.

No Git write commands, network calls or model-record emitter. Minimal Git
metadata is fixture data, not a checkout of the developer's repository.
Manifest/provenance assertions deliberately do not prescribe a serialization.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import stat
import subprocess
import sys

ROOT = Path(sys.argv[1]).resolve()
SCENARIO = int(sys.argv[2])
TMP = Path(os.environ['SANDBOX']).resolve()
FILES = ('hooks/git-guardrails', 'hooks/read-command.py', 'hooks/rules.sh',
         'lib/markdown.sh', 'lib/changes.sh', 'lib/model-record.sh',
         'skills/pre-merge-review/model-record-gate.sh')
OLD_REV = '1' * 40
NEW_REV = '2' * 40


def require(ok, message):
    assert ok, message


def snapshot(path):
    paths = [path, *sorted(path.rglob('*'))] if path.exists() else []
    return {str(p.relative_to(path)): ('link', os.readlink(p)) if p.is_symlink()
            else ('file', stat.S_IMODE(p.stat().st_mode), p.read_bytes()) if p.is_file()
            else ('dir', stat.S_IMODE(p.stat().st_mode)) for p in paths}


def git_metadata(path, revision=None):
    g = path / '.git'
    (g / 'objects').mkdir(parents=True)
    (g / 'refs/heads').mkdir(parents=True)
    (g / 'HEAD').write_text((revision or 'ref: refs/heads/main') + '\n')
    (g / 'config').write_text('[core]\nrepositoryformatversion = 0\nbare = false\n'
                             '[remote "origin"]\nurl = https://github.com/TiesL/spec-driven-guardrails.git\n')


WF = TMP / 'workflow'
shutil.copytree(ROOT, WF, symlinks=True, ignore=shutil.ignore_patterns(
    '.git', '.guardrails', '.agents', '.claude', '.codex', 'CLAUDE.md', 'wip', '__pycache__'))
git_metadata(WF, OLD_REV)
PROJECT = TMP / "project spaces ' dollar$"
PROJECT.mkdir()
git_metadata(PROJECT)
ENV = {k: v for k, v in os.environ.items()
       if not k.startswith(('CLAUDE_WORKFLOW_', 'GH_', 'GIT_')) and k != 'GITHUB_TOKEN'}
ENV.update(HOME=str(TMP / 'home'), CODEX_HOME=str(TMP / 'user-codex'),
           SPEC_DRIVEN_GUARDRAILS_DIR=str(WF), GIT_CONFIG_NOSYSTEM='1',
           GIT_CONFIG_GLOBAL=os.devnull, PYTHONDONTWRITEBYTECODE='1')
Path(ENV['CODEX_HOME']).mkdir()


def run(*args, cwd=WF, env=ENV, input=None):
    return subprocess.run(list(map(str, args)), cwd=cwd, env=env, input=input,
                          capture_output=True, text=True)


def adopt(*flags, rc=0, project=PROJECT):
    before = snapshot(Path(ENV['CODEX_HOME']))
    result = run(WF / 'adopt.sh', '--runtime', 'codex', *flags, project)
    require(result.returncode == rc,
            f'adoption expected exit {rc}, got {result.returncode}: {result.stdout}{result.stderr}')
    require(snapshot(Path(ENV['CODEX_HOME'])) == before, 'adoption changed CODEX_HOME')
    return result.stdout + result.stderr


def bundle():
    p = PROJECT / '.codex/sdg-guard'
    require(p.is_dir() and not p.is_symlink(), '--hooks did not install real .codex/sdg-guard directory')
    return p


def command():
    doc = json.loads((PROJECT / '.codex/hooks.json').read_text())
    return doc['hooks']['PreToolUse'][-1]['hooks'][0]['command']


def status(rc, state):
    before = snapshot(PROJECT)
    out = adopt('--status', rc=rc)
    require(snapshot(PROJECT) == before, 'status wrote project files')
    require(re.search(r'(?:bundle|sdg-guard)[^\n]*\b' + state + r'\b', out, re.I),
            f'status did not identify bundle as {state}: {out}')
    require('activation: unverified' in out, 'status omitted activation: unverified')
    return out


def list_files():
    # Architect gave an example filename, not a mandatory pathname. Locate
    # the plain hand-kept list by its entry-point row, without fixing its name.
    candidates = []
    for path in WF.rglob('*'):
        if not path.is_file() or path.is_symlink() or '.git' in path.parts:
            continue
        try:
            rows = [line.strip() for line in path.read_text().splitlines()
                    if line.strip() and not line.lstrip().startswith('#')]
        except UnicodeError:
            continue
        if 'hooks/git-guardrails' in rows:
            candidates.append((path, rows))
    require(candidates, 'hand-kept Codex guard bundle list is absent')
    require(len(candidates) == 1, 'multiple candidate guard bundle lists')
    path, names = candidates[0]
    require(len(names) == len(set(names)) and set(names) == set(FILES),
            f'bundle list must contain exactly the seven accepted paths: {names}')
    return names


def verify_manifest(b):
    path = b / 'MANIFEST'
    require(path.is_file(), 'bundle MANIFEST is absent')
    text = path.read_text()
    require(OLD_REV in text, 'MANIFEST omits source revision')
    # Accept text rows or JSON entries. Check association within each entry,
    # rather than accepting seven unrelated digests anywhere in the document.
    try:
        doc = json.loads(text)
    except ValueError:
        entries = text.splitlines()
    else:
        entries = []
        def walk(value, key=''):
            if isinstance(value, dict):
                for k, v in value.items():
                    entries.append(json.dumps({k: v})); walk(v, k)
            elif isinstance(value, list):
                for v in value:
                    entries.append(json.dumps(v)); walk(v)
        walk(doc)
    for name in FILES:
        digest = hashlib.sha256((b / name).read_bytes()).hexdigest()
        mode = stat.S_IMODE((b / name).stat().st_mode)
        modes = (str(mode), oct(mode), format(mode, 'o'), format(mode, '04o'))
        require(any(name in e and digest in e and any(m in e for m in modes) for e in entries),
                f'MANIFEST lacks associated sha256 and mode for {name}')


def guard_fixture():
    """Reuse #593's recording fake gh, never its setup/emitter or Git writes."""
    bindir = TMP / 'bin'
    bindir.mkdir()
    for name in ('bash', 'sh', 'env', 'git', 'python3', 'dirname', 'mktemp', 'rm',
                 'cat', 'grep', 'sed', 'awk', 'sort', 'tr', 'head', 'date', 'readlink'):
        source = shutil.which(name)
        if source:
            (bindir / name).symlink_to(source)
    fake = bindir / 'gh'
    fake.write_text('#!/bin/sh\nexec ' + shlex.quote(shutil.which('python3')) + ' ' +
                    shlex.quote(str(ROOT / 'test/fixtures/merge-repo-593.py')) + ' --fake-gh "$@"\n')
    fake.chmod(0o755)
    env = {k: ENV[k] for k in ('HOME', 'CODEX_HOME', 'GIT_CONFIG_NOSYSTEM', 'GIT_CONFIG_GLOBAL')}
    env.update(PATH=str(bindir), TMPDIR=str(TMP), PYTHONDONTWRITEBYTECODE='1')
    for name in ('STATE', 'CALLS', 'ERRORS'):
        env['REPO593_' + name] = str(TMP / name.lower())
    (PROJECT / 'WORKFLOW-ADOPTION.md').write_text(
        '| quality-review-before-merge | yes | date | fixture |\n'
        '| process-multi-agent-roles | yes | date | fixture |\n')
    sub = PROJECT / 'different working directory'
    sub.mkdir()
    # Synthetic evidence, never emitted or posted as role reports.
    rows = []
    for index, stage in enumerate(('Discovery', 'Planning', 'Test', 'Implementation', 'Review')):
        marker = '<!-- model-record: stage=' + stage + ' model="gpt-6.1-sol"'
        if stage == 'Review':
            marker += ' floor-basis="Same model as Implementation."'
        rows.append(f'2026-10-0{index + 2}T00:00:00Z\t{marker} -->')
    def invoke(guard, kind='role', cmd='gh pr merge 41', installed=False, merge_only=True):
        Path(env['REPO593_STATE']).write_text(json.dumps(
            dict(kind=kind, conflict=False, failure='', stage_rows='\n'.join(rows))))
        for name in ('CALLS', 'ERRORS'):
            Path(env['REPO593_' + name]).write_text('')
        payload = json.dumps(dict(hook_event_name='PreToolUse', tool_name='Bash',
                                  cwd=str(sub), tool_input=dict(command=cmd)))
        args = ['bash', '-c', guard] if installed else [str(guard)] + (['--merge-only'] if merge_only else [])
        result = run(*args, cwd=sub, env=env, input=payload)
        require(not Path(env['REPO593_ERRORS']).read_text(), 'unsupported #593 fake-gh request')
        return result.returncode, result.stdout, result.stderr
    return invoke


def parity(target, invoke, installed=False):
    reasons = {'missing': 'without a review marker for the current commit',
               'fail': 'ci-593: fail', 'pending': 'ci-593: pending',
               'stale': 'behind its base', 'role': 'role-played run', 'eligible': ''}
    for kind, reason in reasons.items():
        for cmd in ('gh pr merge 41', 'gh pr merge 41 --repo TiesL/spec-driven-guardrails'):
            source = invoke(WF / 'hooks/git-guardrails', kind, cmd)
            require(source[0] == (0 if kind == 'eligible' else 2) and reason in source[2],
                    f'{kind}: source fixture did not reach intended verdict: {source}')
            require(not source[1] and 'warning:' not in source[2].lower(),
                    f'{kind}: source fixture unexpectedly warned: {source}')
            actual = invoke(target, kind, cmd, installed=installed)
            require(actual == source, f'{kind}: bundled stdout/stderr/exit differ: {actual} != {source}')
    for cmd in ('git reset --hard', 'git clean -fd', 'git push origin main', 'printf hello'):
        require(invoke(target, cmd=cmd, installed=installed) == (0, '', ''),
                f'merge-only bundle acquired unrelated check: {cmd}')



# A47 fault injection lives only in the disposable interpreter. Events name
# persisted records and filesystem operations, never private product functions.
INJECTOR = r"""
import ctypes
import errno
import json
import os
from pathlib import Path
import time
project = Path(os.environ['FAULT_PROJECT'])
receipt = Path(os.environ['FAULT_RECEIPT'])
point = os.environ['FAULT_POINT']
side = os.environ.get('FAULT_SIDE', 'before')
record = project / '.guardrails/installation.json'
def hit(event, when):
    if event != point or when != side:
        return
    receipt.write_text(event + ':' + when)
    if os.environ.get('FAULT_PAUSE'):
        deadline = time.monotonic() + 12
        while not Path(os.environ['FAULT_RELEASE']).exists():
            if time.monotonic() > deadline:
                os._exit(87)
            time.sleep(0.02)
        return
    os._exit(86)
def stage_path(value):
    try:
        return Path(os.fsdecode(value)).is_relative_to(project / '.codex') and '.sdg-guard-stage-' in os.fsdecode(value)
    except TypeError:
        return False
for operation in ('replace', 'rename'):
    original = getattr(os, operation)
    def replacement(src, dst, *args, _original=original, **kwargs):
        event = None
        if Path(os.fsdecode(dst)) == record:
            try:
                doc = json.loads(Path(src).read_text())
                tx = doc.get('guard_bundle_transaction')
                event = 'record-' + (tx['phase'] if tx else 'clear')
            except (OSError, ValueError, KeyError, TypeError):
                pass
        hit(event, 'before')
        result = _original(src, dst, *args, **kwargs)
        hit(event, 'after')
        return result
    setattr(os, operation, replacement)
original_write = Path.write_bytes
def write(self, data):
    if stage_path(self) and str(self).endswith('/hooks/rules.sh'):
        hit('stage-write', 'before')
        result = original_write(self, data)
        hit('stage-write', 'after')
        return result
    return original_write(self, data)
Path.write_bytes = write
for operation in ('unlink', 'remove', 'rmdir'):
    original = getattr(os, operation)
    def removal(path, *args, _original=original, _operation=operation, **kwargs):
        event = None
        if stage_path(path):
            path = Path(path)
            event = ('delete-stage' if _operation == 'rmdir' and path.name.startswith('.sdg-guard-stage-')
                     else 'delete-directory' if _operation == 'rmdir'
                     else 'delete-manifest' if path.name == 'MANIFEST' else 'delete-payload')
            # A47's retained evidence is an independent deletion-order oracle.
            if path.name == 'MANIFEST':
                remaining = list(path.parent.iterdir())
                if remaining != [path]:
                    receipt.write_text('MANIFEST removed before old payload/directories')
                    os._exit(88)
        hit(event, 'before')
        result = _original(path, *args, **kwargs)
        hit(event, 'after')
        return result
    setattr(os, operation, removal)
# Intercept the two A47 platform exchanges, including libc syscall fallback.
# Proxies preserve ctypes argtypes/restype assignment and native return values.
class Exchange:
    def __init__(self, native):
        object.__setattr__(self, 'native', native)
    def __setattr__(self, name, value):
        setattr(self.native, name, value)
    def __call__(self, *args):
        paths = []
        for arg in args:
            value = getattr(arg, 'value', arg)
            if isinstance(value, bytes):
                paths.append(os.fsdecode(value))
        active = str(project / '.codex/sdg-guard')
        relevant = active in paths and any('.sdg-guard-stage-' in p for p in paths)
        if relevant:
            if point == 'unsupported-exchange':
                receipt.write_text('unsupported-exchange')
                ctypes.set_errno(errno.ENOSYS)
                return -1
            hit('exchange', 'before')
        result = self.native(*args)
        if relevant and result == 0:
            hit('exchange', 'after')
        return result
original_get = ctypes.CDLL.__getattr__
def get(self, name):
    value = original_get(self, name)
    if name in ('renameatx_np', 'renameat2', 'syscall'):
        value = Exchange(value)
        setattr(self, name, value)
    return value
ctypes.CDLL.__getattr__ = get
"""


def record_path():
    return PROJECT / '.guardrails/installation.json'


def record():
    return json.loads(record_path().read_text())


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def changed_source(revision=NEW_REV):
    path = WF / 'hooks/rules.sh'
    path.write_bytes(path.read_bytes() + ('\n# generation ' + revision + '\n').encode())
    (WF / '.git/HEAD').write_text(revision + '\n')


def policy_control():
    adopt('--hooks')
    invoke = guard_fixture()
    baseline = invoke(command(), kind='missing', installed=True)
    require(baseline[0] == 2 and 'without a review marker for the current commit' in baseline[2],
            f'missing-review control did not reach policy refusal: {baseline}')
    print('GREEN control: installed missing-review refusal has exit 2', flush=True)
    return invoke, baseline


def policy_same(invoke, baseline, label):
    actual = invoke(command(), kind='missing', installed=True)
    require(actual == baseline, f'{label}: interrupted policy stdout/stderr/exit changed: {actual} != {baseline}')


def fault_env(point, side='before', pause=False):
    injection = TMP / 'transaction-injection'
    injection.mkdir(exist_ok=True)
    (injection / 'sitecustomize.py').write_text(INJECTOR)
    receipt = TMP / 'transaction-receipt'
    receipt.unlink(missing_ok=True)
    release = TMP / 'writer-release'
    release.unlink(missing_ok=True)
    return dict(ENV, PYTHONPATH=str(injection), FAULT_PROJECT=str(PROJECT),
                FAULT_POINT=point, FAULT_SIDE=side, FAULT_RECEIPT=str(receipt),
                FAULT_PAUSE='1' if pause else '', FAULT_RELEASE=str(release))


def interrupt(point, side, invoke, baseline):
    env = fault_env(point, side)
    result = run(WF / 'adopt.sh', '--runtime', 'codex', '--hooks', PROJECT, env=env)
    policy_same(invoke, baseline, point + ':' + side)
    receipt = Path(env['FAULT_RECEIPT'])
    require(receipt.exists() and receipt.read_text() == point + ':' + side,
            f'{point}:{side}: required transaction interruption point not reached')
    require(result.returncode != 0, f'{point}:{side}: interrupted refresh reported success')
    print(f'injected {point}:{side}; exact installed policy preserved', flush=True)


def complete(invoke, baseline):
    adopt('--hooks')
    status(0, 'current')
    rec = record()
    require(rec['version'] == 4 and rec['guard_bundle_transaction'] is None,
            'successful explicit retry did not clear version-4 transaction')
    require(not list((PROJECT / '.codex').glob('.sdg-guard-stage-*')),
            'successful explicit retry left staging artifacts')
    require(rec['guard_bundle']['manifest_sha256'] == digest(bundle() / 'MANIFEST'),
            'committed digest does not authenticate active MANIFEST')
    policy_same(invoke, baseline, 'completed retry')


def seed_transaction(phase='preparing', arrangement='old', partial=False):
    """Build genuine manifests through adoption, then seed specified A47 state.

    No product helpers or historical source snapshot are used for recovery.
    """
    old = TMP / 'old-generation'
    shutil.copytree(bundle(), old)
    changed_source()
    other = TMP / 'new-project'; other.mkdir(); git_metadata(other)
    adopt('--hooks', project=other)
    new = other / '.codex/sdg-guard'
    stage = PROJECT / '.codex/.sdg-guard-stage-QA594'
    if arrangement == 'old':
        shutil.copytree(new, stage)
    else:
        shutil.copytree(old, stage)
        shutil.rmtree(bundle())
        shutil.copytree(new, PROJECT / '.codex/sdg-guard')
    tx = dict(phase=phase, staging_path=str(stage.relative_to(PROJECT)),
              old_manifest_sha256=digest(old / 'MANIFEST'),
              new_manifest_sha256=digest(new / 'MANIFEST'))
    rec = record()
    rec.update(version=4, guard_bundle_transaction=tx)
    rec['guard_bundle']['manifest_sha256'] = tx['new_manifest_sha256' if phase == 'cleanup' else 'old_manifest_sha256']
    record_path().write_text(json.dumps(rec))
    if partial:
        (stage / 'hooks/rules.sh').write_bytes(b'')
    return stage, tx


def pending_read_only(flags, classification, invoke, baseline):
    before = snapshot(PROJECT)
    result = run(WF / 'adopt.sh', '--runtime', 'codex', *flags, PROJECT)
    out = result.stdout + result.stderr
    require(result.returncode == 1 and 'recovery pending' in out.lower(),
            f'{flags}: valid transaction must report recovery pending with exit 1: {out}')
    require(re.search(r'(?:bundle|sdg-guard)[^\n]*\b' + classification + r'\b', out, re.I),
            f'{flags}: pending transaction lost {classification} content classification: {out}')
    require('activation: unverified' in out, 'pending status omits unverified activation')
    require('TiesL' in out and 'outside' in out and 'sandbox' in out,
            'pending status omits explicit recovery by TiesL outside sandbox')
    require(snapshot(PROJECT) == before, f'{flags}: pending transaction or staging changed')
    policy_same(invoke, baseline, 'read-only pending')


def conflict_unchanged(label, offending=None):
    before = snapshot(PROJECT)
    result = run(WF / 'adopt.sh', '--runtime', 'codex', '--hooks', PROJECT)
    out = result.stdout + result.stderr
    require(result.returncode == 1 and 'conflict' in out.lower(), f'{label}: expected ownership conflict exit 1: {out}')
    if offending:
        require(offending in out, f'{label}: refusal omitted offending path {offending}: {out}')
    require(snapshot(PROJECT) == before, f'{label}: conflict wrote project files')


def transaction_scenario():
    import time
    invoke, baseline = policy_control()
    if SCENARIO in (420, 421, 423, 424):
        points = {420: ('record-preparing',), 421: ('record-ready',),
                  423: ('record-cleanup',),
                  424: ('delete-payload', 'delete-directory', 'delete-manifest', 'delete-stage', 'record-clear')}[SCENARIO]
        backup = TMP / 'initial-project'; shutil.copytree(PROJECT, backup, symlinks=True)
        old_digest = digest(bundle() / 'MANIFEST')
        changed_source()
        for point in points:
            for side in ('before', 'after'):
                shutil.rmtree(PROJECT); shutil.copytree(backup, PROJECT, symlinks=True)
                interrupt(point, side, invoke, baseline)
                rec = record(); tx = rec.get('guard_bundle_transaction')
                if point in ('record-preparing', 'record-ready'):
                    require(digest(bundle() / 'MANIFEST') == old_digest,
                            point + ': active generation changed before exchange')
                if point == 'record-preparing':
                    require(tx is None if side == 'before' else tx and tx['phase'] == 'preparing',
                            'preparation record interruption exposed neither expected complete record')
                if point == 'record-ready':
                    require(tx and tx['phase'] == ('preparing' if side == 'before' else 'ready'),
                            'ready record interruption exposed wrong phase')
                    require(digest(PROJECT / tx['staging_path'] / 'MANIFEST') == tx['new_manifest_sha256'],
                            'ready record did not retain verified new staging')
                if point == 'record-cleanup':
                    require(tx and tx['phase'] == ('ready' if side == 'before' else 'cleanup'),
                            'ownership replacement exposed wrong phase')
                    require(digest(bundle() / 'MANIFEST') == tx['new_manifest_sha256'],
                            'ownership commit occurred before new active generation')
                    require(digest(PROJECT / tx['staging_path'] / 'MANIFEST') == tx['old_manifest_sha256'],
                            'ownership commit did not preserve complete old staging')
                if tx:
                    committed = tx['new_manifest_sha256' if tx['phase'] == 'cleanup' else 'old_manifest_sha256']
                    require(rec['guard_bundle']['manifest_sha256'] == committed,
                            'record phase and committed ownership digest disagree')
                if point.startswith('delete-'):
                    require(tx and tx['phase'] == 'cleanup', 'old generation removed before ownership commit')
                    stage = PROJECT / tx['staging_path']
                    if point in ('delete-payload', 'delete-directory'):
                        require(digest(stage / 'MANIFEST') == tx['old_manifest_sha256'],
                                'cleanup removed old MANIFEST before payload/directories')
                    if point == 'delete-stage' or (point == 'delete-manifest' and side == 'after'):
                        require(not stage.exists() or not list(stage.iterdir()), 'MANIFEST removed before old stage was empty')
                if point == 'record-clear':
                    require(not list((PROJECT / '.codex').glob('.sdg-guard-stage-*')),
                            'transaction cleared before old stage was absent')
                complete(invoke, baseline)
    elif SCENARIO == 422:
        backup = TMP / 'initial-project'; shutil.copytree(PROJECT, backup, symlinks=True)
        old_digest = digest(bundle() / 'MANIFEST'); changed_source()
        for side in ('before', 'after'):
            shutil.rmtree(PROJECT); shutil.copytree(backup, PROJECT, symlinks=True)
            interrupt('exchange', side, invoke, baseline)
            tx = record()['guard_bundle_transaction']; stage = PROJECT / tx['staging_path']
            require(tx['phase'] == 'ready', 'exchange interruption lost ready record')
            require(digest(bundle() / 'MANIFEST') == (old_digest if side == 'before' else tx['new_manifest_sha256']),
                    'exchange interruption left wrong active generation')
            require(digest(stage / 'MANIFEST') == (tx['new_manifest_sha256'] if side == 'before' else old_digest),
                    'exchange interruption left wrong staged generation')
            complete(invoke, baseline)
    elif SCENARIO == 425:
        stage, tx = seed_transaction(partial=True)
        interrupt('stage-write', 'after', invoke, baseline)
        require(record()['guard_bundle_transaction']['phase'] == 'preparing', 'interrupted recovery lost preparing phase')
        complete(invoke, baseline)
    elif SCENARIO == 426:
        stage, tx = seed_transaction(partial=True)
        changed_source('3' * 40)
        interrupt('record-ready', 'before', invoke, baseline)
        new_tx = record()['guard_bundle_transaction']
        require(new_tx['phase'] == 'preparing' and new_tx['new_manifest_sha256'] != tx['new_manifest_sha256'],
                'retry did not record new target digest from current source')
        require(new_tx['old_manifest_sha256'] == tx['old_manifest_sha256'] and new_tx['staging_path'] == tx['staging_path'],
                'retry changed old digest or exact staging path')
        require(digest(stage / 'MANIFEST') == new_tx['new_manifest_sha256'], 'rebuilt stage differs from retargeted digest')
        require('3' * 40 in (stage / 'MANIFEST').read_text(), 'retry retained historical source revision')
        require((stage / 'hooks/rules.sh').read_bytes() == (WF / 'hooks/rules.sh').read_bytes(), 'retry retained historical source bytes')
        complete(invoke, baseline)
    elif SCENARIO == 427:
        stage, tx = seed_transaction()
        target = bundle() / 'hooks/rules.sh'; target.write_bytes(target.read_bytes() + b'\n# tampering\n')
        conflict_unchanged('tampered active despite transaction', '.codex/sdg-guard')
        policy_same(invoke, baseline, 'tamper refusal')
        # Restore fixture tampering, then prove explicit recovery is still possible.
        shutil.copy2(TMP / 'old-generation/hooks/rules.sh', target)
        complete(invoke, baseline)
    elif SCENARIO == 428:
        stage, tx = seed_transaction()
        pending_read_only(('--status',), 'stale', invoke, baseline)
        good = record()
        mutations = [[], {}, dict(tx, phase='unknown'), dict(tx, phase=3),
                     dict(tx, staging_path='/tmp/foreign'), dict(tx, staging_path='.codex/../foreign'),
                     dict(tx, staging_path='.codex/.sdg-guard-stage-'), dict(tx, staging_path='.codex/.sdg-guard-stage-a/b'),
                     dict(tx, old_manifest_sha256='A' * 64), dict(tx, new_manifest_sha256=3),
                     dict(tx, extra=True), {k: v for k, v in tx.items() if k != 'phase'},
                     dict(tx, new_manifest_sha256=tx['old_manifest_sha256'])]
        for bad in mutations:
            rec = dict(good, guard_bundle_transaction=bad)
            record_path().write_text(json.dumps(rec))
            conflict_unchanged('malformed transaction ' + repr(bad))
        rec = dict(good); rec['guard_bundle'] = dict(good['guard_bundle'], manifest_sha256='0' * 64)
        record_path().write_text(json.dumps(rec)); conflict_unchanged('inconsistent committed digest')
        record_path().write_text(json.dumps(good)); complete(invoke, baseline)
    elif SCENARIO == 429:
        stage, tx = seed_transaction(partial=True)
        outside = TMP / 'foreign-target'; outside.mkdir(); (outside / 'sentinel').write_text('foreign')
        baseline_tree = snapshot(outside)
        for parent in (stage, bundle()):
            target = parent / 'hooks/rules.sh'; saved = target.read_bytes(); mode = stat.S_IMODE(target.stat().st_mode)
            target.unlink(); target.symlink_to(outside / 'sentinel')
            conflict_unchanged('symlink transaction entry', str(target.relative_to(PROJECT)))
            require(snapshot(outside) == baseline_tree, 'transaction followed external symlink')
            target.unlink(); target.write_bytes(saved); target.chmod(mode)
        # The stage itself must also never be followed or removed.
        saved_stage = TMP / 'saved-stage'; stage.rename(saved_stage); stage.symlink_to(outside, target_is_directory=True)
        conflict_unchanged('symlink stage', tx['staging_path'])
        require(snapshot(outside) == baseline_tree, 'stage symlink target changed')
        stage.unlink(); saved_stage.rename(stage)
        complete(invoke, baseline)
    elif SCENARIO == 430:
        old = snapshot(bundle()); changed_source()
        env = fault_env('unsupported-exchange')
        result = run(WF / 'adopt.sh', '--runtime', 'codex', '--hooks', PROJECT, env=env)
        receipt = Path(env['FAULT_RECEIPT'])
        require(receipt.exists(), 'unsupported atomic exchange injector not reached')
        require(result.returncode == 1, 'unsupported exchange must refuse refresh with exit 1')
        require(snapshot(bundle()) == old, 'unsupported exchange changed active bundle')
        policy_same(invoke, baseline, 'unsupported exchange')
        complete(invoke, baseline)
    elif SCENARIO == 431:
        changed_source(); env = fault_env('record-preparing', 'after', pause=True)
        child = subprocess.Popen([str(WF / 'adopt.sh'), '--runtime', 'codex', '--hooks', str(PROJECT)],
                                 cwd=WF, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            deadline = time.monotonic() + 6
            receipt = Path(env['FAULT_RECEIPT'])
            while not receipt.exists() and child.poll() is None and time.monotonic() < deadline:
                time.sleep(0.02)
            require(receipt.exists(), 'overlapping-writer control never reached locked preparing transition')
            before = snapshot(PROJECT)
            for flags in ((), ('--hooks',)):
                result = run(WF / 'adopt.sh', '--runtime', 'codex', *flags, PROJECT)
                require(result.returncode == 1, f'overlapping writer {flags} did not refuse')
                require(snapshot(PROJECT) == before, f'overlapping writer {flags} wrote adoption files')
            policy_same(invoke, baseline, 'paused writer')
        finally:
            Path(env['FAULT_RELEASE']).touch()
            child.communicate(timeout=15)
        complete(invoke, baseline)
    elif SCENARIO in (432, 433):
        phase = 'preparing' if SCENARIO == 432 else 'cleanup'
        stage, tx = seed_transaction(phase, 'old' if phase == 'preparing' else 'new', partial=phase == 'preparing')
        for flags in ((), ('--status',)):
            pending_read_only(flags, 'stale' if phase == 'preparing' else 'current', invoke, baseline)
        complete(invoke, baseline)
    elif SCENARIO == 434:
        historical = TMP / 'historical-start'
        shutil.copytree(PROJECT, historical, symlinks=True)
        failures = []
        for version in (1, 2, 3):
            shutil.rmtree(PROJECT)
            # Construct each exact historical schema from an actual installation.
            shutil.copytree(historical, PROJECT, symlinks=True)
            rec = record()
            rec.pop('guard_bundle_transaction', None); rec['version'] = version
            if version < 3:
                rec.pop('guard_bundle', None); shutil.rmtree(bundle())
                ignore = PROJECT / '.gitignore'
                ignore.write_text(ignore.read_text().replace('/.codex/sdg-guard\n', ''))
                old_group = {'matcher': 'Bash', 'hooks': [{'type': 'command', 'command':
                    shlex.quote(str(PROJECT / '.guardrails/source/hooks/git-guardrails')) + ' --merge-only'}]}
                if version == 1:
                    rec.pop('managed_hook', None); (PROJECT / '.codex/hooks.json').unlink()
                else:
                    rec['managed_hook'] = old_group
                    (PROJECT / '.codex/hooks.json').write_text(json.dumps({'hooks': {'PreToolUse': [old_group]}}))
            record_path().write_text(json.dumps(rec, indent=2, sort_keys=True) + '\n')
            before = snapshot(PROJECT)
            # Version 2's owned source-path command is readable but stale.
            out = adopt('--status', rc=1 if version == 2 else 0)
            require('malformed/foreign provenance' not in out, f'version {version}: historical record rejected')
            require(snapshot(PROJECT) == before, f'version {version}: status upgraded provenance')
            adopt()
            require(record()['version'] == version, f'version {version}: default adoption upgraded provenance')
            print(f'GREEN control: version {version} read without implicit upgrade', flush=True)
            out = adopt('--hooks')
            if record()['version'] != 4:
                failures.append(f'version {version}: explicit bundle adoption did not upgrade to version 4')
                continue
            require('upgrade' in out.lower() and '4' in out, f'version {version}: upgrade not reported')
            complete(invoke, baseline)
        require(not failures, '; '.join(failures))
    elif SCENARIO == 435:
        status(0, 'current')
        # Valid default absence and invalid input remain separate exit controls.
        absent = TMP / 'default-project'; absent.mkdir(); git_metadata(absent)
        adopt(project=absent); adopt('--status', project=absent)
        invalid = TMP / 'not-a-project'; invalid.mkdir()
        result = run(WF / 'adopt.sh', '--runtime', 'codex', '--status', invalid)
        require(result.returncode == 2, 'invalid input did not exit 2')
        changed_source(); status(1, 'stale')
        # Seed helper expects unchanged old source; it still creates a distinct new digest.
        stage, tx = seed_transaction()
        pending_read_only(('--status',), 'stale', invoke, baseline)
        complete(invoke, baseline)


def current_directory_adoption():
    failures = []
    env = dict(ENV)
    env.pop('SDG_ADOPTION_LOCK_FD', None)
    for runtime, flags in (('claude', ()), ('codex', ('--runtime', 'codex'))):
        project = TMP / ('no-project-argument-' + runtime)
        project.mkdir(); git_metadata(project)
        before_home = snapshot(Path(env['HOME']))
        before_codex = snapshot(Path(env['CODEX_HOME']))
        result = run('/bin/bash', WF / 'adopt.sh', *flags, cwd=project, env=env)
        if result.returncode != 0:
            failures.append(f'{runtime}: current-directory adoption expected exit 0, got '
                            f'{result.returncode}: {result.stdout}{result.stderr}')
            continue
        for name in ('PRD.md', 'TEST-SCENARIOS.md', 'WORKFLOW-ADOPTION.md', '.gitignore'):
            require((project / name).is_file(), f'{runtime}: adoption omitted {name}')
        for name in ('pre-commit', 'commit-msg', 'pre-push'):
            require(os.access(project / '.git/hooks' / name, os.X_OK),
                    f'{runtime}: adoption omitted executable native hook {name}')
        if runtime == 'claude':
            require((project / 'CLAUDE.md').resolve() == WF / 'WORKFLOW.md',
                    'claude: adoption omitted workflow instructions')
            require((project / '.claude/settings.json').resolve() == WF / 'settings/session-hooks.json',
                    'claude: adoption omitted settings link')
        else:
            source = project / '.guardrails/source'
            require(source.is_symlink() and source.resolve() == WF,
                    'codex: adoption did not link workflow source')
            require('spec-driven-guardrails: begin' in (project / 'AGENTS.md').read_text(),
                    'codex: adoption omitted managed instructions')
            require(json.loads((project / '.guardrails/installation.json').read_text())['runtime'] == 'codex',
                    'codex: adoption omitted runtime provenance')
            require(not (project / '.codex/sdg-guard').exists(),
                    'codex: default adoption installed opt-in guard bundle')
        require(snapshot(Path(env['HOME'])) == before_home and
                snapshot(Path(env['CODEX_HOME'])) == before_codex,
                f'{runtime}: project adoption changed user configuration')
        print(f'GREEN control: {runtime} current-directory adoption postconditions', flush=True)
    require(not failures, '; '.join(failures))


def lock_environment_scenario(kind):
    import fcntl
    import time
    invoke, baseline = policy_control()
    # Normal public adoption already exercised the serializer's inherited FD.
    status(0, 'current')
    print('GREEN control: legitimate internally inherited lock completed adoption', flush=True)
    changed_source(); env = fault_env('record-preparing', 'after', pause=True)
    child = subprocess.Popen([str(WF / 'adopt.sh'), '--runtime', 'codex', '--hooks', str(PROJECT)],
                             cwd=WF, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    fd = None
    try:
        deadline = time.monotonic() + 6
        receipt = Path(env['FAULT_RECEIPT'])
        while not receipt.exists() and child.poll() is None and time.monotonic() < deadline:
            time.sleep(0.02)
        require(receipt.exists() and receipt.read_text() == 'record-preparing:after',
                'overlapping-writer control never reached locked preparing transition')
        require(child.poll() is None, 'lock holder exited before second writer')
        # Confirm the target really is locked, independently of its environment.
        target_fd = os.open(PROJECT, os.O_RDONLY)
        try:
            try:
                fcntl.flock(target_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                pass
            else:
                raise AssertionError('paused writer is not holding the target project lock')
        finally:
            os.close(target_fd)
        pass_fds = ()
        value = '999999'
        if kind == 'stale':
            fd = os.open(TMP, os.O_RDONLY)
            value = str(fd); os.close(fd); fd = None
        elif kind == 'unrelated':
            other = TMP / 'unrelated-project'; other.mkdir(); git_metadata(other)
            fd = os.open(other, os.O_RDONLY)
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            value = str(fd); pass_fds = (fd,)
        before = snapshot(PROJECT)
        result = subprocess.run([str(WF / 'adopt.sh'), '--runtime', 'codex', '--hooks', str(PROJECT)],
                                cwd=WF, env=dict(ENV, SDG_ADOPTION_LOCK_FD=value),
                                pass_fds=pass_fds, capture_output=True, text=True, timeout=10)
        unchanged = snapshot(PROJECT) == before
        print(f'{kind} descriptor: second writer exit {result.returncode}; '
              f'project unchanged={unchanged}', flush=True)
    finally:
        Path(env['FAULT_RELEASE']).touch()
        first_out, first_err = child.communicate(timeout=15)
        if fd is not None:
            os.close(fd)
    require(result.returncode != 0,
            f'{kind} SDG_ADOPTION_LOCK_FD={value}: overlapping writer expected nonzero exit, '
            f'got {result.returncode}; project unchanged={unchanged}')
    require(unchanged, f'{kind} SDG_ADOPTION_LOCK_FD={value}: overlapping writer changed project files')
    require(child.returncode == 0,
            f'legitimate inherited-lock writer failed after release: {first_out}{first_err}')
    complete(invoke, baseline)


def descendant_lock_scenario():
    import fcntl
    import time
    # This observer runs in the disposable writer interpreter, after the real
    # atomic replacement. It never changes the workflow source or lock state.
    injection = TMP / 'descendant-injection'
    injection.mkdir()
    (injection / 'sitecustomize.py').write_text(r'''
import json
import os
from pathlib import Path
import subprocess
import time
project = Path(os.environ['DESC_PROJECT'])
control = Path(os.environ['DESC_CONTROL'])
original_replace = os.replace
def wait(name):
    deadline = time.monotonic() + 20
    while not (control / name).exists():
        if time.monotonic() > deadline:
            os._exit(87)
        time.sleep(0.02)
def replace(src, dst, *args, **kwargs):
    result = original_replace(src, dst, *args, **kwargs)
    if Path(dst) == project / '.guardrails/installation.json':
        doc = json.loads(Path(dst).read_text())
        if (doc.get('guard_bundle_transaction') or {}).get('phase') == 'preparing':
            fd = int(os.environ['SDG_ADOPTION_LOCK_FD'])
            (control / 'paused').write_text(str(fd))
            wait('launch')
            env = {k: v for k, v in os.environ.items()
                   if not k.startswith('DESC_') and k != 'PYTHONPATH'}
            child = subprocess.run([os.environ['DESC_ADOPT'], '--runtime', 'codex',
                                    '--hooks', str(project)], env=env,
                                   pass_fds=(fd,), capture_output=True, text=True, timeout=10)
            (control / 'result').write_text(json.dumps(dict(
                rc=child.returncode, stdout=child.stdout, stderr=child.stderr)))
            wait('release')
    return result
os.replace = replace
''')
    adopt('--hooks')
    status(0, 'current')
    print('GREEN control: normal serializer re-execution completed adoption', flush=True)
    changed_source()
    control = TMP / 'descendant-control'
    control.mkdir()
    env = dict(ENV, PYTHONPATH=str(injection), DESC_PROJECT=str(PROJECT),
               DESC_CONTROL=str(control), DESC_ADOPT=str(WF / 'adopt.sh'))
    first = subprocess.Popen([str(WF / 'adopt.sh'), '--runtime', 'codex', '--hooks', str(PROJECT)],
                             cwd=WF, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    def await_file(name):
        deadline = time.monotonic() + 12
        while not (control / name).exists() and first.poll() is None and time.monotonic() < deadline:
            time.sleep(0.02)
        require((control / name).exists(), f'descendant harness never reached {name}')
        require(first.poll() is None, f'first writer exited before {name}')
    def locked():
        fd = os.open(PROJECT, os.O_RDONLY)
        try:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                return
            raise AssertionError('first writer does not hold the target project lock')
        finally:
            os.close(fd)
    try:
        await_file('paused')
        require(record()['guard_bundle_transaction']['phase'] == 'preparing',
                'first writer did not pause after preparing record replacement')
        locked()
        before = snapshot(PROJECT)
        (control / 'launch').touch()
        await_file('result')
        result = json.loads((control / 'result').read_text())
        locked()
        after = snapshot(PROJECT)
        changed = sorted(name for name in before.keys() | after.keys()
                         if before.get(name) != after.get(name))
        print(f'descendant writer exit {result["rc"]}; project unchanged={not changed}; '
              f'changed files={changed}', flush=True)
    finally:
        (control / 'release').touch()
        first_out, first_err = first.communicate(timeout=15)
    print(f'first writer after release exit {first.returncode}: {first_out}{first_err}', flush=True)
    # Always exercise the normal public path again, including recovery after
    # the current defect, before reporting the overlapping-writer assertion.
    adopt('--hooks')
    status(0, 'current')
    if result['rc'] == 0 and changed:
        require(first.returncode == 1 and
                'manifest digest or mode differs from ownership record' in first_out + first_err,
                f'defective overlap did not produce the predictable first-writer conflict: '
                f'{first.returncode}: {first_out}{first_err}')
    require(result['rc'] == 1,
            f'descendant overlapping writer expected exit 1, got {result["rc"]}; '
            f'project unchanged={not changed}; changed files={changed}')
    require(not changed, f'descendant overlapping writer changed project files: {changed}')
    require(first.returncode == 0,
            f'first writer failed after refused descendant: {first_out}{first_err}')


if SCENARIO == 444:
    descendant_lock_scenario()
elif SCENARIO == 440:
    current_directory_adoption()
elif SCENARIO in (441, 442, 443):
    lock_environment_scenario({441: 'invalid', 442: 'stale', 443: 'unrelated'}[SCENARIO])
elif SCENARIO >= 420:
    transaction_scenario()
elif SCENARIO == 397:
    adopt('--hooks')
    b = bundle()
    require({str(p.relative_to(b)) for p in b.rglob('*') if p.is_file()} == set(FILES) | {'MANIFEST'},
            'installed bundle contains missing or extra files')
    for name in FILES:
        require((b / name).read_bytes() == (WF / name).read_bytes(), f'{name}: bytes differ')
        require(stat.S_IMODE((b / name).stat().st_mode) == stat.S_IMODE((WF / name).stat().st_mode),
                f'{name}: modes differ')
        require(str(WF).encode() not in (b / name).read_bytes(), f'{name}: contains clone path')
    verify_manifest(b)
    require('.codex/sdg-guard/hooks/git-guardrails' in command() and '--merge-only' in command()
            and '.guardrails/source' not in command(), 'hook command does not target bundle')
    before = snapshot(PROJECT)
    adopt('--hooks')
    require(snapshot(PROJECT) == before, 'repeated --hooks changed installation')
elif SCENARIO == 398:
    adopt()
    require(not (PROJECT / '.codex/sdg-guard').exists(), 'default adoption created a bundle')
elif SCENARIO == 399:
    for variant in ('parent', 'bundle', 'inner'):
        q = TMP / variant; q.mkdir(); git_metadata(q)
        outside = TMP / ('target-' + variant); outside.mkdir()
        codex = q / '.codex'
        if variant == 'parent':
            codex.symlink_to(outside, target_is_directory=True); offending = '.codex'
        else:
            codex.mkdir()
            if variant == 'bundle':
                (codex / 'sdg-guard').symlink_to(outside, target_is_directory=True)
                offending = '.codex/sdg-guard'
            else:
                (codex / 'sdg-guard').mkdir()
                (outside / 'sentinel').write_text('foreign\n')
                (codex / 'sdg-guard/inner').symlink_to(outside / 'sentinel')
                offending = '.codex/sdg-guard/inner'
        (q / 'AGENTS.md').write_text('must survive preflight\n')
        before, target_before = snapshot(q), snapshot(outside)
        result = run(WF / 'adopt.sh', '--runtime', 'codex', '--hooks', q)
        require(result.returncode == 1, f'{variant}: symlink adoption must refuse, got {result.returncode}')
        require(offending in result.stdout + result.stderr, f'{variant}: refusal omitted offending path {offending}')
        require(snapshot(q) == before and snapshot(outside) == target_before, f'{variant}: refusal wrote files')
elif SCENARIO == 400:
    adopt('--hooks')
    invoke = guard_fixture()
    parity(WF / 'hooks/git-guardrails', invoke)  # validate all source controls before feature assertion
    require('.codex/sdg-guard/' in command(), 'installed command still targets source instead of bundle')
    parity(command(), invoke, installed=True)
    (PROJECT / '.guardrails/source').unlink()
    parity(command(), invoke, installed=True)
    (PROJECT / '.guardrails/source').symlink_to(TMP / 'missing-source')
    parity(command(), invoke, installed=True)
elif SCENARIO == 401:
    adopt('--hooks'); b = bundle()
    foreign = PROJECT / '.codex/foreign.txt'; foreign.write_text('foreign\n')
    before_command = command(); before = snapshot(b)
    changed = WF / 'hooks/rules.sh'; changed.write_text(changed.read_text() + '\n# refresh fixture\n')
    (WF / '.git/HEAD').write_text(NEW_REV + '\n')
    adopt()
    require(snapshot(b) == before, 'default adoption refreshed or removed bundle')
    project_before = snapshot(PROJECT)
    out = adopt('--hooks')
    project_after = snapshot(PROJECT)
    altered = {name for name in project_before.keys() | project_after.keys()
               if project_before.get(name) != project_after.get(name)}
    require(all(name == '.guardrails/installation.json' or name.startswith('.codex/sdg-guard/')
                for name in altered), f'refresh wrote outside owned bundle/record: {altered}')
    require((b / 'hooks/rules.sh').read_bytes() == changed.read_bytes(), 'explicit refresh did not copy changed file')
    require(foreign.read_text() == 'foreign\n' and command() == before_command, 'refresh changed foreign file or command')
    for name in FILES:
        if name != 'hooks/rules.sh':
            require(snapshot(b)[name] == before[name], f'refresh changed unrelated file {name}')
    require(all(s in out for s in ('hooks/rules.sh', OLD_REV, NEW_REV)), 'refresh omits changed path or old/new revisions')
    require(re.search(r'trust[^\n]*(?:not re-prompted|not reprompted)', out, re.I), 'refresh omits trust is not re-prompted')
    status(0, 'current')
elif SCENARIO == 402:
    adopt('--hooks')
    recpath = PROJECT / '.guardrails/installation.json'
    rec = json.loads(recpath.read_text())
    old_group = {'matcher': 'Bash', 'hooks': [{'type': 'command', 'command':
        shlex.quote(str(PROJECT / '.guardrails/source/hooks/git-guardrails')) + ' --merge-only'}]}
    old_rec = {k: rec[k] for k in ('owner', 'runtime', 'checkout', 'links')}
    old_rec.update(version=2, managed_hook=old_group)
    recpath.write_text(json.dumps(old_rec))
    (PROJECT / '.codex/hooks.json').write_text(json.dumps({'hooks': {'PreToolUse': [old_group]}}))
    b = PROJECT / '.codex/sdg-guard'
    if b.exists(): shutil.rmtree(b)
    out = adopt('--hooks')
    require('.codex/sdg-guard/' in command(), 'owned version-2 hook was not migrated to bundle')
    require(json.loads(recpath.read_text())['version'] > 2, 'older provenance did not upgrade')
    require('/hooks' in out and re.search(r'(?:review|trust)', out, re.I), 'migration omitted one-time /hooks review/trust')
    before = snapshot(PROJECT); adopt('--hooks')
    require(snapshot(PROJECT) == before, 'migration repeated or duplicated definition')
elif SCENARIO == 403:
    adopt(); status(0, 'absent')
    adopt('--hooks'); b = bundle(); status(0, 'current')
    changed = WF / 'hooks/rules.sh'; changed.write_text(changed.read_text() + '\n# stale fixture\n')
    (WF / '.git/HEAD').write_text(NEW_REV + '\n')
    out = status(1, 'stale')
    require('outside' in out.lower() and 'sandbox' in out.lower() and 'TiesL' in out,
            'stale status omits refresh by TiesL outside sandbox')
    adopt('--hooks'); status(0, 'current')
    target = b / 'lib/model-record.sh'; original = target.read_bytes()
    target.write_bytes(original + b'\n# corrupt\n'); status(1, 'corrupt')
    target.write_bytes(original); target.unlink(); status(1, 'corrupt')
    shutil.rmtree(b); status(1, 'absent')
    invalid = TMP / 'invalid'; invalid.mkdir()
    result = run(WF / 'adopt.sh', '--runtime', 'codex', '--status', invalid)
    require(result.returncode == 2, 'invalid status must exit 2')
elif SCENARIO == 404:
    for variant in ('unrecorded', 'tampered'):
        q = TMP / variant; q.mkdir(); git_metadata(q)
        if variant == 'tampered':
            adopt('--hooks', project=q)
            b = q / '.codex/sdg-guard'
            require(b.is_dir(), '--hooks did not install bundle needed for tamper test')
            target = b / 'lib/model-record.sh'; target.write_bytes(target.read_bytes() + b'\n# tampered\n')
        else:
            b = q / '.codex/sdg-guard'; b.mkdir(parents=True)
            (b / 'foreign').write_text('unowned\n')
        (q / 'AGENTS.md').write_text('pending update must survive\n')
        before = snapshot(q)
        result = run(WF / 'adopt.sh', '--runtime', 'codex', '--hooks', q)
        require(result.returncode == 1, f'{variant}: expected bundle ownership conflict, got {result.returncode}')
        require('conflict' in (result.stdout + result.stderr).lower(), f'{variant}: missing conflict diagnostic')
        require(snapshot(q) == before, f'{variant}: conflict wrote adoption files')
elif SCENARIO == 405:
    home = Path(ENV['HOME']); before = snapshot(home)
    adopt(); adopt('--hooks')
    require(snapshot(home) == before, 'adoption wrote HOME/Codex config')
    require(not (PROJECT / '.codex/config.toml').exists(), 'adoption wrote project Codex config')
    require(not list(PROJECT.rglob('hooks.state')), 'adoption wrote hooks.state')
    for p in PROJECT.rglob('*'):
        if p.is_file() and not p.is_symlink() and '.git' not in p.parts:
            require(b'trust_level' not in p.read_bytes(), f'adoption wrote trust_level: {p}')
elif SCENARIO in (406, 407):
    # First validate the fake-gh controls and accepted closure even on the red
    # tree; missing feature assertions must not conceal a broken harness.
    names = FILES
    built = TMP / 'list-only-bundle'
    for name in names:
        target = built / name; target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(WF / name, target)
    invoke = guard_fixture()
    parity(built / 'hooks/git-guardrails', invoke)
    if SCENARIO == 407:
        for name in names:
            if name == 'hooks/rules.sh': continue  # sourced but unused by merge-only
            target = built / name; saved = target.read_bytes(); mode = target.stat().st_mode
            target.unlink()
            try:
                if name == 'hooks/git-guardrails':
                    require(not target.exists(), 'guard ablation did not remove entry point')
                    # Shell reports the missing entry point, rather than Python failing to exec.
                    actual = invoke(shlex.quote(str(target)) + ' --merge-only', installed=True)
                else:
                    actual = invoke(built / 'hooks/git-guardrails')
                require(actual[0] != 2, f'{name}: ablation left role-play block unchanged')
            finally:
                target.write_bytes(saved); target.chmod(mode)
    names = list_files()
    require(set(names) == {str(p.relative_to(built)) for p in built.rglob('*') if p.is_file()},
            'list-only build differs from declared closure')
elif SCENARIO == 408:
    names = FILES  # validate real closure and mutation controls before the missing-list assertion
    def tripwire():
        unknown = []
        for name in names:
            text = (WF / name).read_text()
            refs = re.findall(r'\$\{?own_dir\}?/([\w./-]+)', text)
            # Literal script-relative dependencies; do not execute shell text.
            script = r'(?:\$0|\$BASH_SOURCE(?:\[0\])?|\$\{BASH_SOURCE(?:\[0\])?\})'
            refs += re.findall(r'\$\(dirname\s+["\']?' + script + r'["\']?\)/([\w./-]+)', text)
            refs += re.findall(r'\$\{BASH_SOURCE(?:\[0\])?%{1,2}/\*\}/([\w./-]+)', text)
            for ref in refs:
                resolved = os.path.normpath(str(Path(name).parent / ref))
                if resolved not in names: unknown.append((name, resolved))
        return unknown
    require(not tripwire(), f'closure tripwire found unlisted source dependency: {tripwire()}')
    anchors = ('$own_dir', '${own_dir}', '$(dirname "${BASH_SOURCE[0]}")',
               '$(dirname "$0")', '$(dirname "$BASH_SOURCE")',
               '$(dirname "${BASH_SOURCE}")', '$(dirname "$BASH_SOURCE[0]")',
               '${BASH_SOURCE%/*}', '${BASH_SOURCE[0]%/*}')
    for anchor in anchors:
        for directive in ('.', 'source'):
            target = WF / 'hooks/git-guardrails'; original = target.read_text()
            try:
                target.write_text(original + '\n' + directive + ' "' + anchor + '/../lib/not-in-bundle.sh"\n')
                found = tripwire()
                require(('hooks/git-guardrails', 'lib/not-in-bundle.sh') in found,
                        f'tripwire mutation survived: {directive} {anchor}: lib/not-in-bundle.sh')
                print(f'S408: rejected {directive} {anchor}: {found}')
            finally:
                target.write_text(original)
    list_files()
elif SCENARIO == 409:
    adopt('--hooks')
    ignore = (PROJECT / '.gitignore').read_text()
    block = ignore.split('# spec-driven-guardrails: begin', 1)[1].split('# spec-driven-guardrails: end', 1)[0]
    require(re.search(r'^/\.codex/sdg-guard/?$', block, re.M), 'managed .gitignore omits /.codex/sdg-guard')
    rec = json.loads((PROJECT / '.guardrails/installation.json').read_text())
    require(rec['version'] > 2, 'bundle provenance version was not bumped beyond 2')
    text = json.dumps(rec)
    require('.codex/sdg-guard' in text, 'provenance omits owned bundle path')
    require(hashlib.sha256((bundle() / 'MANIFEST').read_bytes()).hexdigest() in text,
            'provenance omits MANIFEST digest')
    ignored = run('git', '-C', PROJECT, 'check-ignore', '.codex/sdg-guard/hooks/git-guardrails')
    require(ignored.returncode == 0, 'Git does not ignore installed bundle')
elif SCENARIO == 410:
    text = (WF / 'adapters/codex/permission-baseline.md').read_text()
    require('.codex/sdg-guard' in text, 'baseline omits installed .codex/sdg-guard bundle')
    for name in FILES:
        require(name in text, f'baseline warning omits {name}')
    for token in ('merge hook optional and off', '[A]', 'quality-review-before-merge',
                  'WORKFLOW-ADOPTION.md', 'PATH', 'CLAUDE_WORKFLOW_GUARDRAILS_OFF',
                  'CLAUDE_WORKFLOW_MERGE_GUARD_OFF'):
        require(token.lower() in text.lower(), f'baseline omits {token}')
    for pattern, message in (
        (r'outside[^.\n]*sandbox', 'refresh outside sandbox'),
        (r'(?:not re-prompted|not reprompted|without a (?:new |fresh )?prompt)', 'content refresh trust limit'),
        (r'(?:negative|fails?)[\s\S]{0,1000}(?:content hash|untrusted)', 'live negative fallback'),
        (r'(?:positive|observed)[\s\S]{0,1000}(?:default|optional and off)', 'positive-live default condition')):
        require(re.search(pattern, text, re.I), f'baseline omits {message}')
elif SCENARIO == 411:
    adopt('--hooks')
    invoke = guard_fixture()
    baseline = invoke(command(), kind='missing', installed=True)
    require(baseline[0] == 2 and 'without a review marker for the current commit' in baseline[2],
            f'missing-review control did not reach policy refusal: {baseline}')
    backup = TMP / 'installed-before-refresh'
    shutil.copytree(PROJECT, backup, symlinks=True)
    for name in FILES:
        path = WF / name
        path.write_bytes(path.read_bytes() + b'\n# interrupted refresh fixture\n')
    (WF / '.git/HEAD').write_text(NEW_REV + '\n')
    # Inject only in the disposable adoption interpreter, never product code.
    # A partial write models interruption after opening/truncating a bundle file.
    injection = TMP / 'write-failure'
    injection.mkdir()
    (injection / 'sitecustomize.py').write_text("""
import os
from pathlib import Path
original = Path.write_bytes
project = Path(os.environ['FAIL_PROJECT'])
name = os.environ['FAIL_BUNDLE_FILE']
def interrupted(self, data):
    if self.is_relative_to(project / '.codex') and str(self).endswith('/' + name):
        original(self, b'')
        Path(os.environ['FAIL_RECEIPT']).write_text(name)
        raise OSError('injected bundle write interruption: ' + name)
    return original(self, data)
Path.write_bytes = interrupted
""")
    failures = []
    for name in FILES:
        shutil.rmtree(PROJECT)
        shutil.copytree(backup, PROJECT, symlinks=True)
        receipt = TMP / 'interruption-receipt'
        if receipt.exists(): receipt.unlink()
        env = dict(ENV, PYTHONPATH=str(injection), FAIL_PROJECT=str(PROJECT),
                   FAIL_BUNDLE_FILE=name, FAIL_RECEIPT=str(receipt))
        result = run(WF / 'adopt.sh', '--runtime', 'codex', '--hooks', PROJECT, env=env)
        require(receipt.exists() and receipt.read_text() == name,
                f'{name}: injection did not reach bundle write: {result.stdout}{result.stderr}')
        require(result.returncode != 0 and 'injected bundle write interruption' in result.stdout + result.stderr,
                f'{name}: injection did not report failed refresh: {result.stdout}{result.stderr}')
        actual = invoke(command(), kind='missing', installed=True)
        if actual != baseline:
            failures.append(f'{name}: interrupted refresh changed missing-review verdict: {actual} != {baseline}')
        recovery = run(WF / 'adopt.sh', '--runtime', 'codex', '--hooks', PROJECT)
        if recovery.returncode != 0:
            failures.append(f'{name}: explicit recovery refused (exit {recovery.returncode}): '
                            + recovery.stdout + recovery.stderr)
        else:
            status(0, 'current')
            recovered = invoke(command(), kind='missing', installed=True)
            require(recovered == baseline, f'{name}: recovered bundle changed policy: {recovered}')
        print(f'S411: exercised interrupted write and recovery for {name}')
    require(not failures, '\n'.join(failures))
else:
    raise AssertionError(f'unknown scenario {SCENARIO}')
print(f'S{SCENARIO}: passed')
