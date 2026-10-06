#!/usr/bin/env bash
# S239 — process-model-choice moves to meaning version 2 (effort is no longer recorded), quality-review-before-merge to 4, each exactly once; process-multi-agent-roles does not move yet; this repo's own rows re-confirm; adopters answered under the old version are re-surfaced.
# Covers: F9, F26, F39
#
# Issue #424 (V3; A33a), AC4. The adoption-registry rule (#254) counts a
# removed obligation as material, so `process-model-choice` (whose "Yes means"
# said every stage records "which model/effort") bumps from the absent
# version (= 1) to 2, and `quality-review-before-merge` from 3 to 4 (S191
# pins its text). Both move once, in this slice. `process-multi-agent-roles`
# is NOT bumped here (its v2, for the stricter guard, comes with the slice that
# makes the guard stricter). Each "Yes means" states that the floor is judged
# on the model and effort is neither chosen nor checked, with the revisit
# trigger "when the dispatch tool gains an effort parameter". Seam: CHANGES.md
# and WORKFLOW-ADOPTION.md as text, and pending-changes.sh run on fixture
# projects (re-surfacing, S141's mechanism).

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"
# shellcheck source=../fixtures/review-floor-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-floor-helpers.sh"
# shellcheck source=../../lib/changes.sh disable=SC1091
. "$TEST_REPO_ROOT/lib/changes.sh"

changes="$TEST_REPO_ROOT/CHANGES.md"
adoption="$TEST_REPO_ROOT/WORKFLOW-ADOPTION.md"
sandbox_create
trap sandbox_destroy EXIT

# ===== each row moves once ==================================================
[ "$(changes_meaning_version quality-review-before-merge "$changes")" = "4" ] \
  || fail "S239/AC4 — quality-review-before-merge must be at Meaning version 4, got '$(changes_meaning_version quality-review-before-merge "$changes")'"
[ "$(changes_meaning_version process-model-choice "$changes")" = "2" ] \
  || fail "S239/AC4 — process-model-choice must be at Meaning version 2, got '$(changes_meaning_version process-model-choice "$changes")'"
pmar="$(changes_meaning_version process-multi-agent-roles "$changes")"
case "$pmar" in
  "" | 1) : ;;
  *) fail "S239/AC4 — process-multi-agent-roles must NOT move in this slice (its bump belongs to the guard slice), got version '$pmar'" ;;
esac

# ===== the process-model-choice entry =======================================
entry="$(awk -v id="process-model-choice" '
  $0 == "## " id { inside = 1; next }
  inside && /^## / { exit }
  inside { print }
' "$changes")"
[ -n "$entry" ] || { fail "S239 — no CHANGES.md entry for process-model-choice"; test_done; }
tmp_entry="$(mktemp)"
tmp_yes="$(mktemp)"
trap 'rm -f "$tmp_entry" "$tmp_yes"; sandbox_destroy' EXIT
printf '%s\n' "$entry" > "$tmp_entry"
awk '/^- \*\*Yes means:\*\*/ { f = 1 } f && /^- \*\*/ && !/^- \*\*Yes means:\*\*/ { exit } f { print }' "$tmp_entry" | LC_ALL=C tr '\n' ' ' | LC_ALL=C tr -s ' ' > "$tmp_yes"
[ -s "$tmp_yes" ] || fail "S239 — the process-model-choice entry has no '- **Yes means:**' field"

grep -qE '\*\*Meaning version:\*\*[[:space:]]*2' <<<"$entry" || fail "S239/AC4 — the Meaning version field does not start with 2"
grep -q '#424' <<<"$entry" || fail "S239/AC4 — the entry does not cite #424 (why the version moved)"
grep -q '#413' <<<"$entry" || fail "S239/AC4 — the entry does not cite #413 (effort removed)"
grep -qiE 'effort is no longer recorded|no longer records? (an )?effort' <<<"$entry" \
  || fail "S239/AC4 — the Meaning version note must say that effort is no longer recorded"
para_has_all "$tmp_yes" 'floor' 'judged on the model' 'effort' 'neither chosen nor checked' \
  || fail "S239/AC4 — 'Yes means' must say the floor is judged on the model and effort is neither chosen nor checked"
para_has_all "$tmp_yes" 'when the dispatch tool gains an effort parameter' \
  || fail "S239/AC4 — 'Yes means' must carry the revisit trigger: when the dispatch tool gains an effort parameter"
