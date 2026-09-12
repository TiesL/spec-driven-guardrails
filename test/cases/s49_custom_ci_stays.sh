#!/usr/bin/env bash
# S49 — A custom ci.yml is not overwritten; the deviation becomes visible
# via the adoption registry instead of via a silent copy.
# Covers: F17

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: a project with a package.json — otherwise adopt.sh would not scaffold
# a workflow anyway — and a handwritten ci.yml that deviates from the template.
project="$(fresh_project eigen-ci)"
echo '{"name":"t"}' > "$project/package.json"
mkdir -p "$project/.github/workflows"
eigen='name: Eigen CI die niet van het sjabloon komt'
echo "$eigen" > "$project/.github/workflows/ci.yml"

# When: adopt.sh runs, twice.
adopt "$project"
na_een="$(cat "$project/.github/workflows/ci.yml")"
adopt "$project"
na_twee="$(cat "$project/.github/workflows/ci.yml")"

# Then: the file was left untouched.
[ "$na_een" = "$eigen" ] || fail "S49 — adopt.sh overwrote a custom ci.yml"

# And: running twice gives the same result.
[ "$na_twee" = "$na_een" ] || fail "S49 — adopt.sh is not idempotent on ci.yml"

# And: the deviation does not stay invisible. Repairing the template only helps
# new projects; existing ones keep their own workflow. That is why the
# adoption registry asks the question — that is the mechanism that makes a
# silent deviation audible, not a one-time message in adopt.sh.
tabel="$project/WORKFLOW-ADOPTION.md"
grep -q '^| ci-op-pr-en-main ' "$tabel" \
  || fail "S49 — ci-op-pr-en-main is not in the adoption table of a project with package.json"

# And: for a project without package.json the question does not apply —
# the same scoping as ci-conventie, which this entry builds on.
kaal="$(fresh_project zonder-package-json)"
adopt "$kaal"
if grep -q '^| ci-op-pr-en-main ' "$kaal/WORKFLOW-ADOPTION.md"; then
  fail "S49 — ci-op-pr-en-main was seeded in a project without package.json"
fi

test_done
