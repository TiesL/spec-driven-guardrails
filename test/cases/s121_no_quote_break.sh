#!/usr/bin/env bash
# S121-S123 — No apostrophe closing a python3 -c '...' block early
# (issue #228). Covers: F24

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

script="$TEST_REPO_ROOT/check-no-quote-break.sh"
[ -x "$script" ] || { fail "S121 — check-no-quote-break.sh is missing or not executable"; test_done; }

# Given: the real repo, as it stands today — including the three existing
# python3 -c '...' blocks in hooks/git-guardrails and the one in
# epic-auto-close.sh, whose closing lines use two different shapes
# (')"' and ' "$var" <<<...)"'). Both must already read as clean.
output="$("$script" "$TEST_REPO_ROOT" 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "S121 — the real repo is not clean: $output"

sandbox_create
trap sandbox_destroy EXIT

repo="$(sandbox_copy_repo)"

# When: a python3 -c '...' block with an apostrophe in its prose (the
# exact shape that broke hooks/git-guardrails while building issue #225)
# is introduced — proving the check is actually sensitive, not just
# accidentally green (AC1, and red-before-green for this new mechanism
# itself). Built without a literal apostrophe adjacent to "python3 -c '"
# in this test's own source: sandbox_copy_repo copies this very file too,
# and a literal match here would flag this test file itself when the
# real-repo check above runs.
p="python3"; a="'"
{
  echo ''
  echo "broken_example() {"
  echo "  foo=\"\$($p -c $a"
  echo "import sys"
  echo "# found during PR #227${a}s own pre-merge-review"
  echo "print(\"hi\")"
  echo "$a)\""
  echo "}"
} >> "$repo/pending-changes.sh"
output_dirty="$("$script" "$repo" 2>&1)"; status_dirty=$?
[ "$status_dirty" -ne 0 ] || fail "S121/AC1 — a reintroduced quote-break was not caught"
assert_contains "S121/AC1 — the offending file is named" "pending-changes.sh" "$output_dirty"
assert_contains "S121/AC1 — the offending line is quoted" "PR #227" "$output_dirty"

# S122 — the two legitimate closing shapes already used in this repo
# (')"' on its own, and ' "$var" <<<...)"' with trailing args) both stay
# clean, added fresh here so the check's own tolerance for both shapes is
# pinned by a test, not just today's snapshot of the real repo.
shapes_repo="$(sandbox_copy_repo shapes)"
{
  echo ''
  echo "shape_one() {"
  echo "  foo=\"\$($p -c $a"
  echo "print(\"hi\")"
  echo "$a)\""
  echo "}"
  echo "shape_two() {"
  echo "  bar=\"\$($p -c $a"
  echo "print(\"bye\")"
  echo "$a \"\$extra\" <<<\"\$data\")\""
  echo "}"
} >> "$shapes_repo/pending-changes.sh"
output_shapes="$("$script" "$shapes_repo" 2>&1)"; status_shapes=$?
[ "$status_shapes" -eq 0 ] || fail "S122 — a legitimate closing shape was wrongly flagged: $output_shapes"

# And: the script excludes itself from its own scan — its own header
# comment and code necessarily mention the pattern by name.
output_self="$("$script" "$repo" 2>&1)"
case "$output_self" in
  *"check-no-quote-break.sh"*) fail "S121 — the script flagged itself for its own header/logic" ;;
esac

# S123 — this is wired into check itself, as a hard error (not a
# warning) — consistent with check-no-dutch.sh (S88) and
# check-no-sigpipe-race.sh (S112), both gated on the script's own
# presence the same way.
if "$repo/check" --no-tests "$repo" >/dev/null 2>&1; then
  fail "S123 — check did not complain about a reintroduced quote-break"
fi
sed -i.bak '/broken_example/,/^}$/d' "$repo/pending-changes.sh"
rm -f "$repo/pending-changes.sh.bak"
if ! "$repo/check" --no-tests "$repo" >/dev/null 2>&1; then
  fail "S123 — check still complains after the reintroduced quote-break is removed"
fi

# And: without python3, check visibly says so (not a silent skip) — same
# reasoning as S118 for check-no-sigpipe-race.sh.
nopy="$(minimal_path_without_validators)"
output_nopy="$(PATH="$nopy" "$repo/check" --no-tests "$repo" 2>&1)"
assert_contains "S123 — python3-missing is reported visibly, not silently skipped" \
  "quote-break check skipped" "$output_nopy"

test_done
