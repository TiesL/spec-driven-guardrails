#!/usr/bin/env bash
# S197 — legacy collector input coverage retained unchanged until #429.
# Covers: F39
# #427 retires gate half; strict gate counterparts: S257/S259/S264/S266.

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
