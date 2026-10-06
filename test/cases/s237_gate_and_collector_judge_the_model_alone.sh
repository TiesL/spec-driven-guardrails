#!/usr/bin/env bash
# S237 — the gate and the collector judge the Review floor on the model alone: no effort finding, gate 2 is model-only, the conflict key is the model, gate 1 reads presence and model.
# Covers: F39, F40
#
# Issue #424 (V3; A33 as amended by A33a), AC2, AC3, AC6. One PR, read by both
# scripts (the gate against a data-driven fake gh, the collector against a
# recording fake gh), with LEGACY `effort` attributes in the markers (this
# repo's own pipeline still emits `effort="unknown"`, and 395 live markers
# carry one): they are read without error and never interpreted.
#   AC2: same model, legacy efforts low (Review) and high (Implementation):
#        the gate prints no effort line (no line at all), and collector gate 2
#        is `evidenced`, its basis named as the model-only floor on
#        self-reported model strings.
#   AC3: different models with a floor-basis: gate 2 is
#        `unverifiable-from-artifacts` and quotes the floor-basis, whatever
#        the efforts (or none).
#   AC6: two closing issues whose Implementation markers name the same model
#        with different legacy efforts: no conflict; gate 1 reads presence and
#        model only (a marker with an odd, empty or missing effort is still a
#        recorded stage). A conflict between DIFFERENT models still names
#        the models only.
# The two gate rows' labels no longer say effort (exact text pinned here and in
# S150's worked example). Seam: the gate's stdout and the collector's table.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"
# shellcheck source=../fixtures/review-floor-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-floor-helpers.sh"

command -v jq >/dev/null 2>&1 || { fail "S237 — jq is needed by the fake gh"; test_done; }
sandbox_create
trap sandbox_destroy EXIT
rf_gate_setup
rf_out=""
rf_status=0 # set by rf_gate
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=../compliance-evidence-fixture.sh
. "$(dirname "${BASH_SOURCE[0]}")/../compliance-evidence-fixture.sh"
script="$TEST_REPO_ROOT/compliance-evidence.sh"
export CE_ID=S237
ce_out=""
# shellcheck source=../fixtures/ce-review-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/ce-review-helpers.sh"

nl=$'\n'
BT='`'
M="claude-sonnet-5"
O="claude-opus-5"
FBX='floor-basis="stronger model, the diff is a mechanical rename"'

# ===== AC2: same model, legacy efforts low vs high ==========================
# the gate: no output at all, and in particular no line that mentions effort
rf_data "$(marker Implementation "$M" high)" "$(marker Review "$M" low "$FBX")"
rf_gate
[ "$rf_status" -eq 0 ] || fail "S237 AC2 gate — exit $rf_status"
[ -z "$rf_out" ] || fail "S237 AC2 gate — Review at legacy effort low vs Implementation at high, same model: expected no output (no effort line), got: '$rf_out'"
! grep -qi 'effort' <<<"$rf_out" || fail "S237 AC2 gate — no line may mention effort, got: '$rf_out'"

# the collector: gate 2 evidenced, basis named
check "AC2 same model, legacy efforts low and high" evidenced "$(mk Implementation "$M" high)$nl$(mk Review "$M" low "$FBX")"
ev="$(row_evidence "$ce_out" 2)"
grep -q "$M" <<<"$ev" || fail "S237 AC2 collector — the evidence must name the model, got: $ev"
grep -qi 'self-reported' <<<"$ev" || fail "S237 AC2 collector — the basis must say the model strings are self-reported, got: $ev"
grep -qiE 'model alone|model-only|only on the model' <<<"$ev" || fail "S237 AC2 collector — the basis must name the model-only floor, got: $ev"
case "$ev" in
  *"${BT}low${BT}"* | *"${BT}high${BT}"* | *"effort ${BT}"*) fail "S237 AC2 collector — the evidence must quote no recorded effort, got: $ev" ;;
esac
# the same verdict whatever the efforts are, or if there are none, or if they are odd
for pair in "high low" "low low" "medium high" "unknown unknown" "session-default high" "max low"; do
  ri="${pair% *}"; rr="${pair#* }"
  check "AC2 same model (Implementation $ri, Review $rr)" evidenced "$(mk Implementation "$M" "$ri")$nl$(mk Review "$M" "$rr" "$FBX")"
done
check "AC2 same model, no effort attribute at all" evidenced \
  "<!-- model-record: stage=Implementation model=\"$M\" -->$nl<!-- model-record: stage=Review model=\"$M\" $FBX -->"
check "AC2 same model, unquoted effort on Review" evidenced "$(mk Implementation "$M" high)$nl<!-- model-record: stage=Review model=\"$M\" effort=low $FBX -->"
check "AC2 same model, empty effort on Implementation" evidenced "<!-- model-record: stage=Implementation model=\"$M\" effort=\"\" -->$nl$(mk Review "$M" low "$FBX")"
# the lookup-failure guard (#302/#336) is unchanged: an unread marker can still overturn the verdict
check "AC2 guard: PR comments fetch fails, markers on the issue" indeterminate FAIL "$(mk Implementation "$M" medium)$nl$(mk Review "$M" low "$FBX")"

