#!/usr/bin/env bash
# S108-S111 — The merge guard blocks a commit-level Closes #N the PR's own
# title/body doesn't also close (gh pr merge --squash composes its message
# from every constituent commit by default, not just the PR's title/body).
# Covers: F21
#
# REST-only fixtures (issue #355): `gh pr view --json
# closingIssuesReferences,commits,title,body` is GraphQL-backed and in the
# same #318 defect class as its four sibling scripts' own calls (403s from
# inside a Claude Code session in at least one confirmed run). Replaced
# with three REST calls: a `pulls` list (used only to resolve the current
# branch's PR number, `resolve_stray_closes_pr_number`'s job when no
# explicit target is given — every case below omits one, same as before),
# `pulls/<n>` for title+body, and `pulls/<n>/commits` for the commit list.
# `closingIssuesReferences` itself is gone — dropped, not replaced by a
# separate REST call, since the #341 fix already established the
# title/body keyword scan as a pure superset of it (see git-guardrails'
# own comment above check_stray_closes_guard). AC5/AC6 below, previously
# the release-branch-only special case, are now simply what every fixture
# looks like: title/body is the only source of "what the PR declares it
# closes", REST or not.

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
pr_data="$fixtures/pr.dat"
commits_data="$fixtures/commits.dat"

# $1 title, $2 body — writes the raw byte shape `gh api
# repos/{owner}/{repo}/pulls/<n> --jq '(.title // "") + "\u0001" + (.body
# // "") + "\u0003"'` would actually produce on stdout (real \x01/\x03
# control bytes, not the two-character escape text).
write_pr_fixture() {
  printf '%s\x01%s\x03' "$1" "$2" > "$pr_data"
}

# Pairs of sha/message ($1 $2, $3 $4, ...) — writes the raw byte shape
# `gh api repos/{owner}/{repo}/pulls/<n>/commits --jq '.[] | (.sha // "")
# + "\u0001" + (.commit.message // "") + "\u0002"'` would produce, one
# record per commit (real REST commits carry a single combined
# `commit.message`, headline+blank-line+body — a plain concatenation is
# an equivalent-enough stand-in here, the keyword regex doesn't care
# about the blank line).
write_commits_fixture() {
  : > "$commits_data"
  while [ $# -ge 2 ]; do
    printf '%s\x01%s\x02' "$1" "$2" >> "$commits_data"
    shift 2
  done
}

through_guard() {
  local extra_path="${1:-}"
  printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"%s","tool_input":{"command":"gh pr merge"}}' \
    "$project" | PATH="${extra_path:+$extra_path:}$PATH" "$guard" 2>&1
}

# A shared fake gh: marker + green CI always present (so only the new
# stray-Closes check is under test), the `pulls` list resolves
# feature/1-work to PR #42 (resolve_stray_closes_pr_number's REST
# list-and-filter, since REST has no `gh pr view <target>` equivalent for
# resolving "the current branch's PR"), and the two per-PR calls read from
# $pr_data/$commits_data — or, if either file is absent, fail (for the
# fail-open case).
fakebin="$(fake_gh_bin '
case "$*" in
  "pr view --json comments,headRefOid")
    printf "%s" "{\"headRefOid\":\"1111111111111111111111111111111111111111\",\"comments\":[{\"body\":\"findings\\n<!-- pre-merge-review:done sha=1111111111111111111111111111111111111111 -->\"}]}"
    exit 0 ;;
  "pr checks --json bucket,name")
    printf "%s" "[{\"name\":\"check\",\"bucket\":\"pass\"}]"
    exit 0 ;;
  "api repos/{owner}/{repo}/pulls --paginate --jq .[] | (.number|tostring) + \"\t\" + .head.ref")
    printf "42\tfeature/1-work\n"
    exit 0 ;;
  "api repos/{owner}/{repo}/pulls/42 --jq (.title // \"\") + \"\u0001\" + (.body // \"\") + \"\u0003\"")
    if [ -f "'"$pr_data"'" ]; then
      cat "'"$pr_data"'"
      exit 0
    fi
    exit 1 ;;
  "api repos/{owner}/{repo}/pulls/42/commits --paginate --jq .[] | (.sha // \"\") + \"\u0001\" + (.commit.message // \"\") + \"\u0002\"")
    if [ -f "'"$commits_data"'" ]; then
      cat "'"$commits_data"'"
      exit 0
    fi
    exit 1 ;;
esac
exit 1
')"

# AC1 — a stray commit-level Closes (for an issue the PR itself doesn't
# close) is blocked.
write_pr_fixture "Closes #10: some change" ""
write_commits_fixture \
  "aaaaaaa1111111" "First commit
Closes #10" \
  "bbbbbbb2222222" "Second commit
Closes #999"
output="$(PATH="$fakebin:$PATH" through_guard)"; status=$?
[ "$status" = "2" ] || fail "S108/AC1 — a stray Closes #999 was not blocked (status $status): $output"
assert_contains "S108/AC1 — names the stray issue" "#999" "$output"

