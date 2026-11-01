#!/usr/bin/env python3
"""Offline CLI regressions for #619; all mutations live in temporary fixtures."""
import collections
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / 'test/fixtures/orchestrator-core.py'
DIFF = ROOT / 'test/behavior/orchestrator_diff.py'
ORCH = 'skills/role-contracts/ORCHESTRATOR.md'
SCEN = 'test/behavior/orchestrator-scenarios.md'
STAMP = 'test/behavior/orchestrator-diff.stamp'


def command(*args, env=None):
    return subprocess.run(list(map(str, args)), stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, text=True, env=env)


def require(result, ok, needle=''):
    assert (result.returncode == 0) == ok, result.stdout
    assert needle in result.stdout, result.stdout


def pins(directory, mode):
    orch = (ROOT / ORCH).read_text()
    pintext = (ROOT / 'test/fixtures/orchestrator-core-pins.tsv').read_text()
    changed = directory / 'orch.md'
    pinfile = directory / 'pins.tsv'
    checks = command(sys.executable, '-I', ROOT / 'hooks/agent-dispatch.py', '--list-checks')

    def check(text, rows):
        changed.write_text(text)
        pinfile.write_text(rows)
        return command(sys.executable, '-I', CORE, 'check', '--orch', changed,
                       '--tsv', ROOT / 'skills/role-contracts/orchestrator-rules.tsv',
                       '--scen', ROOT / SCEN, '--pins', pinfile, '--repo', ROOT,
                       '--list-checks', checks.stdout.replace('\n', ' '))

    require(check(orch, pintext), True)
    if mode == 'loose':
        for suffix in ('\nNever run the self-check.', '\n\nNever run the self-check.'):
            text = orch.replace('  - OR26 No orchestrator-written issue comment carries `model-record` marker.',
                                '  - OR26 No orchestrator-written issue comment carries `model-record` marker.' + suffix)
            require(check(text, pintext), False, 'ERROR item-loose-continuation: OR26')
    elif mode == 'duplicate':
        row = next(x for x in pintext.splitlines() if x.startswith('OR26\t'))
        for extra in (row, 'OR26\t' + '0' * 64):
            for rows in (pintext + extra + '\n', pintext.replace(row, extra + '\n' + row)):
                require(check(orch, rows), False, 'ERROR pin-duplicate: OR26')
    elif mode == 'depth':
        for rid in ('OR24', 'OR25', 'OR26', 'OR27'):
            require(check(orch.replace('  - ' + rid + ' ', '- ' + rid + ' '), pintext),
                    False, 'ERROR pin-mismatch: ' + rid)
        # Wrapping an existing continuation preserves meaning and indentation depth.
        require(check(orch.replace('  - OR26 No orchestrator-written issue comment carries `model-record` marker.',
                                   '  - OR26 No orchestrator-written issue comment\n    carries `model-record` marker.'), pintext), True)


def git(repo, *args):
    result = command('git', '-C', repo, *args)
    require(result, True)
    return result.stdout.strip()


def fixture(directory):
    repo = directory / 'repo'
    (repo / ORCH).parent.mkdir(parents=True)
    (repo / SCEN).parent.mkdir(parents=True)
    (repo / ORCH).write_text('- OR26 Never skip a check.\n')
    (repo / SCEN).write_text('''# Fixture
## Cases
### OB1 · OR26
Given: First fixture situation.
When: Decide.
Then: next_action=dispatch

### OB2 · OR26
Given: Second fixture situation.
When: Decide.
Then: next_action=dispatch

## Intended changes
''')
    git(repo, 'init', '-q', '-b', 'main')
    git(repo, 'config', 'user.email', 'fixture@example.invalid')
    git(repo, 'config', 'user.name', 'fixture')
    git(repo, 'config', 'commit.gpgsign', 'false')
    git(repo, 'add', '.')
    git(repo, 'commit', '-qm', 'ancestor')
    ancestor = git(repo, 'rev-parse', 'HEAD')
    git(repo, 'commit', '-q', '--allow-empty', '-m', 'main tip')
    tip = git(repo, 'rev-parse', 'HEAD')
    git(repo, 'update-ref', 'refs/remotes/origin/main', tip)
    git(repo, 'commit', '-q', '--allow-empty', '-m', 'branch only')
    branch = git(repo, 'rev-parse', 'HEAD')
    stub = directory / 'claude-stub'
    stub.write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
