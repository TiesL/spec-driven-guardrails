#!/usr/bin/env bash
# S26 — The review scope follows the answered spec-* rows.
# Covers: F11

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

repo="$(sandbox_copy_repo)"
project="$SANDBOX/project"
mkdir -p "$project"

# spec-security has a real "ja", spec-data-integriteit still carries the
# provisional stamp that adopt.sh's seed_entry() sets: Answer stays
# literally "ja", the text "vereist onderbouwing" sits in Notes. Both
# belong in scope — spec-privacy is "nee" and spec-testability is unanswered
# (no row) — neither belongs in scope.
cat > "$project/WORKFLOW-ADOPTIE.md" <<'EOF'
# Adoption of shared workflow changes

| Change | Answer | Date | Notes |
|---|---|---|---|
| spec-security | ja | 2026-01-01 | van toepassing |
| spec-data-integriteit | ja | 2026-01-01 | at adoption — requires substantiation during PRD/architecture |
| spec-privacy | nee | 2026-01-01 | niet van toepassing |
EOF

# The anchors come from this repo's own generated PRD block.
cp "$repo/templates/PRD.md" "$project/PRD.md"

uitvoer="$SANDBOX/uitvoer.txt"
"$repo/skills/pre-merge-review/scope.sh" "$project" "$repo" > "$uitvoer" 2>/dev/null

if ! grep -qx 'complexity' "$uitvoer"; then
  fail "S26 — 'complexity' always belongs in scope, regardless of spec-*"
fi
if ! grep -qx 'dependencies' "$uitvoer"; then
  fail "S26 — 'dependencies' always belongs in scope, regardless of spec-*"
fi
if ! grep -qx 'spec-security: Security' "$uitvoer"; then
  fail "S26 — spec-security (ja) is missing from the scope"
fi
if ! grep -qx 'spec-data-integriteit: Data integrity \[requires substantiation\]' "$uitvoer"; then
  fail "S26 — spec-data-integriteit (provisional 'ja') should appear marked in the scope"
fi
if grep -q 'spec-privacy' "$uitvoer"; then
  fail "S26 — spec-privacy is 'nee' and does not belong in the scope"
fi
if grep -q 'spec-testability' "$uitvoer"; then
  fail "S26 — spec-testability is unanswered and does not belong in the scope"
fi

regels="$(grep -c '.' "$uitvoer")"
if [ "$regels" -ne 4 ]; then
  fail "S26 — expected exactly 4 scope lines (complexity, dependencies, 2 NFRs), got $regels"
  cat "$uitvoer" >&2
fi

test_klaar
