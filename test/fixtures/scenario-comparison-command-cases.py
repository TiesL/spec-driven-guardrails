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

old = b'title\npreamble\nbefore\nexpected: old\nafter\nfooter\n'
expected = b'title\npreamble\nbefore\nexpected: new\nafter\nfooter\n'
different = b'title\npreamble\nbefore\nexpected: now\nafter\nfooter\n'


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
             '@@ -3,3 +3,3 @@\n before\n-expected: old\n+expected: new\n after\n')
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
    current_old = b'new main preface\n' + old
    current_expected = b'new main preface\n' + expected
    current_different = b'new main preface\n' + different
    current_base, _ = commit(current_old, base)
    reapplied, _ = commit(current_expected, current_base)
    reapplied_different, _ = commit(current_different, current_base)
    conflict_base, _ = commit(old.replace(b'expected: old', b'expected: conflict'), base)
    conflict_head, _ = commit(b'conflicting developer head\n', conflict_base)
    unrelated, _ = commit(b'unrelated root\n')
    before = snapshot(repo)

    def check(source, head, status, result, committed=None, applicable=base,
              base_bytes=old, qa_bytes=expected, body=None, error=None):
        selected = dict(report)
        if body is not None:
            selected['body'] = body
        report_file.write_text(json.dumps(selected))
        script = source.replace(arguments, f'owner/repo 123 {head} {applicable}')
        process = subprocess.run([shutil.which('bash'), '-c', script], cwd=repo,
                                 env=env, capture_output=True, text=True, timeout=10)
        assert snapshot(repo) == before, 'comparison wrote to fixture repository'
        assert process.returncode == status, (
            f'expected exit {status}, got {process.returncode}: '
            f'{process.stdout}{process.stderr}')
        if status == 2:
            assert 'exit=2 result=unresolved' in process.stdout + process.stderr, process.stdout + process.stderr
            if error:
                assert error in process.stdout + process.stderr, process.stdout + process.stderr
            return
        for field in (f'artifact={report_url}', f'original_base={base}',
                      f'original_base_sha256={sha(old)}',
                      f'original_qa_sha256={sha(expected)}',
                      f'base={applicable}', f'base_sha256={sha(base_bytes)}',
                      f'qa_sha256={sha(qa_bytes)}', f'head={head}',
                      f'committed_sha256={sha(committed)}',
                      f'exit={status} result={result}'):
            assert field in process.stdout, f'missing {field}: {process.stdout}'

    failures = []

    def case(label, **kwargs):
        try:
            check(command, **kwargs)
        except AssertionError as error:
            failures.append(label)
            print(f'FAIL command/{label}: {error}')
        else:
            print(f'PASS command/{label}')

    case('match', head=matching, status=0, result='match', committed=expected)
    case('one-byte-different', head=differing, status=1, result='different', committed=different)
    crlf = report['body'].replace('\n', '\r\n')
    case('crlf-comment-match', head=matching, status=0, result='match', committed=expected, body=crlf)
    case('crlf-comment-one-byte-different', head=differing, status=1,
         result='different', committed=different, body=crlf)
    case('main-reapply-match', head=reapplied, status=0, result='match',
         committed=current_expected, applicable=current_base,
         base_bytes=current_old, qa_bytes=current_expected)
    case('main-reapply-one-byte-different', head=reapplied_different, status=1,
         result='different', committed=current_different, applicable=current_base,
         base_bytes=current_old, qa_bytes=current_expected)
    for name, value in [('base_sha256', sha(old)), ('result_sha256', sha(expected))]:
        case(name + '-mismatch', head=matching, status=2, result='unresolved',
             body=report['body'].replace(f'{name}: {value}', f'{name}: ' + '0' * 64),
             error=('base' if name == 'base_sha256' else 'result') + ' hash mismatch')
    case('apply-conflict', head=conflict_head, applicable=conflict_base,
         status=2, result='unresolved', error='patch does not apply')
    case('missing-base', head=matching, status=2, result='unresolved',
         body=report['body'].replace(f'base: {base}\n', ''), error='missing or duplicate base')
    case('duplicate-base', head=matching, status=2, result='unresolved',
         body=f'base: {base}\n' + report['body'], error='missing or duplicate base')
    case('original-not-ancestor', head=unrelated, status=2, result='unresolved',
         error='merge-base')
    case('applicable-not-ancestor', head=matching, applicable=current_base,
         status=2, result='unresolved', error='merge-base')

    def mutation(label, anchor, replacement, rejected_status, **kwargs):
        assert command.count(anchor) == 1, f'{label}: mutation anchor changed'
        try:
            check(command.replace(anchor, replacement), **kwargs)
        except AssertionError as error:
            diagnostic = f'expected exit {kwargs["status"]}, got {rejected_status}:'
            assert diagnostic in str(error), str(error)
            print(f'PASS command/{label}-control rejected: {diagnostic}')
        else:
            raise AssertionError(label + ' mutation escaped the byte oracle')

    mutation('unconditional-match', 'status = int(committed != expected)', 'status = 0', rejected_status=0,
             head=differing, status=1, result='different', committed=different)
    mutation('reconstruct-old-base', 'expected = reconstruct(current_base)',
             'expected = reconstruct(old)', rejected_status=1, head=reapplied, status=0, result='match',
             committed=current_expected, applicable=current_base,
             base_bytes=current_old, qa_bytes=current_expected)
    assert snapshot(repo) == before, 'mutation wrote to fixture repository'
    if failures:
        raise SystemExit('failed published command cases: ' + ', '.join(failures))
