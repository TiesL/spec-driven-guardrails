#!/usr/bin/env bash
# S190 — compliance-evidence.sh gate 2 reports the Review floor honestly:
# the floor is judged on the model alone (#424): same model is evidenced
# whatever legacy efforts the markers carry; different models are
# unverifiable-from-artifacts; legacy effort and same-model-exception
# attributes are read without error and ignored.
# Covers: F39
#
# Issue #392, R2/R3, AC4/AC5/AC6, A24/A25 and the human decisions of
# 2026-10-03. Seam: the collector's table (gate 2's row: status + evidence
# cell) for PR 279, against a recording fake gh (compliance-evidence-
# fixture.sh). The AC1 worked example and the pre-existing #302/#336 arms
# (S150, updated for #424) cover the exact evidence wording; this file pins
# verdicts and the few phrases that must not read as a verified capability.
# Issue #424 (V3, A33/A33a) removed the effort branch of gate 2 and the
# effort from the inter-issue conflict key: the cases below that used to pin
# an effort verdict now pin the model-only one.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

script="$TEST_REPO_ROOT/compliance-evidence.sh"
[ -x "$script" ] || { fail "S190 — compliance-evidence.sh is missing or not executable"; test_done; }

sandbox_create
trap sandbox_destroy EXIT
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=../compliance-evidence-fixture.sh
. "$(dirname "${BASH_SOURCE[0]}")/../compliance-evidence-fixture.sh"

SHA="cccccccccccccccccccccccccccccccccccccccc"

# emit <body-var-name>: the fake-gh lines that print each marker of a
# newline-separated list as a TEXT record, or fail when the list is FAIL.
emit() {
  local list="$1" m
  if [ "$list" = "FAIL" ]; then
    printf '    echo "simulated failure" >&2\n    exit 1 ;;\n'
    return
  fi
  if [ -n "$list" ]; then
    while IFS= read -r m; do
      [ -n "$m" ] && printf "    printf 'TEXT\\\\t%%s\\\\n' '%s'\n" "$m"
    done <<<"$list"
  fi
  printf '    exit 0 ;;\n'
}

# ce <title> <pr-comment markers|FAIL> <issue-265 markers|FAIL> [<issue-266 markers|FAIL>]
# Runs the collector; sets ce_out.
ce() {
  local title="$1" prc="$2" c265="$3" c266="${4-}"
  {
    echo 'case "$*" in'
    echo '  __CALL_A__)'
    printf "    printf 'HEAD\\\\t%s\\\\n'\n" "$SHA"
    echo "    printf 'STATE\\tOPEN\\n'"
    printf "    printf 'TITLE\\\\t%%s\\\\n' '%s'\n" "$title"
    echo "    printf 'TEXT\\t\\n'"
    echo '    exit 0 ;;'
    echo '  __CALL_A_COMMENTS__)'
    emit "$prc"
    echo '  __CALL_A_REVIEWS__)'
    echo "    printf ''"
    echo '    exit 0 ;;'
    echo '  __CALL_B__)'
    printf "    printf 'check\\\\tSUCCESS\\\\tpass\\\\n'\n"
    echo '    exit 0 ;;'
    echo '  __CALL_C265__)'
    emit "$c265"
    if [ -n "$c266" ]; then
      echo '  __CALL_C266__)'
      emit "$c266"
    fi
    echo 'esac'
    echo 'exit 1'
  } | run_build_fake_gh "$SHA"
  local bin
  bin="$(cat "$FAKEGH_OUT")"
  ce_out="$(PATH="$bin:$PATH" "$script" 279 2>/dev/null)"
}

mk() { # stage model effort [extra]
  printf '<!-- model-record: stage=%s model="%s" effort="%s"%s -->' "$1" "$2" "$3" "${4:+ $4}"
}
FB='floor-basis="stronger model, the diff is a mechanical rename"'

