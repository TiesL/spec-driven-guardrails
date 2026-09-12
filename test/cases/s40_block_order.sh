#!/usr/bin/env bash
# S40 — The order of the template block is fixed.
# Covers: F4

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

repo="$(sandbox_copy_repo)"

# Given: the order field determines the position in the block. Two attributes swap.
one="$repo/nfr/spec-security.md"        # order: 1
two="$repo/nfr/spec-data-integrity.md" # order: 2
sed -i.bak 's/^order: 1$/order: 2/' "$one"
sed -i.bak 's/^order: 2$/order: 1/' "$two"
rm -f "$repo"/nfr/*.bak

# When: the checked-in block is still in the old order.
# Then: check fails. A comparison that sorts by ID does not see this, so the
# order is tested separately.
output="$("$repo/check" --no-tests "$repo" 2>&1)"
status=$?

if [ "$status" -eq 0 ]; then
  fail "S40 — check succeeded while the block order deviates"
fi
assert_contains "S40" "order" "$output"

# And after regenerating it is fine again.
(cd "$repo" && ./generate-prd-block >/dev/null 2>&1)
"$repo/check" --no-tests "$repo" >/dev/null 2>&1 || fail "S40 — check still complains after regenerating"

test_done
