"""S469: scoped loaded-contract pins with independent clause-deletion controls.

These check instruction text, not live orchestration. OR15 is deliberately outside
this seam: the settlement places the injected exemption in OR46 (part 1).
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
LOG = 'QA provenance: result=not-applicable; skip=<record URL>; head=<SHA>'


def scope(text, name):
    if name == 'OR46':
        match = re.search(r'^- OR46\b.*(?:\n +[^\n]+)*', text, re.M)
    else:
        match = re.search(r'^## ' + re.escape(name) + r'\n(.*?)(?=^## |\Z)',
                          text, re.M | re.S)
    return match.group() if match else ''


def matches(pattern, text):
    return bool(re.search(pattern, re.sub(r'\s+', ' ', text.replace('`', '')), re.I))


# label, scope, obligation regex, independent compliant clause.
PINS = [
    ('or46-valid-record', 'OR46', r'valid.*skip=Test.*record.*OR34',
     'Only a valid skip=Test record (OR34) grants this exception.'),
    ('or46-exemption', 'OR46', r'(exempt|not.applic|no|waiv).*QA artifact.*comparison.*(Reviewer|approval)|QA artifact.*comparison.*(Reviewer|approval).*(exempt|not.applic|waiv)',
     'The exemption covers the QA artifact, comparison and Reviewer approval block.'),
    ('or46-log', 'OR46', re.escape(LOG), LOG),
    ('or46-single-session', 'OR46', r'single-session.*(not|never|no).*exempt',
     'A single-session record alone does not exempt.'),
    ('reviewer-valid-record', 'Reviewer / Lead Developer', r'(verif|check).*valid.*skip=Test.*record',
     'Reviewer verifies the valid skip=Test record instead of requiring the QA artifact.'),
    ('reviewer-head', 'Reviewer / Lead Developer', r'(verif|check)[^.]*log[^.]*reviewed head',
     'Reviewer verifies the log line for the reviewed head.'),
    ('reviewer-log', 'Reviewer / Lead Developer', r'log[^.]*not-applicable|not-applicable[^.]*log',
     'Reviewer checks the not-applicable log instead of a QA comparison.'),
    ('developer-valid-record', 'Fullstack Developer', r'only.*valid.*skip=Test.*record',
     'Only under a valid skip=Test record (OR34) may the Developer use this exception.'),
    ('developer-add-only', 'Fullstack Developer', r'(append|add).*new.*### <ID>.*(entries|heading).*scenario.*test files.*(adds|added).*work item',
     'Developer may append new ### <ID> entries and scenario text for test files it adds in this work item.'),
    ('developer-existing-bytes', 'Fullstack Developer', r'existing.*(text|scenario).*byte.identical',
     'Existing scenario text stays byte-identical.'),
    ('developer-stop', 'Fullstack Developer', r'OR19.*(stop|appl)|stop.*OR19',
     'OR19 and the A49 conflict stop still apply.'),
]

failures = []
for label, name, pattern, witness in PINS:
    compliant = '\n'.join(row[3] for row in PINS if row[1] == name)
    assert matches(pattern, compliant), 'broken compliant witness: ' + label
    mutant = compliant.replace(witness, '', 1)
    assert not matches(pattern, mutant), 'clause removal escaped: ' + label
    print('PASS S469/' + label + ' clause-removal control rejected')
    path = ('skills/role-contracts/ORCHESTRATOR.md' if name == 'OR46'
            else 'skills/role-contracts/SKILL.md')
    text = scope((ROOT / path).read_text(), name)
    if not matches(pattern, text):
        failures.append(label)
        print(f'FAIL S469/{label}: {path} [{name}] must require: {witness}')
    else:
        print('PASS S469/' + label + ' loaded contract')
sys.exit(bool(failures))