# check <label> <want status> <pr comment markers> [issue265 [issue266 [title]]]
check() {
  local label="$1" want="$2" prc="$3" c265="${4-}" c266="${5-}" title="${6:-Closes #265}"
  ce "$title" "$prc" "$c265" "$c266"
  assert_table_shape "S190 $label" "$ce_out"
  got="$(row_status "$ce_out" 2)"
  [ "$got" = "$want" ] || fail "S190 — $label: gate 2 should be '$want', got '$got' ($(row_evidence "$ce_out" 2))"
}

nl=$'\n'
impl_m="$(mk Implementation claude-sonnet-5 medium)"

# ===== same model: evidenced on the model alone (#424 AC2) ================
check "same model, equal legacy effort" evidenced "$impl_m$nl$(mk Review claude-sonnet-5 medium "$FB")"
check "same model, Review higher legacy effort" evidenced "$impl_m$nl$(mk Review claude-sonnet-5 high "$FB")"
check "same model, Review LOWER legacy effort (the old not-evidenced case)" evidenced "$impl_m$nl$(mk Review claude-sonnet-5 low "$FB")"
ev="$(row_evidence "$ce_out" 2)"
# the basis is named: the model-only floor on self-reported model strings
BT='`'
grep -qi 'self-reported' <<<"$ev" || fail "S190 — the evidenced basis must say the model strings are self-reported, got: $ev"
grep -qi 'model' <<<"$ev" && grep -qiE 'floor' <<<"$ev" || fail "S190 — the evidenced basis must name the model-only floor, got: $ev"
case "$ev" in
  *"${BT}low${BT}"* | *"${BT}medium${BT}"* | *"Review effort"* | *"Implementation effort"*) fail "S190 — gate 2's evidence must quote no recorded effort (#424), got: $ev" ;;
esac
check "same model, label styles differ, Review lower legacy effort" evidenced "$(mk Implementation claude-sonnet-5-20260101 high)$nl$(mk Review 'Sonnet 5' medium "$FB")"
check "same model, label styles differ, equal effort" evidenced "$(mk Implementation claude-sonnet-5-20260101 high)$nl$(mk Review 'Sonnet 5' high "$FB")"
check "effort values are not compared (HIGH vs Low)" evidenced "$(mk Implementation claude-sonnet-5 HIGH)$nl$(mk Review claude-sonnet-5 Low "$FB")"
# markers with NO effort attribute (what the emitter prints from #424 on)
mkn() { printf '<!-- model-record: stage=%s model="%s"%s -->' "$1" "$2" "${3:+ $3}"; }
check "same model, no effort attribute on either marker" evidenced "$(mkn Implementation claude-sonnet-5)$nl$(mkn Review claude-sonnet-5 "$FB")"
check "different models, no effort attribute (AC3)" unverifiable-from-artifacts "$(mkn Implementation claude-sonnet-5)$nl$(mkn Review claude-opus-5 "$FB")"

# ===== different models: no machine verdict ================================
for pair in "low high" "high low" "medium medium"; do
  ri="${pair% *}"; rr="${pair#* }"
  check "different models (Implementation $ri, Review $rr)" unverifiable-from-artifacts \
    "$(mk Implementation claude-sonnet-5 "$ri")$nl$(mk Review claude-opus-5 "$rr" "$FB")"
done
ev="$(row_evidence "$ce_out" 2)"
case "$ev" in
  *differ*) : ;;
  *) fail "S190 — different-models evidence must say the models differ, got: $ev" ;;
esac
grep -qiE "machine-check|not checked|isn.t checked|not verified|unverif" <<<"$ev" \
  || fail "S190 — different-models evidence must say the capability ordering is not machine-checked, got: $ev"
case "$ev" in
  *claude-sonnet-5*claude-opus-5* | *claude-opus-5*claude-sonnet-5*) : ;;
  *) fail "S190 — different-models evidence must name both models, got: $ev" ;;
esac
check "different models with floor-basis: the sentence is quoted" unverifiable-from-artifacts \
  "$(mk Implementation claude-sonnet-5 medium)$nl$(mk Review claude-opus-5 medium 'floor-basis="stronger model, mechanical rename"')"
case "$(row_evidence "$ce_out" 2)" in
  *"stronger model, mechanical rename"*) : ;;
  *) fail "S190 — the Review marker's floor-basis should be shown for a human to weigh, got: $(row_evidence "$ce_out" 2)" ;;
