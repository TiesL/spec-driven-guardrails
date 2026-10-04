#!/usr/bin/env bash
# S180 — ORCHESTRATOR.md states the run rules, once, in the one place that
# session-context.sh injects.
# Covers: F38
#
# Issue #371, A16/A18, AC1, AC4-AC8. What a session DOES with these rules
# (starts the pipeline unprompted, declines for a question, never nests,
# stops when it cannot dispatch) is model behaviour and cannot be asserted
# here; this is the mechanical proxy: the text that would make it happen is
# present, concrete, and cheap enough to inject in every session. Real
# behaviour stays with a human dry run (see the QA report on #371).

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

orch="$TEST_REPO_ROOT/skills/role-contracts/ORCHESTRATOR.md"
skill="$TEST_REPO_ROOT/skills/role-contracts/SKILL.md"
if [ ! -f "$orch" ]; then
  fail "S180 — skills/role-contracts/ORCHESTRATOR.md does not exist"
  test_done
fi

text="$(cat "$orch")"
lower="$(tr '[:upper:]' '[:lower:]' <<<"$text")"
need() { # label, needle (case-insensitive)
  local n
  n="$(tr '[:upper:]' '[:lower:]' <<<"$2")"
  case "$lower" in *"$n"*) ;; *) fail "S180 — ORCHESTRATOR.md has nothing for: $1 (looked for '$2')" ;; esac
}

# AC5: the recursion guard comes first, so a role session sees it first.
head5="$(grep -v '^[[:space:]]*$' "$orch" | head -5)"
case "$head5" in
  *"ROLE SESSION:"*) ;;
  *) fail "S180/AC5 — 'ROLE SESSION:' guard is not within the first five non-blank lines" ;;
esac
need "AC5 dispatched roles never fork" "fork"
need "AC5 roles are fresh agents" "fresh"

# AC1: announce, set the first label, dispatch Product, then each stage in order.
need "AC1 first label" "role:product"
# each label and its model-record stage value sit on one line (the table)
for pair in role:product:Discovery role:architect:Planning role:qa:Test role:dev:Implementation role:reviewer:Review; do
  lab="${pair%:*}"; stg="${pair##*:}"
  lab_lines="$(grep -F "$lab" "$orch")"
  grep -q "$stg" <<<"$lab_lines" \
    || fail "S180/AC1 — no line pairs $lab with stage $stg"
done
need "AC1 announces the pipeline" "announce"

# AC4: what is and is not a work item.
need "AC4 work item" "work item"
for non in question research "co-thinking" adoption; do need "AC4 non-work-item: $non" "$non"; done

# AC6: the override record, who and why, never self-granted.
need "AC6 override marker" "pipeline-override"
for field in decided-by scope reason; do need "AC6 override field $field" "$field"; done
need "AC6 no self-granted shortcuts" "trivial"

# AC7: cannot dispatch -> stop and ask.
need "AC7 stop" "stop"
need "AC7 ask the human" "ask"

# AC8: resume from evidence.
need "AC8 resume" "resume"
need "AC8 uses the staleness script" "role-label-staleness.sh"

# Single source: SKILL.md points here instead of restating the run rules.
if ! grep -q 'ORCHESTRATOR.md' "$skill"; then
  fail "S180 — role-contracts/SKILL.md does not point to ORCHESTRATOR.md"
fi

# Injected into every opted-in session: keep it short (about 30 lines).
lines="$(wc -l < "$orch" | tr -d ' ')"
if [ "$lines" -gt 80 ]; then
  fail "S180 — ORCHESTRATOR.md is $lines lines; it loads into every opted-in session, keep it near 30"
fi

test_done
