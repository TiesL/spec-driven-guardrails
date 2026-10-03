#!/usr/bin/env bash
# S189 — model-record-gate.sh checks the Review floor it CAN check: same
# model compares effort; every Review marker carries a floor-basis; a legacy
# same-model-exception is ignored.
# Covers: F27
#
# Issue #392, R2/R3/R6, AC3/AC4/AC5/AC9, A24/A25 and the human decisions of
# 2026-10-03. Seam: the installed gate script run for PR 246 against a
# data-driven fake gh (fixtures/pipeline-371-helpers.sh), its stdout lines
# and exit status. Finding text beyond "names the model/efforts" and the
# `model-record:` prefix is deliberately not pinned. Different models: no
# capability finding at all (no ordering a script can check).

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"
# shellcheck source=../fixtures/review-floor-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-floor-helpers.sh"

script="$TEST_REPO_ROOT/skills/pre-merge-review/model-record-gate.sh"
[ -x "$script" ] || { fail "S189 — model-record-gate.sh is missing or not executable"; test_done; }
command -v jq >/dev/null 2>&1 || { fail "S189 — jq is needed by the fake gh"; test_done; }

sandbox_create
trap sandbox_destroy EXIT
rf_gate_setup
rf_out=""
rf_status=0 # set by rf_gate

FB='floor-basis="same model as Implementation at higher effort"'

# silent <label> <impl> <review> [more markers...]: no output, exit 0.
silent() {
  local label="$1"
  shift
  rf_data "$@"
  rf_gate
  [ "$rf_status" -eq 0 ] || fail "S189 — $label: gate exited $rf_status"
  [ -z "$rf_out" ] || fail "S189 — $label: expected no findings, got: $rf_out"
}
# one_finding <label> <ere that the single finding line must match> <markers...>
one_finding() {
  local label="$1" ere="$2"
  shift 2
  rf_data "$@"
  rf_gate
  [ "$rf_status" -eq 0 ] || fail "S189 — $label: gate exited $rf_status (findings are non-blocking)"
  [ "$(rf_findings)" -eq 1 ] || fail "S189 — $label: expected exactly one finding line, got: $rf_out"
  case "$rf_out" in
    "model-record:"*) : ;;
    *) fail "S189 — $label: the finding must start with the model-record: prefix, got: $rf_out" ;;
  esac
  grep -qiE -- "$ere" <<<"$rf_out" || fail "S189 — $label: the finding does not match /$ere/, got: $rf_out"
  ! grep -q '^role-played: ' <<<"$rf_out" || fail "S189 — $label: a #392 finding must never use the role-played: prefix (the merge guard blocks on it)"
}

# ===== AC3: same model -> effort is compared ===============================
one_finding "same model, Review lower (low < high)" 'low.*high|high.*low' \
  "$(marker Implementation Sonnet high)" "$(marker Review Sonnet low "$FB")"
one_finding "same model, Review lower (medium < high)" 'medium.*high|high.*medium' \
  "$(marker Implementation Sonnet high)" "$(marker Review Sonnet medium "$FB")"
one_finding "same model, Review lower (low < medium)" 'low.*medium|medium.*low' \
  "$(marker Implementation Sonnet medium)" "$(marker Review Sonnet low "$FB")"
silent "same model, equal effort" "$(marker Implementation Sonnet high)" "$(marker Review Sonnet high "$FB")"
silent "same model, equal low effort (the dry-run pattern: passes, a documented false pass)" \
  "$(marker Implementation Sonnet low)" "$(marker Review Sonnet low "$FB")"
silent "same model, Review higher" "$(marker Implementation Sonnet medium)" "$(marker Review Sonnet high "$FB")"
silent "same model, Review higher (low vs medium)" "$(marker Implementation Sonnet low)" "$(marker Review Sonnet medium "$FB")"

# the finding names the model too
one_finding "the finding names the model" 'sonnet' \
  "$(marker Implementation Sonnet high)" "$(marker Review Sonnet low "$FB")"

# label style / snapshot date: normalize_model first, then effort
one_finding "label styles normalize equal, lower effort flagged" 'low.*high|high.*low' \
  "$(marker Implementation claude-sonnet-5 high)" "$(marker Review 'Sonnet 5' low "$FB")"
one_finding "snapshot date ignored, lower effort flagged" 'low.*high|high.*low' \
  "$(marker Implementation claude-sonnet-5-20260101 high)" "$(marker Review claude-sonnet-5-20260301 low "$FB")"
silent "label styles normalize equal, equal effort" \
  "$(marker Implementation claude-sonnet-5 medium)" "$(marker Review 'Claude Sonnet 5' medium "$FB")"

# effort values compare case-insensitively
one_finding "effort case-insensitive (LOW < High)" 'low.*high|high.*low' \
  "$(marker Implementation Sonnet High)" "$(marker Review Sonnet LOW "$FB")"

