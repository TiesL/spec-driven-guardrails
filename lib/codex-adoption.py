"""Private filesystem implementation behind adopt.sh's Codex Interface.

Build and validate the entire ownership plan before any project write. Local
provenance authorizes exact symlink targets and, only with --hooks, one exact
project hook definition. It never owns the entire hook file or user config.
"""
import ctypes
import fcntl
import tempfile
import uuid
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import stat
import subprocess
import sys

from managed_blocks import BEGIN, END, Conflict, block, managed, framed
IGNORE_BEGIN = b'# spec-driven-guardrails: begin'
IGNORE_END = b'# spec-driven-guardrails: end'
RECORD = '.guardrails/installation.json'
BUNDLE = '.codex/sdg-guard'
COVERAGE = 'runtime-hooks: not-installed; runtime shell interception unavailable'

def exists(p):
    return p.exists() or p.is_symlink()

def regular(p, name):
    if p.is_symlink() or (p.exists() and not p.is_file()):
        raise Conflict(name + ': expected a regular file, symlinks are not owned')
    return p.read_bytes() if p.exists() else b''

def inventory(source, project):
    rev = subprocess.run(['git', '-C', str(source), 'rev-parse', 'HEAD'],
                         capture_output=True, text=True)
    print('runtime: codex\nproject: ' + str(project) + '\ncheckout: ' + str(source))
    print('revision: ' + (rev.stdout.strip() if rev.returncode == 0 else 'unavailable (unversioned checkout)'))
    print('config/trust/permissions/unrelated-hooks/plugins: project/user-owned; not installed or changed')
    print('native-hooks: shared; foreign hooks/hooksPath/--no-verify may make coverage unavailable')
    print('structural installation only; not live-loaded')

def record_read(project):
    path = project / RECORD
    if not exists(path): return None
    data = regular(path, RECORD)
    try:
        rec = json.loads(data)
        fields = {'owner', 'version', 'runtime', 'checkout', 'links'}
        if isinstance(rec, dict) and rec.get('version') in (2, 3, 4):
            fields.add('managed_hook')
        if isinstance(rec, dict) and rec.get('version') in (3, 4):
            fields.add('guard_bundle')
        if isinstance(rec, dict) and rec.get('version') == 4:
            fields.add('guard_bundle_transaction')
        if set(rec) != fields:
            raise ValueError('unknown or missing fields')
        if rec['owner'] != 'spec-driven-guardrails' or type(rec['version']) is not int or rec['version'] not in (1, 2, 3, 4) or rec['runtime'] != 'codex':
            raise ValueError('foreign owner/runtime/version')
        checkout = rec['checkout']
        if rec['version'] in (2, 3, 4):
            validate_group(rec['managed_hook'])
            if rec['managed_hook'].get('matcher') != 'Bash': raise ValueError('invalid managed matcher')
        if rec['version'] in (3, 4):
            bundle = rec['guard_bundle']
            if (not isinstance(bundle, dict) or set(bundle) != {'path', 'manifest_sha256'}
                    or bundle['path'] != BUNDLE
                    or not re.fullmatch(r'[0-9a-f]{64}', bundle['manifest_sha256'])):
                raise ValueError('invalid bundle ownership')
        if rec['version'] == 4:
            validate_transaction(rec)
        if not isinstance(checkout, str) or not os.path.isabs(checkout): raise ValueError('checkout must be absolute')
        if not isinstance(rec['links'], dict) or '.guardrails/source' not in rec['links']: raise ValueError('missing source ownership')
        for name, target in rec['links'].items():
            if name == '.guardrails/source': expected = checkout
            elif name in ('.git/hooks/pre-commit', '.git/hooks/commit-msg', '.git/hooks/pre-push'):
                expected = str(Path(checkout) / 'hooks' / Path(name).name)
            elif re.fullmatch(r'\.agents/skills/[A-Za-z0-9_-]+', name):
                expected = str(Path(checkout) / 'skills' / Path(name).name)
            else: raise ValueError('foreign owned path: ' + name)
            if target != expected: raise ValueError('foreign target: ' + name)
        return rec
    except (ValueError, TypeError, AttributeError) as exc:
        raise Conflict(RECORD + ': malformed/foreign provenance: ' + str(exc))

