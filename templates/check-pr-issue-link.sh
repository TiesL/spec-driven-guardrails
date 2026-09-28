#!/usr/bin/env bash
# templates/check-pr-issue-link.sh — Link 3 as a hard block in CI (W19b,
# F13 decision d): fails if the PR triggering this CI run references no
# issue at all.
#
# Called from CI, with the PR number as argument:
#
#   ./check-pr-issue-link.sh "$PR_NUMBER"
#
# Only the current PR is judged — no audit over history: an audit over the
# 27 issue-less PRs from before this work item would keep failing forever
# and so get disabled within a week (see F13).
#
# Requires gh + a token with read access; on GitHub Actions, GITHUB_TOKEN is
# available for free. Deliberately not part of the local, offline `check` —
# that's link 1 (check-traceability.sh). Links 2 and 3 need network and so
# live here and in `pre-merge-review`'s gate.
#
# No fail-open here: this is the *hard* block precisely because GITHUB_TOKEN
# is guaranteed on CI. If gh can't consult the PR, that's a real CI infra
# problem and the check should fail loudly, not silently let it through.
#
# Non-default-base PRs (issue #320, surfaced by the release-branch workflow
# tier, issue #309): GitHub only populates `closingIssuesReferences` from a
# closing keyword ("Closes #N" etc.) in the PR body or a commit message
# when the PR's base is the repository's *default* branch — documented
# GitHub behavior, not a bug in the field. A PR into any other branch
# reports zero closing references even when its body plainly says
# "Closes #N".
#
# A *manually* linked issue (via the PR's Development sidebar) populates
# the same field regardless of base branch and needs no fallback — but
# there's no public API to create that link programmatically, so it can't
# be this script's primary remedy for a PR an orchestrating session opens
# itself.
#
# The fix: `closingIssuesReferences` stays the fast path — it already
# covers the default-branch case and any non-default-branch PR that
# happens to have a manual sidebar link. Only when that's empty AND the
# PR's base isn't the default branch do we fall back to a direct keyword
# match against the PR's own title+body. Scanning the *title* too is a
# deliberate broadening beyond GitHub's own documented default-branch
# scope (which names the body/commit messages, not the title) — this
# repo's own release-branch PRs consistently put "Closes #N" only in the
# title (#311/#312/#314/#316), so a fallback that only read the body would
# still miss the exact shape it exists to catch. A default-branch PR with
# zero closing references still fails exactly as before — no
# keyword-fallback logic runs for the case GitHub already handles, so
# there's no risk of this script being laxer than GitHub's own behavior
# for the common case.
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

set -uo pipefail

pr_number="${1:?usage: check-pr-issue-link.sh <pr-number>}"

if ! command -v gh >/dev/null 2>&1; then
  echo "check-pr-issue-link: gh is missing — can't check link 3." >&2
  exit 1
fi

# One call for both fields needed on the fast path, tab-separated (same
# transport convention as compliance-evidence.sh's IFS=$'\t' pairs) —
# avoids a second `gh` round trip for the common case where
# closingIssuesReferences already answers the question.
fast_path="$(gh pr view "$pr_number" \
  --json closingIssuesReferences,baseRefName \
  --jq '[(.closingIssuesReferences | length | tostring), .baseRefName] | join("\t")' \
  2>/dev/null)"
IFS=$'\t' read -r count base_ref <<<"$fast_path"

# Anything other than a clean non-negative number counts as "couldn't
# consult" — including empty output and an unexpected value like "null".
# Without this validation, the comparison below fails silently (bash
# reports an integer-expression error but `set -e` is off), and the script
# then runs through to the last line: exactly the fail-open path this
# file's header rules out for the one hard block.
case "$count" in
  ''|*[!0-9]*)
    echo "check-pr-issue-link: couldn't consult PR #$pr_number." >&2
    exit 1 ;;
esac

if [ "$count" -gt 0 ]; then
  exit 0
fi

if [ -z "$base_ref" ]; then
  echo "check-pr-issue-link: couldn't consult PR #$pr_number." >&2
  exit 1
fi

default_branch="$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null)"
if [ -z "$default_branch" ]; then
  echo "check-pr-issue-link: couldn't establish the repository's default branch — can't judge PR #$pr_number." >&2
  exit 1
fi

if [ "$base_ref" = "$default_branch" ]; then
  echo "check-pr-issue-link: PR #$pr_number references no issue at all (link 3) — add 'Closes #<issue>' or link the issue in the PR sidebar." >&2
  exit 1
fi

# Non-default base, zero closing references: GitHub never parsed this PR's
# title/body for closing keywords at all (that parsing itself is gated on
# the default branch), so fall back to reading the same text ourselves.
title_body="$(gh pr view "$pr_number" --json title,body --jq '.title + "\n" + (.body // "")' 2>/dev/null)"
if [ -z "$title_body" ]; then
  echo "check-pr-issue-link: couldn't consult PR #$pr_number." >&2
  exit 1
fi

# GitHub's own closing-keyword vocabulary: close/closes/closed,
# fix/fixes/fixed, resolve/resolves/resolved, optionally followed by ":",
# then required whitespace, then "#<issue-number>". Case-insensitive, same
# as GitHub's own parser. Deliberately not tied to a specific issue number
# — link 3 only asks "references no issue at all", the same scope the fast
# path already has.
if grep -qiE '\b(close[sd]?|fix(e[sd])?|resolve[sd]?):?[[:space:]]+#[0-9]+\b' <<<"$title_body"
then
  exit 0
fi

echo "check-pr-issue-link: PR #$pr_number references no issue at all (link 3) — add 'Closes #<issue>' or link the issue in the PR sidebar." >&2
exit 1
