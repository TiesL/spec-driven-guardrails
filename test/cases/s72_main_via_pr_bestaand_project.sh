#!/usr/bin/env bash
# S72 — Bestaande projecten krijgen de main-via-PR-vraag alsnog voorgelegd.
# Dekt: F17

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: een project met package.json en een al bestaande ci.yml die
# check-main-via-pr.sh niet aanroept, plus een WORKFLOW-ADOPTIE.md van vóór
# deze entry bestond — precies het geval waarin scaffold_if_missing de ci.yml
# ongemoeid laat én seed_adoptietabel niets meer seedt (dat bestand bestaat al).
project="$(vers_project met-eigen-ci)"
echo '{}' > "$project/package.json"
mkdir -p "$project/.github/workflows"
cat > "$project/.github/workflows/ci.yml" <<'EOF'
name: CI
on: [push, pull_request]
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - run: npm run check
EOF
cat > "$project/WORKFLOW-ADOPTIE.md" <<'EOF'
# Adoptie van gedeelde workflow-wijzigingen

| Wijziging | Antwoord | Datum | Toelichting |
|---|---|---|---|
| ci-conventie | ja | 2026-01-01 | van toepassing |
EOF

adopteer "$project"

# And: de eigen ci.yml blijft ongemoeid — scaffold_if_missing overschrijft
# niets (zelfde regel als S49 voor ci-op-pr-en-main).
if ! grep -qx '      - run: npm run check' "$project/.github/workflows/ci.yml"; then
  fail "S72 — de bestaande ci.yml werd overschreven"
fi
if grep -q 'check-main-via-pr' "$project/.github/workflows/ci.yml"; then
  fail "S72 — de bestaande ci.yml riep check-main-via-pr.sh toch aan (onverwacht voor dit scenario)"
fi

openstaande="$(openstaande_ids "$project")"
if ! printf '%s\n' "$openstaande" | grep -qx 'ci-detecteert-main-buiten-pr'; then
  fail "S72 — ci-detecteert-main-buiten-pr verscheen niet als openstaand voor een bestaand package.json-project"
  printf '%s\n' "$openstaande" >&2
fi

# And: een project zonder package.json krijgt die vraag niet.
project_zonder="$(vers_project zonder-package-json)"
openstaande_zonder="$(openstaande_ids "$project_zonder")"
if printf '%s\n' "$openstaande_zonder" | grep -qx 'ci-detecteert-main-buiten-pr'; then
  fail "S72 — de main-via-PR-vraag verscheen ook zonder package.json"
fi

test_klaar
