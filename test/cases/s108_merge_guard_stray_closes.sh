#!/usr/bin/env bash
# S108-S111 — The merge guard blocks a commit-level Closes #N the PR's own
# title/body doesn't also close (gh pr merge --squash composes its message
# from every constituent commit by default, not just the PR's title/body).
# Covers: F21

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

guard="$TEST_REPO_ROOT/hooks/git-guardrails"
[ -x "$guard" ] || { fail "S108 — hooks/git-guardrails is missing"; test_done; }

project="$(fresh_project stray-closes)"
git -C "$project" commit -q --allow-empty -m start
git -C "$project" checkout -q -b feature/1-work

fixtures="$SANDBOX/fixtures"
mkdir -p "$fixtures"
view_data="$fixtures/view.json"

through_guard() {
  local extra_path="${1:-}"
  printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"%s","tool_input":{"command":"gh pr merge"}}' \
    "$project" | PATH="${extra_path:+$extra_path:}$PATH" "$guard" 2>&1
}

# A shared fake gh: marker + green CI always present (so only the new
# stray-Closes check is under test), plus the new `pr view
# --json closingIssuesReferences,commits` call reading from $view_data —
# or, if that file is absent, failing (for the fail-open case).
fakebin="$(fake_gh_bin '
case "$*" in
  "pr view --json comments")
    printf "%s" "{\"comments\":[{\"body\":\"findings\\n<!-- pre-merge-review:done -->\"}]}"
    exit 0 ;;
  "pr checks --json bucket,name")
    printf "%s" "[{\"name\":\"check\",\"bucket\":\"pass\"}]"
    exit 0 ;;
  "pr view --json closingIssuesReferences,commits")
    if [ -f "'"$view_data"'" ]; then
      cat "'"$view_data"'"
      exit 0
    fi
    exit 1 ;;
esac
exit 1
')"

# AC1 — a stray commit-level Closes (for an issue the PR itself doesn't
# close) is blocked.
cat > "$view_data" <<'EOF'
{
  "closingIssuesReferences": [{"number": 10}],
  "commits": [
    {"oid": "aaaaaaa1111111", "messageHeadline": "First commit", "messageBody": "Closes #10"},
    {"oid": "bbbbbbb2222222", "messageHeadline": "Second commit", "messageBody": "Closes #999"}
  ]
}
EOF
output="$(PATH="$fakebin:$PATH" through_guard)"; status=$?
[ "$status" = "2" ] || fail "S108/AC1 — a stray Closes #999 was not blocked (status $status): $output"
assert_contains "S108/AC1 — names the stray issue" "#999" "$output"

# AC2 — every commit-level Closes agrees with the PR's own
# closingIssuesReferences: not blocked.
cat > "$view_data" <<'EOF'
{
  "closingIssuesReferences": [{"number": 10}, {"number": 11}],
  "commits": [
    {"oid": "aaaaaaa1111111", "messageHeadline": "First commit", "messageBody": "Closes #10"},
    {"oid": "bbbbbbb2222222", "messageHeadline": "Second commit", "messageBody": "Fixes #11"}
  ]
}
EOF
output="$(PATH="$fakebin:$PATH" through_guard)"; status=$?
[ "$status" != "2" ] || fail "S108/AC2 — a legitimate, agreeing Closes was wrongly blocked: $output"

# A cross-repo reference (owner/repo#N, GitHub's own syntax, no space
# before the #) is not a same-repo stray Closes — checked explicitly after
# pre-merge-review of PR #224 raised it as a possible false positive; it
# doesn't reproduce (the keyword regex requires only whitespace between the
# keyword and #, which excludes any owner/repo text in between either
# way), but a regression test makes that permanent instead of relying on
# re-deriving it by hand next time.
cat > "$view_data" <<'EOF'
{
  "closingIssuesReferences": [{"number": 7}],
  "commits": [
    {"oid": "aaaaaaa1111111", "messageHeadline": "A commit", "messageBody": "See owner/repo#42, closes #7"}
  ]
}
EOF
output="$(PATH="$fakebin:$PATH" through_guard)"; status=$?
[ "$status" != "2" ] || fail "S108/cross-repo — a cross-repo owner/repo#42 reference was wrongly treated as a stray same-repo Closes: $output"

# And: no closing keyword anywhere is the ordinary case and must not block.
cat > "$view_data" <<'EOF'
{
  "closingIssuesReferences": [],
  "commits": [
    {"oid": "aaaaaaa1111111", "messageHeadline": "A commit", "messageBody": "no keyword here at all"}
  ]
}
EOF
output="$(PATH="$fakebin:$PATH" through_guard)"; status=$?
[ "$status" != "2" ] || fail "S108/ordinary — a PR with no closing keywords was wrongly blocked: $output"

# AC3 — fail-open when this specific gh call can't be consulted (view_data
# missing, so the fake gh's third case exits 1), independent of the
# marker/CI checks already having passed.
rm -f "$view_data"
output="$(PATH="$fakebin:$PATH" through_guard)"; status=$?
[ "$status" -ne 2 ] || fail "S108/AC3 — an unreachable stray-Closes check blocked instead of failing open: $output"
assert_contains "S108/AC3 — warns that the check was skipped" "warning" "$output"

# AC4 — the escape hatch covers this check too, even with a real stray
# reference present.
cat > "$view_data" <<'EOF'
{
  "closingIssuesReferences": [{"number": 10}],
  "commits": [
    {"oid": "aaaaaaa1111111", "messageHeadline": "First commit", "messageBody": "Closes #999"}
  ]
}
EOF
# The escape hatch must be part of the *judged command text itself* (that's
# how judge_segment reads it), not the calling shell's environment — hence
# building the command string directly here instead of using through_guard.
output="$(printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"%s","tool_input":{"command":"CLAUDE_WORKFLOW_MERGE_GUARD_OFF=1 gh pr merge"}}' "$project" \
  | PATH="$fakebin:$PATH" "$guard" 2>&1)"
status=$?
[ "$status" -ne 2 ] || fail "S108/AC4 — the escape hatch did not bypass the stray-Closes check: $output"

test_done
