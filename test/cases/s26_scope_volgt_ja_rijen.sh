#!/usr/bin/env bash
# S26 — De reviewscope volgt de beantwoorde spec-*-rijen.
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

# spec-security staat op een echt "ja", spec-data-integriteit draagt nog de
# voorlopige stempel die adopt.sh's seed_entry() zet: Antwoord blijft
# letterlijk "ja", de tekst "vereist onderbouwing" zit in Toelichting. Beide
# horen in scope — spec-privacy staat op "nee" en spec-testability is
# onbeantwoord (geen rij) — geen van beide hoort in scope.
cat > "$project/WORKFLOW-ADOPTIE.md" <<'EOF'
# Adoptie van gedeelde workflow-wijzigingen

| Wijziging | Antwoord | Datum | Toelichting |
|---|---|---|---|
| spec-security | ja | 2026-01-01 | van toepassing |
| spec-data-integriteit | ja | 2026-01-01 | bij adoptie — vereist onderbouwing tijdens PRD/architectuur |
| spec-privacy | nee | 2026-01-01 | niet van toepassing |
EOF

# De ankers komen uit het gegenereerde PRD-blok van dit repo zelf.
cp "$repo/templates/PRD.md" "$project/PRD.md"

uitvoer="$SANDBOX/uitvoer.txt"
"$repo/skills/pre-merge-review/scope.sh" "$project" "$repo" > "$uitvoer" 2>/dev/null

if ! grep -qx 'complexiteit' "$uitvoer"; then
  fail "S26 — 'complexiteit' hoort altijd in de scope, ongeacht spec-*"
fi
if ! grep -qx 'dependencies' "$uitvoer"; then
  fail "S26 — 'dependencies' hoort altijd in de scope, ongeacht spec-*"
fi
if ! grep -qx 'spec-security: Security' "$uitvoer"; then
  fail "S26 — spec-security (ja) ontbreekt in de scope"
fi
if ! grep -qx 'spec-data-integriteit: Data-integriteit \[vereist onderbouwing\]' "$uitvoer"; then
  fail "S26 — spec-data-integriteit (voorlopige 'ja') hoort gemarkeerd in de scope te staan"
fi
if grep -q 'spec-privacy' "$uitvoer"; then
  fail "S26 — spec-privacy staat op 'nee' en hoort niet in de scope"
fi
if grep -q 'spec-testability' "$uitvoer"; then
  fail "S26 — spec-testability is onbeantwoord en hoort niet in de scope"
fi

regels="$(grep -c '.' "$uitvoer")"
if [ "$regels" -ne 4 ]; then
  fail "S26 — verwacht precies 4 scope-regels (complexiteit, dependencies, 2 NFR's), kreeg $regels"
  cat "$uitvoer" >&2
fi

test_klaar