if grep -qiE 'model/effort|model and effort|effort combination' "$tmp_yes"; then
  fail "S239/AC4 — 'Yes means' still asks for a model/effort per stage: $(cut -c1-200 "$tmp_yes")"
fi
para_has_all "$tmp_yes" 'records? which model' \
  || fail "S239/AC4 — 'Yes means' must still say every stage records which model was used"
para_has_all "$tmp_yes" 'same model' 'lower effort' '(meets|clears) the floor' 'accepted risk' \
  || fail "S239/AC7 — 'Yes means' must state the accepted limit: the same model at a lower effort meets the floor"
# the unchanged parts of the rule
for must in 'own demands' 'qualitatively' 'cheapest'; do
  grep -qiF -- "$must" "$tmp_yes" || fail "S239/AC4 — the rest of 'Yes means' must be unchanged: '$must' is gone"
done
grep -qE '\*\*Reaches session:\*\*.*gate: *skills/pre-merge-review/model-record-gate\.sh' <<<"$entry" \
  || fail "S239/AC4 — Reaches session must still name the model-record gate"

# ===== this repo's own adoption rows re-confirm at the new versions ===========
row_pmc="$(grep -E '^\| *process-model-choice *\|' "$adoption")"
[ -n "$row_pmc" ] || fail "S239/AC4 — WORKFLOW-ADOPTION.md has no process-model-choice row"
last="$(printf '%s' "$row_pmc" | grep -oE '\(meaning v[0-9]+\)' | tail -1)"
[ "$last" = "(meaning v2)" ] || fail "S239/AC4 — this repo's own process-model-choice row must end with (meaning v2), got '${last:-none}'"
case "$row_pmc" in *"#424"*) : ;; *) fail "S239/AC4 — the re-confirmed process-model-choice row must say why (cite #424)" ;; esac
row_qrbm="$(grep -E '^\| *quality-review-before-merge *\|' "$adoption")"
last="$(printf '%s' "$row_qrbm" | grep -oE '\(meaning v[0-9]+\)' | tail -1)"
[ "$last" = "(meaning v4)" ] || fail "S239/AC4 — this repo's own quality-review-before-merge row must end with (meaning v4), got '${last:-none}'"
# the multi-agent row is not touched in this slice
row_pmar="$(grep -E '^\| *process-multi-agent-roles *\|' "$adoption")"
! grep -qE '\(meaning v2\)' <<<"$row_pmar" || fail "S239/AC4 — process-multi-agent-roles must not be re-confirmed at v2 in this slice"

# ===== adopters answered under the old version are re-surfaced ================
resurface() { # label, notes, expect-substring-or-QUIET
  local label="$1" notes="$2" want="$3" project out
  project="$(fresh_project "$label")"
  git -C "$project" commit -q --allow-empty -m start
  cat > "$project/WORKFLOW-ADOPTION.md" <<EOF2
# Adoption of shared workflow changes

| Change | Answer | Date | Notes |
|---|---|---|---|
| process-model-choice | yes | 2026-09-16 | $notes |
EOF2
  out="$("$TEST_REPO_ROOT/pending-changes.sh" "$project" 2>&1)"
  # only the lines about this row, so a failure message stays short
  out="$(grep -E 'process-model-choice|meaning has changed' <<<"$out" || true)"
  if [ "$want" = QUIET ]; then
    case "$out" in
      *"process-model-choice"*) fail "S239 $label — a row re-confirmed at (meaning v2) must stay quiet, got: $out" ;;
    esac
  else
    case "$out" in
      *"process-model-choice"*"$want"*) : ;;
      *) fail "S239 $label — expected a re-surfacing notice containing '$want', got: $out" ;;
    esac
    case "$out" in
      *"meaning has changed"*) : ;;
      *) fail "S239 $label — the row must be in the 'meaning has changed' block, got: $out" ;;
    esac
    if grep -qE '^  - process-model-choice — Does this project apply' <<<"$out"; then
      fail "S239 $label — a re-surfaced row wrongly appeared in the never-answered list"
    fi
  fi
}
resurface answered-v1 "answered under the first text" "answered under meaning v1, now v2"
resurface answered-v1-marked "re-confirmed (meaning v1)" "answered under meaning v1, now v2"
resurface reconfirmed-v2 "re-confirmed for #424 (meaning v2)" QUIET

test_done
