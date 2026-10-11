#!/usr/bin/env bash
# S265 — gate_meaning_and_docs; #427, independent CLI assertions (A31a/A34a/A37).
# Covers: F9, F26, F38, F39, F40
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
. "$TEST_REPO_ROOT/test/fixtures/gate-v2-helpers.sh"

. "$TEST_REPO_ROOT/lib/changes.sh"
section() { awk -v id="$2" '$0 == "## " id {f=1;next} f && /^## / {exit} f {print}' "$1"; }
changes="$TEST_REPO_ROOT/CHANGES.md"
[ "$(changes_meaning_version process-multi-agent-roles "$changes")" = 2 ] || fail 'multi-agent meaning must be v2'
[ "$(changes_meaning_version quality-review-before-merge "$changes")" = 4 ] || fail 'review meaning must remain v4'
[ "$(changes_meaning_version process-model-choice "$changes")" = 2 ] || fail 'model-choice meaning must remain v2'
v2_out="$(section "$changes" process-multi-agent-roles)"; has 'inline-only'; has '<'; has '>'
v2_out="$(section "$changes" quality-review-before-merge)"; has 'column 0'; has 'control'; has '"'; has '<'; has '>'
v2_out="$(grep '^| process-multi-agent-roles ' "$TEST_REPO_ROOT/WORKFLOW-ADOPTION.md")"; has '(meaning v2)'; has '#427'
v2_out="$(sed -n '/\*\*Marker grammar\.\*\*/,/^## /p' "$TEST_REPO_ROOT/skills/model-choice/SKILL.md")"; has 'A31'; has 'rec_scan_bundle'; has 'rec_field'; has 'latest'; has 'near-miss'
v2_out="$(sed -n '/^### A18 /,/^### /p' "$TEST_REPO_ROOT/ARCHITECTURE.md")"; has 'column 0'; has 'control'; has '<'; has '>'
for version in implicit v1 v2; do
 p="$(fresh_project "$version")"; note='original answer'; [ "$version" = implicit ] || note="reconfirmed (meaning $version)"
 write_adoption "$p/WORKFLOW-ADOPTION.md" process-multi-agent-roles yes
 sed "s/fixture/$note/" "$p/WORKFLOW-ADOPTION.md" > "$p/tmp"; mv "$p/tmp" "$p/WORKFLOW-ADOPTION.md"
 # write_adoption uses its own notes: explicitly stamp the bounded row.
 printf '| process-multi-agent-roles | yes | 2026-10-01 | %s |\n' "$note" > "$p/WORKFLOW-ADOPTION.md"
 v2_out="$("$TEST_REPO_ROOT/pending-changes.sh" "$p" 2>&1)"
 if [ "$version" = v2 ]; then absent '  - process-multi-agent-roles'; else has 'answered under meaning v1, now v2'; fi
done

test_done
