#!/usr/bin/env bash
# S218 — the self-check lines, the stated limit and the override pointer to #415.
# Covers: F42
#
# Issue #410, AC5 and AC6 (Architect A28; the override record and risk note
# are #415's, A29); amended by #499 AC14 (A41): the self-check and override
# rules are located by ID. OR24-OR27 are the four sub-items of OR23's item,
# in part 2, tier core; OR25's sub-item names review-rounds.sh and the
# project's checkout as the working directory (plumbing); OR21 (override)
# starts one item in part 2 with tier judgment, names OR45 by ID and names
# SKILL.md for the risk-note format; absence checks kept: OR21 defines no
# risk-note field list and no marker of its own. The override behaviour
# moved to OB24 and OB25. OR24-OR27 have no behaviour scenario (A41's
# accepted gap: a flipped `not` in a self-check item is caught only by
# review).

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/orchestrator-core-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/orchestrator-core-helpers.sh"

for id in OR24 OR25 OR26 OR27; do
  oc_rule "S218/$id self-check item" "$id" core 2 1
done
order="$(python3 -I "$OC_PY" items --orch "$OC_ORCH" | cut -f1 | tr '\n' ' ')"
case "$order" in
  *"OR23 OR24 OR25 OR26 OR27 "*) ;;
  *) fail "S218 — OR24-OR27 are not the four sub-items of OR23" ;;
esac
or25="$(oc_item OR25)"
grep -q 'review-rounds\.sh' <<<"$or25" || fail "S218/cwd — OR25 does not name review-rounds.sh"
grep -qE "working directory = project.s checkout|project.s checkout as (the )?working directory" <<<"$or25" \
  || fail "S218/cwd — OR25 does not say review-rounds.sh runs with the project's checkout as the working directory"

oc_rule "S218/OR21 override" OR21 judgment 2
or21="$(oc_item OR21)"
grep -qw 'OR45' <<<"$or21" || fail "S218/pointer — OR21 does not name OR45"
grep -q 'SKILL\.md' <<<"$or21" || fail "S218/pointer — OR21 does not name SKILL.md for the risk-note format"
if grep -qiE '(fields?|sections?|template|headings?)[^.]*:' <<<"$or21"; then
  fail "S218/no-own-format — OR21 defines a risk-note field list; the format is #415's"
fi
if grep -q '<!--' <<<"$or21"; then
  fail "S218/no-own-format — OR21 introduces a marker of its own"
fi
if grep -qiE 'loop-?back[^<]*<!--|<!--[^>]*(loop-?back|design-override)' "$OC_ORCH"; then
  fail "S218/no-own-format — ORCHESTRATOR.md introduces a marker for a loop-back override"
fi

test_done
