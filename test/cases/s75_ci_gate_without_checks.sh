#!/usr/bin/env bash
# S75 — The merge guard does not block when no checks are reported.
# Covers: F8
#
# A project without a CI workflow (CI is optional at adoption, see ci-conventie
# in CHANGES.md) must not get stuck on a check that has nothing to check for
# that project. No checks is not a red flag.
#
# Found while reviewing PR #82: gh does not return this case as an
# empty JSON list, not even with --json. Even then it still gives its plain
# text message on stderr, with exit status 1 (verified against a
# real PR without checks). The fake below mimics that exactly — a fake
# that returned "[]" would test a path that does not exist in reality.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(fresh_project no-ci)"
git -C "$project" commit -q --allow-empty -m start
git -C "$project" checkout -q -b feature/werk

fakebin="$(fake_gh_bin '
case "$*" in
  "pr view --json comments")
    printf "%s" "{\"comments\":[{\"body\":\"bevindingen\\n<!-- pre-merge-review:done -->\"}]}"
    exit 0 ;;
  "pr checks --json bucket,name")
    echo "no checks reported on the feature/werk branch" >&2
    exit 1 ;;
esac
exit 1
')"

input='{"tool_name":"Bash","cwd":"'"$project"'","tool_input":{"command":"gh pr merge"}}'
output="$(printf '%s' "$input" | PATH="$fakebin:$PATH" "$TEST_REPO_ROOT/hooks/git-guardrails" 2>&1)"
status=$?

[ "$status" -eq 0 ] || fail "S75 — expected passthrough (exit 0) without reported checks, got $status. Output: $output"

test_done
