#!/usr/bin/env bash
# S135 — CHANGES.md states the CI-enforcement policy for a genuinely
# code-less project (#245): "no — not yet", not "yes", when there's
# nothing to gate in the first place.
# Covers: F9
#
# Found via #238: both PRs in portfolio-mgt-agents merged 17-22 seconds
# after review with zero CI in existence — ci-gate-on-merge read "yes" in
# a repo where it structurally could not fire, with no written policy
# saying that answer was wrong for that state.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

changes="$TEST_REPO_ROOT/CHANGES.md"
content="$(cat "$changes")"

assert_contains "S135 — CHANGES.md documents the code-less policy" "genuinely code-less project" "$content"
assert_contains "S135 — the policy names the correct answer" "not yet" "$content"
assert_contains "S135 — the policy points at the mechanical backstop" "adoption-postcondition-gate.sh" "$content"

test_done