# ===== AC3: different models stay a recorded judgment ======================
for pair in "low high" "high low" "unknown unknown"; do
  ri="${pair% *}"; rr="${pair#* }"
  check "AC3 different models (Implementation $ri, Review $rr)" unverifiable-from-artifacts "$(mk Implementation "$M" "$ri")$nl$(mk Review "$O" "$rr" "$FBX")"
  ev="$(row_evidence "$ce_out" 2)"
  case "$ev" in
    *"stronger model, the diff is a mechanical rename"*) : ;;
    *) fail "S237 AC3 — gate 2 must quote the floor-basis, got: $ev" ;;
  esac
  case "$ev" in
    *"$M"*"$O"* | *"$O"*"$M"*) : ;;
    *) fail "S237 AC3 — gate 2 must name both models, got: $ev" ;;
  esac
done
check "AC3 different models, no effort attribute" unverifiable-from-artifacts \
  "<!-- model-record: stage=Implementation model=\"$M\" -->$nl<!-- model-record: stage=Review model=\"$O\" $FBX -->"
case "$(row_evidence "$ce_out" 2)" in
  *"stronger model, the diff is a mechanical rename"*) : ;;
  *) fail "S237 AC3 (no effort) — gate 2 must quote the floor-basis, got: $(row_evidence "$ce_out" 2)" ;;
esac
# the gate: different models is no finding either
rf_data "$(marker Implementation "$M" high)" "$(marker Review "$O" low "$FBX")"
rf_gate
[ -z "$rf_out" ] || fail "S237 AC3 gate — different models with a floor-basis: no finding, got: '$rf_out'"

# ===== AC6: effort is not in the conflict key, and gate 1 reads model only ===
two="Closes #265, closes #266"
rev="$(mk Review "$M" high "$FBX")"
check "AC6 two issues, same model, different legacy efforts: no conflict" evidenced \
  "$rev" "$(mk Implementation "$M" low)" "$(mk Implementation "$M" high)" "$two"
ev="$(row_evidence "$ce_out" 2)"
! grep -qi 'conflict' <<<"$ev" || fail "S237 AC6 — no conflict may be reported for an effort-only difference, got: $ev"
check "AC6 two issues, same model, one effort and none" evidenced \
  "$rev" "$(mk Implementation "$M" low)" "<!-- model-record: stage=Implementation model=\"$M\" -->" "$two"
check "AC6 two issues, same model with other label style, different efforts" evidenced \
  "$rev" "$(mk Implementation claude-sonnet-5 low)" "$(mk Implementation 'Sonnet 5' high)" "$two"
check "AC6 two issues, different models: conflict, models only" indeterminate \
  "$rev" "$(mk Implementation "$M" low)" "$(mk Implementation "$O" high)" "$two"
ev="$(row_evidence "$ce_out" 2)"
case "$ev" in
  *"$M"*"$O"* | *"$O"*"$M"*) : ;;
  *) fail "S237 AC6 — the model conflict must name both models, got: $ev" ;;
esac
case "$ev" in
  *"(effort"*) fail "S237 AC6 — the model conflict must not quote an effort, got: $ev" ;;
esac
# gate 1 (row 1): presence and model only
ce "Closes #265" "$(mk Planning "$M" low)$nl$(mk Test "$M" high)$nl$(mk Implementation "$M" medium)" "$(mk Discovery "$M" unknown)"
assert_table_shape "S237 gate 1 baseline" "$ce_out"
[ "$(row_status "$ce_out" 1)" = "evidenced" ] || fail "S237 AC6 gate 1 — four stages recorded (Discovery on the issue): expected evidenced, got '$(row_status "$ce_out" 1)' ($(row_evidence "$ce_out" 1))"
ce "Closes #265" "<!-- model-record: stage=Planning model=\"$M\" -->$nl<!-- model-record: stage=Test model=\"$M\" effort=\"\" -->$nl<!-- model-record: stage=Implementation model=\"$M\" effort=high -->" "<!-- model-record: stage=Discovery model=\"$M\" effort=\"unknown\" -->"
[ "$(row_status "$ce_out" 1)" = "evidenced" ] || fail "S237 AC6 gate 1 — a missing, empty or unquoted legacy effort is still a recorded stage: expected evidenced, got '$(row_status "$ce_out" 1)' ($(row_evidence "$ce_out" 1))"
case "$(row_evidence "$ce_out" 1)" in
  *effort*) fail "S237 AC6 gate 1 — the evidence must not mention effort, got: $(row_evidence "$ce_out" 1)" ;;
esac
# the gate (script): a stage marker with no effort is complete
rf_data "$(marker_ne Implementation "$M")" "$(marker_ne Review "$M" "$FBX")"
rf_gate
[ -z "$rf_out" ] || fail "S237 AC6 gate — markers without effort (the emitter's output) must give no finding, got: '$rf_out'"

# ===== the two model rows no longer name effort (exact labels) ==============
ce "Closes #265" "$(mk Implementation "$M" medium)$nl$(mk Review "$M" medium "$FBX")" ""
lbl1="$(printf '%s\n' "$ce_out" | sed -n '3p' | sed -E 's/^\| (.*) \| ([a-z-]+) \| (.*) \|$/\1/')"
lbl2="$(printf '%s\n' "$ce_out" | sed -n '4p' | sed -E 's/^\| (.*) \| ([a-z-]+) \| (.*) \|$/\1/')"
[ "$lbl1" = "$GATE1" ] || fail "S237 labels — row 1 must read '$GATE1', got '$lbl1'"
[ "$lbl2" = "$GATE2" ] || fail "S237 labels — row 2 must read '$GATE2', got '$lbl2'"
case "$lbl1$lbl2" in
  *[Ee]ffort*) fail "S237 labels — the model rows must not name effort" ;;
esac

test_done
