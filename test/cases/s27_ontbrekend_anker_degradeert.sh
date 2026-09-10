#!/usr/bin/env bash
# S27 — Missing anchors degrade the scope, they don't block it.
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

cat > "$project/WORKFLOW-ADOPTIE.md" <<'EOF'
# Adoptie van gedeelde workflow-wijzigingen

| Wijziging | Antwoord | Datum | Toelichting |
|---|---|---|---|
| spec-security | ja | 2026-01-01 | van toepassing |
EOF

# A PRD.md without the anchor placed by F4 — for example a project that wrote
# the section by hand before the generator existed.
cat > "$project/PRD.md" <<'EOF'
# PRD

## Niet-functionele kenmerken

### Security
Wie mag wat, welke rechten zijn minimaal nodig.
EOF

stdout="$SANDBOX/stdout.txt"
stderr="$SANDBOX/stderr.txt"
"$repo/skills/pre-merge-review/scope.sh" "$project" "$repo" > "$stdout" 2> "$stderr"
status=$?

if [ "$status" -ne 0 ]; then
  fail "S27 — a missing anchor should not block, exit status was $status"
fi

# Then: the skill falls back to the heading name from the register (Security,
# from nfr/spec-security.md) instead of reporting nothing.
if ! grep -qx 'spec-security: Security' "$stdout"; then
  fail "S27 — did not fall back to the heading name from the register"
  cat "$stdout" >&2
fi

# And: it explicitly reports that the anchor is missing.
if ! grep -q 'anker' "$stderr" || ! grep -q 'ontbreekt' "$stderr"; then
  fail "S27 — did not explicitly report that the anchor is missing"
  cat "$stderr" >&2
fi

test_klaar
