"""Validate retained live observations, not a substitute for a new live run.

S363 pins evidence to the shipped Codex completion instructions: a record's
`instructions_sha256` is the SHA-256 of adapters/codex/AGENTS.md from the line
"## Completion and fresh context" to the end of the file. A record not marked
`status: historical` must match the current section; a historical record (the
removed #500 stop, superseded by #561) must differ from it. This cannot
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
# #561: the 2026-10-21 runs observed the removed #500 stop. They stay as history: the
# recorded hash is kept (never re-pinned to the reminder text) and the record says so.
# A record that is not historical must still match the shipped section, so the pin
# mechanism survives for a future live run of the reminder.
historical = data.get('status') == 'historical'
if historical:
    assert data.get('instructions_sha256') != digest, (
        'a historical record must not carry the current section hash: re-pinning would certify '
        'observations of the removed stop as made under the reminder text', digest)
else:
    assert data.get('instructions_sha256') == digest, (
        'live evidence is not pinned to the shipped completion instructions',
        data.get('instructions_sha256'), digest)
# The retained runs below assert the sentinel is withheld after a main merge, which is the
# removed stop. Such a record can only stand as history.
assert historical and data.get('superseded_by') == '#561', (
    'the retained #500 stop observations must be marked status historical, superseded_by #561',
    data.get('status'), data.get('superseded_by'))
assert len(data.get('instructions_sha256', '')) == 64
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
assert 'removed in #561' in report, 'report must state the stop was removed in #561'
assert 'no live observation of the reminder' in ' '.join(report.split()).lower(), 'report must say no live observation of the reminder is claimed'
for stale in ['Tag published', 'tag-next', 'independent-tag', 'failed-tag']:
    assert stale not in report, stale
print('S363: retained historical (removed #500 stop) observations validated against their own recorded hash; no live observation of the reminder is claimed; no live run in CI.')
print('S364: CLI /new UI observation retained; desktop, /clear and isolation gaps remain unverified.')