# ===== AC4: different models -> no capability finding ======================
silent "different models, Review lower effort (no ordering a script can check)" \
  "$(marker Implementation Sonnet high)" "$(marker Review Opus low "$FB")"
silent "different models, Review higher effort" \
  "$(marker Implementation Sonnet low)" "$(marker Review Opus high "$FB")"
silent "different models, Review is the lighter model (undetectable: a documented false pass)" \
  "$(marker Implementation Opus high)" "$(marker Review Sonnet high "$FB")"
# the short alias vs its full id counts as different: no effort check
silent "short alias vs full id is a different model: effort check skipped, no finding" \
  "$(marker Implementation claude-opus-5 high)" "$(marker Review opus low "$FB")"

# ===== Unknown / missing / unquoted effort: no claim either way ============
silent "Review effort session-default" "$(marker Implementation Sonnet high)" "$(marker Review Sonnet session-default "$FB")"
silent "Review effort unknown" "$(marker Implementation Sonnet high)" "$(marker Review Sonnet unknown "$FB")"
silent "Implementation effort unknown" "$(marker Implementation Sonnet unknown)" "$(marker Review Sonnet low "$FB")"
silent "effort outside low|medium|high (max)" "$(marker Implementation Sonnet max)" "$(marker Review Sonnet low "$FB")"
silent "Review effort missing" "<!-- model-record: stage=Implementation model=\"Sonnet\" effort=\"high\" -->" "<!-- model-record: stage=Review model=\"Sonnet\" $FB -->"
silent "Implementation effort missing" "<!-- model-record: stage=Implementation model=\"Sonnet\" -->" "$(marker Review Sonnet low "$FB")"
silent "Review effort unquoted" "$(marker Implementation Sonnet high)" "<!-- model-record: stage=Review model=\"Sonnet\" effort=low $FB -->"
silent "Implementation effort unquoted" "<!-- model-record: stage=Implementation model=\"Sonnet\" effort=high -->" "$(marker Review Sonnet low "$FB")"

# ===== Attribute extraction is word-anchored (A25, V5) =====================
one_finding "reviewer-model before model must not be read as model" 'low.*high|high.*low' \
  "$(marker Implementation sonnet high)" \
  "<!-- model-record: stage=Review reviewer-model=\"opus\" model=\"sonnet\" effort=\"low\" $FB -->"
one_finding "peak-effort before effort must not be read as effort" 'low.*high|high.*low' \
  "$(marker Implementation sonnet high)" \
  "<!-- model-record: stage=Review model=\"sonnet\" peak-effort=\"high\" effort=\"low\" $FB -->"
silent "floor-basis text mentioning 'model' does not disturb model/effort extraction" \
  "$(marker Implementation sonnet medium)" \
  "<!-- model-record: stage=Review floor-basis=\"same model as Implementation, higher effort\" model=\"sonnet\" effort=\"high\" -->"

# ===== Latest marker wins (tail -1), per stage =============================
silent "a later Review round replaces an earlier lower-effort one" \
  "$(marker Implementation Sonnet high)" "$(marker Review Sonnet low "$FB")" "$(marker Review Sonnet high "$FB")"
one_finding "a later lower-effort Review round is the one checked" 'low.*high|high.*low' \
  "$(marker Implementation Sonnet high)" "$(marker Review Sonnet high "$FB")" "$(marker Review Sonnet low "$FB")"
silent "the latest Implementation marker wins" \
  "$(marker Implementation Sonnet high)" "$(marker Implementation Sonnet low)" "$(marker Review Sonnet low "$FB")"

# ===== AC9/A24: floor-basis on EVERY Review marker =========================
one_finding "floor-basis missing, same model, equal effort" 'floor-basis' \
  "$(marker Implementation Sonnet high)" "$(marker Review Sonnet high)"
one_finding "floor-basis missing, different models" 'floor-basis' \
  "$(marker Implementation Sonnet high)" "$(marker Review Opus high)"
one_finding "floor-basis empty" 'floor-basis' \
  "$(marker Implementation Sonnet high)" "$(marker Review Opus high 'floor-basis=""')"
one_finding "floor-basis unquoted" 'floor-basis' \
  "$(marker Implementation Sonnet high)" "<!-- model-record: stage=Review model=\"Opus\" effort=\"high\" floor-basis=because -->"
silent "floor-basis present, different models" "$(marker Implementation Sonnet high)" "$(marker Review Opus high "$FB")"
silent "the floor-basis text is never verified (any sentence passes)" \
  "$(marker Implementation Sonnet high)" "$(marker Review Opus low 'floor-basis="x"')"
# only the LATEST Review marker's floor-basis counts
silent "earlier Review without floor-basis, later with" \
  "$(marker Implementation Sonnet high)" "$(marker Review Opus high)" "$(marker Review Opus high "$FB")"
