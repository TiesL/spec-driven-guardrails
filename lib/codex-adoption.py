"""Private filesystem implementation behind adopt.sh's Codex Interface.

Build and validate the entire ownership plan before any project write. Local
provenance authorizes exact symlink targets, never project files or config.
"""
import json
import os
from pathlib import Path
import re
import subprocess
import sys

BEGIN = b'<!-- spec-driven-guardrails: begin -->'
END = b'<!-- spec-driven-guardrails: end -->'
IGNORE_BEGIN = b'# spec-driven-guardrails: begin'
IGNORE_END = b'# spec-driven-guardrails: end'
RECORD = '.guardrails/installation.json'
COVERAGE = 'runtime-hooks: not-installed; runtime shell interception unavailable'

class Conflict(Exception):
    pass

def exists(p):
    return p.exists() or p.is_symlink()

def block(data, begin, end, name):
    if not data.count(begin) and not data.count(end): return None
    if data.count(begin) != 1 or data.count(end) != 1:
        raise Conflict(name + ': duplicate/unmatched/nested managed markers')
    start = data.index(begin); stop = data.index(end)
    if stop < start or (start and data[start-1:start] != b'\n'):
        raise Conflict(name + ': malformed managed markers')
    stop += len(end)
    if data[stop:stop+1] not in (b'', b'\n', b'\r'):
        raise Conflict(name + ': malformed managed markers')
    return start, stop

def regular(p, name):
    if p.is_symlink() or (p.exists() and not p.is_file()):
        raise Conflict(name + ': expected a regular file, symlinks are not owned')
    return p.read_bytes() if p.exists() else b''

def managed(data, span, payload):
    if span:
        return data[:span[0]] + payload + data[span[1]:]
    return data + (b'\n' if data and not data.endswith(b'\n') else b'') + payload + b'\n'

def inventory(source, project):
    rev = subprocess.run(['git', '-C', str(source), 'rev-parse', 'HEAD'],
                         capture_output=True, text=True)
    print('runtime: codex\nproject: ' + str(project) + '\ncheckout: ' + str(source))
    print('revision: ' + (rev.stdout.strip() if rev.returncode == 0 else 'unavailable (unversioned checkout)'))
    print(COVERAGE)
    print('config/trust/permissions/user-hooks/plugins: project/user-owned; not installed or changed')
    print('native-hooks: shared; foreign hooks/hooksPath/--no-verify may make coverage unavailable')
    print('structural installation only; not live-loaded')

def record_read(project):
    path = project / RECORD
    if not exists(path): return None
    data = regular(path, RECORD)
    try:
        rec = json.loads(data)
        if set(rec) != {'owner', 'version', 'runtime', 'checkout', 'links'}:
            raise ValueError('unknown or missing fields')
        if rec['owner'] != 'spec-driven-guardrails' or rec['version'] != 1 or rec['runtime'] != 'codex':
            raise ValueError('foreign owner/runtime/version')
        checkout = rec['checkout']
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
    except (ValueError, TypeError) as exc:
        raise Conflict(RECORD + ': malformed/foreign provenance: ' + str(exc))

def main():
    source = Path(sys.argv[1]).resolve()
    project = Path(sys.argv[2]).resolve()
    status = sys.argv[3] == 'status'
    if not project.is_dir() or not (project / '.git').is_dir():
        print('adopt: invalid/unreadable project (requires .git directory): ' + str(project)); return 2 if status else 1
    inventory(source, project)
    conflicts = []
    files = {}
    links = {}
    removals = []
    old = None
    try:
        for name in ('.guardrails', '.agents', '.agents/skills'):
            p = project / name
            if p.is_symlink() or (exists(p) and not p.is_dir()): raise Conflict(name + ': expected a real directory')
        if exists(project / 'AGENTS.override.md'): raise Conflict('AGENTS.override.md: overrides root instructions; resolve before adoption')
        data = regular(project / 'AGENTS.md', 'AGENTS.md')
        span = block(data, BEGIN, END, 'AGENTS.md')
        payload = (source / 'adapters/codex/AGENTS.md').read_bytes()
        files['AGENTS.md'] = managed(data, span, BEGIN + b'\n' + payload + END)
        old = record_read(project)
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
        tracked = subprocess.run(['git', '-C', str(project), 'ls-files', '-s', '-z'], capture_output=True)
        if tracked.returncode: raise OSError('cannot read Git index')
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
            allowed = {'/.guardrails/source', '/' + RECORD} | {'/' + n for n in set(links) | set(previous) if n.startswith('.agents/skills/')}
            if any(line and line not in allowed for line in entries): raise Conflict('.gitignore: foreign entries in managed block')
        entries = sorted('/' + n for n in links if n.startswith('.agents/skills/'))
        ignore_payload = IGNORE_BEGIN + b'\n' + ('/.guardrails/source\n/' + RECORD + '\n' + '\n'.join(entries) + '\n').encode() + IGNORE_END
        files['.gitignore'] = managed(ignore, ignore_span, ignore_payload)
        rec = {'owner': 'spec-driven-guardrails', 'version': 1, 'runtime': 'codex', 'checkout': str(source), 'links': links}
        files[RECORD] = (json.dumps(rec, indent=2, sort_keys=True) + '\n').encode()
    except Conflict as exc:
        conflicts.append(str(exc))
    if conflicts:
        for message in conflicts: print('conflict: ' + message)
        return 1
    if status:
        stale = False
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
            if p.exists() and p.read_bytes() == wanted:
                print('unchanged: ' + name); continue
            action = 'repaired' if p.exists() else 'created'
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(wanted); print(action + ': ' + name)
    except OSError as exc:
        print('incomplete installation: ' + str(exc)); return 1
    print('Codex adapter installed; not live-loaded')
    return 0

if __name__ == '__main__':
    try: sys.exit(main())
    except (OSError, UnicodeError, ValueError) as exc:
        print('adopt: invalid/unreadable or incomplete installation: ' + str(exc), file=sys.stderr)
        sys.exit(2 if len(sys.argv) > 3 and sys.argv[3] == 'status' else 1)