def validate_group(group):
    if not isinstance(group, dict) or not isinstance(group.get('hooks'), list):
        raise ValueError('expected hook group with hooks array')
    if 'matcher' in group and not isinstance(group['matcher'], str):
        raise ValueError('expected string matcher')
    for hook in group['hooks']:
        if not isinstance(hook, dict) or not isinstance(hook.get('type'), str):
            raise ValueError('expected typed hook object')
        if hook['type'] == 'command' and not isinstance(hook.get('command'), str):
            raise ValueError('expected command string')

def hook_plan(source, project, old, install):
    """Own one exact definition, never the file or other hook groups.

    Without opt-in, inspect recorded ownership for truthful status but do not
    plan any hook write. An absent opt-in is never an uninstall request.
    """
    previous = old.get('managed_hook') if old else None
    if not install and previous is None:
        return None, None, COVERAGE
    parent = project / '.codex'
    if parent.is_symlink() or (exists(parent) and not parent.is_dir()):
        raise Conflict('.codex: expected a real directory')
    path = parent / 'hooks.json'
    data = regular(path, '.codex/hooks.json')
    try:
        doc = json.loads(data) if exists(path) else {}
        if not isinstance(doc, dict) or ('hooks' in doc and not isinstance(doc['hooks'], dict)):
            raise ValueError('expected object with hooks object')
        groups = doc.setdefault('hooks', {})
        for event, definitions in groups.items():
            if not isinstance(definitions, list): raise ValueError(event + ': expected group array')
            for group in definitions: validate_group(group)
        canonical = json.loads((source / 'adapters/codex/merge-hook.json').read_bytes())
        validate_group(canonical)
        guard = shlex.quote(str(project / BUNDLE / 'hooks/git-guardrails'))
        for hook in canonical['hooks']:
            hook['command'] = hook['command'].replace('{guard}', guard)
        definitions = groups.setdefault('PreToolUse', [])
        if previous is not None:
            matches = [i for i, group in enumerate(definitions) if group == previous]
            if len(matches) != 1:
                raise ValueError('owned definition edited, missing or duplicated')
            index = matches[0]
            if previous != canonical and canonical in definitions:
                raise ValueError('duplicate managed definition')
            if install: definitions[index] = canonical
        elif canonical in definitions:
            raise ValueError('unrecorded managed definition; ownership cannot be claimed')
        elif install:
            definitions.append(canonical)
        if not install and previous != canonical:
            return None, previous, 'runtime-hooks: stale/conflict; managed definition differs from source; activation: unverified'
    except (ValueError, TypeError, KeyError, AttributeError) as exc:
        raise Conflict('.codex/hooks.json: malformed/conflicting hooks: ' + str(exc))
    output = (json.dumps(doc, indent=2, ensure_ascii=False) + '\n').encode() if install else None
    return output, canonical if install else previous, 'runtime-hooks: installed; scope: Bash merge interception; activation: unverified'

