#!/usr/bin/env bash
# test/fixtures/orchestrator-core-helpers.sh — bash wrappers around
# test/fixtures/orchestrator-core.py for the scenarios #499 AC14 amended
# from phrase checks to "the ID exists, has its tier and sits in its part".
# Source after test/lib.sh. Not a test case.
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

OC_PY="$TEST_REPO_ROOT/test/fixtures/orchestrator-core.py"
OC_ORCH="${OC_ORCH:-$TEST_REPO_ROOT/skills/role-contracts/ORCHESTRATOR.md}"
OC_TSV="${OC_TSV:-$TEST_REPO_ROOT/skills/role-contracts/orchestrator-rules.tsv}"

# oc_item <ID> [orch] : the item text (line plus continuation lines).
oc_item() { python3 -I "$OC_PY" item --orch "${2:-$OC_ORCH}" "$1"; }
# oc_line <ID> [orch] : the item's first physical line.
oc_line() { python3 -I "$OC_PY" line --orch "${2:-$OC_ORCH}" "$1"; }

# oc_rule <label> <ID> <tier> <part> [depth] : fails unless the ID starts
# exactly one item, in that part (and depth, 0 item / 1 sub-item), and its
# inventory row has that tier and part.
oc_rule() {
  local label="$1" id="$2" tier="$3" part="$4" depth="${5:-}" n where row
  n="$(python3 -I "$OC_PY" items --orch "$OC_ORCH" | awk -F'\t' -v i="$id" '$1==i' | wc -l | tr -d ' ')"
  if [ "$n" != 1 ]; then
    fail "$label — $id starts $n items in ORCHESTRATOR.md, expected exactly 1"
    return
  fi
  where="$(python3 -I "$OC_PY" where --orch "$OC_ORCH" "$id")"
  [ "${where% *}" = "$part" ] || fail "$label — $id sits in part ${where% *}, expected part $part"
  if [ -n "$depth" ] && [ "${where#* }" != "$depth" ]; then
    fail "$label — $id is at depth ${where#* }, expected $depth"
  fi
  row="$(python3 -I "$OC_PY" row --tsv "$OC_TSV" "$id")" || { fail "$label — $id has no inventory row"; return; }
  [ "$(cut -f1 <<<"$row")" = "$tier" ] || fail "$label — $id tier is '$(cut -f1 <<<"$row")', expected '$tier'"
  [ "$(cut -f2 <<<"$row")" = "$part" ] || fail "$label — $id inventory part is '$(cut -f2 <<<"$row")', expected $part"
}
