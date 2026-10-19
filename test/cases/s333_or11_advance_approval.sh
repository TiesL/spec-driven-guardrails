#!/usr/bin/env bash
# S333, S334 — OR11, the core fixture, the inventory and the behavior scenarios follow the advance-approval rule (#516 AC4-AC6; A43)
# Covers: F55
#
# Seam: skills/role-contracts/ORCHESTRATOR.md OR11, the orchestrator-core.py
# harness (its or11-wording check), orchestrator-rules.tsv, and
# test/behavior/orchestrator-scenarios.md parsed by the S315 parser. No model
# call (the paid run is S335). The S311 OR11 mutation lives in S311's own file.
# New scenarios: OB64 advance approval honoured, OB65 finding fix lapses,
# OB66 red CI fix lapses, OB67 update-only head survives, OB68 CI not yet
# green on the updated head, OB69 fix on top of the update lapses, OB70
# paraphrased relay, OB71 verbatim relay, OB72 approval for another PR.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

R="$TEST_REPO_ROOT"
PY="$R/test/behavior/orchestrator_diff.py"
H="$R/test/fixtures/orchestrator-core.py"
ORCH="$R/skills/role-contracts/ORCHESTRATOR.md"
TSV="$R/skills/role-contracts/orchestrator-rules.tsv"
SCEN="$R/test/behavior/orchestrator-scenarios.md"
HOOK="$R/hooks/agent-dispatch.py"
PINS="$R/test/fixtures/orchestrator-core-pins.tsv"
checks="$(python3 -I "$HOOK" --list-checks 2>/dev/null | tr '\n' ' ')"

parse() { pa_out="$(python3 -I "$PY" check-scenarios --scenarios "$1" --orchestrator "$ORCH" 2>&1)"; pa_st=$?; }
harness() { out="$(python3 -I "$H" check --orch "$1" --tsv "$TSV" --scen "$SCEN" --pins "$PINS" --repo "$R" --list-checks "$checks" 2>&1)"; st=$?; }

# --- S333: OR11 text --------------------------------------------------------
or11="$(grep -m1 '^- OR11 ' "$ORCH")"
[ -n "$or11" ] || fail "S333 — no OR11 item"
for x in "Dispatched roles never merge" "in advance" "Review approves" "CI green" "every pre-merge check passes" \
         "no head SHA" "new commit that changes the work lapses the approval" "ask again after fix" \
         "gh pr update-branch" "first parent" "log approval head and merged head" "verbatim words about that PR" \
         "#511" "process-advance-merge-approval" "release-branch-workflow"; do
  grep -qF -- "$x" <<<"$or11" || fail "S333/OR11 — lacks '$x': $or11"
done
grep -qF "final head SHA" <<<"$or11" && fail "S333/OR11 — still says the final head SHA"

harness "$ORCH"
[ "$st" = 0 ] || fail "S333/harness — $out"

# Negative control: the old sentence restored in a copy fails or11-wording by name.
d="$SANDBOX"
python3 - "$ORCH" "$d/o-old.md" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
out = []
for line in open(src, encoding="utf-8"):
    if line.startswith("- OR11 "):
        line = ("- OR11 Dispatched roles never merge. Merge into `main` only after human confirms final head SHA; "
                "new commit after confirmation needs new confirmation. Merging work-item PR into release branch: "
                "your step, per `release-branch-workflow` skill (WORKFLOW.md says when).\n")
    out.append(line)
open(dst, "w", encoding="utf-8").write("".join(out))
PY
harness "$d/o-old.md"
grep -q 'or11-wording' <<<"$out" || fail "S333/neg-old — the old OR11 sentence passed the fixture: $out"

# Inventory row: ID, name, tier and part unchanged; covered_by names every OR11 OB.
row="$(awk -F'\t' '$1=="OR11"' "$TSV")"
[ "$(cut -f2-4 <<<"$row")" = "$(printf 'merge-into-main-gate\tjudgment\t1')" ] || fail "S333/tsv — OR11 row changed name, tier or part: $row"
cov=",$(cut -f5 <<<"$row"),"
for n in 9 10 11 64 65 66 67 68 69 70 71 72; do
  [[ "$cov" == *",OB$n,"* ]] || fail "S333/tsv — OR11 covered_by lacks OB$n: $row"
done

