#!/usr/bin/env bash
# S193 — model-choice and pre-merge-review state the Review floor one way
# and document the floor-basis attribute.
# Covers: F11
#
# Issue #392, R1/AC1/AC9, A24/A25 and human decisions 1-4. Seam: the two
# skills' text, read by paragraph (so an unrelated mention elsewhere cannot
# satisfy a statement). What the Reviewer then WRITES in floor-basis is
# judgment, not asserted; that the marker format documents it is.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"
# shellcheck source=../fixtures/review-floor-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-floor-helpers.sh"

mc="$TEST_REPO_ROOT/skills/model-choice/SKILL.md"
pmr="$TEST_REPO_ROOT/skills/pre-merge-review/SKILL.md"
for f in "$mc" "$pmr"; do
  [ -f "$f" ] || { fail "S193 — ${f#"$TEST_REPO_ROOT"/} is missing"; test_done; }
done

# --- model-choice -----------------------------------------------------------
# AC1: the Review row (a table row) states the floor as model AND effort
# together relative to Implementation, cheapest combination, no different-model
# requirement.
row="$(grep -E '^\| *Review *\|' "$mc" | head -1)"
[ -n "$row" ] || fail "S193/AC1 — model-choice has no Review row in its per-stage table"
grep -qiE 'at least as capable' <<<"$row" || fail "S193/AC1 — the Review row must say at least as capable as Implementation, got: $row"
grep -qiE 'effort' <<<"$row" || fail "S193/AC1 — the Review row must weigh effort too (model and effort together), got: $row"
grep -qiE 'implementation' <<<"$row" || fail "S193/AC1 — the Review row must anchor on Implementation, got: $row"
if grep -qiE 'different model (from|than)|genuinely different' <<<"$row"; then
  fail "S193/AC1 — the Review row still requires a different model: $row"
fi

# the #244 paragraph stays as history and says it was reversed
para_has_all "$mc" 'Resolved contradiction \(#244' '#392' '(revers|superseded|replaced)' \
  || fail "S193/AC1 — the 'Resolved contradiction (#244)' paragraph must be kept as history and say #392 reversed it"

# the marker format: every Review marker carries floor-basis; the legacy
# attribute is no longer part of the format
grep -qE 'stage=Review.*floor-basis="' "$mc" \
  || fail "S193/AC9 — model-choice's marker format does not show floor-basis on the Review marker"
if grep -qE 'stage=Review.*same-model-exception="<' "$mc"; then
  fail "S193/R3 — model-choice's marker format still offers same-model-exception"
fi
para_has_all "$mc" 'floor-basis' 'every Review' 'sentence|one line|free text' \
  || fail "S193/AC9 — model-choice must say floor-basis is required on every Review marker and is one sentence"
para_has_all "$mc" 'floor-basis' '(not|never|n.t) (verif|check|gate)' \
  || fail "S193/AC9 — model-choice must say the floor-basis text itself is not verified"

# what the gate checks and what it cannot
para_has_all "$mc" 'model-record-gate' 'effort' '(lower|below)' '(same|identical) model' \
  || fail "S193/AC3 — model-choice must say the gate flags a same-model Review at lower effort"
para_has_all "$mc" '(different|differ)' 'models?' '(no ordering|ordering|not machine.checked|cannot rank|can.t rank)' \
  || fail "S193/AC4 — model-choice must say two different models have no ordering a script can check"
para_has_all "$mc" 'effort' 'low' 'medium' 'high' 'unknown' \
  || fail "S193/A25 — model-choice must document the effort values low, medium, high and 'unknown'"
# human decision 4: the full id is documented, not required
para_has_all "$mc" '(full|complete) (model )?(id|identifier)' '(platform|reports)' \
  || fail "S193/decision4 — model-choice must document recording the full model id as the platform reports it"
para_has_all "$mc" 'alias' '(opus|short|abbreviat)' '(different|differ|not .*same)' \
  || fail "S193/decision4 — model-choice must say a short alias and the full id count as different models (effort check skipped)"

# --- pre-merge-review --------------------------------------------------------
para_has_all "$pmr" 'Review' 'at least as capable' 'effort' 'Implementation' \
  || fail "S193/AC1 — pre-merge-review's Model choice paragraph must state the floor: at least as capable as Implementation, model and effort"
if para_has_all "$pmr" 'different from' 'at least as skilled'; then
  fail "S193/AC1 — pre-merge-review still says 'different from, and at least as skilled as'"
fi
para_has_all "$pmr" 'floor-basis' 'Review' 'marker' \
  || fail "S193/AC9 — pre-merge-review does not document floor-basis on the Review marker"
para_has_all "$pmr" 'model-record-gate' 'floor-basis' '(missing|no|without)' \
  || fail "S193/AC9 — pre-merge-review must say the gate flags a Review marker without floor-basis"
para_has_all "$pmr" 'model-record-gate' 'effort' '(lower|below)' '(same|identical) model' \
  || fail "S193/AC3 — pre-merge-review must say the gate flags a same-model Review at lower effort"
para_has_all "$pmr" 'blind spot' 'model' \
  || fail "S193/AC1 — pre-merge-review's 'Its limits' must keep the correlated-blind-spots caveat"

test_done
