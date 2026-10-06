#!/usr/bin/env bash
# S197 — a malformed marker (an odd number of quotes, no closing -->, a nested
# <!--) never swallows a later well-formed marker.
# Covers: F39
#
# Issue #392, round 3 of the PR #397 review (medium finding). The shared
# parser scans the text of ALL comments joined, so an unbalanced quote or a
# missing `-->` used to run on into later text, up to any later `-->` with an
# even quote count, possibly in a LATER comment, and the stale attributes
# won. The input is forbidden, but the failure was silent and hid the latest
# review round. Required: the later well-formed marker is found with its own
# values, in the same comment and in a later one; the malformed marker yields
# a finding or is ignored, but never wins. Seam: the gate's stdout and gate 2's
# row, against fake gh.
#
# Issue #424: the floor is on the model alone, so "found with its own values"
# is told apart differently. Gate: the well-formed marker lacks a floor-basis
# and every malformed one carries one, so a floor-basis finding appears iff
# the well-formed marker was the one read. Gate 2: the well-formed marker is
# on Implementation's model and every malformed one claims another model, so
# `evidenced` appears iff the well-formed marker was the one read.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"
# shellcheck source=../fixtures/review-floor-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-floor-helpers.sh"

command -v jq >/dev/null 2>&1 || { fail "S197 — jq is needed by the fake gh"; test_done; }
sandbox_create
trap sandbox_destroy EXIT
rf_gate_setup
rf_out=""
rf_status=0 # set by rf_gate
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=../compliance-evidence-fixture.sh
. "$(dirname "${BASH_SOURCE[0]}")/../compliance-evidence-fixture.sh"
script="$TEST_REPO_ROOT/compliance-evidence.sh"
export CE_ID=S197
ce_out=""
# shellcheck source=../fixtures/ce-review-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/ce-review-helpers.sh"

NL=$'\n'
impl_g="$(marker Implementation Sonnet high)"
good_low='<!-- model-record: stage=Review model="Sonnet" effort="low" -->'
# malformed Review markers (all carry a floor-basis, the well-formed one above
# has none, so a parser that lets them win gives a different answer)
odd='<!-- model-record: stage=Review model="Sonnet" effort="high" floor-basis="5" wide" -->'
unterminated='<!-- model-record: stage=Review model="Sonnet" effort="high" floor-basis="ok"'
unterminated_other_model='<!-- model-record: stage=Review model="Opus" effort="high" floor-basis="ok"'
nested='<!-- model-record: stage=Review model="Sonnet" effort="high" floor-basis="outer" <!-- model-record: stage=Review model="Sonnet" effort="low" -->'
later_text='He said "hello" and left <!-- an unrelated note -->'

# floor_lines: findings that name floor-basis and are not a malformed-marker report
floor_lines() { grep -i 'floor-basis' <<<"$rf_out" | grep -vi 'malformed' | grep -c .; }
lower_finding() { # label ; uses rf_out
  [ "$(floor_lines)" -eq 1 ] \
    || fail "S197 gate/$1 — the later well-formed Review marker (no floor-basis) must be found with its own values and give the floor-basis finding, got: '$rf_out'"
}
gate_run() { # label bodies...
  local label="$1"
  shift
  rf_data "$@"
  rf_gate
  [ "$rf_status" -eq 0 ] || fail "S197 gate/$label — exit $rf_status"
}

# --- same comment, malformed first, well-formed after -----------------------
gate_run "odd quotes, then a good marker in the same comment" "$impl_g" "$odd$NL$good_low"
lower_finding "odd quotes, same comment"
gate_run "odd quotes, same line" "$impl_g" "$odd $good_low"
lower_finding "odd quotes, same line"
gate_run "unterminated, then a good marker" "$impl_g" "see $unterminated${NL}text continues${NL}$good_low"
lower_finding "unterminated, same comment"
gate_run "unterminated with another model, then a good marker" "$impl_g" "$unterminated_other_model$NL$good_low"
lower_finding "unterminated (other model), same comment: the real marker's model counts"
gate_run "nested opener" "$impl_g" "$nested"
lower_finding "nested <!--"

# --- the later well-formed marker is in a LATER comment ---------------------
gate_run "odd quotes in one comment, good marker in a later one" "$impl_g" "$odd" "$good_low"
lower_finding "odd quotes, later comment"
gate_run "unterminated in one comment, good marker in a later one" "$impl_g" "$unterminated" "$good_low"
lower_finding "unterminated, later comment"
# ...and the swallowing text is in a comment AFTER the good marker
gate_run "good marker, then odd quotes and a later quote-and-arrow text" "$impl_g" "$odd" "$good_low" "$later_text"
lower_finding "odd quotes, then more text with a quote and -->"
gate_run "odd quotes THEN well-formed round 2 THEN text with a quote and -->" "$impl_g" "$(marker Review Sonnet high 'floor-basis="5" wide"')" "$good_low" "$later_text"
lower_finding "round 1 odd quotes, round 2 good, trailing text"