# --- S334: behavior scenarios -----------------------------------------------
parse "$SCEN"
[ "$pa_st" = 0 ] || fail "S334/parse — $pa_out"

ob() { awk -v n="$1" '$0 ~ "^### OB" n " "{on=1; print; next} /^### |^## /{on=0} on{print}' "$SCEN"; }
then_of() { grep -m1 '^Then: ' <<<"$1"; }
expect() { # expect <ob> <then-needle>...
  local n="$1" blk h t x gw
  shift
  blk="$(ob "$n")"
  [ -n "$blk" ] || { fail "S334 — OB$n does not exist"; return; }
  h="$(head -1 <<<"$blk")"
  [ "$h" = "### OB$n · OR11" ] || fail "S334/OB$n — heading must cite OR11 only: $h"
  t="$(then_of "$blk")"
  for x in "$@"; do
    grep -qF -- "$x" <<<"$t" || fail "S334/OB$n — Then lacks $x: $t"
  done
  gw="$(grep -E '^(Given|When): ' <<<"$blk")"
  grep -qE '\bOR[0-9]+\b' <<<"$gw" && fail "S334/OB$n — Given or When names a rule ID"
}
expect 9  next_action=ask_human asks_human=true
expect 10 next_action=merge asks_human=false
expect 11 next_action=merge asks_human=false
expect 64 next_action=merge asks_human=false
expect 65 next_action=ask_human asks_human=true
expect 66 next_action=ask_human asks_human=true
expect 67 next_action=merge asks_human=false
expect 68 next_action=answer_directly asks_human=false
expect 69 next_action=ask_human asks_human=true
expect 70 next_action=ask_human asks_human=true
expect 71 next_action=merge asks_human=false
expect 72 next_action=ask_human asks_human=true

# Given content the QA list fixes.
given() { grep -m1 '^Given: ' <<<"$(ob "$1")"; }
grep -qiE 'finding|red' <<<"$(given 9)" || fail "S334/OB9 — the push must be a required change (a finding or red CI)"
grep -qi 'flaky' <<<"$(given 9)" && fail "S334/OB9 — still the optional flaky-test tweak"
for n in 64 65 66 67 68 69 71; do
  grep -qF 'merge once everything is green' <<<"$(given "$n")" || fail "S334/OB$n — Given must carry the advance approval in the maintainer's words"
done
grep -qiE 'finding' <<<"$(given 65)" || fail "S334/OB65 — Given must have a Review finding"
grep -qiE 'red|fail' <<<"$(given 66)" || fail "S334/OB66 — Given must have red CI"
for n in 67 68 69; do
  grep -qF 'gh pr update-branch' <<<"$(given "$n")" || fail "S334/OB$n — Given must have update-branch"
  grep -qF 'git rev-list --parents -n1' <<<"$(given "$n")" || fail "S334/OB$n — Given must show the first-parent shape"
done
grep -qiE 'still running|not finished|pending' <<<"$(given 68)" || fail "S334/OB68 — CI must not be green yet"
grep -qiE 'fix|commit on top' <<<"$(given 69)" || fail "S334/OB69 — Given must have a commit on top of the update"
grep -qiE 'relay' <<<"$(given 70)" && grep -qiE 'relay' <<<"$(given 71)" || fail "S334/OB70-71 — Given must be a relayed approval"
grep -qF 'PR 44' <<<"$(given 72)" || fail "S334/OB72 — Given must be about another PR (44)"

# Intended changes: each changed or new OB listed once, OR list equals heading, cites #516.
inten="$(awk '/^## Intended changes$/{on=1; next} on{print}' "$SCEN")"
for n in 9 64 65 66 67 68 69 70 71 72; do
  it="$(awk -v n="$n" 'BEGIN{p="^- OB" n " [(]"} $0 ~ p{on=1; print; next} /^- OB[0-9]+ /{on=0} /^$/{on=0} on{print}' <<<"$inten")"
  [ -n "$it" ] || { fail "S334/intended — OB$n is not listed"; continue; }
  grep -q '#516' <<<"$it" || fail "S334/intended — OB$n item does not cite #516"
  first="$(head -1 <<<"$it")"
  grep -q "^- OB$n (OR11):" <<<"$first" || fail "S334/intended — OB$n OR list differs from its heading"
done

test_done
