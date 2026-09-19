#!/usr/bin/env bash
# S140 — pre-merge-review's SKILL.md documents running pending-changes.sh
# as a PR-time finding, not only a SessionStart notice (#240 AC1).
# Covers: F10
#
# Found via #238 (portfolio-mgt-agents): pending-changes.sh only ran from
# SessionStart, a single notice easy to scroll past — 8 applicable rows
# sat unanswered across two merged PRs with nothing surfacing it at PR time.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

skill="$TEST_REPO_ROOT/skills/pre-merge-review/SKILL.md"
content="$(cat "$skill")"

assert_contains "S140 — SKILL.md documents the pending adoption gate" "Pending adoption gate" "$content"
assert_contains "S140 — SKILL.md tells the reviewer to run pending-changes.sh" "pending-changes.sh" "$content"

test_done
