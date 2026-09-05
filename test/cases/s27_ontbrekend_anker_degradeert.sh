#!/usr/bin/env bash
# S27 — Ontbrekende ankers degraderen de scope, ze blokkeren hem niet.
# Dekt: F11

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

# Een PRD.md zonder het door F4 geplaatste anker — bijvoorbeeld een project dat
# de sectie met de hand schreef vóór de generator bestond.
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
  fail "S27 — een ontbrekend anker hoort niet te blokkeren, exitstatus was $status"
fi

# Then: de skill valt terug op de kopnaam uit het register (Security, uit
# nfr/spec-security.md) in plaats van niets te melden.
if ! grep -qx 'spec-security: Security' "$stdout"; then
  fail "S27 — viel niet terug op de kopnaam uit het register"
  cat "$stdout" >&2
fi

# And: hij meldt expliciet dat het anker ontbreekt.
if ! grep -q 'anker' "$stderr" || ! grep -q 'ontbreekt' "$stderr"; then
  fail "S27 — meldde niet expliciet dat het anker ontbreekt"
  cat "$stderr" >&2
fi

test_klaar
