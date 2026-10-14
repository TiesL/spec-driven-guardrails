#!/usr/bin/env bash
# S291 — a mutation of the new low-finding rule is caught by the document tests (#488 AC3). Covers: F44
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
fx="$TEST_REPO_ROOT/test/fixtures/decision-table-415.py"
# Red-before-green proof: the pre-change row (issue #415 decision 1) must fail the S288 checks.
old_row='| Low-severity finding: fix in the PR or file an issue | File a low-severity finding as an issue by default. A narrow text-only fix may go in the PR only during a round already required by a medium or high finding, never in a low-only round. An out-of-scope finding keeps its recorded `Disposition` and scope-expansion rules. | Decision-by-rule record in Pipeline log |'
old_doc="$(OLD_ROW="$old_row" python3 -I - "$TEST_REPO_ROOT/skills/role-contracts/ORCHESTRATOR.md" <<'PY'
import os, re, sys
t = open(sys.argv[1]).read()
sys.stdout.write(re.sub(r"(?m)^\| Low-severity finding[^\n]*$", lambda m: os.environ["OLD_ROW"], t, count=1))
PY
)"
if DT415_NEGATIVE=1 DT415_ORCH="$old_doc" python3 "$fx" "$TEST_REPO_ROOT" s288 >/dev/null 2>&1; then
  fail "S291 — the pre-change low-finding row passes the S288 checks"
fi
# Every controlled break is rejected (the fixture reports an escaped break by name).
python3 "$fx" "$TEST_REPO_ROOT" s288 || fail "S291 — a controlled break of the ORCHESTRATOR.md row escaped (S288)"
python3 "$fx" "$TEST_REPO_ROOT" s289 || fail "S291 — a controlled break of the SKILL.md Fix cost field escaped (S289)"
test_done