args = sys.argv[1:]
arm = pathlib.Path(args[args.index('--system-prompt-file') + 1]).name
prompt = sys.stdin.read()
with open(os.environ['CALL_LOG'], 'a') as f:
    f.write(json.dumps([arm, prompt]) + '\\n')
print(json.dumps({'structured_output': {'next_action': 'dispatch'},
                  **({} if os.environ.get('MODEL_USAGE') == 'absent' else
                     {'modelUsage': json.loads(os.environ.get('MODEL_USAGE', '{"claude-stub-1": {}}'))})}))
''')
    stub.chmod(0o755)
    env = dict(os.environ, CLAUDE_BIN=str(stub), CALL_LOG=str(directory / 'calls'))
    return repo, ancestor, tip, branch, env


def stamp(repo, base, model='claude-stub-1', count=2):
    digest = hashlib.sha256((repo / ORCH).read_bytes() + (repo / SCEN).read_bytes()).hexdigest()
    (repo / STAMP).write_text('sha256=%s base=%s model=%s scenarios=%s\n' %
                             (digest, base, model, count))


def stamp_check(repo):
    return command(sys.executable, '-I', DIFF, 'stamp-check', '--repo', repo)


def run(repo, base, env, n=3):
    return command(sys.executable, '-I', DIFF, 'run', '--repo', repo,
                   '--base', base, '--runs', n, env=env)


def bases(directory):
    repo, ancestor, tip, branch, env = fixture(directory)
    for base in (ancestor, ancestor[:12], tip):
        stamp(repo, base)
        require(stamp_check(repo), True, 'stamp matches')
        require(run(repo, base, env), True, 'stamp written')
    # branch-only, nonexistent SHA, symbolic base, malformed SHA.
    for base in (branch, 'f' * 40, 'origin/main', 'nosuchref', ''):
        stamp(repo, base)
        require(stamp_check(repo), False, 'base')
    for base in (branch, 'nosuchref'):
        before = (repo / STAMP).read_bytes()
        require(run(repo, base, env), False, 'base')
        assert (repo / STAMP).read_bytes() == before
    # A real unrelated commit is not an ancestor (nor merely a missing object).
    tree = git(repo, 'rev-parse', 'HEAD^{tree}')
    unrelated = git(repo, 'commit-tree', tree, '-m', 'unrelated root')
    stamp(repo, unrelated)
    require(stamp_check(repo), False, 'base')
    require(run(repo, unrelated, env), False, 'base')
    git(repo, 'update-ref', '-d', 'refs/remotes/origin/main')
    stamp(repo, ancestor)
    require(stamp_check(repo), False, 'origin/main')
    require(run(repo, ancestor, env), False, 'origin/main')


def models(directory):
    repo, ancestor, _, _, env = fixture(directory)
    for model in ('unknown', 'UNKNOWN', 'none', 'null', 'placeholder', 'sonnet',
                  'not-a-model', 'claude-stub-1!', 'claude-unknown'):
        stamp(repo, ancestor, model)
        require(stamp_check(repo), False, 'model')
    for count in (1, 3):
        stamp(repo, ancestor, count=count)
        require(stamp_check(repo), False, 'scenarios=')
    for usage in ('absent', None, {}, {'unknown': {}}, {'bad model': {}}, ['claude-stub-1'],
                  {'claude-stub-1': {}, 'unknown': {}}):
        stamp(repo, ancestor)
        before = (repo / STAMP).read_bytes()
        require(run(repo, ancestor, dict(env, MODEL_USAGE='absent' if usage == 'absent' else json.dumps(usage))), False, 'model')
        assert (repo / STAMP).read_bytes() == before
    for n in (1, 3, 5):
        Path(env['CALL_LOG']).unlink(missing_ok=True)
        require(run(repo, ancestor, env, n), True, 'stamp written')
        calls = [json.loads(line) for line in Path(env['CALL_LOG']).read_text().splitlines()]
        counts = collections.Counter((arm, prompt) for arm, prompt in calls)
        assert len(counts) == 4 and set(counts.values()) == {n}, counts
        require(stamp_check(repo), True)
        assert len((repo / STAMP).read_text().split()) == 4  # existing format, no provenance


if __name__ == '__main__':
    with tempfile.TemporaryDirectory(prefix='core-integrity-') as temp:
        case = sys.argv[1]
        directory = Path(temp)
        if case in ('loose', 'duplicate', 'depth'):
            pins(directory, case)
        else:
            {'bases': bases, 'models': models}[case](directory)
    print(case + ': pass')
