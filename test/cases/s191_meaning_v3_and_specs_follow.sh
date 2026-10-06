#!/usr/bin/env bash
# S191 — quality-review-before-merge is at meaning version 4 (the floor is on
# the model alone, #424), and the specs, registry row and architecture follow.
# (The file keeps its v3 name: the #392 floor-basis rules it pins are unchanged;
# #424 moved the version and removed effort from the floor. The process-model-choice
# equivalent is S239.)
# Covers: F9, F39
#
# Issue #392, R4/R6, AC7/AC10, A24/A25. Seam: the CHANGES.md entry and the
# documents themselves, read as text; the adopter-facing re-surfacing is
# S141 (v1, v2 and v3 answers re-surface, v4 is quiet) and the snapshot sync is
# S90. Not asserted: that `./check` as a whole passes (the Developer runs it).

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
id="quality-review-before-merge"

# --- AC7: the entry --------------------------------------------------------
version="$(changes_meaning_version "$id" "$changes")"
[ "$version" = "4" ] || fail "S191/AC7 — $id must be at Meaning version 4 (#424: the floor is on the model alone), got '${version:-<empty>}'"

entry="$(awk -v id="$id" '
  $0 == "## " id { inside = 1; next }
  inside && /^## / { exit }
  inside { print }
' "$changes")"
[ -n "$entry" ] || { fail "S191 — no CHANGES.md entry for $id"; test_done; }

tmp_entry="$(mktemp)"
tmp_yes="$(mktemp)"
trap 'rm -f "$tmp_entry" "$tmp_yes"' EXIT
printf '%s\n' "$entry" > "$tmp_entry"
# the "Yes means" field alone (to the next "- **" field), as one paragraph
awk '/^- \*\*Yes means:\*\*/ { f = 1 } f && /^- \*\*/ && !/^- \*\*Yes means:\*\*/ { exit } f { print }' "$tmp_entry" | LC_ALL=C tr '\n' ' ' | LC_ALL=C tr -s ' ' > "$tmp_yes"
[ -s "$tmp_yes" ] || fail "S191 — the $id entry has no '- **Yes means:**' field"

# the Meaning version note says why (#392) and what the adopter does
grep -qE '\*\*Meaning version:\*\*[[:space:]]*4' <<<"$entry" || fail "S191/AC7 — the Meaning version field does not start with 4"
grep -q '#392' <<<"$entry" || fail "S191/AC7 — the entry does not cite #392 (why the version moved to 3, kept as history)"
grep -q '#424' <<<"$entry" || fail "S191/AC7 — the entry does not cite #424 (why the version moved to 4)"
grep -q '#413' <<<"$entry" || fail "S191/AC7 — the entry does not cite #413 (effort removed)"
para_has_all "$tmp_entry" 'at least as capable' 'floor-basis' 'Implementation' \
  || fail "S191/AC7 — 'Yes means' must state the floor: at least as capable as Implementation, with a floor-basis"
# #424 AC4: the floor is judged on the model, effort is neither chosen nor checked
para_has_all "$tmp_yes" 'floor' 'judged on the model' 'effort' 'neither chosen nor checked' \
  || fail "S191/AC4 — 'Yes means' must say the floor is judged on the model and effort is neither chosen nor checked"
if para_has_all "$tmp_yes" 'at least as capable' 'model and effort'; then
  fail "S191/AC4 — 'Yes means' still pairs the model with effort (the v3 wording)"
fi
if grep -qiE 'flags a same-model review at[[:space:]]+lower effort|same model at[[:space:]]+lower Review effort is a finding' <<<"$(tr '\n' ' ' < "$tmp_yes")"; then
  fail "S191/AC4 — 'Yes means' still says a lower same-model effort is a finding"
fi
# the revisit trigger (A33a) and the accepted limit (AC7)
para_has_all "$tmp_yes" 'when the dispatch tool gains an effort parameter' \
  || fail "S191/AC4 — 'Yes means' must carry the revisit trigger: when the dispatch tool gains an effort parameter"
para_has_all "$tmp_yes" 'same model' 'lower effort' '(meets|clears) the floor' 'neither chosen nor checked' 'accepted risk' \
  || fail "S191/AC7 — 'Yes means' must say the same model at a lower effort meets the floor because effort is neither chosen nor checked (an accepted risk)"
para_has_all "$tmp_entry" 'different model' '(not|n.t|no longer)[^.]*(required|needed)' \
  || fail "S191/AC7 — 'Yes means' must say a different model is NOT required"
