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

# spec-security has a real "ja", spec-data-integrity still carries the
# provisional stamp that adopt.sh's seed_entry() sets: Answer stays
# literally "ja", the text "requires substantiation" sits in Notes. Both
# belong in scope — spec-privacy is "nee" and spec-testability is unanswered
# (no row) — neither belongs in scope.
cat > "$project/WORKFLOW-ADOPTIE.md" <<'EOF'
# Adoption of shared workflow changes

| Change | Answer | Date | Notes |
|---|---|---|---|
| spec-security | ja | 2026-01-01 | applicable |
| spec-data-integrity | ja | 2026-01-01 | at adoption — requires substantiation during PRD/architecture |
| spec-privacy | nee | 2026-01-01 | not applicable |
EOF

# The anchors come from this repo's own generated PRD block.
cp "$repo/templates/PRD.md" "$project/PRD.md"

output="$SANDBOX/output.txt"
"$repo/skills/pre-merge-review/scope.sh" "$project" "$repo" > "$output" 2>/dev/null

if ! grep -qx 'complexity' "$output"; then
  fail "S26 — 'complexity' always belongs in scope, regardless of spec-*"
fi
if ! grep -qx 'dependencies' "$output"; then
  fail "S26 — 'dependencies' always belongs in scope, regardless of spec-*"
fi
if ! grep -qx 'spec-security: Security' "$output"; then
  fail "S26 — spec-security (ja) is missing from the scope"
fi
if ! grep -qx 'spec-data-integrity: Data integrity \[requires substantiation\]' "$output"; then
  fail "S26 — spec-data-integrity (provisional 'ja') should appear marked in the scope"
fi
if grep -q 'spec-privacy' "$output"; then
  fail "S26 — spec-privacy is 'nee' and does not belong in the scope"
fi
if grep -q 'spec-testability' "$output"; then
  fail "S26 — spec-testability is unanswered and does not belong in the scope"
fi

lines="$(grep -c '.' "$output")"
if [ "$lines" -ne 4 ]; then
  fail "S26 — expected exactly 4 scope lines (complexity, dependencies, 2 NFRs), got $lines"
  cat "$output" >&2
fi

test_done
