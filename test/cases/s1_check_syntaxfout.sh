#!/usr/bin/env bash
# S1 — `check` fails on a syntax error in a script.
# Dekt: F1

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

repo="$(sandbox_copy_repo)"

# Given: a script in this repo with a bash syntax error.
printf '\nif [ 1 -eq 1 ]; then\n  echo kapot\n' >> "$repo/pending-changes.sh"

# When: ./check runs (without the test suite, otherwise the suite calls itself).
uitvoer="$("$TEST_REPO_ROOT/check" --no-tests "$repo" 2>&1)"
status=$?

# Then: exit != 0, with the file in question in the message.
if [ "$status" -eq 0 ]; then
  fail "S1 — check succeeded while there is a syntax error in pending-changes.sh"
fi
assert_contains "S1" "pending-changes.sh" "$uitvoer"

# A script does not need a .sh extension to be a shell script. The
# hook guards from W10 arrive as `hooks/git-guardrails` without an extension, and
# that is exactly the code where a silent syntax error is the most costly: it blocks
# work in four projects at once.
repo2="$SANDBOX/repo2"
mkdir -p "$repo2/settings" "$repo2/hooks"
cp "$TEST_REPO_ROOT/settings/session-hooks.json" "$repo2/settings/"
printf '#!/usr/bin/env bash\nif [ 1 -eq 1 ]; then\n  echo kapot\n' > "$repo2/hooks/git-guardrails"
chmod +x "$repo2/hooks/git-guardrails"

uitvoer2="$("$TEST_REPO_ROOT/check" --no-tests "$repo2" 2>&1)"
status2=$?

if [ "$status2" -eq 0 ]; then
  fail "S1 — check missed a syntax error in a script without a .sh extension"
fi
assert_contains "S1 (without extension)" "git-guardrails" "$uitvoer2"

test_klaar
