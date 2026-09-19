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

# Given: a project with a package.json, an executable check (#248 — the
# real precondition, both for adopt.sh's own scaffold gate and for the
# ci-on-pr-and-main registry row below), and a handwritten ci.yml that
# deviates from the template.
project="$(fresh_project own-ci)"
echo '{"name":"t"}' > "$project/package.json"
printf '#!/usr/bin/env bash\nnpm run check\n' > "$project/check"
chmod +x "$project/check"
mkdir -p "$project/.github/workflows"
own='name: Custom CI that does not come from the template'
echo "$own" > "$project/.github/workflows/ci.yml"

# When: adopt.sh runs, twice.
adopt "$project"
after_one="$(cat "$project/.github/workflows/ci.yml")"
adopt "$project"
after_two="$(cat "$project/.github/workflows/ci.yml")"

# Then: the file was left untouched.
[ "$after_one" = "$own" ] || fail "S49 — adopt.sh overwrote a custom ci.yml"

# And: running twice gives the same result.
[ "$after_two" = "$after_one" ] || fail "S49 — adopt.sh is not idempotent on ci.yml"

# And: the deviation does not stay invisible. Repairing the template only helps
# new projects; existing ones keep their own workflow. That is why the
# adoption registry asks the question — that is the mechanism that makes a
# silent deviation audible, not a one-time message in adopt.sh.
table="$project/WORKFLOW-ADOPTION.md"
grep -q '^| ci-on-pr-and-main ' "$table" \
  || fail "S49 — ci-on-pr-and-main is not in the adoption table of a project with an executable check"

# And: for a project with neither package.json nor an executable check
# the question does not apply — the same scoping as ci-convention, which
# this entry builds on.
bare="$(fresh_project without-package-json)"
adopt "$bare"
if grep -q '^| ci-on-pr-and-main ' "$bare/WORKFLOW-ADOPTION.md"; then
  fail "S49 — ci-on-pr-and-main was seeded in a project without an executable check"
fi

test_done
