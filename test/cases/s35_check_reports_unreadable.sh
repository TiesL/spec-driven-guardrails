#!/usr/bin/env bash
# S35 — `check` reports what it was unable to check.
# Covers: F1

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

repo="$(sandbox_copy_repo)"

# Given: a file that check should examine but cannot read.
mkdir -p "$repo/hooks"
printf '#!/usr/bin/env bash\nif [ 1 -eq 1 ]; then\n  echo kapot\n' > "$repo/hooks/onleesbaar"
chmod 000 "$repo/hooks/onleesbaar"

# When: ./check runs.
uitvoer="$("$TEST_REPO_ROOT/check" --no-tests "$repo" 2>&1)"

# Then: a warning appears that names the file.
assert_contains "S35" "onleesbaar" "$uitvoer"

# And: it doesn't silently drop out of the check.
assert_contains "S35" "couldn't be read" "$uitvoer"

chmod 644 "$repo/hooks/onleesbaar"
test_klaar
