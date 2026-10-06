#!/usr/bin/env bash
# S194 — free text inside a Review marker (`>`, `<`, `--`, `-->`, a newline in
# the floor-basis value) never hides the marker from either script.
# Covers: F39
#
# Issue #392, review of PR #397 (medium finding), human decision "fix the
# parser": the marker grammar used to end a marker at the first `>`, so
# floor-basis="x > y" made the whole Review marker invisible: the gate then
# said "no record found for stage Review", and gate 2 said the marker was
# only a "quoted illustration". Since #424 the floor is on the model alone, so
# "the marker was seen" is proved by the ABSENCE of "no record found" (gate)
# and by `evidenced` instead of `not-evidenced` (gate 2), and by a missing
# floor-basis being reported on the latest round. Quotes are the one thing a value
# cannot contain (A24); every other character is tolerated and the marker
# parses as if the value were plain. Seam: model-record-gate.sh stdout and
# compliance-evidence.sh gate 2's row, both against fake gh.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"
# shellcheck source=../fixtures/review-floor-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-floor-helpers.sh"

command -v jq >/dev/null 2>&1 || { fail "S194 — jq is needed by the fake gh"; test_done; }
sandbox_create
trap sandbox_destroy EXIT
rf_gate_setup
rf_out=""
rf_status=0 # set by rf_gate
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=../compliance-evidence-fixture.sh
. "$(dirname "${BASH_SOURCE[0]}")/../compliance-evidence-fixture.sh"
script="$TEST_REPO_ROOT/compliance-evidence.sh"
export CE_ID=S194
ce_out=""
# shellcheck source=../fixtures/ce-review-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/ce-review-helpers.sh"

# label|value pairs (the newline variant is tested separately, per script)
variants=(
  "gt|stronger model > weaker model"
  "lt|a < b"
  "dashes|mechanical -- rename"
  "arrow|stronger model --> weaker model"
  "opener|mentions an <!-- opener inside"
  "mix|<!-- x --> > < --"
)

NL=$'\n'
SOH=$'\001'
BT='`'

# ---------------------------------------------------------------------------
# model-record-gate.sh
# ---------------------------------------------------------------------------
gate_variant() { # label value
  local label="$1" v="$2" fb
  fb="floor-basis=\"$v\""
  # same model, Review at a lower legacy effort: the marker is seen (no "no
  # record found for stage Review"), its floor-basis is present, and effort
  # gives no finding (#424): no output at all
  rf_data "$(marker Implementation Sonnet high)" "$(marker Review Sonnet low "$fb")"
  rf_gate
  [ "$rf_status" -eq 0 ] || fail "S194 gate/$label — exit $rf_status"
  [ -z "$rf_out" ] || fail "S194 gate/$label — a Review marker with '$v' in floor-basis must be seen and give no finding, got: '$rf_out'"

  rf_data "$(marker Implementation Sonnet high)" "$(marker Review Sonnet high "$fb")"
  rf_gate
  [ -z "$rf_out" ] || fail "S194 gate/$label — equal effort with '$v': expected no findings, got: '$rf_out'"

  rf_data "$(marker Implementation Sonnet high)" "$(marker Review Opus low "$fb")"
  rf_gate
  [ -z "$rf_out" ] || fail "S194 gate/$label — different models with '$v': expected no findings, got: '$rf_out'"

  # the same marker is read as the LATEST round: a later Review without any
  # floor-basis is the one whose missing floor-basis is reported
  rf_data "$(marker Implementation Sonnet high)" "$(marker Review Sonnet low "$fb")" "$(marker Review Sonnet low)"
  rf_gate
  [ "$(rf_findings)" -eq 1 ] && grep -q 'floor-basis' <<<"$rf_out" || fail "S194 gate/$label — a later Review without floor-basis must be the one reported, got: '$rf_out'"
}
for pair in "${variants[@]}"; do gate_variant "${pair%%|*}" "${pair#*|}"; done

# a newline inside the value (a multi-line comment body)
gate_variant nl "line one${NL}line two"
gate_variant nl-gt "stronger >${NL}weaker"

