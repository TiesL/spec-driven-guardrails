"""S365-S369 public adoption and installed hook integration tests (A47)."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(sys.argv[1]).resolve()
scenario = int(sys.argv[2])
with tempfile.TemporaryDirectory() as temp:
    tmp = Path(temp).resolve()
    wf = tmp / 'workflow'
    shutil.copytree(ROOT, wf, ignore=shutil.ignore_patterns('.git', '.guardrails', '.agents', '.claude', 'wip', '__pycache__'))
    env = dict(os.environ, SPEC_DRIVEN_GUARDRAILS_DIR=str(wf))
    def run(*args, rc=0, cwd=None, input=None):
        p = subprocess.run(list(map(str, args)), cwd=cwd or wf, env=env, input=input, capture_output=True, text=True)
        assert p.returncode == rc, (args, p.returncode, rc, p.stdout, p.stderr)
        return p.stdout + p.stderr
    def project(name):
        p = tmp / name
        p.mkdir()
        run('git', 'init', '-q', '-b', 'main', p)
        return p
    def adopt(p, *args, rc=0):
        return run(wf / 'adopt.sh', '--runtime', 'codex', *args, p, rc=rc)
    def snapshot(p):
        return {str(f.relative_to(p)): ('link', os.readlink(f)) if f.is_symlink() else
                ('file', f.read_bytes(), f.stat().st_mode) if f.is_file() else ('dir', f.stat().st_mode)
                for f in p.rglob('*')}
    def status(p, rc=0):
        before = snapshot(p)
        out = adopt(p, '--status', rc=rc)
        assert snapshot(p) == before, 'status mutated project'
        return out
    def hooks(p):
        return json.loads((p / '.codex/hooks.json').read_text())
    def command(p):
        return hooks(p)['hooks']['PreToolUse'][-1]['hooks'][0]['command']
    p = project("project spaces ' ; dollar$")
    if scenario == 365:
        adopt(p)
        assert not (p / '.codex').exists()
        rec = json.loads((p / '.guardrails/installation.json').read_text())
        assert rec['version'] == 1, 'default provenance must stay backwards compatible'
        adopt(p, '--hooks')
        doc = hooks(p)
        assert doc['hooks']['PreToolUse'][0]['matcher'] == 'Bash'
        assert '--merge-only' in command(p) and '.guardrails/source/hooks/git-guardrails' in command(p)
        assert json.loads((p / '.guardrails/installation.json').read_text())['version'] == 2
        before = snapshot(p)
        adopt(p, '--hooks'); assert before == snapshot(p), 'repeat differs'
        adopt(p); assert before == snapshot(p), 'default uninstalls or rewrites opted-in state'
        for args in (('--hooks', '--hooks'), ('--runtime', 'claude', '--hooks'), ('--hooks', '--user')):
            q = project('invalid-' + str(len(list(tmp.iterdir()))))
            before = snapshot(q)
            run(wf / 'adopt.sh', *args, q, rc=2)
            assert before == snapshot(q)
    elif scenario == 366:
        (p / '.codex').mkdir()
        foreign = {'custom': {'sentinel': 3}, 'hooks': {'Other': [], 'PreToolUse': [{'matcher': 'Bash', 'hooks': [{'type': 'command', 'command': 'printf foreign'}]}]}}
        (p / '.codex/hooks.json').write_text(json.dumps(foreign))
        (p / '.codex/config.toml').write_text('[hooks]\ninline = "sentinel"\n')
        config = (p / '.codex/config.toml').read_bytes()
        adopt(p, '--hooks'); adopt(p, '--hooks')
        actual = hooks(p)
        assert actual['custom'] == foreign['custom'] and actual['hooks']['Other'] == []
        assert actual['hooks']['PreToolUse'][:-1] == foreign['hooks']['PreToolUse']
        assert (p / '.codex/config.toml').read_bytes() == config
        # A source template update is authorized only by matching old ownership.
        template = wf / 'adapters/codex/merge-hook.json'
        template.write_text(template.read_text().replace(' --merge-only', ' --merge-only '))
        before_command = command(p); adopt(p, '--hooks')
        assert command(p) != before_command
        for variant in ('edited', 'duplicate', 'malformed', 'shape', 'file-link', 'parent-link', 'bad-record'):
            q = project('conflict-' + variant); adopt(q, '--hooks')
            hp = q / '.codex/hooks.json'
            if variant in ('edited', 'duplicate'):
                doc = hooks(q)
                if variant == 'edited': doc['hooks']['PreToolUse'][0]['hooks'][0]['command'] += ' foreign'
                else: doc['hooks']['PreToolUse'].append(doc['hooks']['PreToolUse'][0])
                hp.write_text(json.dumps(doc))
            elif variant == 'malformed': hp.write_text('{')
            elif variant == 'shape': hp.write_text('{"hooks":{"PreToolUse":{}}}')
            elif variant == 'bad-record':
                rp = q / '.guardrails/installation.json'; rec = json.loads(rp.read_text()); rec['version'] = 99; rp.write_text(json.dumps(rec))
            else:
                outside = tmp / ('outside-' + variant)
                if variant == 'file-link': hp.rename(outside); hp.symlink_to(outside)
                else: (q / '.codex').rename(outside); (q / '.codex').symlink_to(outside)
            (q / 'AGENTS.md').write_text('pending project update\n')
            before = snapshot(q); outside_before = snapshot(tmp / ('outside-' + variant)) if variant.endswith('link') else None
            assert 'conflict:' in adopt(q, '--hooks', rc=1)
            assert snapshot(q) == before, variant
            if outside_before is not None: assert snapshot(tmp / ('outside-' + variant)) == outside_before
    elif scenario == 367:
        adopt(p); assert 'runtime-hooks: not-installed' in status(p)
        adopt(p, '--hooks')
        out = status(p)
        for token in ('runtime-hooks: installed', 'scope: Bash merge interception', 'activation: unverified'): assert token in out
        assert 'runtime-hooks: installed' in run(wf / 'session-context.sh', '--runtime', 'codex', p)
        original = (p / '.codex/hooks.json').read_bytes()
        for variant in ('edited', 'duplicate', 'broken'):
            (p / '.codex/hooks.json').write_bytes(original)
            if variant == 'broken': (p / '.guardrails/source').unlink(); (p / '.guardrails/source').symlink_to(tmp / 'missing')
            else:
                doc = hooks(p)
                if variant == 'edited': doc['hooks']['PreToolUse'][0]['matcher'] = 'foreign'
                else: doc['hooks']['PreToolUse'] *= 2
                (p / '.codex/hooks.json').write_text(json.dumps(doc))
            out = status(p, rc=1)
            assert 'runtime-hooks: installed' not in out and ('conflict' in out or 'stale' in out)
        for path in ('README.md', 'adapters/codex/INSTRUCTIONS.md'):
            text = (wf / path).read_text()
            for token in ('--hooks', 'activation', 'trust', 'merge-preflight'): assert token in text, (path, token)
    elif scenario in (368, 369):
        adopt(p, '--hooks')
        (p / 'sub').mkdir()
        installed = command(p)
        fixture = json.loads((ROOT / 'test/fixtures/codex-544-events.json').read_text())
        event = fixture['events'][0]
        assert len(fixture['events']) == 2 and all(e['hook_event_name'] == 'PreToolUse' and e['tool_name'] == 'Bash' for e in fixture['events'])
        bindir = tmp / 'bin'; bindir.mkdir()
        fake = bindir / 'gh'
        fake.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
a = sys.argv[1:]; mode = os.environ.get('MERGE_STATE', 'allowed'); sha = '1'*40
with open(os.environ['GH_CALLS'], 'a') as f: f.write(json.dumps([os.getcwd(), a])+'\\n')
if a[:2] == ['pr','view']:
 print(json.dumps({'headRefOid':sha, 'comments':[{'body':'<!-- pre-merge-review:done sha='+('2'*40 if mode=='stale-review' else sha)+' -->' if mode!='missing-review' else ''}]}))
elif a[:2] == ['pr','checks']: print(json.dumps([{'name':'check','bucket':'fail' if mode=='ci' else 'pass'}]))
elif a and a[0]=='api':
 path=a[1]
 if '/compare/' in path: print(1 if mode=='behind' else 0)
 elif '.base.ref' in ' '.join(a): print('main\\t'+sha)
 elif path.endswith('/comments') or path.endswith('/issues/544/comments'):
  print('')
 elif path.endswith('/41'):
  print('title\\x01body\\x03')
 elif path.endswith('/commits'): print('')
 else: sys.exit(1)
else: sys.exit(1)
''')
        fake.chmod(0o755)
        calls = tmp / 'calls'; env.update(PATH=str(bindir)+os.pathsep+env['PATH'], GH_CALLS=str(calls))
        def hook(cmd, state='allowed', default=False):
            env['MERGE_STATE'] = state
            event['cwd'] = str(p / 'sub'); event['tool_input']['command'] = cmd
            calls.write_text('')
            args = [str(wf / 'hooks/git-guardrails')] if default else ['bash', '-c', installed]
            return subprocess.run(args, cwd=p / 'sub', env=env, input=json.dumps(event), capture_output=True, text=True)
        if scenario == 368:
            for state, reason in (('missing-review','review marker'), ('stale-review','review marker'), ('ci',"CI isn't green"), ('behind','behind its base'), ('allowed','')):
                for cmd in ('gh pr merge 41', "printf before; gh pr merge '41' --squash"):
                    result = hook(cmd, state)
                    assert result.returncode == (0 if state == 'allowed' else 2), (state,result)
                    assert reason in result.stderr and not result.stdout
                    assert calls.read_text(), 'no merge policy read'
                    assert all(json.loads(line)[0] == str(p / 'sub') for line in calls.read_text().splitlines())
                    sentinel = tmp / 'sentinel'
                    if result.returncode == 0: sentinel.write_text('executed')
                    assert sentinel.exists() == (state == 'allowed')
                    if sentinel.exists(): sentinel.unlink()
            # Opted-in role gate remains in the shared merge decision path.
            (p / 'WORKFLOW-ADOPTION.md').write_text('| process-multi-agent-roles | yes | date | reason |\n')
            result = hook('gh pr merge 41')
            assert result.returncode == 2 and 'role' in result.stderr.lower(), result
        else:
            for cmd in ('printf hello', 'git status', 'git reset --hard', 'git clean -fd', 'git push origin main', 'git checkout -b feature/no-issue'):
                result = hook(cmd)
                assert result.returncode == 0 and not calls.read_text(), (cmd,result)
                if cmd not in ('printf hello', 'git status'):
                    assert hook(cmd, default=True).returncode == 2, cmd
            assert hook('git reset --hard; gh pr merge 41', 'missing-review').returncode == 2
            # Claude install and native hooks still use the ordinary guard.
            q = project('claude'); run(wf / 'adopt.sh', q)
            settings = json.loads((q / '.claude/settings.json').read_text())
            assert '--merge-only' not in json.dumps(settings)
            for h in ('pre-commit','commit-msg','pre-push'): assert (q / '.git/hooks' / h).resolve() == wf / 'hooks' / h
    print('S%d: passed' % scenario)
