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


if SCENARIO == 397:
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
            refs += re.findall(r'\$\(dirname "\$\{BASH_SOURCE\[0\]\}"\)/([\w./-]+)', text)
            for ref in refs:
                resolved = os.path.normpath(str(Path(name).parent / ref))
                if resolved not in names: unknown.append((name, resolved))
        return unknown
    require(not tripwire(), f'closure tripwire found unlisted source dependency: {tripwire()}')
    for anchor in ('$own_dir', '${own_dir}', '$(dirname "${BASH_SOURCE[0]}")'):
        target = WF / 'hooks/git-guardrails'; original = target.read_text()
        target.write_text(original + '\n. "' + anchor + '/../lib/not-in-bundle.sh"\n')
        require(('hooks/git-guardrails', 'lib/not-in-bundle.sh') in tripwire(),
                f'tripwire mutation survived: {anchor}')
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
else:
    raise AssertionError(f'unknown scenario {SCENARIO}')
print(f'S{SCENARIO}: passed')