def bundle_plan(source, project, old, install):
    """Validate ownership and all bytes before planning any bundle write."""
    root = project / BUNDLE
    owned = old.get('guard_bundle') if old else None
    parent = root.parent
    if parent.is_symlink() or (exists(parent) and not parent.is_dir()):
        raise Conflict('.codex: expected a real directory')
    if root.is_symlink() or (exists(root) and not root.is_dir()):
        raise Conflict(BUNDLE + ': expected a real directory')
    if root.exists():
        for path in root.rglob('*'):
            if path.is_symlink():
                raise Conflict(str(path.relative_to(project)) + ': symlink refused')
        if owned is None:
            raise Conflict(BUNDLE + ': unrecorded bundle conflict')
    elif owned is not None:
        raise Conflict(BUNDLE + ': absent recorded bundle conflict')
    revision = subprocess.run(['git', '-C', str(source), 'rev-parse', 'HEAD'],
                              capture_output=True, text=True)
    revision = revision.stdout.strip() if revision.returncode == 0 else 'unavailable (unversioned checkout)'
    names = [line.strip() for line in (source / 'adapters/codex/guard-bundle.list').read_text().splitlines()
             if line.strip() and not line.lstrip().startswith('#')]
    if len(names) != len(set(names)) or any(
            Path(n).is_absolute() or '..' in Path(n).parts for n in names):
        raise Conflict('invalid guard bundle list')
    contents, modes, entries = {}, {}, {}
    for name in names:
        path = source / name
        data = regular(path, name)
        if not path.is_file(): raise Conflict(name + ': missing bundle source')
        mode = stat.S_IMODE(path.stat().st_mode)
        contents[BUNDLE + '/' + name] = data
        modes[BUNDLE + '/' + name] = mode
        entries[name] = {'sha256': hashlib.sha256(data).hexdigest(), 'mode': mode}
    manifest = (json.dumps({'revision': revision, 'files': entries}, indent=2, sort_keys=True) + '\n').encode()
    if owned is not None:
        previous, raw = validate_generation(root, owned['manifest_sha256'])
        current = raw == manifest
        print('guard bundle: ' + ('current' if current else 'stale (warning)'))
        if not current:
            print('Refresh must be run by TiesL outside the sandbox; installed rules remain active.')
        if install and not current:
            print('guard bundle revision: ' + previous['revision'] + ' -> ' + revision)
            for name, entry in entries.items():
                if previous['files'].get(name) != entry: print('bundle changed: ' + name)
            for name in set(previous['files']) - set(entries):
                raise Conflict(BUNDLE + ': obsolete bundle path requires explicit migration: ' + name)
            print('Hook trust is not re-prompted for a content-only refresh.')
    else:
        current = False
        print('guard bundle: absent; activation: unverified')
    if not install:
        return {}, {}, owned, owned is not None and not current
    contents[BUNDLE + '/MANIFEST'] = manifest
    modes[BUNDLE + '/MANIFEST'] = 0o644
    record = {'path': BUNDLE, 'manifest_sha256': hashlib.sha256(manifest).hexdigest()}
    if not old or old.get('version') != 4:
        print('Explicit provenance upgrade to version 4.')
        if not old or old.get('version') in (1, 2):
            print('Review and trust the changed command once more in /hooks.')
    return contents, modes, record, False


def digest(data):
    return hashlib.sha256(data).hexdigest()


def validate_transaction(rec):
    tx = rec['guard_bundle_transaction']
    if tx is None:
        return
    if (not isinstance(tx, dict) or set(tx) != {'phase', 'staging_path',
            'old_manifest_sha256', 'new_manifest_sha256'}):
        raise ValueError('invalid transaction fields')
    if tx['phase'] not in ('preparing', 'ready', 'cleanup'):
        raise ValueError('invalid transaction phase')
    if (not isinstance(tx['staging_path'], str) or not re.fullmatch(
            r'\.codex/\.sdg-guard-stage-[A-Za-z0-9]+', tx['staging_path'])):
        raise ValueError('invalid transaction staging path')
    for key in ('old_manifest_sha256', 'new_manifest_sha256'):
        if not isinstance(tx[key], str) or not re.fullmatch(r'[0-9a-f]{64}', tx[key]):
            raise ValueError('invalid transaction digest')
    committed = tx['new_manifest_sha256' if tx['phase'] == 'cleanup' else 'old_manifest_sha256']
    if (rec['guard_bundle']['manifest_sha256'] != committed or
            tx['new_manifest_sha256'] == tx['old_manifest_sha256']):
        raise ValueError('inconsistent transaction ownership')


def encode_record(rec):
    return (json.dumps(rec, indent=2, sort_keys=True) + '\n').encode()


def atomic_record(project, rec):
    path = project / RECORD
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.installation-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(encode_record(rec))
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def bundle_names(source):
    return {line.strip() for line in (source / 'adapters/codex/guard-bundle.list').read_text().splitlines()
            if line.strip() and not line.lstrip().startswith('#')}


def validate_tree(root, names):
    """Inventory first: no traversal through links or unexpected directories."""
    if root.is_symlink() or (exists(root) and not root.is_dir()):
        raise Conflict(str(root) + ': expected a real directory')
    directories = {str(parent) for name in names for parent in Path(name).parents if parent != Path('.')}
    if not exists(root):
        return
    for path in root.rglob('*'):
        name = str(path.relative_to(root))
        if path.is_symlink():
            raise Conflict(str(path) + ': symlink refused')
        if path.is_dir() and name in directories:
            continue
        if path.is_file() and name in names:
            continue
        raise Conflict(str(path) + ': unexpected bundle entry conflict')