# a `>` in some OTHER attribute, on either marker
rf_data "$(marker Implementation Sonnet high 'note="uses > here"')" "$(marker Review Sonnet low 'floor-basis="ok" note="a > b"')"
rf_gate
[ "$rf_status" -eq 0 ] && [ -z "$rf_out" ] \
  || fail "S194 gate — a '>' in another attribute of either marker must not hide it (no 'no record found'), got: '$rf_out'"

# a marker with '>' elsewhere and NO floor-basis is still a Review marker: the
# missing-floor-basis finding appears (and not "no record found for stage Review")
rf_data "$(marker Implementation Sonnet high)" "$(marker Review Opus high 'note="a > b"')"
rf_gate
[ "$(rf_findings)" -eq 1 ] && grep -q 'floor-basis' <<<"$rf_out" \
  || fail "S194 gate — Review marker with '>' in a note and no floor-basis: expected exactly the floor-basis finding, got: '$rf_out'"
grep -q 'no record found for stage Review' <<<"$rf_out" && fail "S194 gate — the Review marker was not recognised, got: '$rf_out'"

# the latest round still wins when an earlier one carries free text
rf_data "$(marker Implementation Sonnet high)" "$(marker Review Sonnet low 'floor-basis="a > b"')" "$(marker Review Sonnet high 'floor-basis="c > d"')"
rf_gate
[ -z "$rf_out" ] || fail "S194 gate — a later round with '>' must replace the earlier one, got: '$rf_out'"
# ...and the other way round: an earlier round with '>' and floor-basis, a later one without it
rf_data "$(marker Implementation Sonnet high)" "$(marker Review Sonnet high 'floor-basis="a > b"')" "$(marker Review Sonnet high)"
rf_gate
[ "$(rf_findings)" -eq 1 ] && grep -q 'floor-basis' <<<"$rf_out" || fail "S194 gate — the later Review without floor-basis must win over an earlier one with '>', got: '$rf_out'"

# ---------------------------------------------------------------------------
# compliance-evidence.sh gate 2
# ---------------------------------------------------------------------------
impl_m="$(mk Implementation claude-sonnet-5 medium)"
no_misleading() { # label
  local ev
  ev="$(row_evidence "$ce_out" 2)"
  case "$ev" in
    *illustration* | *"code span"* | *quoted* | *"no \`stage=Review\`"*)
      fail "S194 gate2/$1 — the marker was recognised, so the evidence must not claim a quoted illustration or an absent marker, got: $ev" ;;
  esac
}
ce_variant() { # label value
  local label="$1" v="$2" fb
  fb="floor-basis=\"$v\""
  check "gate2/$label same model, lower legacy effort" evidenced "$impl_m
$(mk Review claude-sonnet-5 low "$fb")"
  case "$(row_evidence "$ce_out" 2)" in
    *"${BT}low${BT}"* | *"${BT}medium${BT}"*) fail "S194 gate2/$label — the verdict is on the model alone and must quote no effort (#424), got: $(row_evidence "$ce_out" 2)" ;;
  esac
  no_misleading "$label"
  check "gate2/$label same model, equal effort" evidenced "$impl_m
$(mk Review claude-sonnet-5 medium "$fb")"
  no_misleading "$label"
  check "gate2/$label different models" unverifiable-from-artifacts "$impl_m
$(mk Review claude-opus-5 medium "$fb")"
  no_misleading "$label"
}
for pair in "${variants[@]}"; do ce_variant "${pair%%|*}" "${pair#*|}"; done
ce_variant nl "line one${SOH}line two"

# the marker on a closing issue, with a PR comment fetch failing: the verdict
# degrades to indeterminate because of the lookup guard, not because the marker
# was "not found"
both="$(mk Implementation claude-sonnet-5 medium)
$(mk Review claude-sonnet-5 low 'floor-basis="stronger > weaker"')"
check "gate2 lookup guard, PR comments fail, '>' in floor-basis" indeterminate FAIL "$both"
case "$(row_evidence "$ce_out" 2)" in
  *"no \`stage=Review\`"*) fail "S194 gate2 guard — the Review marker with '>' was read, so the guard text must not say it was not found, got: $(row_evidence "$ce_out" 2)" ;;
esac
check "gate2 sound verdict, one issue fails, markers on the PR, '>' in floor-basis" evidenced \
  "$impl_m
$(mk Review claude-sonnet-5 low 'floor-basis="stronger > weaker"')" FAIL

test_done
