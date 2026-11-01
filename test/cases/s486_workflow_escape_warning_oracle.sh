#!/usr/bin/env bash
# S486 — S308's warning oracle rejects unnamed and unrelated escape warnings. Covers: F7
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 - "$TEST_REPO_ROOT" <<'PYTHON'
import ast
import json
import os
import pathlib
import subprocess
import sys
import types

root = pathlib.Path(sys.argv[1])
source = (root / 'test/cases/s306_s308_guard_no_verify.sh').read_text().split("<<'PY'\n", 1)[1].rsplit('\nPY', 1)[0]
tree = ast.parse(source)
helpers = [node for node in ast.walk(tree) if isinstance(node, ast.FunctionDef) and node.name == 'check']
if len(helpers) != 1:
    sys.exit('S486: expected exactly one S306-S308 check helper')
# Compile the real oracle in isolation; only the hook's captured observation is substituted.
code = compile(ast.Module(body=helpers, type_ignores=[]), '<S308 check>', 'exec')
variable = 'CLAUDE_WORKFLOW_GUARDRAILS_OFF'
valid = f'warning: git-guardrails is disabled via {variable}.\n'
commands = ('git commit --no-verify', 'git commit -n', 'git push --no-verify origin HEAD')
failures = []
checks = 0
for command in commands:
    for form in ('environment', 'prefix'):
        for value in ('1', 'yes'):
            actual = command if form == 'environment' else f'{variable}={value} {command}'
            extra = {variable: value} if form == 'environment' else None
            for kind, stderr, rejected in (
                ('named control', valid, False),
                ('missing-name mutation', valid.replace(variable, 'WORKFLOW_ESCAPE'), True),
                ('unrelated-warning mutation', 'warning: unrelated lookup failed\n', True),
                ('missing-warning mutation', valid.replace('warning:', 'notice:'), True),
                ('unrelated-named-warning mutation', f'warning: {variable} lookup failed\n', True),
            ):
                observation = subprocess.CompletedProcess([], 0, '', stderr)
                seen = []
                def run(*args, **kwargs):
                    seen.append((json.loads(kwargs['input']), kwargs['env']))
                    return observation
                scope = dict(root=root, feature=root, os=os, json=json, failures=[], checks=0,
                             subprocess=types.SimpleNamespace(run=run))
                exec(code, scope)
                scope['check'](actual, extra=extra, warning=True)
                checks += 1
                if bool(scope['failures']) != rejected:
                    failures.append(f'{actual}/{form}/{kind}: expected rejection={rejected}, got {scope["failures"]!r}')
                if rejected and scope['failures'] and 'missing named workflow escape warning' not in scope['failures'][0]:
                    failures.append(f'{actual}/{kind}: rejected for an unrelated reason: {scope["failures"]!r}')
                if len(seen) != 1 or seen[0][0]['tool_input']['command'] != actual:
                    failures.append(f'{actual}/{kind}: helper did not invoke the hook once with the intended command')
                if seen and seen[0][1].get(variable) != (value if form == 'environment' else None):
                    failures.append(f'{actual}/{kind}: wrong process-environment escape')
print(f'S486: {checks // 5} named controls and {checks // 5 * 4} independent observation mutations; {len(failures)} failures')
for failure in failures:
    print(failure)
sys.exit(bool(failures))
PYTHON
