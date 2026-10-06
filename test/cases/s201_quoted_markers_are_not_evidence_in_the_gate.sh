#!/usr/bin/env bash
# S201 — model-record-gate.sh does not count marker-shaped text that is
# quoted (a fenced block, an inline code span, a blockquote), the same as
# compliance-evidence.sh and role-label-staleness.sh.
# Covers: F39
#
# Issue #392, round 5 of the PR #397 review (medium finding). The gate read
# raw bodies while the other two scripts first drop quoted text (live_text), so
# a LATER comment that quotes an example Implementation marker hid a real
# lower-effort Review: the gate took the example as the latest Implementation
# marker, found no lower effort, and stayed silent (live on #397 itself).
# Required: quoted markers (any stage) never count; the same inputs give the
# same outcome through all three scripts where they apply (S151/S153: quoted
# marker-shaped text is not evidence). An INDENTED code block is not stripped
# by live_text in any of the scripts (accepted fail-open, PRD debt, S151 Q18),
# so there the three scripts must merely AGREE. Out of scope (issue #400): five
# markers all inside one fence and the role-played check.
# Seam: the real scripts against fake gh.
#
# Issue #424: the old proof ("the real lower-effort Review still gives the
# lower-effort finding") is gone with the effort finding. Gate: the real
# Review marker has no floor-basis, so exactly ONE finding (the floor-basis
# one) appears iff only the real markers counted; a quoted Implementation
# example with an unquoted model would add a second finding, a quoted Review
# example with a floor-basis would remove the first. Gate 2: the quoted
# examples claim another model, so `evidenced` appears iff only the real
# markers counted.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"
# shellcheck source=../fixtures/review-floor-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-floor-helpers.sh"

command -v jq >/dev/null 2>&1 || { fail "S201 — jq is needed by the fake gh"; test_done; }
sandbox_create
trap sandbox_destroy EXIT
rf_gate_setup
rf_out=""
rf_status=0 # set by rf_gate
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=../compliance-evidence-fixture.sh
. "$(dirname "${BASH_SOURCE[0]}")/../compliance-evidence-fixture.sh"
script="$TEST_REPO_ROOT/compliance-evidence.sh"
export CE_ID=S201
ce_out=""
# shellcheck source=../fixtures/ce-review-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/ce-review-helpers.sh"

NL=$'\n'
BT='`'
impl_real="$(marker Implementation Sonnet high)"
rev_real_low="$(marker Review Sonnet low)"
ex_impl_low='<!-- model-record: stage=Implementation model=Sonnet effort="low" -->'
ex_rev_high='<!-- model-record: stage=Review model="Sonnet" effort="high" floor-basis="example" -->'

# the four ways to quote an example marker (indented: handled separately)
quote_fence() { printf 'Example of the format:%s```%s%s%s```' "$NL" "$NL" "$1" "$NL"; }
quote_tilde() { printf 'Example:%s~~~%s%s%s~~~' "$NL" "$NL" "$1" "$NL"; }
quote_span() { printf 'The format is %s%s%s, as in the skill.' "$BT" "$1" "$BT"; }
quote_block() { printf '> Reviewer wrote:%s> %s' "$NL" "$1"; }

# exactly the one floor-basis finding of the real Review marker, nothing more
lower() { [ "$(rf_findings)" -eq 1 ] && grep -qi 'floor-basis' <<<"$rf_out"; }

# ---- (1) a later comment quotes an Implementation example (effort=low) -------
for form in fence tilde span block; do
  q="$("quote_$form" "$ex_impl_low")"
  rf_data "$impl_real" "$rev_real_low" "$q"
  rf_gate
  [ "$rf_status" -eq 0 ] || fail "S201 gate/$form — exit $rf_status"
  lower || fail "S201 gate/$form — a quoted ($form) example Implementation marker must not count: the real Review (no floor-basis) still gives exactly the floor-basis finding, got: '$rf_out'"
done

# the quoted example in an EARLIER comment, and in the same comment as the real marker
q="$(quote_fence "$ex_impl_low")"
rf_data "$q" "$impl_real" "$rev_real_low"
rf_gate
lower || fail "S201 gate/earlier — quoted example in an earlier comment, got: '$rf_out'"
rf_data "$impl_real" "$q${NL}${NL}$rev_real_low"
rf_gate
lower || fail "S201 gate/same comment — quoted example before the real marker in the same comment, got: '$rf_out'"
# a quoted marker with the open-quote runaway shape is quoted too
rf_data "$impl_real" "$rev_real_low" "$(quote_fence '<!-- model-record: stage=Implementation model="Sonnet effort=low')"
rf_gate
lower || fail "S201 gate/fenced unclosed — got: '$rf_out'"