esac
check "different models without floor-basis" unverifiable-from-artifacts \
  "$(mk Implementation claude-sonnet-5 medium)$nl$(mk Review claude-opus-5 medium)"
grep -qi 'floor-basis' <<<"$(row_evidence "$ce_out" 2)" || fail "S190 — a Review marker without floor-basis should be said so in the evidence, got: $(row_evidence "$ce_out" 2)"
# short alias vs full id: different models, never a pass
check "short alias vs full id: different, never evidenced" unverifiable-from-artifacts \
  "$(mk Implementation claude-opus-5 high)$nl$(mk Review opus low "$FB")"

# ===== unknown / missing / unquoted legacy effort on the SAME model =========
# read without error and ignored: the model-only verdict, never indeterminate
check "Review effort session-default" evidenced "$impl_m$nl$(mk Review claude-sonnet-5 session-default "$FB")"
check "Review effort unknown" evidenced "$impl_m$nl$(mk Review claude-sonnet-5 unknown "$FB")"
check "Implementation effort unknown" evidenced "$(mk Implementation claude-sonnet-5 unknown)$nl$(mk Review claude-sonnet-5 high "$FB")"
check "Review effort missing" evidenced "$impl_m$nl<!-- model-record: stage=Review model=\"claude-sonnet-5\" $FB -->"
check "Implementation effort missing" evidenced "<!-- model-record: stage=Implementation model=\"claude-sonnet-5\" -->$nl$(mk Review claude-sonnet-5 high "$FB")"
check "Review effort unquoted" evidenced "$impl_m$nl<!-- model-record: stage=Review model=\"claude-sonnet-5\" effort=low $FB -->"
# but missing effort with DIFFERENT models stays the different-models verdict
check "different models, effort missing on both" unverifiable-from-artifacts \
  "<!-- model-record: stage=Implementation model=\"claude-sonnet-5\" -->$nl<!-- model-record: stage=Review model=\"claude-opus-5\" $FB -->"
# the existing no-quoted-model branch is unchanged
check "unquoted model: indeterminate as before" indeterminate \
  "<!-- model-record: stage=Implementation model=claude-sonnet-5 effort=medium -->$nl$(mk Review claude-sonnet-5 medium "$FB")"
check "no Review marker: not-evidenced as before" not-evidenced "$impl_m"

# ===== Word-boundary attribute extraction ==================================
check "reviewer-model before model is not read as model" evidenced \
  "$impl_m$nl<!-- model-record: stage=Review reviewer-model=\"claude-opus-5\" model=\"claude-sonnet-5\" effort=\"low\" $FB -->"
check "peak-effort before effort: ignored, same model evidenced" evidenced \
  "$impl_m$nl<!-- model-record: stage=Review model=\"claude-sonnet-5\" peak-effort=\"high\" effort=\"low\" $FB -->"

# ===== AC5: legacy same-model-exception: ignored ===========================
check "legacy exception plus lower legacy effort: ignored, evidenced" evidenced \
  "$impl_m$nl$(mk Review claude-sonnet-5 low "$FB same-model-exception=\"only model available\"")"
check "legacy exception with an empty reason, equal effort" evidenced \
  "$impl_m$nl$(mk Review claude-sonnet-5 medium "$FB same-model-exception=\"\"")"
for exc in "" 'same-model-exception="x"'; do
  check "legacy exception on different models changes nothing ($exc)" unverifiable-from-artifacts \
    "$impl_m$nl$(mk Review claude-opus-5 medium "$FB $exc")"
done
ev="$(row_evidence "$ce_out" 2)"
case "$ev" in
  *same-model-exception*) fail "S190 — the table must not mention a same-model-exception any more, got: $ev" ;;
esac

# ===== inter-issue conflict key = the normalized model alone (#424 AC6) ====
# Two closing issues carry the Implementation marker (the PR carries none);
# the PR carries the Review marker.
two="Closes #265, closes #266"
rev="$(mk Review claude-sonnet-5 high "$FB")"
check "two issues, Implementation markers agree" evidenced \
  "$rev" "$(mk Implementation claude-sonnet-5 medium)" "$(mk Implementation Sonnet-5 medium)" "$two"
