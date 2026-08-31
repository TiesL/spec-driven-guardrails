#!/usr/bin/env bash
# S1 — `check` faalt op een syntaxfout in een script.
# Dekt: F1

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

repo="$(sandbox_copy_repo)"

# Given: een script in dit repo met een bash-syntaxfout.
printf '\nif [ 1 -eq 1 ]; then\n  echo kapot\n' >> "$repo/pending-changes.sh"

# When: ./check draait (zonder de testsuite, anders roept de suite zichzelf aan).
uitvoer="$("$TEST_REPO_ROOT/check" --no-tests "$repo" 2>&1)"
status=$?

# Then: exit != 0, met het betreffende bestand in de melding.
if [ "$status" -eq 0 ]; then
  fail "S1 — check slaagde terwijl er een syntaxfout in pending-changes.sh staat"
fi
assert_contains "S1" "pending-changes.sh" "$uitvoer"

# Een script hoeft geen .sh-extensie te hebben om een shellscript te zijn. De
# hook-guards uit W10 komen als `hooks/git-guardrails` zonder extensie, en dat
# is precies de code waar een stille syntaxfout het duurst is: hij blokkeert
# werk in vier projecten tegelijk.
repo2="$SANDBOX/repo2"
mkdir -p "$repo2/settings" "$repo2/hooks"
cp "$TEST_REPO_ROOT/settings/session-hooks.json" "$repo2/settings/"
printf '#!/usr/bin/env bash\nif [ 1 -eq 1 ]; then\n  echo kapot\n' > "$repo2/hooks/git-guardrails"
chmod +x "$repo2/hooks/git-guardrails"

uitvoer2="$("$TEST_REPO_ROOT/check" --no-tests "$repo2" 2>&1)"
status2=$?

if [ "$status2" -eq 0 ]; then
  fail "S1 — check miste een syntaxfout in een script zonder .sh-extensie"
fi
assert_contains "S1 (zonder extensie)" "git-guardrails" "$uitvoer2"

test_klaar
