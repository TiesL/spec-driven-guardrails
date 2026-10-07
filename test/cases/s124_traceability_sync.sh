#!/usr/bin/env bash
# S124-S126 — check-traceability.sh (root) stays in sync with
# templates/check-traceability.sh (issue #230). Covers: F25

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: the real repo, as it stands today — the two files must already be
# identical (AC1).
if ! diff -q "$TEST_REPO_ROOT/check-traceability.sh" "$TEST_REPO_ROOT/templates/check-traceability.sh" >/dev/null 2>&1; then
  fail "S124/AC1 — the real repo's two copies have already drifted"
fi
output="$("$TEST_REPO_ROOT/check" --no-tests "$TEST_REPO_ROOT" 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "S124/AC1 — check fails on the real, in-sync repo: $output"

repo="$(sandbox_copy_repo)"

# When: the root copy drifts from the template — proving the check is
# actually sensitive, not just accidentally green (AC2, red-before-green
# for this new mechanism itself).
echo "# drift" >> "$repo/check-traceability.sh"
output_drifted="$("$repo/check" --no-tests "$repo" 2>&1)"; status_drifted=$?
[ "$status_drifted" -ne 0 ] || fail "S125/AC2 — a drifted root copy was not caught"
assert_contains "S125/AC2 — names both files" "check-traceability.sh" "$output_drifted"
assert_contains "S125/AC2 — names both files" "templates/check-traceability.sh" "$output_drifted"

# And: fixing the drift makes check green again.
cp "$repo/templates/check-traceability.sh" "$repo/check-traceability.sh"
output_fixed="$("$repo/check" --no-tests "$repo" 2>&1)"; status_fixed=$?
[ "$status_fixed" -eq 0 ] || fail "S125 — check still complains after the drift is fixed: $output_fixed"

# S126/AC3 — gated on both files existing: a target with neither (or only
# one) isn't affected.
neither_repo="$(sandbox_copy_repo neither)"
rm -f "$neither_repo/check-traceability.sh" "$neither_repo/templates/check-traceability.sh"
output_neither="$("$neither_repo/check" --no-tests "$neither_repo" 2>&1)"; status_neither=$?
case "$output_neither" in
  *"drifted"*) fail "S126/AC3 — the sync check ran with neither file present" ;;
esac

only_root_repo="$(sandbox_copy_repo only-root)"
rm -f "$only_root_repo/templates/check-traceability.sh"
output_only_root="$("$only_root_repo/check" --no-tests "$only_root_repo" 2>&1)"; status_only_root=$?
case "$output_only_root" in
  *"drifted"*) fail "S126/AC3 — the sync check ran with only the root copy present" ;;
esac

test_done
