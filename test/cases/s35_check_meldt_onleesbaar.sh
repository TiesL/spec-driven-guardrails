#!/usr/bin/env bash
# S35 — `check` meldt wat hij niet heeft kunnen controleren.
# Dekt: F1

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

repo="$(sandbox_copy_repo)"

# Given: een bestand dat check zou moeten onderzoeken maar niet kan lezen.
mkdir -p "$repo/hooks"
printf '#!/usr/bin/env bash\nif [ 1 -eq 1 ]; then\n  echo kapot\n' > "$repo/hooks/onleesbaar"
chmod 000 "$repo/hooks/onleesbaar"

# When: ./check draait.
uitvoer="$("$TEST_REPO_ROOT/check" --no-tests "$repo" 2>&1)"

# Then: er verschijnt een waarschuwing die het bestand noemt.
assert_contains "S35" "onleesbaar" "$uitvoer"

# And: het verdwijnt niet stilzwijgend uit de controle.
assert_contains "S35" "kon niet gelezen worden" "$uitvoer"

chmod 644 "$repo/hooks/onleesbaar"
test_klaar
