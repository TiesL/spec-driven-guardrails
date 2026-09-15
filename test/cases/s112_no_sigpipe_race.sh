#!/usr/bin/env bash
# S112 — No printf/echo piped into grep -q (SIGPIPE/pipefail race, #218).
# Covers: F22

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

script="$TEST_REPO_ROOT/check-no-sigpipe-race.sh"
[ -x "$script" ] || { fail "S112 — check-no-sigpipe-race.sh is missing or not executable"; test_done; }

# Given: the real repo, as it stands today (AC1: every listed occurrence
# from #218, plus the two more this check itself found in hooks/, is
# fixed).
output="$("$script" "$TEST_REPO_ROOT" 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "S112 — the real repo is not clean: $output"

sandbox_create
trap sandbox_destroy EXIT

repo="$(sandbox_copy_repo)"

# When: the exact anti-pattern is introduced in an ordinary script — proving
# the check is actually sensitive, not just accidentally green (AC3:
# red-before-green for this new mechanism itself). Built via variables, not
# a literal contiguous string in this test's own source: sandbox_copy_repo
# copies this very file too, and a literal match here would flag this test
# file itself when the real-repo check above runs.
p="printf"; g="grep"
{
  echo ''
  echo 'reintroduced_race() {'
  echo "  $p '%s' \"\$1\" | $g -q needle"
  echo '}'
} >> "$repo/pending-changes.sh"
output_dirty="$("$script" "$repo" 2>&1)"; status_dirty=$?
[ "$status_dirty" -ne 0 ] || fail "S112 — a reintroduced race pattern was not caught"
assert_contains "S112 — the offending file is named" "pending-changes.sh" "$output_dirty"

# And: a comment merely *describing* the pattern (as several fixed files
# now do, including this repo's own hooks/pre-commit) is not itself
# flagged — the exclusion is by design (comments aren't executable code),
# not a gap that would make the check impossible to document.
comment_repo="$(sandbox_copy_repo comment-only)"
{
  echo ''
  echo "# See $p '%s' \"\$x\" | $g -q y for why this is wrong."
} >> "$comment_repo/pending-changes.sh"
output_comment="$("$script" "$comment_repo" 2>&1)"; status_comment=$?
[ "$status_comment" -eq 0 ] || fail "S112 — a comment merely describing the pattern was wrongly flagged: $output_comment"

# And: the script excludes itself from its own scan — its own header
# comment and code necessarily mention the pattern by name.
output_self="$("$script" "$repo" 2>&1)"
case "$output_self" in
  *"check-no-sigpipe-race.sh"*) fail "S112 — the script flagged itself for its own header/logic" ;;
esac

# And: this is wired into `check` itself, as a hard error (not a warning) —
# consistent with check-no-dutch.sh (S88) and check-traceability.sh (link
# 1), both gated on the script's own presence the same way.
if "$repo/check" --no-tests "$repo" >/dev/null 2>&1; then
  fail "S112 — check did not complain about a reintroduced race pattern"
fi
sed -i.bak '/reintroduced_race/,+2d' "$repo/pending-changes.sh"
rm -f "$repo/pending-changes.sh.bak"
if ! "$repo/check" --no-tests "$repo" >/dev/null 2>&1; then
  fail "S112 — check still complains after the reintroduced race is removed"
fi

test_done
