#!/usr/bin/env bash
# S311 — every rule has one ID in one part, the parts stand alone, and the
# inventory matches the core (#499 AC2, AC3, AC7)
# Covers: F38
#
# Seam: the files ORCHESTRATOR.md, orchestrator-rules.tsv,
# test/behavior/orchestrator-scenarios.md and `agent-dispatch.py
# --list-checks`, read as data by the shared harness
# test/fixtures/orchestrator-core.py (which the AC14-amended scenarios use
# too). Each negative control breaks one thing in a copy and must fail by
# its own error name.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

R="$TEST_REPO_ROOT"
H="$R/test/fixtures/orchestrator-core.py"
ORCH="$R/skills/role-contracts/ORCHESTRATOR.md"
TSV="$R/skills/role-contracts/orchestrator-rules.tsv"
SCEN="$R/test/behavior/orchestrator-scenarios.md"
HOOK="$R/hooks/agent-dispatch.py"

for f in "$TSV" "$HOOK"; do
  [ -r "$f" ] || { fail "S311 — ${f#"$R"/} is missing"; test_done; }
done
checks="$(python3 -I "$HOOK" --list-checks 2>/dev/null | tr '\n' ' ')"
[ -n "$checks" ] || fail "S311 — agent-dispatch.py --list-checks printed nothing"

run_check() { # orch tsv scen -> harness output; status in $st
  out="$(python3 -I "$H" check --orch "$1" --tsv "$2" --scen "$3" --repo "$R" --list-checks "$checks" 2>&1)"
  st=$?
}
run_check "$ORCH" "$TSV" "$SCEN"
[ "$st" = 0 ] || fail "S311/real — structure check failed:
$out"

# The part lists A41 fixes, from the inventory side.
p1="$(awk -F'\t' 'NR>1 && $4=="1"{print $1}' "$TSV" | sort -V | tr '\n' ' ')"
p2="$(awk -F'\t' 'NR>1 && $4=="2"{print $1}' "$TSV" | sort -V | tr '\n' ' ')"
[ "$p1" = "OR1 OR2 OR3 OR4 OR5 OR6 OR7 OR8 OR11 OR12 OR13 OR33 OR34 OR35 OR43 OR45 " ] \
  || fail "S311/part1 — inventory part 1 is '$p1'"
[ "$p2" = "OR9 OR10 OR14 OR15 OR16 OR17 OR18 OR19 OR20 OR21 OR22 OR23 OR24 OR25 OR26 OR27 OR28 OR29 OR30 OR31 OR32 OR36 OR37 OR38 OR39 OR40 OR41 OR42 OR44 " ] \
  || fail "S311/part2 — inventory part 2 is '$p2'"
grep -qxF '<!-- session-context: slot -->' "$ORCH" || fail "S311 — no marker line"
grep -E '^ *- .*<!-- session-context: slot -->' "$ORCH" >/dev/null && fail "S311 — the marker line is a list item"

# --- negative controls ----------------------------------------------------
neg() { # name expected-error orch tsv scen
  run_check "$3" "$4" "$5"
  if [ "$st" = 0 ]; then
    fail "S311/neg-$1 — the break passed"
  elif ! grep -q "^ERROR $2:" <<<"$out"; then
    fail "S311/neg-$1 — expected ERROR $2, got: $out"
  fi
}
d="$SANDBOX"
grep -v '^- OR20 ' "$ORCH" > "$d/o-removed.md"
neg id-removed id-missing "$d/o-removed.md" "$TSV" "$SCEN"

awk -v l="$(grep '^- OR9 ' "$ORCH")" '{print} /^## Dispatch$/{print ""; print l}' "$ORCH" > "$d/o-dup.md"
neg id-duplicated id-not-once "$d/o-dup.md" "$TSV" "$SCEN"

awk -F'\t' -v OFS='\t' '$1=="OR9"{$4="1"} {print}' "$TSV" > "$d/t-part.tsv"
neg part-changed wrong-part "$ORCH" "$d/t-part.tsv" "$SCEN"

sed 's/^- OR15 Review round brief/- OR15 See above. Review round brief/' "$ORCH" > "$d/o-above.md"
neg see-above above-below "$d/o-above.md" "$TSV" "$SCEN"

grep -v '^Part 1 of 2 (fundamentals) also applies' "$ORCH" > "$d/o-header.md"
neg header-removed part-header "$d/o-header.md" "$TSV" "$SCEN"

awk -F'\t' -v OFS='\t' '$1=="OR20"{$5=""} {print}' "$TSV" > "$d/t-cov.tsv"
neg judgment-uncovered judgment-no-ob "$ORCH" "$d/t-cov.tsv" "$SCEN"

sed 's/^### OB21 · OR20$/### OB21 · OR20, OR99/' "$SCEN" > "$d/s-or99.md"
neg ob-cites-or99 ob-unknown-id "$ORCH" "$TSV" "$d/s-or99.md"

awk -F'\t' -v OFS='\t' '$3=="hook:no-fork"{$3="hook:no-forks"} {print}' "$TSV" > "$d/t-hook.tsv"
neg hook-renamed hook-checks "$ORCH" "$d/t-hook.tsv" "$SCEN"

sed 's/^- OR11 \(.*\)Merge into `main` only after human confirms final head SHA; /- OR11 \1Merge into `main` after human confirms; /' "$ORCH" > "$d/o-or11.md"
neg or11-weakened or11-wording "$d/o-or11.md" "$TSV" "$SCEN"

sed 's/in OR5 order, //' "$ORCH" > "$d/o-xref.md"
neg xref-dropped xref-or36 "$d/o-xref.md" "$TSV" "$SCEN"

awk -F'\t' -v OFS='\t' '$1=="OR29"{$2="Dispatch tool takes no effort"} {print}' "$TSV" > "$d/t-text.tsv"
neg rule-text-in-tsv row-name "$ORCH" "$d/t-text.tsv" "$SCEN"

test_done
