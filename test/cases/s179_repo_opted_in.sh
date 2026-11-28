#!/usr/bin/env bash
# S179 — This repo answers process-multi-agent-roles yes and gets the
# orchestrator core like any other opted-in project.
# Covers: F38
#
# Issue #371, AC2 (and human decision 2); amended by #750 (A66 D1, D2): the
# core arrives through the always-loaded link the S732 installer makes, not
# through session-context.sh. Seam: this repo's own WORKFLOW-ADOPTION.md;
# adopt.sh run on a sandbox copy of this repo with itself as source and
# target (the S81 self-adoption); session-context.sh on that copy and on a
# project answering no. No repo-specific special case.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"
# shellcheck source=../fixtures/core-delivery-750.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/core-delivery-750.sh"
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

# Self-adoption of a sandbox copy (S81 pattern): the copy's own answer is
# the real row, and the installer links the copy's own ORCHESTRATOR.md.
repo="$(sandbox_copy_repo self)"
# A link the real checkout may already carry points outside the sandbox.
rm -f "$repo/$CORE750_LINK"
git -C "$repo" init -q -b main
git -C "$repo" -c user.name=test -c user.email=test@example.invalid \
  commit -q --allow-empty -m "first commit"
orch="$repo/$CORE750_ORCH_REL"
if [ ! -x "$repo/session-context.sh" ] || [ ! -f "$orch" ]; then
  fail "S179 — session-context.sh or $CORE750_ORCH_REL is missing"
  test_done
fi
core750_adopt "$repo" "$repo" || fail "S179 — self-adoption failed: $(tail -n 3 "$SANDBOX/adopt.out")"
link="$repo/$CORE750_LINK"
if [ ! -L "$link" ]; then
  fail "S179 — self-adoption made no $CORE750_LINK symlink"
else
  [ "$(core750_physical "$link")" = "$(core750_physical "$orch")" ] \
    || fail "S179 — $CORE750_LINK resolves to '$(core750_physical "$link")', not this repo's own ORCHESTRATOR.md"
  cmp -s "$link" "$orch" || fail "S179 — the linked bytes differ from ORCHESTRATOR.md"
fi

# session-context.sh prints none of the core, on this repo and for a no.
out="$("$repo/session-context.sh" "$repo" 2>/dev/null)"
output_has_any_line "$orch" "$out" \
  && fail "S179 — session-context.sh on this repo prints ORCHESTRATOR.md text"
p="$(fresh_project other)"
write_adoption "$p/WORKFLOW-ADOPTION.md" "$id" no
out="$("$repo/session-context.sh" "$p" 2>/dev/null)"
output_has_any_line "$orch" "$out" && fail "S179 — a project answering no got the orchestrator text"

test_done
