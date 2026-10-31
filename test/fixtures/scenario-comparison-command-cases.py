"""Execute the exact A49 command offline; only gh transport is substituted."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import zlib

root = Path(__file__).resolve().parents[2]
text = (root / 'skills/role-contracts/SKILL.md').read_text()
section = text.split('## QA scenario comparison\n', 1)[1].split('\n## ', 1)[0]
blocks = re.findall(r'^```bash\n(.*?)^```$', section, re.M | re.S)
assert len(blocks) == 1, 'comparison command must be unambiguous'
command = blocks[0]
arguments = 'owner/repo COMMENT_ID FULL_DEVELOPER_HEAD_SHA APPLICABLE_BASE_SHA'
assert command.count(arguments) == 1, 'comparison invocation changed'

old = b'title\nexpected: old\nfooter\n'
expected = b'title\nexpected: new\nfooter\n'
different = b'title\nexpected: now\nfooter\n'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def snapshot(directory):
    return {str(p.relative_to(directory)): p.read_bytes()
            for p in directory.rglob('*') if p.is_file()}


with tempfile.TemporaryDirectory(prefix='qa-command-test-') as tmp:
    directory = Path(tmp)
    repo = directory / 'repo'
    gitdir = repo / '.git'
    (gitdir / 'objects').mkdir(parents=True)
    (gitdir / 'refs/heads').mkdir(parents=True)
    (gitdir / 'config').write_text('[core]\nrepositoryformatversion = 0\nbare = false\n')
    (gitdir / 'HEAD').write_text('ref: refs/heads/fixture\n')
    # Construct the tiny real Git object graph directly, without a Git write
    # command, user configuration, hooks, or writes to the working repository.
    def obj(kind, data):
        raw = kind.encode() + b' ' + str(len(data)).encode() + b'\0' + data
        oid = hashlib.sha1(raw).hexdigest()
        path = gitdir / 'objects' / oid[:2] / oid[2:]
        path.parent.mkdir(exist_ok=True)
        path.write_bytes(zlib.compress(raw))
        return oid

    def commit(data, parent=None):
        blob = obj('blob', data)
        tree = obj('tree', b'100644 TEST-SCENARIOS.md\0' + bytes.fromhex(blob))
        payload = f'tree {tree}\n'
        if parent:
            payload += f'parent {parent}\n'
        payload += ('author Fixture <fixture@example.test> 1 +0000\n'
                    'committer Fixture <fixture@example.test> 1 +0000\n\nfixture\n')
        return obj('commit', payload.encode()), blob

    base, old_blob = commit(old)
    matching, new_blob = commit(expected, base)
    differing, _ = commit(different, base)
    (gitdir / 'refs/heads/fixture').write_text(matching + '\n')
    (repo / 'TEST-SCENARIOS.md').write_bytes(b'local tree must not be used\n')
    patch = (f'diff --git a/TEST-SCENARIOS.md b/TEST-SCENARIOS.md\n'
             f'index {old_blob}..{new_blob} 100644\n'
             '--- a/TEST-SCENARIOS.md\n+++ b/TEST-SCENARIOS.md\n'
             '@@ -1,3 +1,3 @@\n title\n-expected: old\n+expected: new\n footer\n')
    report_url = 'https://github.com/owner/repo/issues/40#issuecomment-123'
    report = dict(html_url=report_url,
                  issue_url='https://api.github.com/repos/owner/repo/issues/40',
                  body=f'base: {base}\nbase_sha256: {sha(old)}\n'
                       f'result_sha256: {sha(expected)}\nempty: no\n~~~diff\n{patch}~~~\n')
    report_file = directory / 'report.json'
    report_file.write_text(json.dumps(report))
    bindir = directory / 'bin'
    bindir.mkdir()
    gh = bindir / 'gh'
    gh.write_text('#!/bin/sh\n'
                  'if [ "$*" = "repo view --json nameWithOwner --jq .nameWithOwner" ]; then\n'
                  '  echo owner/repo\n'
                  'elif [ "$*" = "api repos/owner/repo/issues/comments/123" ]; then\n'
                  '  cat "$QA_COMMAND_REPORT"\n'
                  'else\n  echo "unexpected gh invocation" >&2\n  exit 97\nfi\n')
    gh.chmod(0o755)
    env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
    env.update(PATH=str(bindir) + os.pathsep + os.environ['PATH'],
               QA_COMMAND_REPORT=str(report_file), GIT_CONFIG_NOSYSTEM='1',
               GIT_CONFIG_GLOBAL=os.devnull)
    before = snapshot(repo)

    def check(source, head, status, result, committed):
        script = source.replace(arguments, f'owner/repo 123 {head} {base}')
        process = subprocess.run([shutil.which('bash'), '-c', script], cwd=repo,
                                 env=env, capture_output=True, text=True, timeout=10)
        assert process.returncode == status, (
            f'expected exit {status}, got {process.returncode}: '
            f'{process.stdout}{process.stderr}')
        for field in (f'artifact={report_url}', f'base={base}',
                      f'base_sha256={sha(old)}', f'qa_sha256={sha(expected)}',
                      f'head={head}', f'committed_sha256={sha(committed)}',
                      f'exit={status} result={result}'):
            assert field in process.stdout, f'missing {field}: {process.stdout}'
        assert snapshot(repo) == before, 'comparison wrote to fixture repository'

    check(command, matching, 0, 'match', expected)
    print('PASS command/match')
    check(command, differing, 1, 'different', different)
    print('PASS command/one-byte-different')
    # Run the same oracle on an in-memory defect in the published command.
    comparison = 'status = int(committed != expected)'
    assert command.count(comparison) == 1, 'mutation anchor changed'
    mutant = command.replace(comparison, 'status = 0')
    try:
        check(mutant, differing, 1, 'different', different)
    except AssertionError as error:
        assert 'expected exit 1, got 0:' in str(error), str(error)
        print('PASS command/unconditional-match-control rejected: expected exit 1, got 0')
    else:
        raise AssertionError('unconditional-match mutation escaped the byte oracle')
    assert snapshot(repo) == before, 'mutation wrote to fixture repository'