def validate_generation(root, expected, partial=False):
    """The independently anchored manifest authenticates every remaining byte."""
    try:
        if not exists(root):
            if partial: return None, b''
            raise ValueError('absent recorded bundle')
        if root.is_symlink() or not root.is_dir():
            raise Conflict(str(root) + ': expected a real directory')
        manifest = root / 'MANIFEST'
        if partial and not exists(manifest) and not list(root.iterdir()):
            return None, b''
        if not exists(manifest):
            raise ValueError('missing MANIFEST')
        raw = regular(manifest, str(manifest))
        if digest(raw) != expected or stat.S_IMODE(manifest.stat().st_mode) != 0o644:
            raise ValueError('manifest digest or mode differs from ownership record')
        doc = json.loads(raw)
        if (not isinstance(doc, dict) or set(doc) != {'revision', 'files'} or
                not isinstance(doc['revision'], str) or not isinstance(doc['files'], dict)):
            raise ValueError('invalid manifest schema')
        if set(doc['files']) != bundle_names(Path(sys.argv[1]).resolve()):
            raise ValueError('unexpected manifest inventory')
        for name, entry in doc['files'].items():
            if (not isinstance(name, str) or str(Path(name)) != name or
                    Path(name).is_absolute() or '..' in Path(name).parts or name in ('.', 'MANIFEST') or
                    not isinstance(entry, dict) or set(entry) != {'sha256', 'mode'} or
                    not isinstance(entry['sha256'], str) or not re.fullmatch(r'[0-9a-f]{64}', entry['sha256']) or
                    type(entry['mode']) is not int or not 0 <= entry['mode'] <= 0o7777):
                raise ValueError('invalid manifest entry')
        validate_tree(root, set(doc['files']) | {'MANIFEST'})
        for name, entry in doc['files'].items():
            path = root / name
            if partial and not exists(path): continue
            if (not path.is_file() or digest(regular(path, str(path))) != entry['sha256'] or
                    stat.S_IMODE(path.stat().st_mode) != entry['mode']):
                raise ValueError('bytes or mode differ: ' + name)
        return doc, raw
    except (ValueError, KeyError, TypeError, AttributeError) as exc:
        raise Conflict(str(root) + ': corrupt bundle conflict: ' + str(exc))


def validate_pending(project, rec):
    tx = rec['guard_bundle_transaction']
    root, stage = project / BUNDLE, project / tx['staging_path']
    for parent in (root.parent, root):
        if parent.is_symlink() or (exists(parent) and not parent.is_dir()):
            raise Conflict(str(parent) + ': expected a real directory')
    if tx['phase'] == 'preparing':
        validate_generation(root, tx['old_manifest_sha256'])
        # Preparation may contain partial bytes, but only at declared paths.
        source = Path(sys.argv[1]).resolve()
        validate_tree(stage, bundle_names(source) | {'MANIFEST'})
        return 'old'
    if tx['phase'] == 'cleanup':
        validate_generation(root, tx['new_manifest_sha256'])
        validate_generation(stage, tx['old_manifest_sha256'], partial=True)
        return 'new'
    raw = regular(root / 'MANIFEST', str(root / 'MANIFEST'))
    active = digest(raw)
    if active == tx['old_manifest_sha256']:
        validate_generation(root, active)
        validate_generation(stage, tx['new_manifest_sha256'])
        return 'old'
    if active == tx['new_manifest_sha256']:
        validate_generation(root, active)
        validate_generation(stage, tx['old_manifest_sha256'])
        return 'new'
    raise Conflict(str(root) + ': active generation matches neither authorized digest')


def exchange_function():
    """No two-rename fallback: both supported calls exchange directories once."""
    libc = ctypes.CDLL(None, use_errno=True)
    if sys.platform == 'darwin':
        name, flag, cwd = 'renameatx_np', 2, -2  # RENAME_SWAP, AT_FDCWD
    elif sys.platform.startswith('linux'):
        name, flag, cwd = 'renameat2', 2, -100  # RENAME_EXCHANGE, AT_FDCWD
    else:
        raise Conflict('atomic directory exchange unsupported on this platform')
    try:
        native = getattr(libc, name)
    except AttributeError:
        raise Conflict('atomic directory exchange unsupported: ' + name)
    native.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
    native.restype = ctypes.c_int
    def exchange(left, right):
        if native(cwd, os.fsencode(left), cwd, os.fsencode(right), flag):
            error = ctypes.get_errno()
            raise OSError(error, 'atomic directory exchange refused: ' + os.strerror(error))
    return exchange


