#!/usr/bin/env bash
# S323 — the new rules hold under a real model, and the stamp is refreshed once after all edits (#532 AC1-AC6; A42; needs a paid run)
# Covers: F38
#
# The paid run itself is ./test/behavior/orchestrator-diff.sh (subscription, no
# spend approval), made once after every rule and scenario edit is final. This
# test is what ./check can say about it with no model call: the committed stamp
# matches ORCHESTRATOR.md plus the scenario file (so no edit came after the
# run), and the stamp's scenario count covers the A42 scenarios (OB52 onward),
# so a stamp from before the rewrite cannot pass.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

R="$TEST_REPO_ROOT"
PY="$R/test/behavior/orchestrator_diff.py"
SCEN="$R/test/behavior/orchestrator-scenarios.md"
STAMP="$R/test/behavior/orchestrator-diff.stamp"

[ -f "$STAMP" ] || { fail "S323 — no committed stamp"; test_done; }
grep -q '^### OB62 ' "$SCEN" || fail "S323 — the A42 scenarios (OB52-OB62) are not in the scenario file, so this stamp cannot cover them"
out="$(python3 -I "$PY" stamp-check --repo "$R" 2>&1)" || fail "S323 — stamp does not match the final ORCHESTRATOR.md and scenarios: $out"
count="$(grep -c '^### OB' "$SCEN")"
grep -Eq "^sha256=[0-9a-f]{64} base=[^ ]+ model=[^ ]+ scenarios=$count\$" "$STAMP" || fail "S323 — stamp format or scenarios=$count wrong: $(cat "$STAMP")"
base="$(sed 's/.* base=\([^ ]*\).*/\1/' "$STAMP")"
[ "$base" != "17a1b3d" ] || fail "S323 — the stamp still carries the #499 base 17a1b3d; the run for #532 has not been made"

test_done
