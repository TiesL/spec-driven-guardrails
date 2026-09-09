#!/usr/bin/env bash
# S69 — `diagnose-bug` beschrijft de dwingende volgorde.
# Dekt: F10

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

skill="$TEST_REPO_ROOT/skills/diagnose-bug/SKILL.md"

[ -f "$skill" ] || { fail "S69 — skills/diagnose-bug/SKILL.md ontbreekt"; test_klaar; }

inhoud="$(cat "$skill")"

assert_contains "S69 — noemt reproductie" "eproducti" "$inhoud"
assert_contains "S69 — noemt hypotheses" "ypothes" "$inhoud"
assert_contains "S69 — noemt regressietest" "egression test" "$inhoud"
assert_contains "S69 — noemt de fix als laatste stap" "Fix" "$inhoud"

# De volgorde zelf, aan de hand van de genummerde stappen — niet aan de hand
# van losse trefwoorden, want de description in de frontmatter noemt alle drie
# de termen al op één regel, vóór de genummerde stappen zelf beginnen.
pos_repro="$(grep -n '^\*\*1\. Reproduction' "$skill" | head -1 | cut -d: -f1)"
pos_hyp="$(grep -n '^\*\*2\. Hypotheses' "$skill" | head -1 | cut -d: -f1)"
pos_regr="$(grep -n '^\*\*3\. Regression test' "$skill" | head -1 | cut -d: -f1)"
pos_fix="$(grep -n '^\*\*4\. Fix' "$skill" | head -1 | cut -d: -f1)"

if ! { [ -n "$pos_repro" ] && [ -n "$pos_hyp" ] && [ -n "$pos_regr" ] && [ -n "$pos_fix" ] \
     && [ "$pos_repro" -lt "$pos_hyp" ] && [ "$pos_hyp" -lt "$pos_regr" ] \
     && [ "$pos_regr" -lt "$pos_fix" ]; }; then
  fail "S69 — de volgorde reproductie -> hypotheses -> regressietest -> fix staat niet zo in het bestand"
fi

# Hypotheses worden getoond vóór ze getest worden.
assert_contains "S69 — hypotheses worden getoond vóór ze getest worden" "shown before" "$inhoud"

test_klaar