def remove_stage(stage):
    """Caller validated all entries; retain MANIFEST until payload is gone."""
    if not exists(stage): return
    for path in sorted(stage.rglob('*'), key=lambda p: len(p.parts), reverse=True):
        if path.name == 'MANIFEST' and path.parent == stage: continue
        if path.is_dir(): os.rmdir(path)
        else: os.unlink(path)
    manifest = stage / 'MANIFEST'
    if exists(manifest): os.unlink(manifest)
    os.rmdir(stage)


def prepare_bundle(source, project, rec, contents, modes):
    tx = rec['guard_bundle_transaction']
    stage = project / tx['staging_path']
    stage.mkdir()
    for name, data in contents.items():
        relative = str(Path(name).relative_to(BUNDLE))
        path = stage / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        path.chmod(modes[name])
    validate_generation(stage, tx['new_manifest_sha256'])
    # Planning is a snapshot: don't publish if source moved during preparation.
    again, again_modes, _, _ = bundle_plan(source, project, rec, True)
    if again != contents or again_modes != modes:
        raise Conflict('source changed during preparation; recovery pending')
    tx['phase'] = 'ready'
    atomic_record(project, rec)


def finish_exchange(project, rec, exchange):
    tx = rec['guard_bundle_transaction']
    arrangement = validate_pending(project, rec)
    if tx['phase'] == 'ready':
        if arrangement == 'old': exchange(project / BUNDLE, project / tx['staging_path'])
        validate_generation(project / BUNDLE, tx['new_manifest_sha256'])
        tx['phase'] = 'cleanup'
        rec['guard_bundle']['manifest_sha256'] = tx['new_manifest_sha256']
        atomic_record(project, rec)
    validate_pending(project, rec)
    remove_stage(project / tx['staging_path'])
    rec['guard_bundle_transaction'] = None
    atomic_record(project, rec)


def recover_bundle(source, project, rec, exchange):
    tx = rec['guard_bundle_transaction']
    validate_pending(project, rec)
    if tx['phase'] == 'preparing':
        remove_stage(project / tx['staging_path'])
        contents, modes, owned, _ = bundle_plan(source, project, rec, True)
        if owned['manifest_sha256'] == tx['old_manifest_sha256']:
            rec['guard_bundle_transaction'] = None
            atomic_record(project, rec)
            return
        tx['new_manifest_sha256'] = owned['manifest_sha256']
        atomic_record(project, rec)
        prepare_bundle(source, project, rec, contents, modes)
    finish_exchange(project, rec, exchange)


def refresh_bundle(source, project, old, contents, modes, exchange):
    new_digest = digest(contents[BUNDLE + '/MANIFEST'])
    if new_digest == old['guard_bundle']['manifest_sha256']: return
    rec = dict(old, version=4, guard_bundle=dict(old['guard_bundle']),
               guard_bundle_transaction=dict(phase='preparing',
                   staging_path='.codex/.sdg-guard-stage-' + uuid.uuid4().hex,
                   old_manifest_sha256=old['guard_bundle']['manifest_sha256'],
                   new_manifest_sha256=new_digest))
    atomic_record(project, rec)
    prepare_bundle(source, project, rec, contents, modes)
    finish_exchange(project, rec, exchange)


