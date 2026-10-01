#!/usr/bin/env bash
# S174 — COMMIT_CHECK_BUDGET must be a positive integer; a bad value is rejected and never read as a timeout (#378, review finding 3).
# Covers: F17
#
# The check-commit fixture really fails (after 1 s, so it is not a race with
# a zero budget). With a bad budget the hook must not wave that failure
# through as "exceeded the budget": the commit must not land, the output must
# name COMMIT_CHECK_BUDGET, and it must not claim a timeout.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

n=0
for bad in abc "" 0 -3 1.5 10s; do
  n=$((n + 1))
  label="S174 budget '$bad'"
  project="$(fresh_project "b$n")"
  adopt "$project"
  git -C "$project" commit -q --allow-empty -m "first commit"
  git -C "$project" checkout -q -b feature/1-something
  printf '#!/usr/bin/env bash\nsleep 1\necho "REAL FAILURE"\nexit 1\n' > "$project/check-commit"
  chmod +x "$project/check-commit"
  out="$(cd "$project" && COMMIT_CHECK_BUDGET="$bad" git commit -q --allow-empty -m "second commit" 2>&1)"; st=$?
  [ "$st" -ne 0 ] || fail "$label — the commit went through although check-commit really failed: $out"
  [ "$(git -C "$project" rev-list --count HEAD)" = "1" ] || fail "$label — a commit landed despite a real failure"
  assert_contains "$label — the message names the variable" "COMMIT_CHECK_BUDGET" "$out"
  case "$out" in *"exceeded"*) fail "$label — a bad budget was reported as a timeout: $out" ;; esac
done

test_done
