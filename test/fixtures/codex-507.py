"""#507 public status Interface and instruction pins; never live-loading proof."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(sys.argv[1])
SCENARIO = int(sys.argv[2])


def snapshot(root, readable_handles=None):
    # Include hidden paths, empty directories, modes, link text and file bytes.
    # Do not follow links out of the isolated trees or use timestamps changed by reads.
    def content(p):
        if readable_handles and p in readable_handles:
            handle = readable_handles[p]
            handle.seek(0)
            return handle.read()
        return p.read_bytes()

    return {str(p.relative_to(root)): (p.lstat().st_mode,
            ('link', os.readlink(p)) if p.is_symlink() else
            ('file', content(p)) if p.is_file() else ('directory',))
            for p in root.rglob('*')}


def run(args, cwd, env, rc=0):
    result = subprocess.run([str(a) for a in args], cwd=cwd, env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    assert result.returncode == rc, (args, result.returncode, rc, result.stdout)
    return result.stdout


def pins(text, checks, label):
    failures = [description for description, pattern in checks
                if not re.search(pattern, ' '.join(text.split()), re.I)]
    assert not failures, label + ': missing ' + '; '.join(failures)


with tempfile.TemporaryDirectory() as directory:
    tmp = Path(directory)
    wf = tmp / 'workflow'
    # Same isolated canonical-checkout pattern as codex-455.py on main.
    shutil.copytree(ROOT, wf, symlinks=True, ignore=shutil.ignore_patterns(
        '.git', '.claude', '.guardrails', '.agents', '__pycache__'))
    env = dict(os.environ, SPEC_DRIVEN_GUARDRAILS_DIR=str(wf), PYTHONDONTWRITEBYTECODE='1')

    def project(name):
        p = tmp / name
        # An empty Git repository, without running a Git write command.
        for child in ('objects', 'refs/heads', 'hooks'):
            (p / '.git' / child).mkdir(parents=True, exist_ok=True)
        (p / '.git/HEAD').write_text('ref: refs/heads/main\n')
        run([wf / 'adopt.sh', '--runtime', 'codex', p], ROOT, env)
        return p

    def status(p, rc=0, launcher=None):
        before = snapshot(tmp)
        result = run([launcher or wf / 'adopt.sh', '--runtime', 'codex', '--status', '.'],
                     p, env, rc)
        assert snapshot(tmp) == before, 'status changed project, checkout or external sentinel tree'
        return result

    if SCENARIO == 436:
        checks = [
            ('status command before dependent work', r'\.guardrails/source/adopt\.sh --runtime codex --status \..{0,200}before dependent work|before dependent work.{0,200}\.guardrails/source/adopt\.sh --runtime codex --status \.'),
            ('surface each stale/broken/missing skill line', r'(surface|report|show).{0,100}(each|every).{0,100}stale/broken/missing: \.agents/skills/'),
            ('ordinary Codex adoption remedy', r'(rerun|re-run).{0,100}(ordinary Codex adoption|adopt\.sh --runtime codex)'),
            ('report unavailable or failure and continue the session', r'(unavailable|failure|nonzero|non-zero).{0,250}(report|surface).{0,250}continue|report.{0,250}(unavailable|failure|nonzero|non-zero).{0,250}continue'),
            ('structural drift is not current-session loading', r'structural drift.{0,160}(not|never).{0,160}(load|discover)'),
            ('no session repair/create/delete', r'(do not|never|must not).{0,100}repair.{0,100}create.{0,100}(delete|remove)'),
            ('nonzero status means structural drift only', r'(nonzero|non-zero|exit.{0,20}1).{0,160}structural drift'),
            ('adopt.sh owns repair', r'adopt\.sh.{0,100}(sole owner|only owner|only command).{0,100}repair'),
        ]
        errors = []
        for name in ('adapters/codex/INSTRUCTIONS.md', 'adapters/codex/AGENTS.md', 'AGENTS.md'):
            try:
                pins((wf / name).read_text(), checks, name)
            except AssertionError as exc:
                errors.append(str(exc))
        assert not errors, '\n'.join(errors)
    elif SCENARIO == 437:
        checker = wf / 'check-workflow-adapters.sh'
        before = snapshot(tmp)
        run([checker], ROOT, env)
        assert snapshot(tmp) == before, 'generation drift checker wrote files'
        # Exercise the existing checker, not a second generator oracle.
        for name in ('adapters/codex/INSTRUCTIONS.md', 'adapters/codex/AGENTS.md', 'AGENTS.md'):
            target = wf / name
            original = target.read_bytes()
            if name == 'AGENTS.md':
                target.write_bytes(original.replace(b'<!-- spec-driven-guardrails: end -->',
                                                   b'COPY-DRIFT-507\n<!-- spec-driven-guardrails: end -->'))
            else:
                target.write_bytes(original + b'\nCOPY-DRIFT-507\n')
            before = snapshot(tmp)
            out = run([checker], ROOT, env, 1)
            assert 'drift:' in out and ('root AGENTS.md' if name == 'AGENTS.md' else 'adapters/codex/AGENTS.md') in out, out
            assert snapshot(tmp) == before, 'generation drift checker repaired drift'
            target.write_bytes(original)
        run([checker], ROOT, env)
    elif SCENARIO == 438:
        p = project('added-skill')
        assert 'stale/broken/missing: .agents/skills/' not in status(p)
        for name in ('new-skill-507-a', 'new-skill-507-b'):
            skill = wf / 'skills' / name
            skill.mkdir()
            (skill / 'SKILL.md').write_text('---\nname: ' + name + '\ndescription: Test skill\n---\n')
        out = status(p, 1)
        for name in ('new-skill-507-a', 'new-skill-507-b'):
            assert 'stale/broken/missing: .agents/skills/' + name in out, out
            assert not os.path.lexists(p / '.agents/skills' / name), 'status repaired missing link'
    elif SCENARIO == 439:
        p = project('current')
        out = status(p, launcher=p / '.guardrails/source/adopt.sh')
        assert 'stale/broken/missing: .agents/skills/' not in out, out
        for skill in (wf / 'skills').iterdir():
            if skill.is_dir():
                assert 'unchanged: .agents/skills/' + skill.name in out, out
        assert 'structural installation only; not live-loaded' in out, out
    elif SCENARIO == 440:
        for case in ('absent-record', 'malformed-record', 'missing-source',
                     'foreign-file', 'foreign-directory', 'foreign-link', 'broken-link'):
            p = project(case)
            record = p / '.guardrails/installation.json'
            link = p / '.agents/skills/grilling'
            if case == 'absent-record':
                record.unlink()
                expected = 'stale/missing: .guardrails/installation.json'
            elif case == 'malformed-record':
                record.write_text('{bad json')
                expected = 'conflict: .guardrails/installation.json: malformed/foreign provenance:'
            elif case == 'missing-source':
                (p / '.guardrails/source').unlink()
                expected = 'stale/broken/missing: .guardrails/source'
            else:
                link.unlink()
                expected = 'conflict: .agents/skills/grilling: '
                if case == 'foreign-file':
                    link.write_text('project-owned sentinel')
                    expected += 'project-owned file/directory'
                elif case == 'foreign-directory':
                    link.mkdir()
                    (link / 'SKILL.md').write_text('project-owned sentinel')
                    expected += 'project-owned file/directory'
                else:
                    foreign = tmp / (case + '-target')
                    if case == 'foreign-link':
                        foreign.mkdir()
                        (foreign / 'SKILL.md').write_text('foreign sentinel')
                    link.symlink_to(foreign)
                    expected += 'foreign/broken unrecorded/manually redirected link'
            out = status(p, 1)
            assert expected in out, (case, expected, out)
            print(case + ': exit 1, expected diagnostic, identical tree')
        # Missing source prevents the instructed project-relative command from
        # starting at all. This is unavailable, not a status scanner verdict.
        before = snapshot(tmp)
        out = run(['bash', '.guardrails/source/adopt.sh', '--runtime', 'codex', '--status', '.'], tmp / 'missing-source', env, 127)
        assert 'No such file or directory' in out, out
        assert snapshot(tmp) == before, 'unavailable launcher changed tree'
        # An unreadable script is a launcher failure, too. Probe readability so
        # privileged runners never turn an unobserved permission case green.
        script = wf / 'adopt.sh'
        mode = script.stat().st_mode
        # Keep a read descriptor opened before chmod, so the snapshot still
        # observes actual bytes rather than caching an expected unreadable file.
        handle = script.open('rb')
        readable = {script: handle}
        script.chmod(0)
        try:
            if os.access(script, os.R_OK):
                print('UNVERIFIED: unreadable status script; runner bypasses mode permissions')
            else:
                before = snapshot(tmp, readable)
                out = run(['bash', script, '--runtime', 'codex', '--status', '.'], tmp / 'absent-record', env, 126)
                assert 'Permission denied' in out, out
                assert snapshot(tmp, readable) == before, 'unreadable launcher changed tree'
                print('unreadable status script: exit 126, Permission denied, identical tree')
        finally:
            script.chmod(mode)
            handle.close()
    elif SCENARIO == 441:
        architecture = (wf / 'ARCHITECTURE.md').read_text()
        a39 = re.search(r'^### A39\b.*?(?=^### |\Z)', architecture, re.M | re.S).group()
        checks = [
            ('instruction suppression', r'suppress'),
            ('instruction noncompliance', r'noncompliance|non-compliance|disobey|non-compliant'),
            ('parent/deeper instructions', r'parent.{0,80}deeper'),
            ('AGENTS.override.md', r'AGENTS\.override\.md'),
            ('instruction budget', r'instruction budget'),
            ('model choice', r'model choice'),
            ('check is not mechanically enforced', r'(check|status).{0,120}not mechanically enforced|not mechanically enforced.{0,120}(check|status)'),
            ('remote/cloud sessions unverified', r'remote.{0,40}cloud.{0,120}unverified|unverified.{0,120}remote.{0,40}cloud'),
        ]
        errors = []
        for label, text in [('A39', a39), ('Codex instructions', (wf / 'adapters/codex/INSTRUCTIONS.md').read_text())]:
            try:
                pins(text, checks, label)
            except AssertionError as exc:
                errors.append(str(exc))
        assert not errors, '\n'.join(errors)
    else:
        raise AssertionError('unknown scenario')
    print('S' + str(SCENARIO) + ': automated assertions passed; no live-session claim')
