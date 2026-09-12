#!/usr/bin/env bash
# S71 — Existing projects are still presented with the link-3 question.
# Covers: F13

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: a project with package.json and an already-existing ci.yml that
# does not call check-pr-issue-link.sh, plus a WORKFLOW-ADOPTIE.md predating
# this entry's existence — exactly the case where scaffold_if_missing leaves
# ci.yml untouched and seed_adoption_table no longer seeds anything (that file
# already exists).
project="$(fresh_project with-own-ci)"
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
# Adoption of shared workflow changes

| Change | Answer | Date | Notes |
|---|---|---|---|
| ci-conventie | ja | 2026-01-01 | van toepassing |
EOF

adopt "$project"

# And: the existing ci.yml remains untouched — scaffold_if_missing overwrites
# nothing (same rule as S49 for ci-op-pr-en-main).
if ! grep -qx '      - run: npm run check' "$project/.github/workflows/ci.yml"; then
  fail "S71 — the existing ci.yml was overwritten"
fi
if grep -q 'check-pr-issue-link' "$project/.github/workflows/ci.yml"; then
  fail "S71 — the existing ci.yml called check-pr-issue-link.sh after all (unexpected for this scenario)"
fi

pending="$(pending_ids "$project")"
if ! printf '%s\n' "$pending" | grep -qx 'ci-schakel-3-hard-slot'; then
  fail "S71 — ci-schakel-3-hard-slot did not appear as pending for an existing package.json project"
  printf '%s\n' "$pending" >&2
fi

# And: a project without package.json does not get that question.
project_without="$(fresh_project without-package-json)"
pending_without="$(pending_ids "$project_without")"
if printf '%s\n' "$pending_without" | grep -qx 'ci-schakel-3-hard-slot'; then
  fail "S71 — the link-3 question also appeared without package.json"
fi

test_done
