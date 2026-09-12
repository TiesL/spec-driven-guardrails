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
project="$(fresh_project leeg)"
adopt "$project"

# When: pending-changes.sh runs.
gekregen="$SANDBOX/gekregen.txt"
pending_ids "$project" > "$gekregen"

# Then: exactly these 8 IDs, in any order.
verwacht="$SANDBOX/verwacht.txt"
cat > "$verwacht" <<'IDS'
proces-issue-tracking
process-context-document
spec-compliance
spec-cost-management
spec-performance-scale
spec-portability
spec-usability
test-integratie
IDS

assert_ids_equal "R2" "$verwacht" "$gekregen"

test_done
