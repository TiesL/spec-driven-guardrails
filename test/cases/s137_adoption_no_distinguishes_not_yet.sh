#!/usr/bin/env bash
# S137 — The seeded WORKFLOW-ADOPTION.md explains that "no" covers two
# distinct cases: a permanent decline, and "not yet — applicable, but the
# precondition doesn't hold" (with a concrete trigger to revisit, same
# shape as PRD.md's Technical debt table).
# Covers: F9
#
# Found via #239 (AC3): a repo without this distinction has only yes/no to
# pick from, and an agent facing "this applies, but nothing exists yet"
# reaches for yes instead — inflating adopted scope with unfilled
# scaffolding (portfolio-mgt-agents, review finding 7). The fix isn't a
# third parser-level value: answered() in pending-changes.sh already
# treats any row's existence as answered regardless of its text (see that
# file's own comments), so free text already carries this distinction —
# the gap was that nothing ever told an agent to write it that way.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(fresh_project new-project)"
git -C "$project" commit -q --allow-empty -m start

adopt "$project"

header="$(cat "$project/WORKFLOW-ADOPTION.md")"

case "$header" in
  *"not yet"*"trigger"*) : ;;
  *) fail "S137 — expected the seeded header to distinguish a permanent 'no' from a 'not yet' with a revisit trigger. Got:
$header" ;;
esac

# Found during PR #259's pre-merge-review: the scenario's own Then clause
# claims this distinction is documented in three places, but until now
# only the seeded header was actually asserted on.
own_adoption="$(cat "$TEST_REPO_ROOT/WORKFLOW-ADOPTION.md")"
case "$own_adoption" in
  *"not yet"*"trigger"*) : ;;
  *) fail "S137 — expected this repo's own WORKFLOW-ADOPTION.md to carry the same distinction" ;;
esac

registry_skill="$(cat "$TEST_REPO_ROOT/skills/adoption-registry/SKILL.md")"
case "$registry_skill" in
  *"not yet"*"trigger"*) : ;;
  *) fail "S137 — expected the adoption-registry skill to document the same distinction" ;;
esac

test_done
