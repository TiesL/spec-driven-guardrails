#!/usr/bin/env bash
# S72 — Existing projects are still presented with the main-via-PR question.
# Covers: F17

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: a project with package.json, an executable check (#248 — the
# real precondition for the CI questions below, not package.json alone),
# and an already-existing ci.yml that does not call check-main-via-pr.sh,
# plus a WORKFLOW-ADOPTIE.md predating this entry — exactly the case where
# scaffold_if_missing leaves the ci.yml untouched and seed_adoption_table
# no longer seeds anything (that file already exists).
project="$(fresh_project with-own-ci)"
echo '{}' > "$project/package.json"
printf '#!/usr/bin/env bash\nnpm run check\n' > "$project/check"
chmod +x "$project/check"
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
| ci-convention | ja | 2026-01-01 | applicable |
EOF

adopt "$project"

# And: the existing ci.yml stays untouched — scaffold_if_missing overwrites
# nothing (same rule as S49 for ci-on-pr-and-main).
if ! grep -qx '      - run: npm run check' "$project/.github/workflows/ci.yml"; then
  fail "S72 — the existing ci.yml was overwritten"
fi
if grep -q 'check-main-via-pr' "$project/.github/workflows/ci.yml"; then
  fail "S72 — the existing ci.yml called check-main-via-pr.sh anyway (unexpected for this scenario)"
fi

pending="$(pending_ids "$project")"
# <<< here-string, not a piped printf | grep -q, here and below:
# SIGPIPE/pipefail race, see issue #218.
if ! grep -qx 'ci-detects-main-outside-pr' <<<"$pending"; then
  fail "S72 — ci-detects-main-outside-pr did not appear as outstanding for an existing project with an executable check"
  printf '%s\n' "$pending" >&2
fi

# And: a project with neither package.json nor an executable check does
# not get that question.
project_without="$(fresh_project without-package-json)"
pending_without="$(pending_ids "$project_without")"
if grep -qx 'ci-detects-main-outside-pr' <<<"$pending_without"; then
  fail "S72 — the main-via-PR question appeared even without an executable check"
fi

test_done
