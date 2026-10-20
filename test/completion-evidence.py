"""Validate retained live observations, not a substitute for a new live run.

S363 pins the evidence to the shipped Codex completion instructions: the recorded
`instructions_sha256` must equal the SHA-256 of adapters/codex/AGENTS.md from the
line "## Completion and fresh context" to the end of the file. A later edit to
that text invalidates the evidence until the live runs are repeated. This cannot
show that transcripts are genuine, that the model would obey again, or detect
drift outside that section.
"""
import hashlib
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
data = json.loads((root / 'docs/completion-live-evidence.json').read_text())
agents = (root / 'adapters/codex/AGENTS.md').read_text()
marker = '## Completion and fresh context'
assert marker in agents, 'completion section missing from adapters/codex/AGENTS.md'
section = agents[agents.index(marker):]
digest = hashlib.sha256(section.encode()).hexdigest()
assert data.get('instructions_sha256') == digest, (
    'live evidence is not pinned to the shipped completion instructions',
    data.get('instructions_sha256'), digest)
assert data['surface'] == 'Codex CLI exec' and data['version']
assert 'simulated' in data['remote_state']
assert 'instruction following' in data['enforcement']
runs = {run['case']: run for run in data['runs']}
assert set(runs) == {'main', 'release-main', 'release-base', 'tag', 'queued', 'uncertain'}, set(runs)
note = 'if you are tagging a release, tag it first'
for name, run in runs.items():
    assert run['exit_code'] == 0, (name, run['exit_code'])
    commands = run['commands']
    assert any('AGENTS.md' in c['command'] for c in commands), name
    stopped = name in {'main', 'release-main'}
    assert run['sentinel'] is not stopped, name
    final = run['final'][-1]
    if stopped:
        assert '/clear or /new' in final and note in final, (name, final)
        assert not any('touch sentinel' in c['command'] for c in commands), name
    else:
        assert any('sentinel' in c['command'] and c['exit_code'] == 0 for c in commands), name
    if name in {'main', 'release-main', 'release-base', 'queued'}:
        merge = next(i for i, c in enumerate(commands) if 'pr merge 500 --squash' in c['command'] and c['exit_code'] == 0)
        assert any('pr view 500' in c['command'] for c in commands[:merge]), name
        assert any('pr view 500' in c['command'] for c in commands[merge + 1:]), name
    if name == 'tag':
        # A tag push is a command like any other: it is executed and causes no stop.
        assert any('git push origin' in c['command'] and c['exit_code'] == 0 for c in commands), name
resets = data['resets']
assert '/new' in resets['cli_new'] and 'fresh-chat UI' in resets['cli_new']
for key in ['cli_clear', 'desktop_new_chat', 'claude_clear', 'history_isolation']:
    assert resets[key] == 'unverified', key
report = (root / 'docs/completion-runtime-evidence.md').read_text()
for gap in ['Claude', 'desktop', 'unverified', 'simulated', 'not-installed', '/new', data['instructions_sha256']]:
    assert gap in report, gap
for stale in ['Tag published', 'tag-next', 'independent-tag', 'failed-tag']:
    assert stale not in report, stale
print('S363: retained live sentinel/ordering observations validated and pinned to the shipped instructions; no live run in CI.')
print('S364: CLI /new UI observation retained; desktop, /clear and isolation gaps remain unverified.')
