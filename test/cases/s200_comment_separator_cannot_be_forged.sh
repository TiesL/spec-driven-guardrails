#!/usr/bin/env bash
# S200 — the comment-boundary byte (U+001E) in a comment body cannot forge or
# remove a comment boundary.
# Covers: F39
#
# Issue #392, round 4 of the PR #397 review. Callers frame comments with U+001E
# so the parser can contain a malformed marker to its own comment (S199) and
# the role-play check can tell one comment from the next (#371). A body that
# contains the byte itself must not change either. Safe outcome asserted
# (A24: a malformed marker never reaches another comment, and one comment's
# markers are not split into several): the byte inside a body is removed or
# ignored, so (1) a well-formed marker in the NEXT comment is still found with
# its own values, whatever the byte does inside this comment, and (2) one
# comment carrying five stage markers separated by the byte is still ONE
# comment, so the role-played finding is still raised in an opted-in project.
# Seam: model-record-gate.sh and compliance-evidence.sh against fake gh.
#
# Issue #424: "found with its own values" is told apart without effort. Gate:
# the well-formed Review marker has no floor-basis (a floor-basis finding
# appears iff it was read; its first quoted value is a `note`). Gate 2: the
# unclosed marker claims another model than Implementation's, so `evidenced`
# appears iff the well-formed marker was read.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"
# shellcheck source=../fixtures/review-floor-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-floor-helpers.sh"

command -v jq >/dev/null 2>&1 || { fail "S200 — jq is needed by the fake gh"; test_done; }
sandbox_create
trap sandbox_destroy EXIT
rf_gate_setup
rf_out=""
rf_status=0 # set by rf_gate
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=../compliance-evidence-fixture.sh
. "$(dirname "${BASH_SOURCE[0]}")/../compliance-evidence-fixture.sh"
script="$TEST_REPO_ROOT/compliance-evidence.sh"
export CE_ID=S200
ce_out=""
# shellcheck source=../fixtures/ce-review-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/ce-review-helpers.sh"

RS=$'\036'
NL=$'\n'
impl_good="$(marker Implementation Sonnet high)"
rev_sp='<!-- model-record: stage=Review note=" same model --> lower effort" model="Sonnet" effort="low" -->'
UNC='<!-- model-record: stage=Review model="Sonnet effort=high'

expect_lower() {
  [ "$rf_status" -eq 0 ] || fail "S200 gate/$1 — exit $rf_status"
  [ "$(grep -i 'floor-basis' <<<"$rf_out" | grep -vi 'malformed' | grep -c .)" -eq 1 ] \
    || fail "S200 gate/$1 — the well-formed marker in the next comment (no floor-basis) must be found with its own values: the floor-basis finding, got: '$rf_out'"
  ! grep -q 'no record found' <<<"$rf_out" || fail "S200 gate/$1 — a well-formed marker was lost ('no record found'), got: '$rf_out'"
}
case_run() { # label bodies...
  local label="$1"
  shift
  rf_data "$@"
  rf_gate
  expect_lower "$label"
}

# (1) the byte inside the comment that holds the unclosed quote
case_run "separator right after the open quote" "$impl_good" "${UNC}${RS}" "$rev_sp"
case_run "separator inside, closing text after it" "$impl_good" "${UNC}${RS} x\" -->" "$rev_sp"
case_run "separator at the start of the comment" "$impl_good" "${RS}${UNC}" "$rev_sp"
case_run "several separators in a row" "$impl_good" "${UNC}${RS}${RS}${RS}" "$rev_sp"
# ...and inside the good comment itself, before its marker
case_run "separator before the good marker" "$impl_good" "$UNC" "${RS}${rev_sp}"
case_run "separator after the good marker" "$impl_good" "$UNC" "${rev_sp}${RS}"
# ...and in the Implementation comment
case_run "separator in the Implementation comment" "x${RS}y${NL}$impl_good" "$UNC" "$rev_sp"

# a separator in the middle of a well-formed marker must not corrupt the next one
rf_data "$impl_good" "<!-- model-record: stage=Review model=\"Sonnet\"${RS} effort=\"low\" -->" "$(marker Review Sonnet high 'floor-basis="ok"')"
rf_gate
[ "$rf_status" -eq 0 ] || fail "S200 gate — exit $rf_status with a separator inside a marker"
# the latest round (with a floor-basis) wins; whatever happens to the split marker (it has none), no crash and no floor-basis claim from it
grep -qi 'floor-basis' <<<"$rf_out" && fail "S200 gate — a later round must win over an earlier marker that held a separator, got: '$rf_out'"

# (2) role-play: one comment carrying all five markers separated by the byte is ONE comment
id="process-multi-agent-roles"
optin="$(fresh_project optin)"
write_adoption "$optin/WORKFLOW-ADOPTION.md" "$id" yes
rf_data
five="$(mr Discovery)${RS}$(mr Planning)${RS}$(mr Test)${RS}$(mr Implementation)${RS}$(mr Review)"
json_comments "$FAKE_GH_DATA/comments-246.json" "$five"
json_comments "$FAKE_GH_DATA/comments-239.json"
rf_gate "$optin"
grep -q '^role-played: ' <<<"$rf_out" \
  || fail "S200 gate — five stage markers in ONE comment, separated by the boundary byte, must still be reported as role-played (a body cannot forge boundaries), got: '$rf_out'"
# control: five genuinely separate comments are not role-played
rf_data
json_comments "$FAKE_GH_DATA/comments-246.json" "$(mr Planning)" "$(mr Test)" "$(mr Implementation)" "$(mr Review)"
rf_gate "$optin"
grep -q '^role-played: ' <<<"$rf_out" && fail "S200 gate control — a dispatched run (one comment per stage) must not be role-played, got: '$rf_out'"

# ---------------------------------------------------------------------------
# compliance-evidence.sh: the same byte in a PR comment
# ---------------------------------------------------------------------------
impl_c="$(mk Implementation claude-sonnet-5 medium)"
c_unc='<!-- model-record: stage=Review model="claude-opus-5 effort=high'
c_rev_sp='<!-- model-record: stage=Review note=" same model --> lower effort" model="claude-sonnet-5" effort="low" -->'
for variant in "${c_unc}${RS}" "${RS}${c_unc}" "${c_unc}${RS} x\" -->"; do
  ce "Closes #265" "$impl_c
$variant
$c_rev_sp" ""
  assert_table_shape "S200 gate2 separator in an unclosed comment" "$ce_out"
  [ "$(row_status "$ce_out" 2)" = "evidenced" ] || fail "S200 gate2 — the separator byte in comment N must not change how comment N+1 is read, got '$(row_status "$ce_out" 2)' ($(row_evidence "$ce_out" 2))"
done

test_done
