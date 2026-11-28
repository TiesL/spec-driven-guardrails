#!/usr/bin/env bash
# S627 — Branch core snapshot, pointers, budget and projection evidence (#646; A60 + addendum 1)
# Covers: F74
# Oracle: QA-owned S627 including A60 addenda 1-3 where applicable.
#
# Seam: the bytes of skills/role-contracts/ORCHESTRATOR.md (OR11, OR43, OR6 as in
# A58 D2), policy/WORKFLOW.md step 4 and its generated projections
# (check-workflow-adapters.sh). The differential behavior run and its stamp are
# the orchestrator's (UNRUN here); the SNAPSHOTS re-pin is S548's.
# Mutation checks: the `#511` token removed (pointer check fails); a
# hand-edited projection (generator check fails). The slot-headroom part
# (500-character floor, relative OR11 growth, short path) is retired by #750
# (A66): the core no longer reaches the session through a capped hook output.
#
# shellcheck disable=SC2016 # backticks are literal rule text, never expansions
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"
sandbox_create
trap sandbox_destroy EXIT

MARKER='<!-- session-context: slot -->'
OR11_TAIL='Autonomy without per-PR approval: #511, only via accepted `merge-risk-panel` delegation.'
WF_SENTENCE='Merge autonomy without a per-PR approval is #511, not this rule. Only the accepted #646 delegation (the `merge-risk-panel` skill) provides it.'
clone() { # dest
  mkdir -p "$1"
  (cd "$TEST_REPO_ROOT" && tar --exclude='./.git' --exclude='./prep' --exclude='./CLAUDE.md' \
    --exclude='./.claude/settings.json' --exclude='./.claude/skills' --exclude='./.handoff' --exclude='./REPORT.md' -cf - .) | (cd "$1" && tar -xf -)
}

long="$(printf 'p%.0s' $(seq 1 100))"

# pointer_problems <clone>: prints one line per violated pointer rule.
pointer_problems() {
  local orch="$1/skills/role-contracts/ORCHESTRATOR.md" part1 or11 or43 or6
  [ "$(grep -cxF "$MARKER" "$orch")" = 1 ] || echo "K must stay 2 (exactly one marker line)"
  part1="$(sed "/^$MARKER\$/q" "$orch")"
  or11="$(grep -m1 '^- OR11 ' <<<"$part1")"
  or43="$(grep -m1 '^- OR43 ' <<<"$part1")"
  or6="$(grep -m1 '^- OR6 ' <<<"$part1")"
  grep -qF -- "$OR11_TAIL" <<<"$or11" || echo "OR11 lacks the pointer sentence: $or11"
  grep -qF -- '#511' <<<"$or11" || echo "OR11 lost the #511 token"
  grep -qF -- 'merges into `main` (OR11);' <<<"$or43" || echo "OR43 lacks (OR11): $or43"
  grep -qF -- 'confirmation before merge into `main` (OR11)' <<<"$or6" || echo "OR6 lacks (OR11): $or6"
  [ "$(grep -c 'merge-risk' "$orch")" = 1 ] || echo "procedure text entered the core: merge-risk named $(grep -c 'merge-risk' "$orch") times"
  grep -qE 'merge-risk-evidence|merge-autonomy|hold_seconds|--match-head-commit' "$orch" && echo "procedure text entered the core"
}

projection_problems() { # clone
  local f
  for f in policy/WORKFLOW.md WORKFLOW.md AGENTS.md adapters/codex/AGENTS.md; do
    grep -qF -- "$WF_SENTENCE" "$1/$f" || echo "$f lacks the step 4 delegation sentence"
  done
  (cd "$1" && ./check-workflow-adapters.sh >/dev/null 2>&1) || echo "check-workflow-adapters.sh is not clean"
}

wf="$SANDBOX/wf-$long"
clone "$wf"
while IFS= read -r p; do [ -n "$p" ] && fail "S627/pointer — $p"; done < <(pointer_problems "$wf")
while IFS= read -r p; do [ -n "$p" ] && fail "S627/projection — $p"; done < <(projection_problems "$wf")
# The #646 mention belongs only in #679's process-multi-agent-roles v4 reason.
awk '
  /^## process-multi-agent-roles$/ { in_row = 1 }
  /^## / && !/^## process-multi-agent-roles$/ { in_row = 0; in_reason = 0 }
  in_row && /^- \*\*Meaning version:\*\* 4 —/ { in_reason = 1; next }
  in_reason && /^- \*\*/ { in_reason = 0 }
  !in_reason && index($0, "#646") { found = 1 }
  END { exit !found }
' "$TEST_REPO_ROOT/CHANGES.md" && fail "S627/meaning — CHANGES.md carries #646 outside #679's v4 reason"

# --- mutation checks ----------------------------------------------------------
m="$SANDBOX/m-$long"
clone "$m"
rm -rf "$m"; clone "$m"
sed -i.bak 's/approval: #511, only via/approval: only via/' "$m/skills/role-contracts/ORCHESTRATOR.md"
out="$(pointer_problems "$m")"
grep -qF 'lost the #511 token' <<<"$out" || fail "S627/mutation — removing the #511 token went unnoticed"

rm -rf "$m"; clone "$m"
printf '\nhand edit\n' >>"$m/WORKFLOW.md"
out="$(projection_problems "$m")"
grep -qF 'not clean' <<<"$out" || fail "S627/mutation — a hand-edited projection passed the generator check"

# A60's A identity is retained. A64 addendum 2 allows only the shared exact
# #706 pairs and S548's single genuine stamp digest; the pins stay identical.
python3 -I - "$TEST_REPO_ROOT" <<'PY706'
from pathlib import Path
import runpy, sys
root = Path(sys.argv[1])
a = runpy.run_path(str(root/'test/fixtures/wip-706-substitutions.py'))
errors = a['protected_a_checks'](root)
for error in errors:
    print('FAIL: '+error)
sys.exit(bool(errors))
PY706
[ "$?" -eq 0 ] || fail "S627 — protected A exact allowances not satisfied"

test_done
