#!/usr/bin/env bash
# S604 — no tracked skill, test or scenario text calls a behavior run "paid" (#676 AC1-AC3)
# Covers: F38
#
# Seam: a tracked-file grep for the word over skills/, test/ and TEST-SCENARIOS.md.
# A hit is allowed only when it is a different sense of the word: GitHub's paid
# plan, "paid down" (debt), or a file named in ALLOWED. Historical A-entries in
# ARCHITECTURE.md are append-only and are not scanned. Scratch lines prove the
# filter keeps a behavior-run hit and drops the allowed senses.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

SELF="test/cases/s604_behavior_run_not_called_paid.sh"
ALLOWED='^(skills/refactoring-triggers/SKILL\.md|test/fixtures/adopter-docs-622\.py):'

hits() { # reads "path:line:text" lines on stdin, prints the ones that call a run paid
  grep -v -E "$ALLOWED" | grep -v -E -i 'paid[ -]plan|paid down'
}

found="$(cd "$TEST_REPO_ROOT" && git grep -n -i -w -e paid -- skills test TEST-SCENARIOS.md ":!$SELF" | hits)"
[ -z "$found" ] || fail "S604 — behavior-run wording still says the word (say behavior-test run or subscription usage):
$found"

# Controls (the word is assembled so this file never contains it as a token).
w="p""aid"
kept() { local out; out="$(hits <<< "$1")"; [ -n "$out" ]; }
kept "skills/x/SKILL.md:1:the $w behavior run" || fail "S604/control — a behavior-run hit was filtered out"
if kept "TEST-SCENARIOS.md:1:a $w plan limitation"; then fail "S604/control — GitHub plan sense was flagged"; fi
if kept "skills/refactoring-triggers/SKILL.md:1:can be $w down"; then fail "S604/control — refactoring-triggers sense was flagged"; fi

test_done