if grep -qE 'same-model-exception' <<<"$entry"; then
  grep -qiE 'legacy|retired|ignored|replaced' <<<"$entry" \
    || fail "S191/AC7 — the entry mentions same-model-exception without saying it is retired/ignored"
fi
grep -qE 'unchanged|ranks? two different models|can.t rank|cannot rank|not machine-checked|judgment' <<<"$entry" \
  || fail "S191/AC7 — the entry should say what the gate cannot check (two different models stay the Reviewer's judgment)"
# the gate is now where the rule reaches a session
grep -qE '\*\*Reaches session:\*\*.*gate: *skills/pre-merge-review/model-record-gate\.sh' <<<"$entry" \
  || fail "S191/AC7 — Reaches session must name gate: skills/pre-merge-review/model-record-gate.sh (A24)"
# unchanged parts of the rule
for must in 'fresh context' 'complexity' 'dependencies' 'spec-' 'Findings go into the PR'; do
  grep -qiF -- "$must" <<<"$entry" || fail "S191/AC7 — the rest of the entry must be unchanged: '$must' is gone"
done

# --- this repo's own adoption row is re-confirmed at v4 ---------------------
row="$(grep -E "^\| *$id *\|" "$TEST_REPO_ROOT/WORKFLOW-ADOPTION.md")"
[ -n "$row" ] || fail "S191/AC10 — WORKFLOW-ADOPTION.md has no $id row"
last="$(printf '%s' "$row" | grep -oE '\(meaning v[0-9]+\)' | tail -1)"
[ "$last" = "(meaning v4)" ] || fail "S191/AC4 — this repo's own $id row must end with (meaning v4), got '${last:-none}'"
case "$row" in
  *"#424"*) : ;;
  *) fail "S191/AC4 — the re-confirmed row must say why (cite #424)" ;;
esac

# --- AC10: specs follow -------------------------------------------------------
arch="$TEST_REPO_ROOT/ARCHITECTURE.md"
grep -qE '^### A24( |$)' "$arch" || fail "S191/AC10 — ARCHITECTURE.md has no ### A24 entry (the Review floor and floor-basis)"
grep -qE '^### A25( |$)' "$arch" || fail "S191/AC10 — ARCHITECTURE.md has no ### A25 entry (effort scale, lib/model-record.sh)"
a24="$(awk '/^### A24( |$)/ { f = 1; next } f && /^### / { exit } f { print }' "$arch")"
a25="$(awk '/^### A25( |$)/ { f = 1; next } f && /^### / { exit } f { print }' "$arch")"
grep -q 'floor-basis' <<<"$a24" || fail "S191/AC10 — A24 does not describe floor-basis"
grep -q 'lib/model-record.sh' <<<"$a25" || fail "S191/AC10 — A25 does not name lib/model-record.sh"
grep -qE 'low *< *medium *< *high' <<<"$a25" || fail "S191/AC10 — A25 does not state the effort scale low < medium < high (kept as history)"
# #424: A25 is marked superseded and A33 is added
grep -qiE 'superseded' <<<"$a25" || fail "S191/#424 — A25 must be marked superseded (effort left the floor)"
grep -qE '^### A33( |$)' "$arch" || fail "S191/#424 — ARCHITECTURE.md has no ### A33 entry (the emitter without effort, the model-only floor)"
a33="$(awk '/^### A33( |$)/ { f = 1; next } f && /^### / { exit } f { print }' "$arch")"
grep -q 'neither chosen nor checked' <<<"$a33" || fail "S191/#424 — A33 must state the limit: effort is neither chosen nor checked"
grep -q 'when the dispatch tool gains an effort parameter' <<<"$a33" || fail "S191/#424 — A33 must carry the revisit trigger"

# the short-alias false pass is recorded as technical debt (human decision 4)
debt="$(awk '/^## Technical debt/ { f = 1; next } f && /^## / { exit } f { print }' "$TEST_REPO_ROOT/PRD.md")"
alias_rows="$(grep -iE 'alias' <<<"$debt")"
grep -qE '#392|model-record' <<<"$alias_rows" \
  || fail "S191/AC10 — PRD.md's Technical debt register has no row on short model aliases (opus vs claude-opus-5 count as different, effort check skipped)"

# the lib exists (the shared module A25 introduces)
[ -f "$TEST_REPO_ROOT/lib/model-record.sh" ] || fail "S191/AC10 — lib/model-record.sh does not exist"

test_done