# ---- (2) quoted Review examples are not counted either ----------------------
for form in fence span block; do
  q="$("quote_$form" "$ex_rev_high")"
  rf_data "$impl_real" "$rev_real_low" "$q"
  rf_gate
  lower || fail "S201 gate/review-$form — a quoted ($form) example Review marker (effort=high) must not replace the real latest Review (low), got: '$rf_out'"
done
# ...and a quoted example is not a real marker: with ONLY a quoted Review
# marker the Review stage is missing (the collector says not-evidenced, S151)
rf_data "$impl_real" "$(quote_fence "$ex_rev_high")"
rf_gate
grep -q 'no record found for stage Review' <<<"$rf_out" \
  || fail "S201 gate/quoted-only — a Review marker that exists only inside a code fence is not a record: expected 'no record found for stage Review' (like the collector), got: '$rf_out'"
# an unquoted-looking real marker next to a quoted one counts once, as real
rf_data "$impl_real" "$(quote_span "$ex_rev_high")${NL}$rev_real_low"
rf_gate
lower || fail "S201 gate/real after span — got: '$rf_out'"

# ---- the same inputs through compliance-evidence.sh gate 2 -------------------
impl_c="$(mk Implementation claude-sonnet-5 medium)"
rev_c_low="$(mk Review claude-sonnet-5 low 'floor-basis="ok"')"
c_ex_impl_low='<!-- model-record: stage=Implementation model="claude-opus-5" effort="low" -->'
c_ex_rev_high='<!-- model-record: stage=Review model="claude-opus-5" effort="high" floor-basis="example" -->'
# one TEXT record per comment; a multi-line comment is sent with the \001 sentinel
for form in fence tilde span block; do
  q="$("quote_$form" "$c_ex_impl_low")"
  q="${q//$NL/$'\001'}"
  ce "Closes #265" "$impl_c
$rev_c_low
$q" ""
  [ "$(row_status "$ce_out" 2)" = "evidenced" ] || fail "S201 gate2/$form — the quoted example (another model) must not count: the real Review is on Implementation's model, so evidenced, got '$(row_status "$ce_out" 2)' ($(row_evidence "$ce_out" 2))"
done
for form in fence span block; do
  q="$("quote_$form" "$c_ex_rev_high")"
  q="${q//$NL/$'\001'}"
  ce "Closes #265" "$impl_c
$rev_c_low
$q" ""
  [ "$(row_status "$ce_out" 2)" = "evidenced" ] || fail "S201 gate2/review-$form — a quoted Review example must not replace the real one, got '$(row_status "$ce_out" 2)'"
done

# ---- an indented code block: live_text keeps it in every script (accepted
# debt, S151 Q18): the three scripts must AGREE, whatever they decide ---------
ind="    $ex_impl_low"
rf_data "$impl_real" "$rev_real_low" "Indented example:${NL}${NL}$ind"
rf_gate
if lower; then gate_says=finding; else gate_says=silent; fi
c_ind="    $c_ex_impl_low"
c_ind="${c_ind//$NL/$'\001'}"
ce "Closes #265" "$impl_c
$rev_c_low
Indented example:${NL}${NL}$c_ind" ""
case "$(row_status "$ce_out" 2)" in
  evidenced) ce_says=finding ;; # the indented example was NOT counted: the real markers decide
  unverifiable-from-artifacts) ce_says=silent ;; # the indented example (another model) WAS counted
  *) ce_says="other:$(row_status "$ce_out" 2)" ;;
esac
[ "$gate_says" = "$ce_says" ] \
  || fail "S201 indented — the gate ($gate_says) and the collector ($ce_says) must treat an indented example marker the same way (S151 Q18: accepted fail-open, but one rule for all scripts)"

# ---- and through role-label-staleness.sh ------------------------------------
# shellcheck source=../fixtures/role-label-fake-gh.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/role-label-fake-gh.sh"
rl_verdict() { # label, comment-text (one comment, \001 for newlines)
  local label="$1" body="$2" bin
  body="${body//$NL/$'\001'}"
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
__CALL_PR501_COMMENTS__)
  printf 'TEXT\t%s\n' '$body'
  exit 0 ;;
__CALL_PR501_REVIEWS__)
  exit 0 ;;
GHEOF
  bin="$(cat "$FAKEGH_OUT")"
  rl="$(PATH="$bin:$PATH" "$TEST_REPO_ROOT/role-label-staleness.sh" 400 2>/dev/null)"
}
# the label is at the real stage (Test); a quoted example of a LATER stage
# would make it look stale if it counted
for form in fence span block; do
  rl_verdict role:qa "$(marker Test Sonnet medium)${NL}$("quote_$form" "$ex_rev_high")"
  case "$rl" in
    *" — in-sync "*) : ;;
    *) fail "S201 role-label/$form — a quoted Review example must not make role:qa stale, got: $rl" ;;
  esac
done

test_done
