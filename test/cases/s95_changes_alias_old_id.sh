#!/usr/bin/env bash
# S95 — An answer under a pre-rename CHANGES.md entry ID is still recognized.
# Covers: F3

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: a project with a package.json (so ci-convention actually applies)
# that answered "yes" under the pre-#175 ID (ci-conventie), before that
# entry was renamed to ci-convention — the exact real-world case found in
# tennis-admin's own frozen fixture.
project="$(fresh_project alias-old-changes-id)"
echo '{}' > "$project/package.json"

cat > "$project/WORKFLOW-ADOPTION.md" <<'EOF'
# Adoption of shared workflow changes

| Change | Answer | Date | Notes |
|---|---|---|---|
| ci-conventie | yes | 2026-01-01 | answered before the #175 rename |
EOF

# When: pending-changes.sh runs.
actual="$SANDBOX/actual.txt"
pending_ids "$project" > "$actual"

# Then: ci-convention (the current ID) is not reported as pending — the
# old-ID row satisfies the current question, same treatment as #156's
# nfr alias and W42/#114's ja/nee support.
if grep -qx 'ci-convention' "$actual"; then
  fail "S95 — ci-convention was reported as pending despite an answered pre-rename row"
fi

test_done
