#!/usr/bin/env bash
# S532 — OB83 is in the inventory under OR43 and OR45 and graded dispatch to QA (#620)
# Covers: F38
#
# Seam: orchestrator-rules.tsv (covered_by column) and
# test/behavior/orchestrator-scenarios.md read as text. No model call.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

R="$TEST_REPO_ROOT"

# covers <tsv> <rule> <OBn> : the rule's covered_by (column 5) lists OBn.
covers() { awk -F'\t' -v r="$2" -v s="$3" '$1==r{n=split($5,a,","); for(i=1;i<=n;i++) if(a[i]==s) f=1} END{exit f?0:1}' "$1"; }
# block <scenarios> : the OB83 block (heading to the next heading).
block() { awk '/^### OB83 /{p=1;print;next} /^### /{p=0} p' "$1"; }
# scen_ok <scenarios> : heading names both rules, Then is the dispatch to QA.
scen_ok() {
  b="$(block "$1")"
  [ -n "$b" ] || { echo "no OB83 block"; return 1; }
  [ "$(head -1 <<<"$b")" = '### OB83 · OR43, OR45' ] || { echo "OB83 heading is not 'OR43, OR45'"; return 1; }
  grep -qxF 'Then: next_action=dispatch; next_role=QA; asks_human=false' <<<"$b" || { echo "OB83 Then differs"; return 1; }
}

TSV="$R/skills/role-contracts/orchestrator-rules.tsv"
SCEN="$R/test/behavior/orchestrator-scenarios.md"
for rule in OR43 OR45; do
  covers "$TSV" "$rule" OB83 || fail "S532 — the inventory row of $rule does not list OB83"
done
msg="$(scen_ok "$SCEN")" || fail "S532 — $msg"

# Controls on scratch copies built from the real files plus the expected edits.
t="$SANDBOX/rules.tsv"; s="$SANDBOX/scen.md"
# Only the control edit (appending OB83 where absent) so the control is independent of the real state.
awk -F'\t' 'BEGIN{OFS="\t"} ($1=="OR43"||$1=="OR45") && $5 !~ /OB83/ {$5=$5",OB83"} {print}' "$TSV" >"$t"
{ covers "$t" OR43 OB83 && covers "$t" OR45 OB83; } || fail "S532/control — inventory with OB83 added was rejected"
# Mutants: OB83 dropped from one rule.
for rule in OR43 OR45; do
  awk -F'\t' -v r="$rule" 'BEGIN{OFS="\t"} $1==r {gsub(/,?OB83/,"",$5)} {print}' "$t" >"$SANDBOX/m.tsv"
  covers "$SANDBOX/m.tsv" "$rule" OB83 && fail "S532/mutant — OB83 dropped from $rule still passes"
done
# Scenario control: the file with a correct OB83 block present (appended if missing).
cp "$SCEN" "$s"
if [ -z "$(block "$s")" ]; then
  printf '\n### OB83 · OR43, OR45\nGiven: g\nWhen: w\nThen: next_action=dispatch; next_role=QA; asks_human=false\n' >>"$s"
fi
scen_ok "$s" >/dev/null || fail "S532/control — a correct OB83 block was rejected"
# Mutants: Then changed, heading changed.
sed 's/^Then: next_action=dispatch; next_role=QA; asks_human=false$/Then: next_action=ask_human; asks_human=true/' "$s" >"$SANDBOX/m.md"
scen_ok "$SANDBOX/m.md" >/dev/null && fail "S532/mutant — OB83 with ask_human passed"
sed 's/^### OB83 · OR43, OR45$/### OB83 · OR45/' "$s" >"$SANDBOX/m2.md"
scen_ok "$SANDBOX/m2.md" >/dev/null && fail "S532/mutant — OB83 under OR45 only passed"
test_done
