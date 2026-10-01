#!/usr/bin/env bash
# S172 — the docs describe the new commit-time split and no longer say pre-commit runs the suite (#378, AC10, R6).
# Covers: F17

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

r="$TEST_REPO_ROOT"

# The README no longer promises that a bad commit is caught before it reaches a branch.
if grep -q 'a bad commit is caught before it reaches a branch' "$r/README.md"; then
  fail "S172 — README still says a bad commit is caught before it reaches a branch"
fi
grep -q 'check-commit' "$r/README.md" || fail "S172 — README does not mention check-commit"

# The PRD's open debt about the untimed ./check call is retired, and F17 names the declared check.
if grep -q "pre-commit\`'s \`./check\` call (#263) has no timeout" "$r/PRD.md"; then
  fail "S172 — PRD still lists the pre-commit ./check no-timeout debt row"
fi
grep -q 'check-commit' "$r/PRD.md" || fail "S172 — PRD does not mention check-commit"

# CHANGELOG: an Unreleased line for #378 naming check-commit and the entry id.
unreleased="$(awk '/^## Unreleased/{f=1;next} /^## /{f=0} f' "$r/CHANGELOG.md")"
case "$unreleased" in *"#378"*"check-commit"*|*"check-commit"*"#378"*) : ;; *) fail "S172 — CHANGELOG Unreleased has no #378 line naming check-commit" ;; esac
case "$unreleased" in *"ci-commit-check"*) : ;; *) fail "S172 — CHANGELOG Unreleased does not point adopters at ci-commit-check" ;; esac

# check-convention names check-commit as a fixed command, and says CI calls only check.
grep -q 'check-commit' "$r/skills/check-convention/SKILL.md" || fail "S172 — check-convention does not define check-commit"

# TEST-SCENARIOS.md: the S144 section is the new one, and nothing says pre-commit runs the suite.
s144="$(awk '/^### S144 /{f=1;print;next} /^### /{f=0} f' "$r/TEST-SCENARIOS.md")"
case "$s144" in *"check-commit"*) : ;; *) fail "S172 — S144 does not describe check-commit" ;; esac
case "$s144" in *"blocking on a real failure"*"./check"*"green"*) fail "S172 — S144 still describes the old ./check-at-commit behaviour" ;; esac

# This repo ships the declaration itself.
[ -x "$r/check-commit" ] || fail "S172 — this repo has no executable check-commit"
grep -q 'no-tests' "$r/check-commit" 2>/dev/null || fail "S172 — check-commit does not run the static part (--no-tests) of check"

test_done
