#!/usr/bin/env bash
# S139 — .github/ISSUE_TEMPLATE/ is only created for the first time once
# process-issue-tracking is answered "yes" — not unconditionally.
# Covers: F9
#
# Found via #238 (finding 4, portfolio-mgt-agents): adopt.sh refreshed
# .github/ISSUE_TEMPLATE/ regardless of whether process-issue-tracking had
# ever been answered. The gate applies only to *first creation* — S31/AC3
# still needs an already-existing directory refreshed unconditionally,
# since a project with the directory already in place has self-evidently
# opted in, answered or not.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# A fresh project: process-issue-tracking defaults to "question", never
# auto-answered — no directory should be created.
project="$(fresh_project no-answer-yet)"
adopt "$project"
if [ -d "$project/.github/ISSUE_TEMPLATE" ]; then
  fail "S139 — .github/ISSUE_TEMPLATE/ was created before process-issue-tracking was answered"
fi

# Once the row is answered yes, the next adopt.sh run creates it.
cat >> "$project/WORKFLOW-ADOPTION.md" <<'EOF'
| process-issue-tracking | yes | 2026-01-01 | this project splits work into epics/work items |
EOF
adopt "$project"
if [ ! -f "$project/.github/ISSUE_TEMPLATE/work-item.md" ]; then
  fail "S139 — .github/ISSUE_TEMPLATE/ was not created once the row was answered yes"
fi

# The pre-migration format (W42/#114) gates the same way.
project2="$(fresh_project old-format-no)"
cat > "$project2/WORKFLOW-ADOPTIE.md" <<'EOF'
# Adoption of shared workflow changes

| Change | Answer | Date | Notes |
|---|---|---|---|
| proces-context-document | nee | 2026-01-01 | unrelated row, not process-issue-tracking |
EOF
SPEC_DRIVEN_GUARDRAILS_DIR="$TEST_REPO_ROOT" "$TEST_REPO_ROOT/adopt.sh" "$project2" >/dev/null 2>&1
if [ -d "$project2/.github/ISSUE_TEMPLATE" ]; then
  fail "S139 — pre-migration format: .github/ISSUE_TEMPLATE/ was created without proces-issue-tracking answered ja"
fi

# Cross case (found during PR #247's pre-merge-review): a migrated
# filename (WORKFLOW-ADOPTION.md) that still carries an unmigrated,
# pre-rename row (proces-issue-tracking / ja) must count the same as the
# current id/value — matching pending-changes.sh's own answered().
project3="$(fresh_project migrated-file-old-row)"
cat > "$project3/WORKFLOW-ADOPTION.md" <<'EOF'
# Adoption of shared workflow changes

| Change | Answer | Date | Notes |
|---|---|---|---|
| proces-issue-tracking | ja | 2026-01-01 | answered before the #175 rename, filename already migrated |
EOF
adopt "$project3"
if [ ! -f "$project3/.github/ISSUE_TEMPLATE/work-item.md" ]; then
  fail "S139 — cross case: migrated filename with an unmigrated proces-issue-tracking/ja row did not scaffold"
fi

# Mixed pairing (found during PR #247's pre-merge-review, round 2): the
# current id with the Dutch value — plausible from a partial manual
# migration. Id and value are checked independently, not paired, so this
# must count too.
project4="$(fresh_project mixed_pairing)"
cat > "$project4/WORKFLOW-ADOPTION.md" <<'EOF'
# Adoption of shared workflow changes

| Change | Answer | Date | Notes |
|---|---|---|---|
| process-issue-tracking | ja | 2026-01-01 | current id, Dutch value from a partial manual migration |
EOF
adopt "$project4"
if [ ! -f "$project4/.github/ISSUE_TEMPLATE/work-item.md" ]; then
  fail "S139 — mixed pairing: current id with Dutch value 'ja' did not scaffold"
fi

test_done
