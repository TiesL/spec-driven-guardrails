#!/usr/bin/env bash
# S199 — an unclosed quote in one comment never changes how a well-formed
# marker in ANOTHER comment is read.
# Covers: F39
#
# Issue #392, round 4 of the PR #397 review (medium finding) and the human
# decision "contain a malformed marker to its own comment". Callers join the
# comments before parsing. A marker whose quote is left open in comment N used
# to run into comment N+1: the first quote of N+1 closed N's value, and when
# that first quoted value started with a space or `-->` the glued-text check
# did not fire, so N read as a well-formed marker and N+1's Review marker was
# never seen: the gate skipped the floor check silently and the collector said
# not-evidenced. Required: the well-formed marker in the other comment is found
# with its own values; the malformed marker is a visible finding or ignored,
# never wins. Seam: the real callers only (model-record-gate.sh,
# compliance-evidence.sh gate 2, role-label-staleness.sh) against fake gh.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"
# shellcheck source=../fixtures/review-floor-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-floor-helpers.sh"

command -v jq >/dev/null 2>&1 || { fail "S199 — jq is needed by the fake gh"; test_done; }
sandbox_create
trap sandbox_destroy EXIT
rf_gate_setup
rf_out=""
rf_status=0 # set by rf_gate
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=../compliance-evidence-fixture.sh
. "$(dirname "${BASH_SOURCE[0]}")/../compliance-evidence-fixture.sh"
script="$TEST_REPO_ROOT/compliance-evidence.sh"
export CE_ID=S199
ce_out=""
# shellcheck source=../fixtures/ce-review-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/ce-review-helpers.sh"

NL=$'\n'
# an unclosed quote: the marker opens a value and never closes it
UNC_REVIEW='<!-- model-record: stage=Review model="Sonnet effort=high'
UNC_IMPL='<!-- model-record: stage=Implementation model="Sonnet effort=high'
UNC_TEST='<!-- model-record: stage=Test model="Sonnet effort=high'
# well-formed markers whose FIRST quoted value starts with a space / with -->
# (the case that slipped through) or with a letter (control: always caught)
rev_sp='<!-- model-record: stage=Review floor-basis=" same model --> lower effort" model="Sonnet" effort="low" -->'
rev_sp_plain='<!-- model-record: stage=Review floor-basis=" same model, lower effort" model="Sonnet" effort="low" -->'
rev_ar='<!-- model-record: stage=Review floor-basis="--> same model, lower effort" model="Sonnet" effort="low" -->'
rev_ab='<!-- model-record: stage=Review floor-basis="same model, lower effort" model="Sonnet" effort="low" -->'
rev_sp_model='<!-- model-record: stage=Review model=" Sonnet" effort="low" floor-basis="ok" -->'
impl_sp='<!-- model-record: stage=Implementation note=" first --> value starts with a space" model="Sonnet" effort="high" -->'
impl_good="$(marker Implementation Sonnet high)"
rev_good_low="$(marker Review Sonnet low 'floor-basis="ok"')"

expect_lower() { # label
  [ "$rf_status" -eq 0 ] || fail "S199 gate/$1 — exit $rf_status"
  grep -qiE 'lower effort' <<<"$rf_out" \
    || fail "S199 gate/$1 — the well-formed marker in the other comment must be found with its own values (same model, Review low vs Implementation high: lower-effort finding), got: '$rf_out'"
}
gate_case() { # label, comment bodies...
  local label="$1"
  shift
  rf_data "$@"
  rf_gate
  expect_lower "$label"
}

# --- the unclosed quote is in comment N, the well-formed marker in N+1 ------
for pair in "sp|$rev_sp" "arrow|$rev_ar" "sp-plain|$rev_sp_plain" "letter|$rev_ab" "model-space|$rev_sp_model"; do
  v="${pair%%|*}"; r="${pair#*|}"
  gate_case "unclosed Review, then Review ($v)" "$impl_good" "$UNC_REVIEW" "$r"
  gate_case "unclosed Implementation, then Review ($v)" "$impl_good" "$UNC_IMPL" "$r"
  gate_case "unclosed Test, then Review ($v)" "$impl_good" "$UNC_TEST" "$r"
  gate_case "unclosed text with prose around it ($v)" "$impl_good" "Draft, do not use: $UNC_REVIEW and so on" "$r"
done
# N+1 is the IMPLEMENTATION marker (the Review marker came first)
gate_case "unclosed, then Implementation (space)" "$rev_good_low" "$UNC_REVIEW" "$impl_sp"
gate_case "unclosed Implementation, then Implementation (space)" "$rev_good_low" "$UNC_IMPL" "$impl_sp"
# several unclosed comments in a row
gate_case "three unclosed comments in a row, then a good Review" "$impl_good" "$UNC_REVIEW" "$UNC_IMPL" "$UNC_TEST" "$rev_sp"
gate_case "unclosed comments on both sides of the good ones" "$UNC_IMPL" "$impl_good" "$UNC_REVIEW" "$rev_ar"
# the unclosed quote is in the LAST comment: it must neither win nor hide
gate_case "unclosed Review in the last comment" "$impl_good" "$rev_sp" "$UNC_REVIEW"
if grep -q 'no record found for stage Review' <<<"$rf_out"; then
  fail "S199 gate/last comment — the good Review marker was lost: $rf_out"
fi
gate_case "unclosed Implementation in the last comment" "$impl_good" "$rev_sp" "$UNC_IMPL"
# an unclosed quote inside a code fence of comment N (the gate reads fences as text)
gate_case "unclosed quote inside a code fence" "$impl_good" "Example:${NL}\`\`\`${NL}$UNC_REVIEW${NL}\`\`\`" "$rev_sp"
# the open quote at the very end of the comment, closing text at the start of the next
gate_case "N ends with an open value, N+1 starts with the closing text" "$impl_good" "$UNC_REVIEW" "$rev_sp"

