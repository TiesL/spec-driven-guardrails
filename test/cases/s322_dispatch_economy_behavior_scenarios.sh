#!/usr/bin/env bash
# S322 — the behavior file holds the A42 scenarios, parses against the closed schema, and OB51 follows the new OR13 (#532 AC1-AC6; A42)
# Covers: F38
#
# Seam: test/behavior/orchestrator-scenarios.md parsed by the S315 parser
# (orchestrator_diff.py check-scenarios) and the S311 harness cross-checks. No
# model call (the paid run is S323). New scenarios are OB52 onward, in the
# order of the QA list: 52 continue small, 53 fresh at 300k, 54 fresh next
# work item, 55 no-agent stamp and check, 56 failing command dispatched, 57
# hand edit dispatched, 58 stage not done, 59 mechanical cheapest model, 60
# affected scenarios only, 61 stamp needs full run, 62 doc-only commit.

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
harness() { out="$(python3 -I "$H" check --orch "$ORCH" --tsv "$TSV" --scen "$1" --pins "$PINS" --repo "$R" --list-checks "$checks" 2>&1)"; st=$?; }

parse "$SCEN"
[ "$pa_st" = 0 ] || fail "S322/parse — $pa_out"
harness "$SCEN"
[ "$st" = 0 ] || fail "S322/harness — $out"

ob() { awk -v n="$1" '$0 ~ "^### OB" n " "{on=1; print; next} /^### |^## /{on=0} on{print}' "$2"; }
heading() { grep -m1 "^### OB$1 " "$2"; }
then_of() { grep -m1 '^Then: ' <<<"$1"; }

expect() { # expect <ob> <heading-needle>... -- <then-needle>...
  local n="$1" blk h t seen_dash=0 x
  shift
  blk="$(ob "$n" "$SCEN")"
  [ -n "$blk" ] || { fail "S322 — OB$n does not exist"; return; }
  h="$(heading "$n" "$SCEN")"; t="$(then_of "$blk")"
  for x in "$@"; do
    if [ "$x" = -- ]; then seen_dash=1; continue; fi
    if [ "$seen_dash" = 0 ]; then
      grep -qF -- "$x" <<<"$h" || fail "S322/OB$n — heading lacks $x: $h"
    else
      grep -qF -- "$x" <<<"$t" || fail "S322/OB$n — Then lacks $x: $t"
    fi
  done
}
expect 52 OR13 -- next_action=continue_agent
expect 53 OR13 -- next_action=dispatch
expect 54 OR13 -- next_action=dispatch
expect 55 OR46 OR4 -- next_action=answer_directly
expect 56 OR46 -- next_action=dispatch
expect 57 OR46 -- next_action=dispatch
expect 58 OR33 OR46 -- next_action=dispatch
expect 59 OR28 OR39 -- next_action=dispatch model_choice=weaker
expect 60 OR48 -- run_scope=affected
expect 61 OR48 -- run_scope=full
expect 62 OR48 -- run_scope=hooks_only
expect 63 OR22 OR23 -- next_action=self_check
# Given/When of the new scenarios name no rule ID (both arms read the same prompt).
for n in 52 53 54 55 56 57 58 59 60 61 62 63; do
  blk="$(ob "$n" "$SCEN")"
  gw="$(grep -E '^(Given|When): ' <<<"$blk")"
  grep -qE '\bOR[0-9]+\b' <<<"$gw" && fail "S322/OB$n — Given or When names a rule ID"
done
# Specific content the QA list fixes.
grep -q '57k' <<<"$(ob 52 "$SCEN")" && grep -q '7 tool' <<<"$(ob 52 "$SCEN")" || fail "S322/OB52 — Given must carry 57k reported and 7 tool uses"
grep -q '300k' <<<"$(ob 53 "$SCEN")" && grep -q '269' <<<"$(ob 53 "$SCEN")" || fail "S322/OB53 — Given must carry 300k and 269 tool uses"
grep -qi 'stamp' <<<"$(ob 61 "$SCEN")" || fail "S322/OB61 — Given must have a stamp covering the whole file"
grep -qiE 'doc|\.md' <<<"$(ob 62 "$SCEN")" || fail "S322/OB62 — Given must be a doc-only commit"

