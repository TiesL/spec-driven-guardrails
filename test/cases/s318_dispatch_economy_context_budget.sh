#!/usr/bin/env bash
# S318 — both injected slots stay inside the context budget with the new rules (#532 AC8, C5; A42 budget)
# Covers: F38
#
# Seam: `session-context.sh --runtime claude --slot n <project>` output length
# against CONTEXT_BUDGET_CHARS (sourced, never a literal), on the S309 worst-case
# fixture, plus the slot-2 headroom floor and the A42 fallback consistency
# (OR47/OR48 sit in one part, and the inventory and the core agree on which).

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"

sandbox_create
trap sandbox_destroy EXIT

MARKER='<!-- session-context: slot -->'
FLOOR=500
# shellcheck source=../../lib/context-budget.sh
. "$TEST_REPO_ROOT/lib/context-budget.sh"
case "${CONTEXT_BUDGET_CHARS:-}" in
  ''|*[!0-9]*) fail "S318 — CONTEXT_BUDGET_CHARS is not a number"; test_done ;;
esac

long="$(printf 'p%.0s' $(seq 1 100))"
wf="$SANDBOX/clone-$long"
mkdir -p "$wf"
(cd "$TEST_REPO_ROOT" && tar --exclude='./.git' --exclude='./wip' --exclude='./CLAUDE.md' \
  --exclude='./.claude/settings.json' --exclude='./.claude/skills' -cf - .) | (cd "$wf" && tar -xf -)
proj="$SANDBOX/project-$long"
mkdir -p "$proj"
git -C "$proj" init -q -b main
ids=()
while IFS='|' read -r id value _; do
  case "$value" in session-context:*) ids+=("$id" yes) ;; esac
done < <(. "$wf/lib/changes.sh"; reaches_session_values "$wf/CHANGES.md")
write_adoption "$proj/WORKFLOW-ADOPTION.md" "${ids[@]}"
ln -s "$SANDBOX/nowhere/WORKFLOW.md" "$proj/CLAUDE.md"

slot_size() { # clone project n
  local out
  out="$("$1/session-context.sh" --runtime claude --slot "$3" "$2" 2>/dev/null; printf x)"
  out="${out%x}"
  printf '%s' "$out" | context_chars
}

ORCH="$wf/skills/role-contracts/ORCHESTRATOR.md"
TSV="$wf/skills/role-contracts/orchestrator-rules.tsv"
[ "$(grep -cxF "$MARKER" "$ORCH")" = 1 ] || fail "S318 — K must stay 2 (exactly one marker line)"

s1="$(slot_size "$wf" "$proj" 1)"
s2="$(slot_size "$wf" "$proj" 2)"
echo "S318 sizes: slot1=$s1 slot2=$s2 budget=$CONTEXT_BUDGET_CHARS" >&2
[ "$s1" -le "$CONTEXT_BUDGET_CHARS" ] || fail "S318/slot-1 — slot 1 is $s1 characters, over the budget of $CONTEXT_BUDGET_CHARS"
[ "$s2" -le "$CONTEXT_BUDGET_CHARS" ] || fail "S318/slot-2 — slot 2 is $s2 characters, over the budget of $CONTEXT_BUDGET_CHARS"
head2=$((CONTEXT_BUDGET_CHARS - s2))
[ "$head2" -ge "$FLOOR" ] || fail "S318/headroom — slot 2 is $s2 characters, headroom $head2 is below the floor of $FLOOR (slot 1 is $s1)"

# Fallback consistency: OR47 and OR48 exist, sit together, and the inventory part
# equals the part of the core they stand in.
marker_ln="$(grep -nxF "$MARKER" "$ORCH" | cut -d: -f1)"
for id in OR47 OR48; do
  ln="$(grep -n "^- $id " "$ORCH" | head -1 | cut -d: -f1)"
  row="$(awk -F'\t' -v i="$id" '$1==i{print $4}' "$TSV")"
  if [ -z "$ln" ] || [ -z "$row" ]; then
    fail "S318/$id — $id is missing from the core or the inventory"
    continue
  fi
  if [ "$ln" -lt "$marker_ln" ]; then actual=1; else actual=2; fi
  [ "$actual" = "$row" ] || fail "S318/$id — core part $actual, inventory part $row"
done
p47="$(awk -F'\t' '$1=="OR47"{print $4}' "$TSV")"
p48="$(awk -F'\t' '$1=="OR48"{print $4}' "$TSV")"
[ "$p47" = "$p48" ] || fail "S318/fallback — OR47 is in part '$p47' and OR48 in part '$p48': a half move"
if [ "$s2" -gt 8500 ] && [ "$p47" != 1 ]; then
  fail "S318/fallback — slot 2 is $s2 (> 8,500): OR47 and OR48 must move to part 1"
fi

# --- negative controls ------------------------------------------------------
pad="$SANDBOX/pad"
mkdir -p "$pad"
(cd "$wf" && tar -cf - .) | (cd "$pad" && tar -xf -)
python3 -I - "$pad/skills/role-contracts/ORCHESTRATOR.md" "$CONTEXT_BUDGET_CHARS" <<'PY'
import sys
p, b = sys.argv[1], int(sys.argv[2])
t = open(p, encoding="utf-8").read()
head, sep, tail = t.partition("<!-- session-context: slot -->\n")
tail = tail + "x" * (b + 1 - len(tail)) + "\n"
open(p, "w", encoding="utf-8").write(head + sep + tail)
PY
ps="$(slot_size "$pad" "$proj" 2)"
[ "$ps" -gt "$CONTEXT_BUDGET_CHARS" ] || fail "S318/neg-pad — padded part 2 is $ps, not over budget (control broken)"
# Headroom floor: part 2 grown to headroom FLOOR-1 must be refused by the floor rule.
extra=$((CONTEXT_BUDGET_CHARS - FLOOR + 1 - s2))
(cd "$wf" && tar -cf - .) | (rm -rf "$pad" && mkdir -p "$pad" && cd "$pad" && tar -xf -)
python3 -I - "$pad/skills/role-contracts/ORCHESTRATOR.md" "$extra" <<'PY2'
import sys
p, n = sys.argv[1], int(sys.argv[2])
t = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(t.rstrip("\n") + "\n" + "x" * n + "\n")
PY2
ps="$(slot_size "$pad" "$proj" 2)"
[ "$ps" -le "$CONTEXT_BUDGET_CHARS" ] || fail "S318/neg-floor — floor control grew past the budget itself ($ps)"
[ $((CONTEXT_BUDGET_CHARS - ps)) -lt "$FLOOR" ] || fail "S318/neg-floor — headroom $((CONTEXT_BUDGET_CHARS - ps)) is not below the floor (control broken)"

test_done
