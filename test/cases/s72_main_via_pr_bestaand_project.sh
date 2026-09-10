#!/usr/bin/env bash
# S72 — Existing projects are still presented with the main-via-PR question.
# Dekt: F17

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: a project with package.json and an already-existing ci.yml that
# does not call check-main-via-pr.sh, plus a WORKFLOW-ADOPTIE.md predating
# this entry — exactly the case where scaffold_if_missing leaves the ci.yml
# untouched and seed_adoptietabel no longer seeds anything (that file already exists).
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

# And: the existing ci.yml stays untouched — scaffold_if_missing overwrites
# nothing (same rule as S49 for ci-op-pr-en-main).
if ! grep -qx '      - run: npm run check' "$project/.github/workflows/ci.yml"; then
  fail "S72 — the existing ci.yml was overwritten"
fi
if grep -q 'check-main-via-pr' "$project/.github/workflows/ci.yml"; then
  fail "S72 — the existing ci.yml called check-main-via-pr.sh anyway (unexpected for this scenario)"
fi

openstaande="$(openstaande_ids "$project")"
if ! printf '%s\n' "$openstaande" | grep -qx 'ci-detecteert-main-buiten-pr'; then
  fail "S72 — ci-detecteert-main-buiten-pr did not appear as outstanding for an existing package.json project"
  printf '%s\n' "$openstaande" >&2
fi

# And: a project without package.json does not get that question.
project_zonder="$(vers_project zonder-package-json)"
openstaande_zonder="$(openstaande_ids "$project_zonder")"
if printf '%s\n' "$openstaande_zonder" | grep -qx 'ci-detecteert-main-buiten-pr'; then
  fail "S72 — the main-via-PR question appeared even without package.json"
fi

test_klaar
