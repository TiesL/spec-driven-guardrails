#!/usr/bin/env bash
# S202 — unreadable candidates are diagnosed once, never presence; collector legacy controls retained.
# Covers: F40
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
. "$TEST_REPO_ROOT/test/fixtures/gate-v2-helpers.sh"
. "$TEST_REPO_ROOT/test/compliance-evidence-fixture.sh"
script="$TEST_REPO_ROOT/compliance-evidence.sh"
export CE_ID=S202
. "$TEST_REPO_ROOT/test/fixtures/ce-review-helpers.sh"
M=claude-haiku-4-5
good() { # stage -> a fully well-formed quoted marker
  if [ "$1" = Review ]; then
    printf '<!-- model-record: stage=Review model="%s" effort="high" floor-basis="same model, higher effort" -->' "$M"
  else
    printf '<!-- model-record: stage=%s model="%s" effort="medium" -->' "$1" "$M"
  fi
}
bad() { # stage form -> a marker with one unreadable field (Review keeps its floor-basis)
  local s="$1" form="$2" fb=""
  [ "$s" = Review ] && fb=' floor-basis="why"'
  case "$form" in
    unquoted-model) printf '<!-- model-record: stage=%s model=%s effort="low"%s -->' "$s" "$M" "$fb" ;;
    unquoted-effort) printf '<!-- model-record: stage=%s model="%s" effort=low%s -->' "$s" "$M" "$fb" ;;
    empty-model) printf '<!-- model-record: stage=%s model="" effort="low"%s -->' "$s" "$fb" ;;
    empty-effort) printf '<!-- model-record: stage=%s model="%s" effort=""%s -->' "$s" "$M" "$fb" ;;
    missing-model) printf '<!-- model-record: stage=%s effort="low"%s -->' "$s" "$fb" ;;
    missing-effort) printf '<!-- model-record: stage=%s model="%s"%s -->' "$s" "$M" "$fb" ;;
    unquoted-both) printf '<!-- model-record: stage=%s model=%s effort=low%s -->' "$s" "$M" "$fb" ;;
  esac
}


for stage in Discovery Planning Test Implementation Review; do
 for shape in unquoted-model empty-model missing-model unquoted-effort unquoted-both; do
  v2_base; v2_comments comments-239.json; v2_comments reviews-246.json
  v2_times comments-246.json "$late" "$(bad "$stage" "$shape")" "$early" "$(good "$stage")"
  v2_run; count 'near-miss' 1; has "latest stage=$stage record is unreadable"; absent "no record found for stage $stage"
 done
 for shape in empty-effort missing-effort; do
  v2_base; v2_comments comments-246.json "$(good Planning)" "$(good Test)" "$(good Implementation)" "$(bad "$stage" "$shape")"; v2_run; clean
 done
done
# ---- the collector says indeterminate for the same input (control) ----------------
mkr() { # stage form-or-good
  if [ "$2" = good ]; then good "$1"; else bad "$1" "$2"; fi
}
ce_case() { # label, planning, implementation, expected row-1, expected row-2
  ce "Closes #265" "$2
$(good Test)
$3
$(good Review)" "$(good Discovery)"
  assert_table_shape "S202 collector $1" "$ce_out"
  [ "$(row_status "$ce_out" 1)" = "$4" ] || fail "S202 collector/$1 — gate 1 should be $4, got '$(row_status "$ce_out" 1)' ($(row_evidence "$ce_out" 1))"
  [ "$(row_status "$ce_out" 2)" = "$5" ] || fail "S202 collector/$1 — gate 2 should be $5, got '$(row_status "$ce_out" 2)' ($(row_evidence "$ce_out" 2))"
}
ce_case "well-formed (control)" "$(good Planning)" "$(good Implementation)" evidenced evidenced
ce_case "unquoted Planning model" "$(bad Planning unquoted-model)" "$(good Implementation)" indeterminate evidenced
ce_case "unquoted Implementation model" "$(good Planning)" "$(bad Implementation unquoted-model)" indeterminate indeterminate

test_done
