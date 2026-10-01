#!/usr/bin/env bash
# R2 — Open questions after a fresh adoption.
# Covers: F3

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: a fresh project, right after adoption.
project="$(fresh_project empty)"
adopt "$project"

# When: pending-changes.sh runs.
actual="$SANDBOX/actual.txt"
pending_ids "$project" > "$actual"

# Then: exactly these 9 IDs, in any order. process-multi-agent-roles
# joined in #369 (F37): a `question` default, so pending, never seeded.
expected="$SANDBOX/expected.txt"
cat > "$expected" <<'IDS'
process-context-document
process-issue-tracking
process-multi-agent-roles
spec-compliance
spec-cost-management
spec-performance-scale
spec-portability
spec-usability
test-integration
IDS

assert_ids_equal "R2" "$expected" "$actual"

test_done
