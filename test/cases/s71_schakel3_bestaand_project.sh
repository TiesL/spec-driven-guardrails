#!/usr/bin/env bash
# S71 — Bestaande projecten krijgen de schakel-3-vraag alsnog voorgelegd.
# Dekt: F13

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: een project met package.json en een al bestaande ci.yml die
# check-pr-issue-link.sh niet aanroept — precies het geval waarin
# scaffold_if_missing het bestand ongemoeid laat.
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

openstaande="$(openstaande_ids "$project")"
if ! printf '%s\n' "$openstaande" | grep -qi 'schakel-3\|schakel3\|pr-issue-link\|check-pr-issue-link'; then
  fail "S71 — geen entry over schakel 3 (PR->issue) verscheen als openstaand voor een package.json-project"
  printf '%s\n' "$openstaande" >&2
fi

# And: een project zonder package.json krijgt die vraag niet.
project_zonder="$(vers_project zonder-package-json)"
openstaande_zonder="$(openstaande_ids "$project_zonder")"
if printf '%s\n' "$openstaande_zonder" | grep -qi 'schakel-3\|schakel3\|pr-issue-link\|check-pr-issue-link'; then
  fail "S71 — de schakel-3-vraag verscheen ook zonder package.json"
fi

test_klaar