# AC1, colon form — GitHub also accepts "Fixes: #123" as a closing
# keyword, not just "Fixes #123"; the first version of this check missed
# it (found during this PR's own pre-merge-review, round 3).
write_pr_fixture "Closes #10: some change" ""
write_commits_fixture \
  "aaaaaaa1111111" "First commit
Fixes: #999"
output="$(PATH="$fakebin:$PATH" through_guard)"; status=$?
[ "$status" = "2" ] || fail "S108/colon-form — a stray 'Fixes: #999' was not blocked (status $status): $output"

# AC2 — every commit-level Closes agrees with what the PR's own title/body
# declares: not blocked.
write_pr_fixture "Closes #10, Fixes #11: some change" ""
write_commits_fixture \
  "aaaaaaa1111111" "First commit
Closes #10" \
  "bbbbbbb2222222" "Second commit
Fixes #11"
output="$(PATH="$fakebin:$PATH" through_guard)"; status=$?
[ "$status" != "2" ] || fail "S108/AC2 — a legitimate, agreeing Closes was wrongly blocked: $output"

# A cross-repo reference (owner/repo#N, GitHub's own syntax, no space
# before the #) is not a same-repo stray Closes — checked explicitly after
# pre-merge-review of PR #224 raised it as a possible false positive; it
# doesn't reproduce (the keyword regex requires only whitespace between the
# keyword and #, which excludes any owner/repo text in between either
# way), but a regression test makes that permanent instead of relying on
# re-deriving it by hand next time.
write_pr_fixture "Closes #7: some change" ""
write_commits_fixture \
  "aaaaaaa1111111" "A commit
See owner/repo#42, closes #7"
output="$(PATH="$fakebin:$PATH" through_guard)"; status=$?
[ "$status" != "2" ] || fail "S108/cross-repo — a cross-repo owner/repo#42 reference was wrongly treated as a stray same-repo Closes: $output"

# And: no closing keyword anywhere is the ordinary case and must not block.
write_pr_fixture "some change" "no closing keyword here either"
write_commits_fixture \
  "aaaaaaa1111111" "A commit
no keyword here at all"
output="$(PATH="$fakebin:$PATH" through_guard)"; status=$?
[ "$status" != "2" ] || fail "S108/ordinary — a PR with no closing keywords was wrongly blocked: $output"

# AC3 — fail-open when this specific gh call can't be consulted ($pr_data
# missing, so the fake gh's `pulls/42` case exits 1), independent of the
# marker/CI checks already having passed.
rm -f "$pr_data"
output="$(PATH="$fakebin:$PATH" through_guard)"; status=$?
[ "$status" -ne 2 ] || fail "S108/AC3 — an unreachable stray-Closes check blocked instead of failing open: $output"
assert_contains "S108/AC3 — warns that the check was skipped" "warning" "$output"

# AC4 — the escape hatch covers this check too, even with a real stray
# reference present.
write_pr_fixture "Closes #10: some change" ""
write_commits_fixture \
  "aaaaaaa1111111" "First commit
Closes #999"
# The escape hatch must be part of the *judged command text itself* (that's
# how judge_segment reads it), not the calling shell's environment — hence
# building the command string directly here instead of using through_guard.
output="$(printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"%s","tool_input":{"command":"CLAUDE_WORKFLOW_MERGE_GUARD_OFF=1 gh pr merge"}}' "$project" \
  | PATH="$fakebin:$PATH" "$guard" 2>&1)"
status=$?
[ "$status" -ne 2 ] || fail "S108/AC4 — the escape hatch did not bypass the stray-Closes check: $output"

# AC5 (issue #341, still exercised under REST — issue #355): a
# commit-level Closes matching what the PR's own title says must NOT be
# treated as stray. Title carries the keyword, body doesn't — same shape
# as this repo's own release-branch PRs (#311/#312/#314/#316/#340).
write_pr_fixture "Fix #10: some change" "No closing keyword in the body, only the title."
write_commits_fixture \
  "aaaaaaa1111111" "First commit
Closes #10"
output="$(PATH="$fakebin:$PATH" through_guard)"; status=$?
[ "$status" != "2" ] || fail "S108/AC5 — a commit-level Closes matching the PR title was wrongly blocked as stray: $output"

# AC6 (issue #341, still exercised under REST — issue #355): same shape,
# but this time a commit really does close an unrelated issue the PR's own
# title/body never mentions — still blocked. Proves AC5's fix doesn't just
# disable the check outright.
write_pr_fixture "Fix #10: some change" "No closing keyword in the body, only the title."
write_commits_fixture \
  "aaaaaaa1111111" "First commit
Closes #10" \
  "bbbbbbb2222222" "Second commit
Closes #999"
output="$(PATH="$fakebin:$PATH" through_guard)"; status=$?
[ "$status" = "2" ] || fail "S108/AC6 — a genuinely stray Closes #999 was not blocked (status $status): $output"
assert_contains "S108/AC6 — names the stray issue" "#999" "$output"

test_done
