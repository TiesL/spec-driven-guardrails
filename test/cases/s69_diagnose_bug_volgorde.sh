#!/usr/bin/env bash
# S69 — `diagnose-bug` describes the mandatory order.
# Dekt: F10

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

skill="$TEST_REPO_ROOT/skills/diagnose-bug/SKILL.md"

[ -f "$skill" ] || { fail "S69 — skills/diagnose-bug/SKILL.md is missing"; test_klaar; }

inhoud="$(cat "$skill")"

assert_contains "S69 — mentions reproduction" "eproducti" "$inhoud"
assert_contains "S69 — mentions hypotheses" "ypothes" "$inhoud"
assert_contains "S69 — mentions regression test" "egression test" "$inhoud"
assert_contains "S69 — mentions the fix as the last step" "Fix" "$inhoud"

# The order itself, based on the numbered steps — not based on loose
# keywords, since the description in the frontmatter already names all three
# terms on one line, before the numbered steps themselves begin.
pos_repro="$(grep -n '^\*\*1\. Reproduction' "$skill" | head -1 | cut -d: -f1)"
pos_hyp="$(grep -n '^\*\*2\. Hypotheses' "$skill" | head -1 | cut -d: -f1)"
pos_regr="$(grep -n '^\*\*3\. Regression test' "$skill" | head -1 | cut -d: -f1)"
pos_fix="$(grep -n '^\*\*4\. Fix' "$skill" | head -1 | cut -d: -f1)"

if ! { [ -n "$pos_repro" ] && [ -n "$pos_hyp" ] && [ -n "$pos_regr" ] && [ -n "$pos_fix" ] \
     && [ "$pos_repro" -lt "$pos_hyp" ] && [ "$pos_hyp" -lt "$pos_regr" ] \
     && [ "$pos_regr" -lt "$pos_fix" ]; }; then
  fail "S69 — the order reproduction -> hypotheses -> regression test -> fix does not appear that way in the file"
fi

# Hypotheses are shown before they are tested.
assert_contains "S69 — hypotheses are shown before they are tested" "shown before" "$inhoud"

test_klaar
