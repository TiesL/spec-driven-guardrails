#!/usr/bin/env bash
# S531 — no test, scenario or fixture names OR40 as the calibration mutant (#620)
# Covers: F38
#
# Seam: s291_low_rule_mutations.sh, decision-table-415.py, the S288 and S291
# sections of TEST-SCENARIOS.md and the A41 section of ARCHITECTURE.md outside
# the #620 amendment, read as text. The calibration mutant is OR43.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

R="$TEST_REPO_ROOT"

# offending <file> : prints the matching phrase, returns 0 when one is found.
# Comment markers and line breaks are removed first, so a phrase wrapped over
# a comment block still matches.
offending() {
  sed -e 's/^[[:space:]]*#//' "$1" | tr '\n' ' ' | sed -e 's/  */ /g' \
    | grep -oE "OR40['\`]? calibration|calibration[^.;]{0,100}OR40" | head -1
}

# Extract the sources into the sandbox.
S="$SANDBOX/src"; mkdir -p "$S"
cp "$R/test/cases/s291_low_rule_mutations.sh" "$S/s291.txt"
cp "$R/test/fixtures/decision-table-415.py" "$S/dt415.txt"
awk '/^### S288 /{p=1} /^### S289 /{p=0} p' "$R/TEST-SCENARIOS.md" >"$S/s288.txt"
awk '/^### S291 /{p=1} /^### S292 /{p=0} p' "$R/TEST-SCENARIOS.md" >"$S/s291sc.txt"
# A41 section minus the #620 amendment (from its bullet to the next ### heading).
awk '/^### A41 /{p=1;next} /^### A42 /{p=0} /^- \*\*#620 amendment/{skip=1} p && !skip' "$R/ARCHITECTURE.md" >"$S/a41.txt"
for f in s291 dt415 s288 s291sc a41; do
  [ -s "$S/$f.txt" ] || fail "S531 — could not extract the $f source"
done

for f in s291 dt415 s288 s291sc a41; do
  hit="$(offending "$S/$f.txt")"
  [ -z "$hit" ] || fail "S531 — $f names OR40 as the calibration mutant: '$hit'"
done

# Control: wording that names OR43 and mentions OR40 behavior elsewhere passes.
printf '%s\n' '# the calibration mutant is OR43. OR40 behavior is covered by OB40-OB44.' >"$S/ok.txt"
[ -z "$(offending "$S/ok.txt")" ] || fail "S531/control — the corrected wording was flagged"

# Mutants: one injected phrase per source, in each of the two forms, wrapped
# over a comment line break to prove the flattening.
for f in s291 dt415 s288 s291sc a41; do
  { cat "$S/$f.txt"; printf '# the differential run OR40\n# calibration mutant\n'; } >"$S/m1.txt"
  [ -n "$(offending "$S/m1.txt")" ] || fail "S531/mutant — '$f' with 'OR40 calibration' was not flagged"
  { cat "$S/$f.txt"; printf "the calibration mutant on\n  \`OR40\`\n"; } >"$S/m2.txt"
  [ -n "$(offending "$S/m2.txt")" ] || fail "S531/mutant — '$f' with 'calibration mutant on OR40' was not flagged"
done
test_done