# the reviewer's reproduction: one stray quote later restores the parity, so
# the malformed marker used to extend over the good marker up to that `-->`
rebalance='a 5" pipe -->'
gate_run "odd quotes, good round 2, then a stray quote and -->" "$impl_g" "$odd" "$good_low" "$rebalance"
lower_finding "odd quotes swallowing round 2 up to a rebalancing stray quote"
gate_run "odd quotes and good round 2 in one comment, then a stray quote and -->" "$impl_g" "$odd $good_low $rebalance"
lower_finding "same, one comment"

# --- a malformed marker AFTER a good one never wins -------------------------
good_high='<!-- model-record: stage=Review model="Sonnet" effort="high" floor-basis="ok" -->'
bad_low='<!-- model-record: stage=Review model="Sonnet" effort="low" note="a"b" -->'
gate_run "good (with floor-basis), then a malformed one without" "$impl_g" "$good_high" "$bad_low"
if [ "$(floor_lines)" -ne 0 ]; then
  fail "S197 gate/malformed later marker — a malformed marker must never win (finding or ignore, but no verdict taken from its attributes: it has no floor-basis, the good one does), got: '$rf_out'"
fi
bad_unterminated_low='<!-- model-record: stage=Review model="Sonnet" effort="low"'
gate_run "good high, then an unterminated low" "$impl_g" "$good_high" "$bad_unterminated_low"
if [ "$(floor_lines)" -ne 0 ]; then
  fail "S197 gate/unterminated later marker — an unterminated marker must never win, got: '$rf_out'"
fi

# --- a well-formed marker is unaffected --------------------------------------
gate_run "control: only well-formed markers" "$impl_g" "$good_low"
lower_finding "control"

# ---------------------------------------------------------------------------
# gate 2
# ---------------------------------------------------------------------------
impl_c="$(mk Implementation claude-sonnet-5 medium)"
c_good_low='<!-- model-record: stage=Review model="claude-sonnet-5" effort="low" floor-basis="ok" -->'
# every malformed marker claims ANOTHER model than Implementation's
c_odd='<!-- model-record: stage=Review model="claude-opus-5" effort="high" floor-basis="5" wide" -->'
c_unt='<!-- model-record: stage=Review model="claude-opus-5" effort="high"'
c_unt_other='<!-- model-record: stage=Review model="claude-opus-5" effort="high"'
c_nested='<!-- model-record: stage=Review model="claude-opus-5" effort="high" <!-- model-record: stage=Review model="claude-sonnet-5" effort="low" floor-basis="ok" -->'
c_later='He said "hello" and left <!-- an unrelated note -->'

lower_row() { # label  (after check ... evidenced)
  case "$(row_evidence "$ce_out" 2)" in
    *claude-opus-5*) fail "S197 gate2/$1 — verdict must come from the well-formed marker's model, not a malformed marker's, got: $(row_evidence "$ce_out" 2)" ;;
    *claude-sonnet-5*) : ;;
    *) fail "S197 gate2/$1 — verdict must name the well-formed marker's model (claude-sonnet-5), got: $(row_evidence "$ce_out" 2)" ;;
  esac
}
check "gate2 odd quotes, then a good marker (same comment)" evidenced "$impl_c
$c_odd $c_good_low"
lower_row "odd quotes, same comment"
check "gate2 odd quotes, good marker in a later comment" evidenced "$impl_c
$c_odd
$c_good_low"
lower_row "odd quotes, later comment"
check "gate2 unterminated, then a good marker" evidenced "$impl_c
$c_unt text continues $c_good_low"
lower_row "unterminated"
check "gate2 unterminated with another model, good marker in a later comment" evidenced "$impl_c
$c_unt_other
$c_good_low"
lower_row "unterminated (other model)"
check "gate2 nested opener" evidenced "$impl_c
$c_nested"
lower_row "nested"
check "gate2 odd quotes, good marker, later quote-and-arrow text" evidenced "$impl_c
$c_odd
$c_good_low
$c_later"
lower_row "trailing text"
check "gate2 odd quotes, good round 2, then a stray quote and -->" evidenced "$impl_c
$c_odd
$c_good_low
a 5\" pipe -->"
lower_row "odd quotes swallowing round 2 up to a rebalancing stray quote"
# a malformed marker after a good one does not win
check "gate2 good marker, then a malformed one on another model" evidenced "$impl_c
$(mk Review claude-sonnet-5 medium 'floor-basis="ok"')
<!-- model-record: stage=Review model=\"claude-opus-5\" effort=\"low\" floor-basis=\"a\"b\" -->"

test_done
