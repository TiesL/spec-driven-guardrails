#!/usr/bin/env bash
# S624 — Live exercises for the model-dependent parts (#646)
# Covers: F70, F71, F72, F73, F74
#
# S624 is the live exercise for #682: UNRUN by design (subscription usage),
# never invoked here. This case checks only the exercise file's structure:
# E1-E10 each with Given, When, Then, an UNRUN status line and owner #682.
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
BEH="$TEST_REPO_ROOT/test/behavior/merge-risk-scenarios.md"
[ -f "$BEH" ] || fail "S624 - test/behavior/merge-risk-scenarios.md missing"
problems="$(python3 - "$BEH" <<'PY'
import re, sys
text = open(sys.argv[1], encoding='utf-8').read()
out = []
if 'Status: **UNRUN**' not in text.split('\n## ', 1)[0]:
    out.append('the file header is not marked UNRUN')
sections = re.split(r'^## ', text, flags=re.M)[1:]
ids = [s.split(' ', 1)[0] for s in sections]
if ids != ['E%d' % i for i in range(1, 11)]:
    out.append('exercises are %s, expected E1-E10 in order' % ids)
for s in sections:
    name = s.split(' ', 1)[0]
    for need in ('- Given: ', '- When: ', '- Then: ', '- Status: UNRUN', '- Owner: #682'):
        if not re.search('^' + re.escape(need), s, re.M):
            out.append('%s lacks %r' % (name, need.strip()))
    if re.search(r'^- Status: (?!UNRUN)', s, re.M) or re.search(r'\b(GREEN|PASSED)\b', s):
        out.append('%s claims a result' % name)
print('\n'.join(out))
PY
)" || fail "S624 - the structure check did not run"
[ -z "$problems" ] || fail "S624 - $problems"
test_done
