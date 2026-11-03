#!/usr/bin/env bash
# S485 — S305's clean-empty oracle rejects warning-only fail-open results. Covers: F28
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python3 - "$TEST_REPO_ROOT" <<'PYTHON'
import os
import pathlib
import re
import subprocess
import sys

root = pathlib.Path(sys.argv[1])
source = (root / 'test/cases/s305_carryforward_slug_exact.sh').read_text()
# Exercise the actual test helper, not a second implementation of its oracle.
start = source.index('check() {\n')
end = source.index('\n}\n', start) + 3
helper = source[start:end]
labels = re.findall(r'^\s*check "([^"]+)" "" ', source, re.M)
labels = [label.replace('$s', slug) for label in labels for slug in (('a.c', 'a+c', 'a*c', 'a[c') if '$s' in label else ('',))]
if not labels:
    sys.exit('S485: no clean-empty S305 cases found')
harness = r'''set -uo pipefail
failures=0
fail() { printf '%s\n' "$*" >&2; failures=$((failures + 1)); }
rr_reset() { :; }
rr_json() { :; }
rr_script_run() { rr_status=0; rr_out=''; rr_err="$INJECTED_STDERR"; }
T1=t1 T2=t2 T3=t3 FAKE_GH_DATA=/unused RR_PR=246 GATE=/unused
NL=$'\n' rev=review dn=done
''' + helper + '\ncheck "$CASE_LABEL" "" round1 round2\nexit "$failures"\n'
failures = []
for label in labels:
    for kind, stderr, expected in (
        ('clean control', '', 0),
        ('fail-open mutation', 'warning: carry-forward check skipped: lookup failed', 1),
    ):
        env = dict(os.environ, CASE_LABEL=label, INJECTED_STDERR=stderr)
        result = subprocess.run(['bash', '-c', harness], env=env, text=True, capture_output=True)
        if result.returncode != expected:
            failures.append(f'{label}/{kind}: expected {expected}, got {result.returncode}; {result.stderr!r}')
        elif expected and 'stderr' not in result.stderr:
            failures.append(f'{label}/{kind}: rejection did not identify stderr: {result.stderr!r}')
print(f'S485: {len(labels)} clean controls and {len(labels)} warning mutations; {len(failures)} failures')
for failure in failures:
    print(failure)
sys.exit(bool(failures))
PYTHON
