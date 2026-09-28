#!/usr/bin/env bash
# T4 — CI check "PR references issue" (link 3, hard block).
# Covers: F13

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

script="$TEST_REPO_ROOT/templates/check-pr-issue-link.sh"
[ -x "$script" ] || { fail "T4 — templates/check-pr-issue-link.sh is missing or not executable"; test_done; }

sandbox_create
trap sandbox_destroy EXIT

fixtures="$SANDBOX/fixtures"
mkdir -p "$fixtures"

# Dispatches on the actual gh subcommand/--json shape the script calls,
# not just the PR number — needed because issue #320's fix makes three
# distinct calls (`pr view` for the fast-path count+baseRefName pair,
# `repo view` for the default branch name, `pr view` again for
# title+body only on the non-default-base fallback path).
fakebin="$(fake_gh_bin '
case "$1 $2" in
  "pr view")
    nummer="$3"
    case "$5" in
      closingIssuesReferences,baseRefName)
        file="'"$fixtures"'/$nummer.count_base" ;;
      title,body)
        file="'"$fixtures"'/$nummer.title_body" ;;
      *) exit 1 ;;
    esac
    [ -f "$file" ] && { cat "$file"; exit 0; }
    exit 1
    ;;
  "repo view")
    file="'"$fixtures"'/default_branch"
    [ -f "$file" ] && { cat "$file"; exit 0; }
    exit 1
    ;;
  *) exit 1 ;;
esac
')"

printf 'main' > "$fixtures/default_branch"

# --- Default-branch behavior, unchanged (AC3) ---

# AC2 — a PR without a linked issue, on the default branch, fails, with
# the PR number in the message. Its title+body *does* carry a closing
# keyword (issue #1) — this is the AC3 regression guard: if the
# default-branch short-circuit were ever accidentally removed or
# bypassed, the fallback would find this keyword and wrongly pass, so
# this fixture actually pins "no fallback runs for the default branch",
# not just "PR 42 happens to have no keyword anywhere".
printf '0\tmain' > "$fixtures/42.count_base"
printf 'Closes #1: unrelated title\n\nSome body mentioning Closes #1 too' > "$fixtures/42.title_body"
output="$(PATH="$fakebin:$PATH" "$script" 42 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "T4/AC2 — PR without a linked issue gave exit 0"
assert_contains "T4/AC2 — the PR number is in the message" "42" "$output"

# AC3 — a PR with a linked issue passes. base_ref is irrelevant once
# count > 0 — the fast path never even looks at it.
printf '1\tmain' > "$fixtures/43.count_base"
output="$(PATH="$fakebin:$PATH" "$script" 43 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "T4/AC3 — PR with a linked issue gave exit $status: $output"

# AC4 — only the current PR is judged: PR 42 (issue-less, already checked
# above) still sits that way in the fixtures, and a call for PR 43 does not
# touch that.
output="$(PATH="$fakebin:$PATH" "$script" 43 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "T4/AC4 — the earlier PR 42 affected the judgment of PR 43"

# No fail-open on unexpected gh output (found in pre-merge-review on
# PR #70): "null" or other junk instead of a number must not silently let
# this hard block pass.
printf 'null' > "$fixtures/44.count_base"
output="$(PATH="$fakebin:$PATH" "$script" 44 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "T4 — non-numeric gh output ('null') gave exit 0 instead of a hard error"

# --- Non-default-base fallback (issue #320) ---

# AC1 — a release-branch PR with the closing keyword only in the title
# passes (this repo's own real shape: #311/#312/#314/#316).
printf '0\trelease/295-x' > "$fixtures/100.count_base"
printf 'Closes #400: some change\n\nBody text without a keyword' > "$fixtures/100.title_body"
output="$(PATH="$fakebin:$PATH" "$script" 100 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "T4/AC1 — release-branch PR with a title-only closing keyword gave exit $status: $output"

# AC1 — same, but the keyword is only in the body.
printf '0\trelease/295-x' > "$fixtures/101.count_base"
printf 'Some unrelated title\n\nFixes #400 in the body' > "$fixtures/101.title_body"
output="$(PATH="$fakebin:$PATH" "$script" 101 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "T4/AC1 — release-branch PR with a body-only closing keyword gave exit $status: $output"

# AC2 — a release-branch PR with no closing reference anywhere still
# fails, with the same message shape as the default-branch case.
printf '0\trelease/295-x' > "$fixtures/102.count_base"
printf 'Some unrelated title\n\nNo reference to any issue here' > "$fixtures/102.title_body"
output="$(PATH="$fakebin:$PATH" "$script" 102 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "T4/AC2 — release-branch PR with no issue reference gave exit 0"
assert_contains "T4/AC2 (release branch) — the PR number is in the message" "102" "$output"

# AC4 — the default-branch lookup itself failing must fail closed, never
# silently treat the PR as if its base were the default branch.
rm -f "$fixtures/default_branch"
printf '0\trelease/295-x' > "$fixtures/103.count_base"
output="$(PATH="$fakebin:$PATH" "$script" 103 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "T4/AC4 — a failed default-branch lookup gave exit 0 instead of a hard error"
printf 'main' > "$fixtures/default_branch"

# AC4 — the title+body fallback fetch itself failing (no .title_body
# fixture at all) must also fail closed, not silently pass or silently
# treat it as "no keyword found".
printf '0\trelease/295-x' > "$fixtures/104.count_base"
output="$(PATH="$fakebin:$PATH" "$script" 104 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "T4/AC4 — a failed title/body fetch gave exit 0 instead of a hard error"

test_done
