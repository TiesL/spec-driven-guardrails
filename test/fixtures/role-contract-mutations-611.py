#!/usr/bin/env python3
"""Offline mutations against the actual contract tests, in a private file tree."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
mode = sys.argv[2]
roles = 'skills/role-contracts/SKILL.md'
orch = 'skills/role-contracts/ORCHESTRATOR.md'
pmr = 'skills/pre-merge-review/SKILL.md'
cases = {
    'reviewer': ('s209_fresh_reviewer_every_round.sh', [
        (roles, 'never resumed or continued: not by `SendMessage`, and not by', 'never resumed or continued except by `SendMessage`, or by'),
        (pmr, 'never continued, by `SendMessage` or by', 'never continued except by `SendMessage` or by'),
        (orch, 'never continued: never `SendMessage`', 'never continued except by `SendMessage`'),
        (orch, "Reviewer, never dispatch tool's `fork` type", "Reviewer, except by dispatch tool's `fork` type"),
    ]),
    'reclassification': ('s214_route_by_class.sh', [
        (roles, 'Architect may record', 'Architect may not record'),
        (orch, 'Architect may record', 'Architect may not record'),
    ]),
    'cwd': ('s218_self_check_and_override.sh', [
        (orch, "working directory = project's checkout (in guardrails repo", "working directory = guardrails clone, never the project's checkout (in guardrails repo"),
        (orch, "working directory = project's checkout (in guardrails repo", "working directory = never project's checkout (in guardrails repo"),
    ]),
    'pushback': ('s281_one_pushback.sh', [
        (orch, "Dispatch recommending role once for reasoned pushback before decision recorded; its input = its recommendation and maintainer's words.", ''),
        (orch, 'pushback before decision recorded', 'pushback after decision recorded'),
    ]),
    'risk': ('s282_architect_risk_note.sh', [
        (orch, "Non-Architect role's overrule: dispatch Architect for issue risk note.", ''),
        (orch, 'dispatch Architect for issue risk note', 'never dispatch Architect for issue risk note'),
        (roles, '**Decision** linking', 'linking'),
    ]),
}
# Copy only the offline readers and their data; no git setup or executable hooks.
with tempfile.TemporaryDirectory(prefix='sdg-611-') as tmp:
    target = Path(tmp)
    for path in ('test/lib.sh', 'lib/git-env.sh', roles, orch, pmr,
                 'skills/role-contracts/orchestrator-rules.tsv'):
        dest = target / path
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(root / path, dest)
    shutil.copytree(root / 'test/fixtures', target / 'test/fixtures')
    script, mutations = cases[mode]
    dest = target / 'test/cases' / script
    dest.parent.mkdir(parents=True)
    shutil.copyfile(root / 'test/cases' / script, dest)
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(('DT415_', 'OC_'))}
    env['PYTHONDONTWRITEBYTECODE'] = '1'

    def run():
        return subprocess.run(['bash', str(dest)], env=env, capture_output=True, text=True)

    baseline = run()
    assert baseline.returncode == 0, baseline.stdout + baseline.stderr
    escaped = []
    for path, old, new in mutations:
        doc = target / path
        original = doc.read_text()
        assert original.count(old) == 1, f'ambiguous or absent anchor: {path}: {old}'
        doc.write_text(original.replace(old, new, 1))
        result = run()
        doc.write_text(original)
        if result.returncode == 0:
            escaped.append(f'{path}: {old} -> {new!r}')
        else:
            assert 'FAIL:' in result.stderr, result.stderr
            print(f'rejected: {path}: {old} -> {new!r}')
    assert not escaped, 'mutations escaped:\n' + '\n'.join(escaped)
    print(f'{mode}: current text passes; all {len(mutations)} mutations fail')
