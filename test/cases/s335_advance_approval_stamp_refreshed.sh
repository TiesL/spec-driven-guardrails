#!/usr/bin/env bash
# S335 — the advance-approval rule holds under a real model, and the stamp is refreshed once after all edits (#516 AC4-AC6; A43; needs a paid run)
# Covers: F55
#
# The paid run itself is ./test/behavior/orchestrator-diff.sh (subscription, no
# spend approval), made once after the OR11 text and scenarios are final. This
# test is what ./check can say about it with no model call: the committed stamp
# matches ORCHESTRATOR.md plus the scenario file (so no edit came after the
# run), its scenario count covers the #516 scenarios (OB64-OB72), and its base
# is not the #499/#532 stamp's base 1aba086.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

R="$TEST_REPO_ROOT"
PY="$R/test/behavior/orchestrator_diff.py"
SCEN="$R/test/behavior/orchestrator-scenarios.md"
STAMP="$R/test/behavior/orchestrator-diff.stamp"

[ -f "$STAMP" ] || { fail "S335 — no committed stamp"; test_done; }
grep -q '^### OB72 ' "$SCEN" || fail "S335 — the #516 scenarios (OB64-OB72) are not in the scenario file, so this stamp cannot cover them"
out="$(python3 -I "$PY" stamp-check --repo "$R" 2>&1)" || fail "S335 — stamp does not match the final ORCHESTRATOR.md and scenarios: $out"
count="$(grep -c '^### OB' "$SCEN")"
[ "$count" -ge 72 ] || fail "S335 — only $count scenarios; the #516 ones are missing"
grep -Eq "^sha256=[0-9a-f]{64} base=[^ ]+ model=[^ ]+ scenarios=$count\$" "$STAMP" || fail "S335 — stamp format or scenarios=$count wrong: $(cat "$STAMP")"
base="$(sed 's/.* base=\([^ ]*\).*/\1/' "$STAMP")"
[ "$base" != "1aba086" ] || fail "S335 — the stamp still carries the #532 base 1aba086; the run for #516 has not been made"

test_done
