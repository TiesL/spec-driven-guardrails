"""Reject new uses of the retired role name in contract-facing files."""
from pathlib import Path
import re
import sys

root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]
allow_file = root / 'test/fixtures/old-role-name-allow.tsv'
allow = {}
for line in allow_file.read_text().splitlines():
    if not line or line.startswith('#'):
        continue
    path, maximum = line.split('\t')
    allow[path] = maximum

old_name = re.compile(r'Fullstack\s+Developer')
paths = [root / p for p in ('CHANGELOG.md', 'CHANGES.md', 'WORKFLOW.md', 'AGENTS.md',
                            'README.md', 'PRD.md', 'ARCHITECTURE.md', 'TEST-SCENARIOS.md')]
for directory in ('skills', 'policy', 'adapters', 'templates', 'hooks', 'lib',
                  'test/behavior', 'test/fixtures', 'prep'):
    paths.extend(p for p in (root / directory).rglob('*') if p.is_file())
paths.extend((root / 'test/cases').glob('s312*.sh'))
bad = []
for path in paths:
    if path == Path(__file__).resolve() or not path.is_file():
        continue
    try:
        count = len(old_name.findall(path.read_text()))
    except UnicodeError:
        continue
    if not count:
        continue
    relative = path.relative_to(root).as_posix()
    maximum = allow.get(relative, allow.get('prep/**') if relative.startswith('prep/') else '0')
    if maximum != '*' and count > int(maximum):
        bad.append(f'{relative}: {count} > {maximum}')
if bad:
    print('old role name exceeds allow-list: ' + '; '.join(bad), file=sys.stderr)
    raise SystemExit(1)
print('old role name: bounded')