# OB51 follows the new OR13: not "undecided".
ob51="$(ob 51 "$SCEN")"
grep -qi 'Nothing in your rules or from the maintainer says' <<<"$ob51" && fail "S322/OB51 — still the 'undecided' Given"
grep -q 'OR13' <<<"$(heading 51 "$SCEN")" || fail "S322/OB51 — heading must still cite OR13"

# Intended changes: each new or changed OB listed once, OR list equals heading, cites #532.
listed_check() { # listed_check <scenario file> <ob numbers...>: prints one line per problem
  local f="$1" n inten it hl il; shift
  inten="$(awk '/^## Intended changes$/{on=1; next} on{print}' "$f")"
  for n in "$@"; do
    it="$(awk -v n="$n" 'BEGIN{p="^- OB" n " [(]"} $0 ~ p{on=1; print; next} /^- OB[0-9]+ /{on=0} /^$/{on=0} on{print}' <<<"$inten")"
    if [ -z "$it" ]; then echo "OB$n is not listed under Intended changes"; continue; fi
    grep -q '#532' <<<"$it" || echo "OB$n item does not cite #532"
    hl="$(grep -m1 "^### OB$n " "$f" | sed 's/^### OB[0-9]* · //')"
    il="$(head -1 <<<"$it" | sed 's/^- OB[0-9]* (\([^)]*\)).*/\1/')"
    [ "$hl" = "$il" ] || echo "OB$n OR list '$il' differs from heading '$hl'"
  done
}
lc="$(listed_check "$SCEN" 51 52 53 54 55 56 57 58 59 60 61 62)"
[ -z "$lc" ] || fail "S322/intended — $lc"

# covered_by of every judgment row touched names at least one of these OBs; OR22 and OR23 have one.
for id in OR4 OR13 OR22 OR23 OR28 OR33 OR46 OR47 OR48; do
  cov="$(awk -F'\t' -v i="$id" '$1==i{print $5}' "$TSV")"
  case "$id" in
    OR47) [[ ",$cov," == *,OB5[2-9],* || ",$cov," == *,OB6[0-2],* ]] || fail "S322/covered — $id covered_by '$cov' names no new OB" ;;
    *)    [[ ",$cov," == *,OB5[2-9],* || ",$cov," == *,OB6[0-3],* || ",$cov," == *,OB51,* ]] || fail "S322/covered — $id covered_by '$cov' names no new or amended OB" ;;
  esac
done
for id in OR22 OR23; do
  cov="$(awk -F'\t' -v i="$id" '$1==i{print $5}' "$TSV")"
  # a Pipeline log line without the new fields is incomplete: one OB of 52-62 must cover each
  [[ ",$cov," == *,OB5[2-9],* || ",$cov," == *,OB6[0-3],* ]] || fail "S322/covered — $id must be covered by a new OB (52-63), got '$cov'"
done

# --- negative controls -------------------------------------------------------
d="$SANDBOX"
sed 's/^### OB52 · OR13$/### OB52 · OR13, OR49/' "$SCEN" > "$d/s-or49.md"
parse "$d/s-or49.md"; [ "$pa_st" != 0 ] || harness "$d/s-or49.md"
{ [ "$pa_st" != 0 ] || [ "$st" != 0 ]; } || fail "S322/neg-or49 — an OB citing OR49 passed"

awk '/^- OB52 [(]/{skip=1; next} skip && /^  /{next} {skip=0; print}' "$SCEN" > "$d/s-unlisted.md"
[ -n "$(listed_check "$d/s-unlisted.md" 52)" ] || fail "S322/neg-unlisted — a new OB missing from Intended changes passed"

sed 's/^- OB52 (OR13)/- OB52 (OR13, OR12)/' "$SCEN" > "$d/s-mismatch.md"
[ -n "$(listed_check "$d/s-mismatch.md" 52)" ] || fail "S322/neg-mismatch — an Intended-changes item whose OR list differs passed"
parse "$d/s-mismatch.md"
[ "$pa_st" != 0 ] || fail "S322/neg-mismatch-parser — the parser accepted an Intended-changes item whose OR list differs"

test_done
