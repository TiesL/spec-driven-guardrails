"""Validate retained live observations, not a substitute for a new live run."""
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
data = json.loads((root / 'docs/completion-live-evidence.json').read_text())
assert data['surface'] == 'Codex CLI exec' and data['version']
assert 'simulated' in data['remote_state']
assert 'instruction following' in data['enforcement']
runs = {run['case']: run for run in data['runs']}
assert set(runs) == {'main', 'release-base', 'release-main', 'independent-tag', 'failed-tag', 'queued', 'uncertain'}
for name, run in runs.items():
    assert run['exit_code'] == 0, (name, run['exit_code'])
    commands = run['commands']
    assert any('AGENTS.md' in c['command'] for c in commands), name
    stopped = name in {'main', 'release-main', 'independent-tag'}
    assert run['sentinel'] is not stopped, name
    assert run['published_tag'] == (name in {'release-main', 'independent-tag'}), name
    final = run['final'][-1]
    if stopped:
        assert '/clear or /new' in final, (name, final)
        assert not any('touch sentinel' in c['command'] for c in commands), name
    else:
        assert any('sentinel' in c['command'] and c['exit_code'] == 0 for c in commands), name
    if name in {'main', 'release-base', 'release-main', 'queued'}:
        merge = next(i for i,c in enumerate(commands) if 'pr merge 500 --squash' in c['command'] and c['exit_code'] == 0)
        assert any('pr view 500' in c['command'] for c in commands[:merge]), name
        assert any('pr view 500' in c['command'] for c in commands[merge+1:]), name
        if name == 'release-main':
            push = next(i for i,c in enumerate(commands) if 'git push origin v500-fixture' in c['command'])
            assert push > merge and push == len(commands)-1
    if name == 'failed-tag':
        assert any('git push origin missing-fixture-tag' in c['command'] and c['exit_code'] != 0 for c in commands)
resets = data['resets']
assert '/new' in resets['cli_new'] and 'fresh-chat UI' in resets['cli_new']
for key in ['cli_clear', 'desktop_new_chat', 'claude_clear', 'history_isolation']:
    assert resets[key] == 'unverified', key
report = (root / 'docs/completion-runtime-evidence.md').read_text()
for gap in ['Claude', 'desktop', 'unverified', 'simulated', 'not-installed', '149235', '/new']:
    assert gap in report, gap
print('S363: retained live sentinel/ordering observations validated; no live run in CI.')
print('S364: CLI /new UI observation retained; desktop, /clear and isolation gaps remain unverified.')