# same model, DIFFERENT legacy effort: no conflict, effort is not in the key
check "two issues, same model but different legacy effort: NO conflict" evidenced \
  "$rev" "$(mk Implementation claude-sonnet-5 medium)" "$(mk Implementation claude-sonnet-5 high)" "$two"
check "two issues, same model but different legacy effort, order swapped: NO conflict" evidenced \
  "$rev" "$(mk Implementation claude-sonnet-5 high)" "$(mk Implementation claude-sonnet-5 medium)" "$two"
check "two issues, one marker with an effort and one without: NO conflict" evidenced \
  "$rev" "$(mk Implementation claude-sonnet-5 medium)" "$(mkn Implementation claude-sonnet-5)" "$two"
check "two issues, different models: conflict (unchanged)" indeterminate \
  "$rev" "$(mk Implementation claude-sonnet-5 medium)" "$(mk Implementation claude-opus-5 medium)" "$two"
# the same on the Review stage (Implementation on the PR)
check "two issues, Review markers differ in legacy effort only: NO conflict" evidenced \
  "$impl_m" "$(mk Review claude-sonnet-5 medium "$FB")" "$(mk Review claude-sonnet-5 high "$FB")" "$two"
# a conflict, when there is one, quotes no effort
check "two issues, different models: the conflict text names models, not efforts" indeterminate \
  "$rev" "$(mk Implementation claude-sonnet-5 medium)" "$(mk Implementation claude-opus-5 high)" "$two"
case "$(row_evidence "$ce_out" 2)" in
  *"(effort"*) fail "S190 — the conflict evidence must not quote an effort (#424), got: $(row_evidence "$ce_out" 2)" ;;
esac
# the PR's own marker still outranks an issue-side one (no conflict)
check "PR-side marker wins over an issue's planned marker (no conflict)" evidenced \
  "$impl_m$nl$(mk Review claude-sonnet-5 low "$FB")" "$(mk Review claude-sonnet-5 high "$FB")"
# a legacy exception on one of two otherwise equal issue markers is no disagreement
check "two issues, equal model, one legacy exception: no conflict" evidenced \
  "$impl_m" "$(mk Review claude-sonnet-5 medium "$FB same-model-exception=\"x\"")" "$(mk Review claude-sonnet-5 medium "$FB")" "$two"

# ===== AC6: the lookup-failure guard (#302/#336) still applies ============
# markers only on closing issue 265, the PR comments fetch fails: a
# superseding PR marker cannot be ruled out, whatever the legacy efforts
# (an unread marker must never produce a definite verdict either way).
both_low="$(mk Implementation claude-sonnet-5 medium)$nl$(mk Review claude-sonnet-5 low "$FB")"
both_eq="$(mk Implementation claude-sonnet-5 medium)$nl$(mk Review claude-sonnet-5 medium "$FB")"
check "PR comments fetch fails, issue markers lower effort" indeterminate FAIL "$both_low"
check "PR comments fetch fails, issue markers equal effort" indeterminate FAIL "$both_eq"
# two closing issues, one fetch fails, the markers come from the other
check "two issues, one fetch fails, lower effort" indeterminate "" "$both_low" FAIL "$two"
check "two issues, one fetch fails, equal effort" indeterminate "" "$both_eq" FAIL "$two"
# but ONE closing issue failing while both markers sit on the PR is sound:
# the verdict rests on data in hand, unchanged
check "one issue lookup fails, markers on the PR, lower legacy effort: still evidenced (model-only)" evidenced "$both_low" FAIL
check "one issue lookup fails, markers on the PR, equal effort: still evidenced" evidenced "$both_eq" FAIL
check "one issue lookup fails, different models on the PR: still unverifiable" unverifiable-from-artifacts \
  "$(mk Implementation claude-sonnet-5 medium)$nl$(mk Review claude-opus-5 medium "$FB")" FAIL
# absent marker + failed lookup: indeterminate as before
check "Review marker absent and a lookup failed: indeterminate as before" indeterminate "$impl_m" FAIL

test_done