# the malformed marker itself: visible or ignored, never a verdict of its own.
# Here it would be the latest Review marker and (if read) say effort=high:
rf_data "$impl_good" "$rev_good_low" "$UNC_REVIEW"
rf_gate
grep -qiE 'lower effort' <<<"$rf_out" || fail "S199 gate — a malformed LATER marker must not win over the earlier well-formed round, got: '$rf_out'"

# ---------------------------------------------------------------------------
# compliance-evidence.sh gate 2
# ---------------------------------------------------------------------------
impl_c="$(mk Implementation claude-sonnet-5 medium)"
c_unc_review='<!-- model-record: stage=Review model="claude-sonnet-5 effort=high'
c_unc_impl='<!-- model-record: stage=Implementation model="claude-sonnet-5 effort=high'
c_rev_sp='<!-- model-record: stage=Review floor-basis=" same model --> lower effort" model="claude-sonnet-5" effort="low" -->'
c_rev_ar='<!-- model-record: stage=Review floor-basis="--> same model, lower effort" model="claude-sonnet-5" effort="low" -->'
c_impl_sp='<!-- model-record: stage=Implementation note=" starts --> with a space" model="claude-sonnet-5" effort="medium" -->'
c_rev_low="$(mk Review claude-sonnet-5 low 'floor-basis="ok"')"

gate2_lower() { # label ; uses ce_out
  [ "$(row_status "$ce_out" 2)" = "not-evidenced" ] || fail "S199 gate2/$1 — gate 2 must see the well-formed Review marker (low) and say not-evidenced because of it, got '$(row_status "$ce_out" 2)' ($(row_evidence "$ce_out" 2))"
  case "$(row_evidence "$ce_out" 2)" in
    *low*medium* | *medium*low*) : ;;
    *) fail "S199 gate2/$1 — the verdict must come from the marker's own efforts (low, medium), got: $(row_evidence "$ce_out" 2)" ;;
  esac
}
for pair in "sp|$c_rev_sp" "arrow|$c_rev_ar"; do
  v="${pair%%|*}"; r="${pair#*|}"
  ce "Closes #265" "$impl_c
$c_unc_review
$r" ""
  assert_table_shape "S199 gate2 unclosed Review, then Review ($v)" "$ce_out"
  gate2_lower "unclosed Review, then Review ($v)"
  ce "Closes #265" "$impl_c
$c_unc_impl
$r" ""
  assert_table_shape "S199 gate2 unclosed Implementation, then Review ($v)" "$ce_out"
  gate2_lower "unclosed Implementation, then Review ($v)"
done
ce "Closes #265" "$c_rev_low
$c_unc_review
$c_impl_sp" ""
gate2_lower "unclosed, then Implementation (space)"
ce "Closes #265" "$impl_c
$c_unc_review
$c_unc_impl
$c_rev_sp" ""
gate2_lower "two unclosed comments in a row"
ce "Closes #265" "$impl_c
$c_rev_sp
$c_unc_review" ""
gate2_lower "unclosed Review in the last comment"
# the unclosed marker on the closing issue (comments of #265), the good one on the PR
ce "Closes #265" "$impl_c
$c_rev_sp" "$c_unc_review"
gate2_lower "unclosed on the closing issue, good one on the PR"
# the good marker on the closing issue, the unclosed one in the PR comments before it
ce "Closes #265" "$impl_c
$c_unc_review" "$c_rev_sp"
[ "$(row_status "$ce_out" 2)" != "evidenced" ] || fail "S199 gate2 — an unclosed PR marker must not turn the verdict into evidenced, got: $(row_evidence "$ce_out" 2)"

# ---------------------------------------------------------------------------
# role-label-staleness.sh (joins comments the same way)
# ---------------------------------------------------------------------------
# shellcheck source=../fixtures/role-label-fake-gh.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/role-label-fake-gh.sh"
rl_verdict() { # label-on-issue marker...: one PR comment per marker argument
  local label="$1" arms="" m bin
  shift
  for m in "$@"; do arms="$arms
  printf 'TEXT\\t%s\\n' '$m'"; done
  run_build_fake_gh > "$FAKEGH_OUT" <<GHEOF
__CALL_ISSUE__)
  printf 'LABEL\t$label\n'
  exit 0 ;;
__CALL_ISSUE_COMMENTS__)
  exit 0 ;;
__CALL_REPO_IDENTITY__)
  printf 'owner/repo\n'
  exit 0 ;;
__CALL_TIMELINE__)
  printf 'PR\t501\n'
  exit 0 ;;
__CALL_PR501_TITLEBODY__)
  printf 'TITLE\t\nBODY\tCloses #400\n'
  exit 0 ;;
__CALL_PR501_COMMENTS__)$arms
  exit 0 ;;
__CALL_PR501_REVIEWS__)
  exit 0 ;;
GHEOF
  bin="$(cat "$FAKEGH_OUT")"
  rl="$(PATH="$bin:$PATH" "$TEST_REPO_ROOT/role-label-staleness.sh" 400 2>/dev/null)"
}
# an unclosed Discovery marker (an early stage, so a swallowed Review marker
# would leave the label looking in sync), then a well-formed Review marker
for r in "$rev_sp" "$rev_ar"; do
  rl_verdict role:architect '<!-- model-record: stage=Discovery model="Sonnet effort=low' "$r"
  case "$rl" in
    *" — stale "* | *" — indeterminate "*) : ;;
    *) fail "S199 role-label — the Review marker in the next comment must not be swallowed (stale, or indeterminate for the malformed one), got: $rl" ;;
  esac
done

test_done
