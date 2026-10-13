"""S288-S298: public commands and filesystem oracles; no fake runtime evidence."""
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(sys.argv[1])
SCENARIO = int(sys.argv[2])
tmp = Path(tempfile.mkdtemp())
wf = tmp / 'workflow'
shutil.copytree(ROOT, wf, ignore=shutil.ignore_patterns('.git', '.claude', '__pycache__'))
env = dict(os.environ, SPEC_DRIVEN_GUARDRAILS_DIR=str(wf))
def run(*args, rc=0, cwd=None):
    p = subprocess.run([str(a) for a in args], cwd=cwd or wf, env=env,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    assert p.returncode == rc, (args, p.returncode, rc, p.stdout)
    return p.stdout

def project(name='project'):
    p = tmp / name
    p.mkdir()
    run('git', 'init', '-q', '-b', 'main', p)
    return p

def adopt(p, *args, rc=0):
    return run(wf / 'adopt.sh', '--runtime', 'codex', *args, p, rc=rc)

def snapshot(p):
    return {str(f.relative_to(p)): ('link', os.readlink(f)) if f.is_symlink()
            else ('file', f.read_bytes()) for f in p.rglob('*') if f.is_symlink() or f.is_file()}

def status(p, rc=0):
    before = snapshot(p)
    out = adopt(p, '--status', rc=rc)
    assert before == snapshot(p), 'status wrote project/index'
    return out

def expect(out, text):
    assert text in out, (text, out)

try:
    if SCENARIO == 288:
        assert (wf / 'generate-workflow-adapters.sh').is_file(), 'missing generator'
        run(wf / 'generate-workflow-adapters.sh')
        before = snapshot(wf)
        run(wf / 'generate-workflow-adapters.sh')
        assert snapshot(wf) == before, 'nondeterministic generation'
        run(wf / 'check-workflow-adapters.sh')
        policy = wf / 'policy/WORKFLOW.md'
        policy.write_bytes(policy.read_bytes() + b'\nPOLICY-SENTINEL-455\n')
        out = run(wf / 'check-workflow-adapters.sh', rc=1)
        expect(out, 'WORKFLOW.md'); expect(out, 'adapters/codex/AGENTS.md')
        run(wf / 'generate-workflow-adapters.sh')
        for f in ('WORKFLOW.md', 'adapters/codex/AGENTS.md'):
            expect((wf / f).read_text(), 'POLICY-SENTINEL-455')
        for f in ('WORKFLOW.md', 'adapters/codex/AGENTS.md', 'adapters/claude/INSTRUCTIONS.md',
                  'adapters/codex/INSTRUCTIONS.md', 'skills/role-contracts/ORCHESTRATOR.md',
                  'skills/model-choice/SKILL.md'):
            target = wf / f; old = target.read_bytes(); target.unlink()
            expect(run(wf / 'check-workflow-adapters.sh', rc=1), f)
            target.write_bytes(old)
        run(wf / 'check-workflow-adapters.sh', tmp / 'missing', rc=2)
        assert 'check-workflow-adapters.sh' in (wf / 'check').read_text()
        p = project(); adopt(p)
        (p / 'WORKFLOW-ADOPTION.md').write_text('| process-multi-agent-roles | yes | date | reason |\n')
        out = run(wf / 'session-context.sh', '--runtime', 'codex', p)
        expect(out, (wf / 'skills/role-contracts/ORCHESTRATOR.md').read_text())
        (p / 'WORKFLOW-ADOPTION.md').write_text('| process-multi-agent-roles | no | date | reason |\n')
        assert (wf / 'skills/role-contracts/ORCHESTRATOR.md').read_text() not in run(wf / 'session-context.sh', '--runtime', 'codex', p)
    elif SCENARIO in (289, 290):
        p = project(); (p / '.codex').mkdir(); (p / '.codex/config.toml').write_text('trust = "withheld"\n')
        out = adopt(p); status(p)
        for skill in ('grilling', 'role-contracts', 'model-choice'):
            assert (p / '.agents/skills' / skill).is_symlink()
            assert (p / '.agents/skills' / skill / 'SKILL.md').read_bytes() == (wf / 'skills' / skill / 'SKILL.md').read_bytes()
        expect((p / 'AGENTS.md').read_text(), '.guardrails/source/session-context.sh --runtime codex')
        assert (p / '.codex/config.toml').read_text() == 'trust = "withheld"\n'
        assert not (p / 'CLAUDE.md').exists()
        expect(out, 'installed'); expect(out, 'not live-loaded')
        print('Structural discovery only; real CLI/desktop loading remains unobserved.')
    elif SCENARIO == 291:
        p = project(); prefix = b'Project-owned notes with no final newline'
        (p / 'AGENTS.md').write_bytes(prefix)
        (p / '.agents/skills/local').mkdir(parents=True)
        (p / '.agents/skills/local/SKILL.md').write_text('own skill')
        adopt(p); before = snapshot(p); adopt(p); assert before == snapshot(p)
        assert (p / 'AGENTS.md').read_bytes().startswith(prefix)
        status(p)
        for args in [('--runtime', 'other'), ('--runtime', 'codex', '--runtime', 'claude'),
                     ('--runtime', 'codex', '--user'), ('--bad',), ('--status', '--user')]:
            old = snapshot(p)
            run(wf / 'adopt.sh', *args, p, rc=2)
            assert snapshot(p) == old
        fixtures = ['override', 'symlink', 'duplicate', 'unmatched', 'nested', 'namespace',
                    'child-file', 'child-dir', 'foreign-link', 'broken-link', 'record', 'ignore', 'tracked', 'tracked-missing']
        for name in fixtures:
            q = project(name)
            if name == 'override': (q / 'AGENTS.override.md').write_text('override')
            elif name == 'symlink': (q / 'AGENTS.md').symlink_to(tmp / 'elsewhere')
            elif name in ('duplicate', 'unmatched', 'nested'):
                begin = '<!-- spec-driven-guardrails: begin -->\n'; end = '<!-- spec-driven-guardrails: end -->\n'
                (q / 'AGENTS.md').write_text(begin+end+begin+end if name == 'duplicate' else begin if name == 'unmatched' else begin+begin+end+end)
            elif name == 'namespace':
                (q / '.agents').mkdir(); (q / '.agents/skills').symlink_to(tmp)
            elif name in ('child-file', 'child-dir', 'foreign-link', 'broken-link', 'tracked', 'tracked-missing'):
                (q / '.agents/skills').mkdir(parents=True)
                f = q / '.agents/skills/grilling'
                if name == 'child-file': f.write_text('own')
                elif name == 'child-dir': f.mkdir()
                else: f.symlink_to(wf / 'skills/grilling' if name.startswith('tracked') else tmp / 'missing')
                if name.startswith('tracked'):
                    run('git', '-C', q, 'add', '.agents/skills/grilling')
                    if name == 'tracked-missing': f.unlink()
            elif name == 'record':
                (q / '.guardrails').mkdir(); (q / '.guardrails/installation.json').write_text('{"foreign":true}')
            elif name == 'ignore': (q / '.gitignore').write_text('# spec-driven-guardrails: begin\n')
            old = snapshot(q); expect(adopt(q, rc=1), 'conflict'); assert snapshot(q) == old, name
        # Recorded links may repair, manually redirected links may not.
        f = p / '.agents/skills/grilling'; f.unlink(); f.symlink_to(tmp / 'foreign')
        old = snapshot(p); adopt(p, rc=1); assert snapshot(p) == old
    elif SCENARIO == 292:
        p = project(); adopt(p)
        b = tmp / 'machine-b'; shutil.copytree(wf, b)
        shutil.rmtree(wf); env['SPEC_DRIVEN_GUARDRAILS_DIR'] = str(b); wf = b
        status(p, rc=1); adopt(p); status(p)
        assert (p / '.guardrails/source').resolve() == b.resolve()
        assert str(tmp) not in (p / 'AGENTS.md').read_text()
        for path in ('.guardrails/source', '.guardrails/installation.json', '.agents/skills/grilling'):
            run('git', '-C', p, 'check-ignore', path)
        assert run('git', '-C', p, 'check-ignore', '.agents/skills/project-skill', rc=1) == ''
        # Removed canonical skill cleans up only recorded ownership.
        shutil.rmtree(wf / 'skills/grilling'); adopt(p)
        assert not (p / '.agents/skills/grilling').is_symlink()
        (wf / 'policy/WORKFLOW.md').write_text((wf / 'policy/WORKFLOW.md').read_text()+'\nUPDATED-455\n')
        run(wf / 'generate-workflow-adapters.sh'); status(p, rc=1); adopt(p); status(p)
        print('One-host two-path recovery; real second-machine run remains unobserved.')
    elif SCENARIO == 293:
        p = project(); adopt(p)
        out = run(p / '.agents/skills/pre-merge-review/model-record-emit.sh', '--stage', 'Implementation', '--model', 'gpt-6.1-sol', cwd=p)
        control = run(wf / 'skills/pre-merge-review/model-record-emit.sh', '--stage', 'Implementation', '--model', 'gpt-6.1-sol')
        assert out == control
        run(p / '.agents/skills/pre-merge-review/model-record-emit.sh', '--stage', 'Review', '--model', 'gpt-6.1-sol', rc=2, cwd=p)
        assert not list((wf / 'adapters').rglob('*model-record*'))
        # Execute the shared skill's documented pending-adoption command from
        # a Codex project: it must resolve without Claude-only settings.
        skill = (p / '.agents/skills/pre-merge-review/SKILL.md').read_text()
        section = skill.split('## Pending adoption gate')[1].split('## ')[0]
        command = re.search(r'```(?:bash)?\n(.*?)```', section, re.S).group(1)
        expect(run('bash', '-c', command, cwd=p), 'process-multi-agent-roles')
    elif SCENARIO == 294:
        p = project(); (p / '.claude').mkdir(); (p / '.claude/settings.json').write_text('own settings')
        out = adopt(p)
        claim = 'runtime-hooks: not-installed; runtime shell interception unavailable'
        expect(out, claim); expect(status(p), claim)
        assert (p / '.claude/settings.json').read_text() == 'own settings'
        for hook in ('pre-commit', 'commit-msg', 'pre-push'):
            assert (p / '.git/hooks' / hook).is_symlink()
        assert not (p / '.codex').exists()
        expect((wf / 'adapters/codex/INSTRUCTIONS.md').read_text(), 'gh pr merge')
    elif SCENARIO in (295, 296, 298):
        assert (wf / 'adapters/codex/INSTRUCTIONS.md').is_file(), 'missing Codex mapping'
        mapping = (wf / 'adapters/codex/INSTRUCTIONS.md').read_text()
        orch = (wf / 'skills/role-contracts/ORCHESTRATOR.md').read_text()
        expect(mapping, 'ORCHESTRATOR.md'); expect(mapping, 'fresh'); expect(mapping, 'override')
        if SCENARIO == 295: expect(mapping, 'unavailable'); expect(orch, '**Cannot dispatch**')
        if SCENARIO == 296: expect(mapping, 'durable'); expect(orch, 'open findings')
        if SCENARIO == 298:
            expect(orch, 'without requesting confirmation'); expect(mapping, 'continue')
            expect(orch, 'completed initial stage'); expect(orch, 'main')
        print('Instruction contract only; live dispatch/resume/continuation remains unobserved.')
    elif SCENARIO == 297:
        p = project()
        expect(run(wf / 'adopt.sh', p), 'created: CLAUDE.md')
        expect(run(wf / 'adopt.sh', p), 'unchanged: CLAUDE.md')
        claude = {k:v for k,v in snapshot(p).items() if k == 'CLAUDE.md' or k.startswith('.claude/')}
        adopt(p)
        assert {k:v for k,v in snapshot(p).items() if k == 'CLAUDE.md' or k.startswith('.claude/')} == claude
        report = wf / 'docs/codex-dry-runs.md'
        assert report.is_file(), 'missing honest runtime evidence matrix'
        for text in ('CLI', 'desktop', 'Claude', 'second machine', 'unobserved'):
            expect(report.read_text(), text)
    print('S%d: automated assertions passed' % SCENARIO)
finally:
    shutil.rmtree(tmp)
