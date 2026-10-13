"""Read-only structural inventory for the preserved Claude adapter."""
from pathlib import Path
import subprocess
import json
import os
import hashlib
import sys

def managed_snapshot(source, project):
    names = {'CLAUDE.md', '.claude/settings.json', '.gitignore', 'PRD.md',
             'TEST-SCENARIOS.md', 'ARCHITECTURE.md', 'CONTEXT.md',
             'WORKFLOW-ADOPTION.md', 'check-traceability.sh', 'wait-for-ci.sh',
             'check-pr-issue-link.sh', 'check-main-via-pr.sh', '.github/workflows/ci.yml'}
    names.update('.git/hooks/' + n for n in ('pre-commit', 'commit-msg', 'pre-push'))
    for directory in (source / 'skills', project / '.claude/skills'):
        if directory.is_dir(): names.update('.claude/skills/' + p.name for p in directory.iterdir())
    templates = source / 'templates/ISSUE_TEMPLATE'
    if templates.is_dir(): names.update('.github/ISSUE_TEMPLATE/' + p.name for p in templates.iterdir() if p.is_file())
    result = {}
    for name in sorted(names):
        p = project / name
        if p.is_symlink(): result[name] = ['link', os.readlink(p)]
        elif p.is_file(): result[name] = ['file', hashlib.sha256(p.read_bytes()).hexdigest()]
        elif p.exists(): result[name] = ['project-directory']
        else: result[name] = None
    return result

try:
    source = Path(sys.argv[1]).resolve(); project = Path(sys.argv[2]).resolve()
    mode = sys.argv[3] if len(sys.argv) > 3 else 'status'
    if mode == 'snapshot':
        print(json.dumps(managed_snapshot(source, project), sort_keys=True)); sys.exit(0)
    if mode == 'report':
        before = json.loads(Path(sys.argv[4]).read_bytes())
        after = managed_snapshot(source, project)
        for name in sorted(set(before) | set(after)):
            was, now = before.get(name), after.get(name)
            if was is None and now is None: continue
            action = 'unchanged' if was == now else 'created' if was is None else 'removed' if now is None else 'repaired'
            print(action + ': ' + name)
        sys.exit(0)
    if not project.is_dir() or not (project / '.git').is_dir():
        print('invalid/unreadable project: ' + str(project)); sys.exit(2)
    rev = subprocess.run(['git', '-C', str(source), 'rev-parse', 'HEAD'], capture_output=True, text=True)
    print('runtime: claude\nproject: ' + str(project) + '\ncheckout: ' + str(source))
    print('revision: ' + (rev.stdout.strip() if not rev.returncode else 'unavailable'))
    links = {'CLAUDE.md': source / 'WORKFLOW.md', '.claude/settings.json': source / 'settings/session-hooks.json'}
    for skill in (source / 'skills').iterdir() if (source / 'skills').is_dir() else ():
        if skill.is_dir(): links['.claude/skills/' + skill.name] = skill
    for name in ('pre-commit', 'commit-msg', 'pre-push'): links['.git/hooks/' + name] = source / 'hooks' / name
    stale = False
    for name, target in links.items():
        p = project / name
        if not p.is_symlink() or not p.exists() or p.resolve() != target:
            print('stale/broken/foreign/missing: ' + name); stale = True
        else: print('unchanged: ' + name)
    print('runtime-hooks: settings/session-hooks.json; Bash interception only; fail-open and indirect bypass limits remain')
    print('native-hooks: shared; hooksPath/foreign hooks/--no-verify/dependencies limit coverage')
    print('structural installation only; not live-loaded')
    sys.exit(1 if stale else 0)
except (OSError, ValueError) as exc:
    print('invalid/unreadable: ' + str(exc)); sys.exit(2)
