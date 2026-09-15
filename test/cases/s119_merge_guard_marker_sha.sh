#!/usr/bin/env bash
# S119-S120 — The pre-merge-review marker is pinned to a commit SHA.
# Covers: F23

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

guard="$TEST_REPO_ROOT/hooks/git-guardrails"
[ -x "$guard" ] || { fail "S119 — hooks/git-guardrails is missing"; test_done; }

sandbox_create
trap sandbox_destroy EXIT

project="$(fresh_project marker-sha)"
git -C "$project" commit -q --allow-empty -m start
git -C "$project" checkout -q -b feature/work

through_guard() {
  local extra_path="$1"
  printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":"gh pr merge"}}' "$project" \
    | PATH="$extra_path:$PATH" "$guard" 2>&1
}

# S119/AC1 — a marker posted for an older commit than the PR's current
# HEAD is not accepted; same block as no marker at all.
fakebin_stale="$(fake_gh_merge_bin "stale" "")"
output_stale="$(through_guard "$fakebin_stale")"; status_stale=$?
[ "$status_stale" -eq 2 ] || fail "S119/AC1 — a stale (wrong-commit) marker was not blocked (status $status_stale): $output_stale"
assert_contains "S119/AC1 — names the current-commit requirement" "current HEAD" "$output_stale"

# S119/AC2 — a marker matching the PR's current HEAD is accepted (also
# covered by S16, repeated here for the pairing with AC1 above).
fakebin_match="$(fake_gh_merge_bin "match" "")"
output_match="$(through_guard "$fakebin_match")"; status_match=$?
[ "$status_match" -ne 2 ] || fail "S119/AC2 — a marker matching the current HEAD was wrongly blocked: $output_match"

# S120 — stdout/stderr are kept separate when consulting the PR: a routine
# stderr line from gh must not contaminate the JSON on stdout and
# silently fail the check open (the same class of bug check_ci_guard was
# hardened against for issue #81, and check_stray_closes_guard for PR
# #224's own review — this is that same hardening applied here).
fakebin_noisy="$(fake_gh_bin '
case "$*" in
  "pr view --json comments,headRefOid")
    echo "a routine gh notice" >&2
    printf "%s" "{\"headRefOid\":\"1111111111111111111111111111111111111111\",\"comments\":[{\"body\":\"findings\\n<!-- pre-merge-review:done sha=1111111111111111111111111111111111111111 -->\"}]}"
    exit 0 ;;
esac
exit 1
')"
output_noisy="$(through_guard "$fakebin_noisy")"; status_noisy=$?
[ "$status_noisy" -ne 2 ] || fail "S120 — stderr noise alongside a valid marker caused a false block: $output_noisy"

test_done
