#!/usr/bin/env bash
# S191 — quality-review-before-merge is at meaning version 3 with the new
# floor, and the specs, registry row and architecture follow.
# Covers: F9, F39
#
# Issue #392, R4/R6, AC7/AC10, A24/A25. Seam: the CHANGES.md entry and the
# documents themselves, read as text; the adopter-facing re-surfacing is
# S141 (v1 and v2 answers re-surface, v3 is quiet) and the snapshot sync is
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
[ "$version" = "3" ] || fail "S191/AC7 — $id must be at Meaning version 3, got '${version:-<empty>}'"

entry="$(awk -v id="$id" '
  $0 == "## " id { inside = 1; next }
  inside && /^## / { exit }
  inside { print }
' "$changes")"
[ -n "$entry" ] || { fail "S191 — no CHANGES.md entry for $id"; test_done; }

tmp_entry="$(mktemp)"
trap 'rm -f "$tmp_entry"' EXIT
printf '%s\n' "$entry" > "$tmp_entry"

# the Meaning version note says why (#392) and what the adopter does
grep -qE '\*\*Meaning version:\*\*[[:space:]]*3' <<<"$entry" || fail "S191/AC7 — the Meaning version field does not start with 3"
grep -q '#392' <<<"$entry" || fail "S191/AC7 — the entry does not cite #392 (why the version moved)"
para_has_all "$tmp_entry" 'at least as capable' 'effort' 'floor-basis' 'Implementation' \
  || fail "S191/AC7 — 'Yes means' must state the floor: at least as capable as Implementation, model and effort, with a floor-basis"
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

# --- this repo's own adoption row is re-confirmed at v3 ---------------------
row="$(grep -E "^\| *$id *\|" "$TEST_REPO_ROOT/WORKFLOW-ADOPTION.md")"
[ -n "$row" ] || fail "S191/AC10 — WORKFLOW-ADOPTION.md has no $id row"
last="$(printf '%s' "$row" | grep -oE '\(meaning v[0-9]+\)' | tail -1)"
[ "$last" = "(meaning v3)" ] || fail "S191/AC10 — this repo's own $id row must end with (meaning v3), got '${last:-none}'"

# --- AC10: specs follow -------------------------------------------------------
arch="$TEST_REPO_ROOT/ARCHITECTURE.md"
grep -qE '^### A24( |$)' "$arch" || fail "S191/AC10 — ARCHITECTURE.md has no ### A24 entry (the Review floor and floor-basis)"
grep -qE '^### A25( |$)' "$arch" || fail "S191/AC10 — ARCHITECTURE.md has no ### A25 entry (effort scale, lib/model-record.sh)"
a24="$(awk '/^### A24( |$)/ { f = 1; next } f && /^### / { exit } f { print }' "$arch")"
a25="$(awk '/^### A25( |$)/ { f = 1; next } f && /^### / { exit } f { print }' "$arch")"
grep -q 'floor-basis' <<<"$a24" || fail "S191/AC10 — A24 does not describe floor-basis"
grep -q 'lib/model-record.sh' <<<"$a25" || fail "S191/AC10 — A25 does not name lib/model-record.sh"
grep -qE 'low *< *medium *< *high' <<<"$a25" || fail "S191/AC10 — A25 does not state the effort scale low < medium < high"

# the short-alias false pass is recorded as technical debt (human decision 4)
debt="$(awk '/^## Technical debt/ { f = 1; next } f && /^## / { exit } f { print }' "$TEST_REPO_ROOT/PRD.md")"
alias_rows="$(grep -iE 'alias' <<<"$debt")"
grep -qE '#392|model-record' <<<"$alias_rows" \
  || fail "S191/AC10 — PRD.md's Technical debt register has no row on short model aliases (opus vs claude-opus-5 count as different, effort check skipped)"

# the lib exists (the shared module A25 introduces)
[ -f "$TEST_REPO_ROOT/lib/model-record.sh" ] || fail "S191/AC10 — lib/model-record.sh does not exist"

test_done
