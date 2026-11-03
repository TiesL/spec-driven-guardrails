#!/usr/bin/env python3
"""Directional text oracles for the current role-contract carriers (#611)."""
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
mode = sys.argv[2]


def read(path):
    return re.sub(r'\s+', ' ', (root / path).read_text())


def item(rid):
    text = (root / 'skills/role-contracts/ORCHESTRATOR.md').read_text()
    hits = re.findall(rf'^ *- {rid} (.*)$', text, re.M)
    assert len(hits) == 1, f'{rid}: expected one item'
    return hits[0]


if mode == 'reviewer':
    # Bind both mechanisms to the ban, rather than accepting a nearby "never".
    contracts = {
        'skills/role-contracts/SKILL.md':
            r'never resumed or continued: not by `SendMessage`, and not by the dispatch tool\'s `fork` type',
        'skills/pre-merge-review/SKILL.md':
            r'never continued, by `SendMessage` or by the dispatch tool\'s `fork` type',
    }
    for path, pattern in contracts.items():
        assert re.search(pattern, read(path)), f'{path}: explicit continuation ban'
    assert re.search(r'Reviewer never continued: never `SendMessage` to earlier round\'s Reviewer, never dispatch tool\'s `fork` type', item('OR12')), 'OR12: explicit ban for each mechanism'
elif mode == 'reclassification':
    assert re.search(r'Architect may record that a finding is not a design defect and route it as code', read('skills/role-contracts/SKILL.md')), 'SKILL: affirmative Architect reclassification permission'
    assert re.search(r'Architect may record not design defect, route as code', item('OR18')), 'OR18: affirmative Architect reclassification permission'
else:
    raise AssertionError(f'unknown mode: {mode}')