def inherited_lock_held(project):
    """Consume the serializer's handoff only in its re-executed shell."""
    try:
        fd = int(os.environ.get('SDG_ADOPTION_LOCK_FD', ''))
        if fd < 0: return False
        inherited = os.fstat(fd)
        probe = os.open(project, os.O_RDONLY)
        try:
            target = os.fstat(probe)
            if (inherited.st_dev, inherited.st_ino) != (target.st_dev, target.st_ino):
                return False
            # A fresh description must contend. Success means the inherited
            # descriptor was open but did not hold a lock; release on close.
            try:
                fcntl.flock(probe, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                pass
            else:
                return False
            # Contention alone could be another writer. Only the inherited
            # locking description can also obtain the exclusive lock here.
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            handoff = int(os.environ.get('SDG_ADOPTION_REEXEC_FD', ''))
            if handoff < 0 or not stat.S_ISFIFO(os.fstat(handoff).st_mode):
                return False
            os.set_blocking(handoff, False)
            # exec preserves the serializer's PID. Reading consumes the only
            # handoff, so even a descendant inheriting both FDs cannot reuse it.
            return os.read(handoff, 32) == str(os.getppid()).encode('ascii')
        finally:
            os.close(probe)
    except (OSError, ValueError, OverflowError):
        return False


def main():
    if sys.argv[1] == '--lock-held':
        return 0 if inherited_lock_held(Path(sys.argv[2]).resolve()) else 1
    if sys.argv[1] == '--serialize':
        project = Path(sys.argv[2]).resolve()
        fd = os.open(project, os.O_RDONLY)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print('adopt: overlapping adoption writer refused')
            return 1
        os.set_inheritable(fd, True)
        os.environ['SDG_ADOPTION_LOCK_FD'] = str(fd)
        handoff, sender = os.pipe()
        os.write(sender, str(os.getpid()).encode('ascii'))
        os.close(sender)
        os.set_inheritable(handoff, True)
        os.environ['SDG_ADOPTION_REEXEC_FD'] = str(handoff)
        os.execv(sys.argv[3], sys.argv[3:])
    source = Path(sys.argv[1]).resolve()
    project = Path(sys.argv[2]).resolve()
    status = sys.argv[3] == 'status'
    install_hooks = sys.argv[3] == 'install-hooks'
    if not project.is_dir() or not (project / '.git').is_dir():
        print('adopt: invalid/unreadable project (requires .git directory): ' + str(project)); return 2 if status else 1
    inventory(source, project)
    conflicts = []
    files = {}
    modes = {}
    bundle_stale = False
    links = {}
    removals = []
    old = None
    try:
        # Shared scaffolding runs after this Module, but belongs to this same
        # preflight. Inspect the whole path without authorizing writes through
        # symlinks, including leaves copy-if-missing would skip before chmod.
        for name in sys.argv[4:]:
            relative = Path(name)
            for part in reversed((relative, *relative.parents)):
                if part == Path('.'): continue
                p = project / part
                if p.is_symlink():
                    raise Conflict(str(part) + ': unsafe shared scaffolding symlink')
                directory = part != relative or name in ('.github/ISSUE_TEMPLATE', '.github/workflows')
                if exists(p) and not (p.is_dir() if directory else p.is_file()):
                    raise Conflict(str(part) + ': unsafe shared scaffolding parent; expected directory')
        for name in ('.git', '.git/hooks'):
            p = project / name
            if p.is_symlink() or (exists(p) and not p.is_dir()):
                raise Conflict(name + ': unsafe parent; expected a real directory')
        for name in ('.guardrails', '.agents', '.agents/skills'):
            p = project / name
            if p.is_symlink() or (exists(p) and not p.is_dir()): raise Conflict(name + ': expected a real directory')
        # Provenance contains machine-local absolute paths even when its
        # worktree copy is absent. Reject indexed ownership before reading it.
        tracked = subprocess.run(['git', '-C', str(project), 'ls-files', '-s', '-z'], capture_output=True)
        if tracked.returncode: raise OSError('cannot read Git index')
        for entry in tracked.stdout.decode().split('\0'):
            if entry and entry.split('\t', 1)[1] == RECORD:
                raise Conflict(RECORD + ': tracked machine-local provenance; explicitly untrack or relocate before adoption')
        if exists(project / 'AGENTS.override.md'): raise Conflict('AGENTS.override.md: overrides root instructions; resolve before adoption')
        data = regular(project / 'AGENTS.md', 'AGENTS.md')
        span = block(data, BEGIN, END, 'AGENTS.md')
        payload = (source / 'adapters/codex/AGENTS.md').read_bytes()
        files['AGENTS.md'] = managed(data, span, framed(payload))
        old = record_read(project)
        transaction = old.get('guard_bundle_transaction') if old else None
        if transaction:
            validate_pending(project, old)
        planning_old = old
        if transaction:
            planning_old = dict(old, guard_bundle=dict(old['guard_bundle'],
                manifest_sha256=hashlib.sha256((project / BUNDLE / 'MANIFEST').read_bytes()).hexdigest()))
        if transaction and install_hooks:
            bundle_files, modes, owned_bundle = {}, {}, old['guard_bundle']
        else:
            bundle_files, modes, owned_bundle, bundle_stale = bundle_plan(source, project, planning_old, install_hooks)
        files.update(bundle_files)
        hook_bytes, owned_hook, coverage = hook_plan(source, project, old, install_hooks)
        if hook_bytes is not None: files['.codex/hooks.json'] = hook_bytes
        links['.guardrails/source'] = str(source)
        for skill in sorted((source / 'skills').iterdir()):
            if skill.is_dir():
                if not re.fullmatch(r'[A-Za-z0-9_-]+', skill.name): raise Conflict('skills/' + skill.name + ': unsupported skill path')
                if not (skill / 'SKILL.md').is_file(): raise Conflict('skills/' + skill.name + ': missing canonical SKILL.md')
                links['.agents/skills/' + skill.name] = str(skill)
        previous = old['links'] if old else {}
        for hook in ('pre-commit', 'commit-msg', 'pre-push'):
            name = '.git/hooks/' + hook
            p = project / name
            target = str(source / 'hooks' / hook)
            if not Path(target).is_file():
                print('native-hook unavailable/missing source: ' + name)
                previous = {k: v for k, v in previous.items() if k != name}
                continue
            if not exists(p) or (p.is_symlink() and (os.readlink(p) == previous.get(name) or p.resolve() == Path(target))):
                links[name] = target
            else:
                print('native-hook unavailable/foreign: ' + name + '; left untouched')
                previous = {k: v for k, v in previous.items() if k != name}
        # Every recorded link, including removed skills, must still be owned.
        for name in sorted(set(links) | set(previous)):
            p = project / name
            if not exists(p): continue
            if not p.is_symlink(): raise Conflict(name + ': project-owned file/directory')
            target = os.readlink(p)
            canonical = links.get(name)
            live_canonical = canonical is not None and p.exists() and p.resolve() == Path(canonical).resolve()
            if target != previous.get(name) and not live_canonical:
                raise Conflict(name + ': foreign/broken unrecorded/manually redirected link; restore recorded target or relocate project path')
            if name not in links: removals.append(name)
        # Absolute managed links cannot remain in the index. Never edit it.
        for entry in tracked.stdout.decode().split('\0'):
            if not entry: continue
            metadata, name = entry.split('\t', 1)
            if name in set(links) | set(previous):
                p = project / name
                absolute = p.is_symlink() and os.path.isabs(os.readlink(p))
                if metadata.startswith('120000 '):
                    blob = subprocess.run(['git', '-C', str(project), 'cat-file', 'blob', metadata.split()[1]], capture_output=True)
                    if blob.returncode: raise OSError('cannot read indexed managed link: ' + name)
                    absolute = absolute or os.path.isabs(os.fsdecode(blob.stdout))
                if absolute:
                    raise Conflict(name + ': tracked absolute managed link; explicitly untrack or relocate before adoption')
        ignore = regular(project / '.gitignore', '.gitignore')
        ignore_span = block(ignore, IGNORE_BEGIN, IGNORE_END, '.gitignore')
        if ignore_span:
            entries = ignore[ignore_span[0]+len(IGNORE_BEGIN):ignore_span[1]-len(IGNORE_END)].decode().splitlines()
            allowed = {'/.guardrails/source', '/' + RECORD, '/' + BUNDLE} | {'/' + n for n in set(links) | set(previous) if n.startswith('.agents/skills/')}
            if any(line and line not in allowed for line in entries): raise Conflict('.gitignore: foreign entries in managed block')
        entries = sorted('/' + n for n in links if n.startswith('.agents/skills/'))
        bundle_ignore = '/' + BUNDLE + '\n' if owned_bundle is not None else ''
        ignore_payload = IGNORE_BEGIN + b'\n' + ('/.guardrails/source\n/' + RECORD + '\n' + bundle_ignore + '\n'.join(entries) + '\n').encode() + IGNORE_END
        files['.gitignore'] = managed(ignore, ignore_span, ignore_payload)
        rec = {'owner': 'spec-driven-guardrails', 'version': 1, 'runtime': 'codex', 'checkout': str(source), 'links': links}
        if owned_hook is not None:
            rec.update(version=2, managed_hook=owned_hook)
        if owned_bundle is not None:
            rec.update(version=4 if install_hooks or old['version'] == 4 else 3, guard_bundle=owned_bundle)
            if rec['version'] == 4:
                rec['guard_bundle_transaction'] = transaction
        files[RECORD] = (json.dumps(rec, indent=2, sort_keys=True) + '\n').encode()
    except Conflict as exc:
        conflicts.append(str(exc))
    if conflicts:
        print('runtime-hooks: stale/conflict; activation: unverified')
        for message in conflicts: print('conflict: ' + message)
        return 1
    print(coverage)
    if transaction and not install_hooks:
        print('guard bundle: recovery pending; activation: unverified')
        print('Refresh must be run by TiesL outside the sandbox; explicit --hooks authorizes recovery.')
        return 1
    if status:
        stale = bundle_stale or coverage.startswith('runtime-hooks: stale/conflict')
        for name, wanted in files.items():
            p = project / name
            if not p.exists() or p.read_bytes() != wanted:
                print('stale/missing: ' + name); stale = True
            else: print('unchanged: ' + name)
        for name, target in links.items():
            p = project / name
            if not p.is_symlink() or os.readlink(p) != target or not p.exists():
                print('stale/broken/missing: ' + name); stale = True
            else: print('unchanged: ' + name)
        for name in removals: print('stale removed canonical skill: ' + name); stale = True
        for name in ('pre-commit', 'commit-msg', 'pre-push'):
            p = project / '.git/hooks' / name
            if not p.is_symlink() or p.resolve() != source / 'hooks' / name:
                print('native-hook unavailable/foreign/missing: ' + name)
                stale = True
        return 1 if stale else 0
    try:
        if install_hooks and old and old.get('guard_bundle'):
            # Resolve recorded generations before considering today's source.
            needs_exchange = transaction or digest(bundle_files[BUNDLE + '/MANIFEST']) != old['guard_bundle']['manifest_sha256']
            exchange = exchange_function() if needs_exchange else None
            if transaction:
                recover_bundle(source, project, old, exchange)
                old = record_read(project)
                bundle_files, modes, owned_bundle, bundle_stale = bundle_plan(source, project, old, True)
            refresh_bundle(source, project, old, bundle_files, modes, exchange)
            rec['guard_bundle'] = owned_bundle
            rec['guard_bundle_transaction'] = None
            files[RECORD] = encode_record(rec)
            files = {k: v for k, v in files.items() if not k.startswith(BUNDLE + '/')}
        for name in removals:
            (project / name).unlink(); print('removed: ' + name)
        for name, target in links.items():
            p = project / name
            if p.is_symlink() and os.readlink(p) == target:
                print('unchanged: ' + name); continue
            action = 'repaired' if exists(p) else 'created'
            p.parent.mkdir(parents=True, exist_ok=True)
            if exists(p): p.unlink()
            p.symlink_to(target); print(action + ': ' + name)
        for name, wanted in files.items():
            p = project / name
            if p.exists() and p.read_bytes() == wanted and (name not in modes or stat.S_IMODE(p.stat().st_mode) == modes[name]):
                print('unchanged: ' + name); continue
            action = 'repaired' if p.exists() else 'created'
            p.parent.mkdir(parents=True, exist_ok=True)
            if name == RECORD:
                atomic_record(project, json.loads(wanted))
            else:
                p.write_bytes(wanted)
            if name in modes: p.chmod(modes[name])
            print(action + ': ' + name)
    except (OSError, Conflict) as exc:
        print('incomplete installation: ' + str(exc)); return 1
    print('Codex adapter installed; not live-loaded')
    return 0

if __name__ == '__main__':
    try: sys.exit(main())
    except (OSError, UnicodeError, ValueError) as exc:
        print('adopt: invalid/unreadable or incomplete installation: ' + str(exc), file=sys.stderr)
        sys.exit(2 if len(sys.argv) > 3 and sys.argv[3] == 'status' else 1)
