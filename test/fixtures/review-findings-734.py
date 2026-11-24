"""Focused public-text and configuration oracles for #734 (no network)."""
import json
import hashlib
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]

def read(path, revision=None):
    if revision:
        return subprocess.check_output(['git', '-C', str(ROOT), 'show', f'{revision}:{path}']).decode()
    return (ROOT / path).read_text()

def check(ok, label):
    if not ok:
        print('FAIL ' + label)
        raise SystemExit(1)
    print('PASS ' + label)

def mapped(pattern, path):
    # Git-style path glob: * stays inside a segment, ** covers descendants.
    regex = re.escape(pattern).replace(r'\*\*', '.*').replace(r'\*', '[^/]*')
    return re.fullmatch(regex, path) is not None

def s662():
    config = json.loads(read('policy/merge-autonomy.json'))
    check(config['enabled'] is False and config['acceptance'] is None, 'S662/shipped-inert')
    patterns = [p for group in config['hard_stops'].values() for p in group]
    reserved = subprocess.check_output(['git', '-C', str(ROOT), 'ls-files', 'skills', 'policy', 'templates']).decode().splitlines()
    reserved += ['skills/__qa734__/child.txt', 'policy/__qa734__/child.txt', 'templates/__qa734__/child.txt']
    reserved += ['skills/release-branch-workflow/SKILL.md', 'skills/model-choice/SKILL.md',
                 'skills/deploy-guards/SKILL.md', 'templates/PRD.md',
                 'templates/ISSUE_TEMPLATE/work-item.md', 'templates/wait-for-ci.sh',
                 'CHANGES.md', 'USER-CLAUDE.md']
    for path in reserved:
        check(any(mapped(pattern, path) for pattern in patterns), 'S662/reserved/' + path)
    check(not any(mapped(pattern, 'docs/ordinary-notes.md') for pattern in patterns), 'S662/unreserved-control')

def s714():
    # Inventory only current contract surfaces. Historical quotations and negative
    # argv/prefix fixtures are outside this live prose seam.
    files = ['skills/role-contracts/SKILL.md', 'policy/WORKFLOW.md', 'README.md',
             'CHANGES.md', 'WORKFLOW.md', 'AGENTS.md', 'adapters/codex/AGENTS.md',
             'ARCHITECTURE.md', 'TEST-SCENARIOS.md']
    for name in files:
        text = read(name)
        if name == 'README.md': text = '\n'.join(text.splitlines()[23:])
        if name == 'ARCHITECTURE.md': text = text.split('### A41 —',1)[1].split('### A42 —',1)[0]
        if name == 'TEST-SCENARIOS.md':
            # Bound the historical and rejected-input lines by their exact
            # surrounding scenario fragments; other new live text is scanned.
            historical = ('ROLE SESSION: Fullstack Developer',
                          'SESSION: Developer` with `--role "Fullstack Developer"',
                          'Fullstack Developer alias',
                          'single quoted Fullstack Developer argument',
                          'product, Fullstack, Fullstack Developer,',
                          'preserving the space within Fullstack Developer',
                          'row still spelling `Fullstack Developer`',
                          '("Fullstack Developer", "Developer", "Implementation")')
            text = '\n'.join(line for line in text.splitlines()
                             if not any(marker in line for marker in historical))
        if name == 'CHANGES.md':
            text = text.split('## process-multi-agent-roles',1)[1].split('\n## ',1)[0]
        normalized = re.sub(r'\s+', ' ', text)
        check('Fullstack Developer' not in normalized, 'S714/live-name/' + name)
    roles = read('skills/role-contracts/SKILL.md')
    check(re.search(r'^## Developer\s*$', roles, re.M) is not None, 'S714/developer-heading')
    for name in ('test/fixtures/oracle-contract-pins.py','test/fixtures/skip-test-qa-exemption-pins.py'):
        check("'Fullstack Developer'" not in read(name), 'S714/heading-consumer/' + name)

def s715():
    for name in ('PRD.md','ARCHITECTURE.md','TEST-SCENARIOS.md'):
        text = read(name)
        refs = sorted(set(re.findall(r'(?<![\w/])(?:[\w.-]+/)*\.handoff/[\w./-]+', text)))
        for ref in refs:
            check((ROOT / ref).is_file() and ref in subprocess.check_output(
                ['git','-C',str(ROOT),'ls-files', '--',ref],text=True).splitlines(),
                'S715/tracked-citation/' + name + '/' + ref)
    table = 'policy/MODEL-SCORES-2026-11-11.md'
    check((ROOT / table).is_file() and table in subprocess.check_output(
        ['git','-C',str(ROOT),'ls-files','--',table],text=True).splitlines(),
        'S715/tracked-score-table')
    check(hashlib.sha256((ROOT / table).read_bytes()).hexdigest() ==
          '91949f5731a4b3b27293ed25e6d37cd20d843517caf6062d9035b2b92c6d6797',
          'S715/dated-score-rows')
    f71 = read('PRD.md').split('### F71 —',1)[1].split('\n### ',1)[0]
    a60 = read('ARCHITECTURE.md').split('### A60 addendum 2 —',1)[1].split('\n### ',1)[0]
    check(table in f71, 'S715/F71-score-citation')
    check(table in a60, 'S715/A60-score-citation')
    fixture = read('test/fixtures/merge-risk-646.py')
    check('blob/main/.handoff/' not in fixture and 'HANDOFF =' not in fixture,
          'S715/verifier-score-source')
    check("UNACCEPTED_COMMENT = 'https://github.com/laboratory/other/issues/650#issuecomment-9100'" in fixture
          and "('table-at-unaccepted-foreign-comment',repin(source={'table':UNACCEPTED_COMMENT}),'capability-table-invalid')" in fixture,
          'S715/bounded-negative-source')

def s716(revision=None):
    text = read('ARCHITECTURE.md', revision)
    a58 = re.search(r'^### A58\b', text, re.M)
    next_heading = re.search(r'^### ', text[a58.end():], re.M)
    boundary = a58.end() + next_heading.start()
    addenda = list(re.finditer(r'^#### A58 addendum(?: \d+)?\b', text, re.M))
    check(len(addenda) >= 6 and all(a58.end() < x.start() < boundary for x in addenda),
          'S716/A58-addenda-heading-order')

def s717(revision=None):
    text = read('PRD.md', revision).split('## Technical debt',1)[1].split('\n## ',1)[0]
    row = next((line for line in text.splitlines() if line.startswith('| #646 merge-risk oracle size ')), '')
    check(bool(row and 'test/fixtures/merge-risk-646.py' in row and 'A58/A60 addendum sprawl' in row
               and 'Retain' in row and 'When #646 is activated' in row and 'split it by scenario family' in row),
          'S717/technical-debt-row')

if __name__ == '__main__':
    scenario = sys.argv[1]
    revision = sys.argv[2] if len(sys.argv)>2 else None
    {'662':s662,'714':s714,'715':s715,'716':lambda:s716(revision),
     '717':lambda:s717(revision)}[scenario]()
