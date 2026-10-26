"""S294-S304: public commands and filesystem oracles; no fake runtime evidence."""
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
shutil.copytree(ROOT, wf, ignore=shutil.ignore_patterns('.git', '.claude', '.guardrails', '.agents', '__pycache__'))
env = dict(os.environ, SPEC_DRIVEN_GUARDRAILS_DIR=str(wf))
def run(*args, rc=0, cwd=None):
    p = subprocess.run([str(a) for a in args], cwd=cwd or wf, env=env,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    assert p.returncode == rc, (args, p.returncode, rc, p.stdout)
    return p.stdout

SLOT_MARKER = '<!-- session-context: slot -->'


def rule_item(orch, rid, tier, part):
    """The one OR item of rid (with continuation lines), checked against the inventory."""
    hits, cur = [], 1
    lines = orch.split('\n')
    for i, line in enumerate(lines):
        if line == SLOT_MARKER:
            cur += 1
        if re.match(r'^ *- %s ' % rid, line):
            j = i + 1
            while j < len(lines) and lines[j].strip() and lines[j].startswith(' ') and not re.match(r'^ *- OR\d+ ', lines[j]):
                j += 1
            hits.append((cur, '\n'.join(lines[i:j])))
    assert len(hits) == 1, f'{rid} starts exactly one item'
    assert hits[0][0] == part, f'{rid} sits in part {part}'
    rows = [l.split('\t') for l in (wf / 'skills/role-contracts/orchestrator-rules.tsv').read_text().splitlines()]
    row = [r for r in rows if r[0] == rid]
    assert row and row[0][2] == tier and row[0][3] == str(part), f'{rid} inventory row is {tier}, part {part}'
    return hits[0][1]


def project(name='project'):
    p = tmp / name
    p.mkdir()
    run('git', 'init', '-q', '-b', 'main', p)
    return p

def adopt(p, *args, rc=0):
    return run(wf / 'adopt.sh', '--runtime', 'codex', *args, p, rc=rc)

def snapshot(p):
    return {str(f.relative_to(p)): ('link', os.readlink(f), f.lstat().st_mode) if f.is_symlink()
            else ('file', f.read_bytes(), f.lstat().st_mode) if f.is_file() else ('directory', f.lstat().st_mode)
            for f in p.rglob('*')}

def status(p, rc=0):
    before = snapshot(p)
    out = adopt(p, '--status', rc=rc)
    assert before == snapshot(p), 'status wrote project/index'
    return out

def expect(out, text):
    assert text in out, (text, out)

try:
    if SCENARIO == 294:
        assert (wf / 'generate-workflow-adapters.sh').is_file(), 'missing generator'
        committed = (wf / 'AGENTS.md').read_bytes().split(b'<!-- spec-driven-guardrails: begin -->', 1)[1].split(b'<!-- spec-driven-guardrails: end -->', 1)[0]
        assert b'Abbreviated workflow' in committed and b'pipeline-override.sh' in committed
        run(wf / 'generate-workflow-adapters.sh')
        before = snapshot(wf)
        run(wf / 'generate-workflow-adapters.sh')
        assert snapshot(wf) == before, 'nondeterministic generation'
        run(wf / 'check-workflow-adapters.sh')
        # #575: delete the short-track bullet only in the root carrier.
        root_agents = wf / 'AGENTS.md'
        payload = (wf / 'adapters/codex/AGENTS.md').read_bytes()
        begin = b'<!-- spec-driven-guardrails: begin -->'
        end = b'<!-- spec-driven-guardrails: end -->'
        framed = begin + b'\n' + payload + end
        root_agents.write_bytes(framed + b'\n')
        root_agents.write_bytes(re.sub(rb'^- \*\*Abbreviated workflow\*\*[^\n]*\n', b'', root_agents.read_bytes(), flags=re.M))
        out = run(wf / 'check-workflow-adapters.sh', rc=1)
        expect(out, 'AGENTS.md'); expect(out, 'adapters/codex/AGENTS.md')
        run(wf / 'generate-workflow-adapters.sh')
        assert root_agents.read_bytes() == framed + b'\n'
        before = snapshot(wf)
        run(wf / 'check-workflow-adapters.sh', wf)
        assert snapshot(wf) == before, 'checker wrote workflow'
        for literal in ('Abbreviated workflow', 'pipeline-override.sh'):
            run('grep', '-F', literal, root_agents)
        assert root_agents.read_bytes() == framed + b'\n'
        # Payload-only drift is compared to the root before regeneration.
        codex = wf / 'adapters/codex/AGENTS.md'
        codex.write_bytes(payload + b'PAYLOAD-ONLY\n')
        out = run(wf / 'check-workflow-adapters.sh', rc=1)
        expect(out, 'root AGENTS.md'); expect(out, 'adapters/codex/AGENTS.md')
        run(wf / 'generate-workflow-adapters.sh', wf)
        prefix = b'owner \xff\r\n'
        suffix = b'\r\nowner \xfe no final newline'
        root_agents.write_bytes(prefix + framed + suffix)
        run(wf / 'check-workflow-adapters.sh')
        root_agents.write_bytes(prefix + begin + b'\nstale\n' + end + suffix)
        run(wf / 'generate-workflow-adapters.sh')
        assert root_agents.read_bytes() == prefix + framed + suffix
        before = snapshot(wf)
        run(wf / 'generate-workflow-adapters.sh')
        assert snapshot(wf) == before
        adopted = project('root-framing'); adopt(adopted)
        assert (adopted / 'AGENTS.md').read_bytes() == framed + b'\n'
        (adopted / '.codex').mkdir()
        (adopted / '.codex/config.toml').write_text('project config')
        (adopted / 'WORKFLOW-ADOPTION.md').write_text('project answers')
        adopted_before = snapshot(adopted)
        external = tmp / 'external-root'; external.write_bytes(b'external sentinel')
        workflow_output = wf / 'WORKFLOW.md'
        workflow_bytes = workflow_output.read_bytes()
        workflow_output.write_bytes(b'stale output must not be repaired on invalid root')
        for bad in (b'unmarked', begin, end + b'\n' + begin,
                    begin + begin + end + end, framed + b'\n' + framed,
                    'link', 'broken-link', 'directory'):
            root_agents.unlink()
            if bad == 'directory': root_agents.mkdir()
            elif bad in ('link', 'broken-link'):
                root_agents.symlink_to(external if bad == 'link' else tmp / 'absent-target')
            else: root_agents.write_bytes(bad)
            before = snapshot(wf)
            for command in ('generate', 'check'):
                expect(run(wf / (command + '-workflow-adapters.sh'), wf, rc=2), 'AGENTS.md')
                assert snapshot(wf) == before, 'invalid root caused writes'
                assert external.read_bytes() == b'external sentinel'
            if root_agents.is_dir() and not root_agents.is_symlink(): root_agents.rmdir()
            else: root_agents.unlink()
            root_agents.write_bytes(framed + b'\n')
        workflow_output.write_bytes(workflow_bytes)
        root_agents.chmod(0)
        if os.access(root_agents, os.R_OK):
            print('Unreadable-root fixture unavailable: runner bypasses mode permissions')
        else:
            for command in ('generate', 'check'):
                run(wf / (command + '-workflow-adapters.sh'), rc=2)
        root_agents.chmod(0o644)
        root_agents.unlink()
        expect(run(wf / 'check-workflow-adapters.sh', rc=1), 'missing output: root AGENTS.md')
        run(wf / 'generate-workflow-adapters.sh')
        assert root_agents.read_bytes() == framed + b'\n'
        assert snapshot(adopted) == adopted_before
        policy = wf / 'policy/WORKFLOW.md'
        policy.write_bytes(policy.read_bytes() + b'\nPOLICY-SENTINEL-455\n')
        out = run(wf / 'check-workflow-adapters.sh', rc=1)
        expect(out, 'WORKFLOW.md'); expect(out, 'adapters/codex/AGENTS.md')
        run(wf / 'generate-workflow-adapters.sh')
        assert snapshot(adopted) == adopted_before, 'generation changed adopted project'
        for f in ('WORKFLOW.md', 'adapters/codex/AGENTS.md', 'AGENTS.md'):
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
        # Amended by #499 (AC14, A41): verbatim means the file minus its one
        # slot marker line, both parts and their headers kept; the marker
        # line itself is never printed.
        orch_text = (wf / 'skills/role-contracts/ORCHESTRATOR.md').read_text()
        assert orch_text.count(SLOT_MARKER + '\n') == 1, 'ORCHESTRATOR.md has one slot marker line'
        expect(out, orch_text.replace(SLOT_MARKER + '\n', ''))
        assert SLOT_MARKER not in out, 'the slot marker line was printed'
        (p / 'WORKFLOW-ADOPTION.md').write_text('| process-multi-agent-roles | no | date | reason |\n')
        out_no = run(wf / 'session-context.sh', '--runtime', 'codex', p)
        for part in orch_text.split(SLOT_MARKER + '\n'):
            assert part.splitlines()[0] not in out_no, 'a part printed for a project that did not opt in'

    elif SCENARIO in (295, 296):
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
    elif SCENARIO == 297:
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
        foreign_hooks = project('foreign-hooks')
        for hook in ('pre-commit', 'commit-msg', 'pre-push'):
            (foreign_hooks / '.git/hooks' / hook).write_text('project-owned hook sentinel')
        hook_before = snapshot(foreign_hooks / '.git/hooks')
        out = adopt(foreign_hooks)
        expect(out, 'native-hook unavailable/foreign: .git/hooks/pre-commit')
        assert snapshot(foreign_hooks / '.git/hooks') == hook_before
        status(foreign_hooks, rc=1)
        assert snapshot(foreign_hooks / '.git/hooks') == hook_before
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
                else:
                    target = wf / 'skills/grilling' if name.startswith('tracked') else tmp / 'missing'
                    if name == 'foreign-link':
                        target = tmp / 'live-foreign'; target.mkdir()
                        (target / 'SKILL.md').write_text('foreign sentinel')
                    f.symlink_to(target)
                    assert f.is_symlink()
                    if name == 'foreign-link':
                        assert f.exists() and f.resolve() == target.resolve()
                        assert (f / 'SKILL.md').read_text() == 'foreign sentinel'
                    elif name == 'broken-link': assert not f.exists()
                if name.startswith('tracked'):
                    run('git', '-C', q, 'add', '.agents/skills/grilling')
                    if name == 'tracked-missing': f.unlink()
            elif name == 'record':
                (q / '.guardrails').mkdir(); (q / '.guardrails/installation.json').write_text('{"foreign":true}')
            elif name == 'ignore': (q / '.gitignore').write_text('# spec-driven-guardrails: begin\n')
            external = tmp / 'live-foreign'
            external_before = snapshot(external) if external.exists() else {}
            old = snapshot(q); out = adopt(q, rc=1); expect(out, 'conflict'); assert snapshot(q) == old, name
            if name in ('foreign-link', 'broken-link'): expect(out, '.agents/skills/grilling')
            assert (snapshot(external) if external.exists() else {}) == external_before, name
        # Valid machine-local provenance is forbidden in the index, even when
        # its worktree file or original checkout has disappeared (S297/S298).
        failures = []
        for case in ('staged', 'committed', 'absent-record', 'clone', 'retained'):
            for command in ((), ('--status',)):
                label = case + ('-status' if command else '-adopt')
                a = (tmp / ('checkout-a-' + label)).resolve()
                shutil.copytree(wf, a)
                q = project('provenance-' + label)
                (q / 'AGENTS.md').write_text('project outside-block sentinel\n')
                (q / 'WORKFLOW-ADOPTION.md').write_text('project answers sentinel\n')
                (q / '.codex').mkdir(); (q / '.codex/config.toml').write_text('project config')
                (q / '.agents/skills/local').mkdir(parents=True)
                (q / '.agents/skills/local/SKILL.md').write_text('project skill')
                env['SPEC_DRIVEN_GUARDRAILS_DIR'] = str(a)
                adopt(q)
                env['SPEC_DRIVEN_GUARDRAILS_DIR'] = str(wf)
                record = '.guardrails/installation.json'
                valid = json.loads((q / record).read_bytes())
                assert valid['checkout'] == str(a) and valid['links']['.guardrails/source'] == str(a)
                assert all(target.startswith(str(a)) for target in valid['links'].values())
                run('git', '-C', q, 'add', 'AGENTS.md', 'WORKFLOW-ADOPTION.md', '.codex', '.agents/skills/local', '.gitignore')
                run('git', '-C', q, 'add', '-f', record)
                if case != 'staged':
                    run('git', '-C', q, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                        '-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'tracked provenance')
                committed = run('git', '-C', q, 'show', 'HEAD:' + record) if case != 'staged' else None
                if case == 'clone':
                    original = q; q = tmp / ('received-' + label)
                    run('git', 'clone', '-q', original, q)
                    assert not (q / '.guardrails/source').is_symlink()
                if case == 'absent-record': (q / record).unlink()
                if case == 'retained': shutil.rmtree(a)
                (q / 'tracked-sentinel').write_text('unrelated staged sentinel')
                run('git', '-C', q, 'add', 'tracked-sentinel')
                (q / 'check').write_text('stale scaffolding sentinel')
                indexed = run('git', '-C', q, 'show', ':' + record)
                assert json.loads(indexed) == valid and str(a) in indexed
                if case != 'absent-record': assert json.loads((q / record).read_bytes()) == valid
                # Read Git identity/index oracles before raw snapshots; no Git
                # command between the raw snapshots may refresh the index.
                staged = run('git', '-C', q, 'ls-files', '--stage', '-z')
                head = run('git', '-C', q, 'rev-parse', '--verify', 'HEAD', rc=128 if case == 'staged' else 0)
                before = snapshot(q); index = (q / '.git/index').read_bytes()
                env['SPEC_DRIVEN_GUARDRAILS_DIR'] = str(a if case in ('staged', 'committed', 'absent-record') else wf)
                result = subprocess.run([str(wf / 'adopt.sh'), '--runtime', 'codex', *command, str(q)],
                                        env=env, capture_output=True, text=True)
                after = snapshot(q); index_after = (q / '.git/index').read_bytes()
                env['SPEC_DRIVEN_GUARDRAILS_DIR'] = str(wf)
                out = result.stdout + result.stderr
                try:
                    assert result.returncode == 1, (result.returncode, out)
                    expect(out, record + ': tracked machine-local provenance')
                    expect(out, 'explicitly untrack or relocate')
                    assert before == after, 'project/index mutation'
                    assert index == index_after, 'raw index mutation'
                    assert staged == run('git', '-C', q, 'ls-files', '--stage', '-z')
                    assert head == run('git', '-C', q, 'rev-parse', '--verify', 'HEAD', rc=128 if case == 'staged' else 0)
                    assert indexed == run('git', '-C', q, 'show', ':' + record)
                    if committed is not None: assert committed == run('git', '-C', q, 'show', 'HEAD:' + record)
                except AssertionError as exc:
                    failures.append((label, str(exc)))
                print('tracked provenance %s: %s' % (label, 'FAIL' if failures and failures[-1][0] == label else 'PASS'))
        assert not failures, failures
        # S297: shared scaffolds are part of the same no-write preflight.
        failures = []
        cases = [(path, live) for path in (
            '.github', '.github/ISSUE_TEMPLATE', '.github/workflows',
            '.github/ISSUE_TEMPLATE/bug.md', '.github/ISSUE_TEMPLATE/config.yml',
            '.github/workflows/ci.yml', 'check-traceability.sh',
            'check-pr-issue-link.sh', 'check-main-via-pr.sh', 'wait-for-ci.sh',
            'PRD.md', 'TEST-SCENARIOS.md', 'ARCHITECTURE.md',
            'WORKFLOW-ADOPTION.md', 'CONTEXT.md') for live in (False, True) if not (path == 'WORKFLOW-ADOPTION.md' and live)]
        template_name = next((wf / 'templates/ISSUE_TEMPLATE').glob('*.md')).name
        cases = [(path.replace('bug.md', template_name), live) for path, live in cases]
        cases += [('.github', True), ('wait-for-ci.sh', True)]
        for number, (path, live) in enumerate(cases):
            q = project('shared-%d' % number)
            (q / '.agents').mkdir(); (q / '.guardrails').mkdir()
            (q / 'tracked-sentinel').write_text('staged sentinel')
            run('git', '-C', q, 'add', 'tracked-sentinel')
            (q / 'check').write_text('#!/bin/sh\nexit 0\n'); (q / 'check').chmod(0o750)
            (q / 'AGENTS.md').write_text('project prefix')
            (q / '.gitignore').write_text('local-ignore\n')
            if path != 'WORKFLOW-ADOPTION.md':
                (q / 'WORKFLOW-ADOPTION.md').write_text(
                    '| process-issue-tracking | yes | date | reason |\n'
                    '| process-context-document | yes | date | reason |\n')
            if number == len(cases)-1:
                adopt(q)
                (q / 'AGENTS.md').write_text((q / 'AGENTS.md').read_text().replace('project prefix', 'pending prefix'))
            external = tmp / ('shared-external-%d' % number); external.mkdir(); external.chmod(0o750)
            (external / 'sentinel').write_text('external sentinel'); (external / 'sentinel').chmod(0o640)
            target = external / 'target'
            directory = path in ('.github', '.github/ISSUE_TEMPLATE', '.github/workflows')
            if live:
                if directory:
                    target.mkdir(); target.chmod(0o750)
                    if path.endswith('ISSUE_TEMPLATE'):
                        for src in (wf / 'templates/ISSUE_TEMPLATE').iterdir():
                            (target / src.name).write_text('external template'); (target / src.name).chmod(0o640)
                    if number == len(cases)-2: (target / 'workflows').mkdir()
                else: target.write_text('external file'); target.chmod(0o640)
            leaf = q / path; leaf.parent.mkdir(parents=True, exist_ok=True)
            if leaf.exists(): leaf.unlink()
            leaf.symlink_to(target, target_is_directory=directory)
            assert leaf.is_symlink() and os.readlink(leaf) == str(target)
            assert leaf.exists() == live and not target.is_relative_to(q)
            if live: assert leaf.resolve() == target.resolve()
            for args in ((), ('--status',)):
                before = snapshot(q); outside = snapshot(external)
                index = ((q / '.git/index').read_bytes(), (q / '.git/index').stat().st_mode)
                result = subprocess.run([str(wf / 'adopt.sh'), '--runtime', 'codex', *args, str(q)],
                                        env=env, capture_output=True, text=True)
                out = result.stdout + result.stderr
                try:
                    assert result.returncode == 1, out
                    expect(out, 'conflict: ' + path)
                    assert 'adapter installed' not in out and 'Done:' not in out, out
                    assert snapshot(q) == before, 'project changed'
                    assert snapshot(external) == outside, 'external bytes/modes changed'
                    assert ((q / '.git/index').read_bytes(), (q / '.git/index').stat().st_mode) == index
                except AssertionError as exc:
                    failures.append((path, live, args, str(exc)))
        assert not failures, failures
        # Real-file controls: template refresh, executable helpers, stable index,
        # repeated adoption, explicit/default Claude, and Codex coexistence.
        for runtime in ('codex', 'default-claude', 'claude'):
            q = project('ordinary-' + runtime)
            (q / 'tracked-sentinel').write_text('index sentinel')
            run('git', '-C', q, 'add', 'tracked-sentinel')
            index = (q / '.git/index').read_bytes()
            (q / 'check').write_text('#!/bin/sh\nexit 0\n'); (q / 'check').chmod(0o750)
            (q / 'WORKFLOW-ADOPTION.md').write_text('| process-context-document | yes | date | reason |\n')
            (q / '.github/ISSUE_TEMPLATE').mkdir(parents=True)
            (q / '.github/ISSUE_TEMPLATE' / template_name).write_text('outdated project template')
            for name in ('PRD.md', 'TEST-SCENARIOS.md', 'ARCHITECTURE.md', 'CONTEXT.md'):
                (q / name).write_text('preserved ' + name)
            command = [wf / 'adopt.sh'] + ([] if runtime == 'default-claude' else ['--runtime', runtime])
            run(*command, q)
            assert (q / '.github/ISSUE_TEMPLATE' / template_name).read_bytes() == (wf / 'templates/ISSUE_TEMPLATE' / template_name).read_bytes()
            assert (q / '.github/workflows/ci.yml').is_file()
            for name in ('check-traceability.sh', 'check-pr-issue-link.sh', 'check-main-via-pr.sh', 'wait-for-ci.sh'):
                assert os.access(q / name, os.X_OK)
            for name in ('PRD.md', 'TEST-SCENARIOS.md', 'ARCHITECTURE.md', 'CONTEXT.md'):
                assert (q / name).read_text() == 'preserved ' + name
            before = snapshot(q); run(*command, q); assert before == snapshot(q)
            assert (q / '.git/index').read_bytes() == index
            if runtime != 'codex':
                claude = {k:v for k,v in snapshot(q).items() if k == 'CLAUDE.md' or k.startswith('.claude/')}
                adopt(q)
                assert {k:v for k,v in snapshot(q).items() if k == 'CLAUDE.md' or k.startswith('.claude/')} == claude
        # Recorded links may repair, manually redirected links may not.
        foreign = tmp / 'redirect-live'; foreign.mkdir(); (foreign / 'SKILL.md').write_text('redirect sentinel')
        f = p / '.agents/skills/grilling'; f.unlink(); f.symlink_to(foreign)
        assert f.exists() and f.resolve() == foreign.resolve()
        assert (f / 'SKILL.md').read_text() == 'redirect sentinel'
        external_before = snapshot(foreign)
        old = snapshot(p); expect(adopt(p, rc=1), '.agents/skills/grilling'); assert snapshot(p) == old
        assert snapshot(foreign) == external_before
        # Parent escapes need an independent oracle: the project walker does not follow links.
        for parent in ('.git/hooks', '.git'):
            q = project('escape-' + parent.replace('/', '-'))
            (q / 'tracked-sentinel').write_text('index sentinel')
            run('git', '-C', q, 'add', 'tracked-sentinel')
            external = tmp / ('external-' + parent.replace('/', '-'))
            shutil.move(str(q / parent), external)
            (q / parent).symlink_to(external, target_is_directory=True)
            (external / 'sentinel').write_text('external sentinel')
            hooks = external if parent.endswith('hooks') else external / 'hooks'
            assert (q / parent).resolve() == external.resolve()
            assert not external.is_relative_to(q)
            assert all(not (hooks / h).exists() for h in ('pre-commit', 'commit-msg', 'pre-push'))
            for args in ((), ('--status',)):
                old = snapshot(q); external_before = snapshot(external)
                expect(adopt(q, *args, rc=1), parent + ': unsafe parent')
                assert snapshot(q) == old, parent
                assert snapshot(external) == external_before, parent
                assert all(not (hooks / h).exists() for h in ('pre-commit', 'commit-msg', 'pre-push'))
    elif SCENARIO == 298:
        p = project()
        (p / 'AGENTS.md').write_text('owner prefix\n')
        (p / 'WORKFLOW-ADOPTION.md').write_text('owner answers')
        (p / 'tracked-sentinel').write_text('index sentinel')
        run('git', '-C', p, 'add', 'tracked-sentinel')
        index = (p / '.git/index').read_bytes()
        adopt(p)
        run('git', '-C', p, 'add', 'AGENTS.md', 'WORKFLOW-ADOPTION.md', '.gitignore')
        run('git', '-C', p, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
            '-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'portable shared project')
        clone = tmp / 'portable-clone'; run('git', 'clone', '-q', p, clone)
        assert not (clone / '.guardrails/installation.json').exists()
        assert not (clone / '.guardrails/source').is_symlink()
        index = (p / '.git/index').read_bytes()
        b = tmp / 'machine-b'; shutil.copytree(wf, b)
        shutil.rmtree(wf); env['SPEC_DRIVEN_GUARDRAILS_DIR'] = str(b); wf = b
        status(p, rc=1); adopt(p); status(p)
        assert (p / '.git/index').read_bytes() == index
        assert (p / 'AGENTS.md').read_text().startswith('owner prefix\n')
        assert (p / 'WORKFLOW-ADOPTION.md').read_text() == 'owner answers'
        status(clone, rc=1)
        clone_index = (clone / '.git/index').read_bytes()
        adopt(clone); status(clone)
        before = snapshot(clone); adopt(clone); assert snapshot(clone) == before
        assert (clone / '.git/index').read_bytes() == clone_index
        for shared in (p, clone):
            names = run('git', '-C', shared, 'ls-files', '-z').split('\0')
            assert '.guardrails/installation.json' not in names
            assert not any(n.startswith('.agents/skills/') or n == '.guardrails/source' for n in names)
            for name in filter(None, names):
                blob = run('git', '-C', shared, 'show', 'HEAD:' + name)
                assert str(tmp) not in blob and str(tmp.resolve()) not in blob
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
    elif SCENARIO == 299:
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
    elif SCENARIO == 300:
        p = project(); (p / '.claude').mkdir(); (p / '.claude/settings.json').write_text('own settings')
        out = adopt(p)
        claim = 'runtime-hooks: not-installed; runtime shell interception unavailable'
        expect(out, claim); expect(status(p), claim)
        assert (p / '.claude/settings.json').read_text() == 'own settings'
        for hook in ('pre-commit', 'commit-msg', 'pre-push'):
            assert (p / '.git/hooks' / hook).is_symlink()
        assert not (p / '.codex').exists()
        expect((wf / 'adapters/codex/INSTRUCTIONS.md').read_text(), 'gh pr merge')
    elif SCENARIO in (301, 302, 304):
        assert (wf / 'adapters/codex/INSTRUCTIONS.md').is_file(), 'missing Codex mapping'
        mapping = (wf / 'adapters/codex/INSTRUCTIONS.md').read_text()
        orch = (wf / 'skills/role-contracts/ORCHESTRATOR.md').read_text()
        expect(mapping, 'ORCHESTRATOR.md'); expect(mapping, 'fresh'); expect(mapping, 'override')
        # Amended by #499 (AC14, A41): ORCHESTRATOR.md rules located by ID,
        # tier and part instead of bold labels and case-sensitive literals.
        if SCENARIO == 301: expect(mapping, 'unavailable'); rule_item(orch, 'OR35', 'judgment', 1)
        if SCENARIO == 302: expect(mapping, 'durable'); expect(orch, 'open findings')
        if SCENARIO == 304:
            assert '`main`' in rule_item(orch, 'OR6', 'judgment', 1), 'OR6 names main (the merge stop)'
            expect(mapping, 'continue')
            rule_item(orch, 'OR36', 'judgment', 2)
        print('Instruction contract only; live dispatch/resume/continuation remains unobserved.')
    elif SCENARIO == 303:
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
