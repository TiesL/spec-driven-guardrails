#!/usr/bin/env bash
# S89 — An answer under a pre-rename NFR ID is still recognized.
# Covers: F3, F11

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: a project that answered "yes" under the pre-#156 ID
# (spec-data-integriteit), before that NFR's file/ID was renamed to
# spec-data-integrity. No PRD.md — this deliberately forces the anchor
# lookup in scope.sh to miss and fall through to the nfr/ register
# fallback, the exact path the alias was added to.
project="$(vers_project alias-oude-id)"

cat > "$project/WORKFLOW-ADOPTION.md" <<'EOF'
# Adoption of shared workflow changes

| Change | Answer | Date | Notes |
|---|---|---|---|
| spec-data-integriteit | yes | 2026-01-01 | answered before the #156 rename |
EOF

# When: pending-changes.sh runs.
gekregen="$SANDBOX/gekregen.txt"
openstaande_ids "$project" > "$gekregen"

# Then: spec-data-integrity (the current ID) is not reported as pending —
# the old-ID row satisfies the current question, same as W42/#114's
# ja/nee support satisfied the value-format migration.
if grep -qx 'spec-data-integrity' "$gekregen"; then
  fail "S89 — spec-data-integrity was reported as pending despite an answered pre-rename row"
fi

# And: pre-merge-review's scope still recognizes the row and resolves a
# readable heading via the alias, instead of falling back to the bare ID.
uitvoer="$SANDBOX/scope-uitvoer.txt"
"$TEST_REPO_ROOT/skills/pre-merge-review/scope.sh" "$project" "$TEST_REPO_ROOT" > "$uitvoer" 2>/dev/null

if ! grep -qx 'spec-data-integriteit: Data integrity' "$uitvoer"; then
  fail "S89 — scope.sh did not resolve a heading for the pre-rename ID via the alias"
  cat "$uitvoer" >&2
fi

test_klaar