one_finding "earlier Review with floor-basis, later without" 'floor-basis' \
  "$(marker Implementation Sonnet high)" "$(marker Review Opus high "$FB")" "$(marker Review Opus high)"
# no floor-basis requirement on the other four stages
silent "Implementation needs no floor-basis" "$(marker Implementation Sonnet high)" "$(marker Review Opus high "$FB")"
# both findings at once
rf_data "$(marker Implementation Sonnet high)" "$(marker Review Sonnet low)"
rf_gate
[ "$(rf_findings)" -eq 2 ] || fail "S189 — lower effort AND no floor-basis: expected two finding lines, got: $rf_out"

# ===== AC5/R3: legacy same-model-exception is ignored completely ===========
one_finding "legacy exception does not waive a lower-effort same-model Review" 'low.*high|high.*low' \
  "$(marker Implementation Sonnet high)" "$(marker Review Sonnet low "$FB same-model-exception=\"only one model available\"")"
one_finding "legacy exception does not stand in for floor-basis" 'floor-basis' \
  "$(marker Implementation Sonnet high)" "$(marker Review Sonnet high 'same-model-exception="only one model available"')"
silent "legacy exception + floor-basis, equal effort: no finding because of it" \
  "$(marker Implementation Sonnet high)" "$(marker Review Sonnet high "$FB same-model-exception=\"only one model available\"")"
silent "legacy exception with an EMPTY reason is simply ignored" \
  "$(marker Implementation Sonnet high)" "$(marker Review Sonnet high "$FB same-model-exception=\"\"")"
silent "legacy exception on different models" \
  "$(marker Implementation Sonnet high)" "$(marker Review Opus high "$FB same-model-exception=\"x\"")"
silent "same model, equal effort, no exception: the #244 finding is gone" \
  "$(marker Implementation Sonnet medium)" "$(marker Review Sonnet medium "$FB")"
rf_data "$(marker Implementation Sonnet high)" "$(marker Review Sonnet high "$FB")"
rf_gate
! grep -q 'same-model-exception' <<<"$rf_out" || fail "S189 — no output may ask for a same-model-exception any more, got: $rf_out"

# ===== Missing stages stay the existing findings; no extra claims ==========
rf_data "$(marker Implementation Sonnet high)"
rf_gate
case "$rf_out" in
  *"no record found for stage Review"*) : ;;
  *) fail "S189 — Review missing: the existing 'no record found for stage Review' line is expected, got: $rf_out" ;;
esac
[ "$(rf_findings)" -eq 1 ] || fail "S189 — Review missing: only the missing-stage line, no floor-basis/effort claim about a marker that is not there, got: $rf_out"
rf_data "$(marker Review Sonnet low "$FB")"
rf_gate
case "$rf_out" in
  *"no record found for stage Implementation"*) : ;;
  *) fail "S189 — Implementation missing: expected the existing missing-stage line, got: $rf_out" ;;
esac
[ "$(rf_findings)" -eq 1 ] || fail "S189 — Implementation missing: no effort comparison without both markers, got: $rf_out"

# ===== Opted-in project: findings never gain the role-played: prefix =======
id="process-multi-agent-roles"
optin="$(fresh_project optin)"
write_adoption "$optin/WORKFLOW-ADOPTION.md" "$id" yes
# the shape of a real dispatched run: one comment per stage
rf_data "$(marker Implementation Sonnet high)"
json_comments "$FAKE_GH_DATA/reviews-246.json" "$(marker Review Sonnet low)"
rf_gate "$optin"
grep -q 'floor-basis' <<<"$rf_out" || fail "S189 — opted-in project: the floor-basis finding is expected too, got: $rf_out"
grep -qiE 'low.*high|high.*low' <<<"$rf_out" || fail "S189 — opted-in project: the lower-effort finding is expected too, got: $rf_out"
! grep -q '^role-played: ' <<<"$rf_out" || fail "S189 — a dispatched run with only model-record findings must produce no role-played: line, got: $rf_out"

# ===== The gate finds lib/model-record.sh through a symlinked skills dir ====
# (adopted projects get skills/ as a symlink into the clone; the gate must
# resolve it, as it does for lib/changes.sh).
linked="$SANDBOX/linked-project"
mkdir -p "$linked/.claude"
ln -s "$TEST_REPO_ROOT/skills" "$linked/.claude/skills"
rf_data "$(marker Implementation Sonnet high)" "$(marker Review Sonnet low "$FB")"
rf_gate "$RF_PLAIN" "$linked/.claude/skills/pre-merge-review/model-record-gate.sh"
grep -qiE 'low.*high|high.*low' <<<"$rf_out" || fail "S189 — run through a symlinked skills dir, the effort finding is missing (lib not found?), got: $rf_out"

test_done
