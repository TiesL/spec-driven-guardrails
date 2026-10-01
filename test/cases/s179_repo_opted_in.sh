#!/usr/bin/env bash
# S179 — This repo answers process-multi-agent-roles yes and gets the
# orchestrator rules at session start like any other opted-in project.
# Covers: F37
#
# Issue #371, AC2 (and human decision 2). Seam: this repo's own
# WORKFLOW-ADOPTION.md and session-context.sh run against this repo's own
# tree; no repo-specific special case, so the same script and the same
# shared rule as for an adopter.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"
# shellcheck source=../../lib/changes.sh disable=SC1091
. "$TEST_REPO_ROOT/lib/changes.sh"

sandbox_create
trap sandbox_destroy EXIT

id="process-multi-agent-roles"

if ! type answered_yes >/dev/null 2>&1; then
  fail "S179 — lib/changes.sh defines no answered_yes function"
  test_done
fi
answered_yes "$TEST_REPO_ROOT" "$id" \
  || fail "S179 — this repo's WORKFLOW-ADOPTION.md does not answer $id yes"

# A real answer, not the provisional stamp.
row="$(grep "^| *$id *|" "$TEST_REPO_ROOT/WORKFLOW-ADOPTION.md" | head -1)"
case "$row" in
  *"requires substantiation"*|*"vereist onderbouwing"*)
    fail "S179 — the row is still the provisional stamp, not a reasoned answer" ;;
esac

orch="$TEST_REPO_ROOT/skills/role-contracts/ORCHESTRATOR.md"
if [ ! -x "$TEST_REPO_ROOT/session-context.sh" ] || [ ! -f "$orch" ]; then
  fail "S179 — session-context.sh or skills/role-contracts/ORCHESTRATOR.md is missing"
  test_done
fi

out="$("$TEST_REPO_ROOT/session-context.sh" "$TEST_REPO_ROOT" 2>/dev/null)"
output_has_all_lines "$orch" "$out" \
  || fail "S179 — session-context.sh on this repo does not print all of ORCHESTRATOR.md"

# No special case: the same script prints nothing for a project that says no.
p="$(fresh_project other)"
write_adoption "$p/WORKFLOW-ADOPTION.md" "$id" no
out="$("$TEST_REPO_ROOT/session-context.sh" "$p" 2>/dev/null)"
output_has_any_line "$orch" "$out" && fail "S179 — a project answering no got the orchestrator text"

test_done
