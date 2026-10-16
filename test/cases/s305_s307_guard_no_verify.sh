#!/usr/bin/env bash
# S305-S307 — Bypass options, operand controls, and explicit escapes. Covers: F7
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT

python3 - "$(cd "$(dirname "$0")/../.." && pwd)" <<'PY'
import json, os, pathlib, subprocess, sys, tempfile
root = pathlib.Path(sys.argv[1])
failures = []
checks = 0
with tempfile.TemporaryDirectory() as tmp:
    base = pathlib.Path(tmp)
    def git(directory, *args):
        subprocess.run(['git', '-C', str(directory), *args], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    feature = base / 'feature'; feature.mkdir()
    git(feature, 'init', '-b', 'main')
    git(feature, '-c', 'user.name=Test', '-c', 'user.email=test@example.com', 'commit', '--allow-empty', '-m', 'start')
    git(feature, 'checkout', '-b', 'feature/test')
    unborn = base / 'unborn'; unborn.mkdir(); git(unborn, 'init', '-b', 'main')
    outside = base / 'outside'; outside.mkdir()
    def check(command, expected=0, flag=None, cwd=feature, extra=None, tool='Bash', warning=False):
        global checks
        checks += 1
        env = dict(os.environ)
        for key in ('CLAUDE_WORKFLOW_GUARDRAILS_OFF', 'CLAUDE_WORKFLOW_MERGE_GUARD_OFF'):
            env.pop(key, None)
        env.update(extra or {})
        payload = dict(tool_name=tool, cwd=str(cwd), tool_input=dict(command=command))
        result = subprocess.run([str(root / 'hooks/git-guardrails')], input=json.dumps(payload), text=True, capture_output=True, env=env)
        errors = []
        if result.returncode != expected: errors.append(f'exit {result.returncode}, expected {expected}')
        if flag and (flag not in result.stderr or 'CLAUDE_WORKFLOW_GUARDRAILS_OFF=1' not in result.stderr): errors.append('missing bypass diagnostic')
        if warning and 'warning:' not in result.stderr: errors.append('missing warning')
        if errors: failures.append(f'{command!r} [{cwd.name}]: {", ".join(errors)}; stderr={result.stderr!r}')
    direct = [('git commit --no-verify', '--no-verify'), ('git commit -n', '-n'), ('git push --no-verify origin HEAD', '--no-verify')]
    def blocked(command, flag='--no-verify', **kwargs): check(command, 2, flag, **kwargs)
    for command, flag in direct:
        for cwd in (feature, unborn, outside): blocked(command, flag, cwd=cwd)
    git(feature, 'checkout', 'main')
    for command, flag in direct: blocked(command, flag)
    git(feature, 'checkout', '--detach')
    for command, flag in direct: blocked(command, flag)
    git(feature, 'checkout', 'feature/test')
    for command, flag in [('git commit "--no-verify"', '--no-verify'), ('git commit -an', '-an'), ('git commit -nm text', '-nm'), ('git commit --no-verify --verify', '--no-verify')]: blocked(command, flag)
    for prefix in ['FOO=1 git', f'git -C {feature}', f'git --git-dir={feature}/.git --work-tree={feature}', 'git -c color.ui=false']:
        blocked(prefix + ' commit --no-verify')
    for prefix in ['echo ok; ', 'echo ok && ', 'echo ok\n']:
        blocked(prefix + 'git commit --no-verify')
    for tail in ["-m '--no-verify'", "-m '-n'", '--message=--no-verify', '-m--no-verify', '-mn', '-am--no-verify', '-F --no-verify', '--file --no-verify', '--file=--no-verify', '-- --no-verify', '-- -n', '-m ordinary']:
        check('git commit ' + tail)
    for tail in ['-o --no-verify', '--push-option --no-verify', '--push-option=--no-verify', '-- --no-verify', '-n origin HEAD', 'origin HEAD']:
        check('git push ' + tail)
    blocked("git commit -m '-n' --no-verify")
    blocked('git push -o --no-verify --no-verify origin HEAD')
    check("echo 'git commit --no-verify; git commit -n; git push --no-verify'")
    heredoc = 'cat <<EOF\ngit commit --no-verify\ngit commit -n\ngit push --no-verify\nEOF\n'
    check(heredoc)
    blocked(heredoc + 'git commit --no-verify')
    check('git commit "--no-verify')
    check('git commit --no-verify', tool='Read')
    for command, flag in direct:
        for value in ('1', 'yes'):
            check(command, extra={'CLAUDE_WORKFLOW_GUARDRAILS_OFF': value}, warning=True)
            check(f'CLAUDE_WORKFLOW_GUARDRAILS_OFF={value} ' + command, warning=True)
        blocked(command, flag, extra={'CLAUDE_WORKFLOW_MERGE_GUARD_OFF': '1'})
        blocked('CLAUDE_WORKFLOW_MERGE_GUARD_OFF=1 ' + command, flag)
print(f'S305-S307: {checks} checks; {len(failures)} failures')
for failure in failures: print(failure)
sys.exit(bool(failures))
PY
