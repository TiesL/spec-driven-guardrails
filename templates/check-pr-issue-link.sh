#!/usr/bin/env bash
# templates/check-pr-issue-link.sh — Link 3 as a hard block in CI (W19b,
# F13 decision d): fails if the PR triggering this CI run references no
# issue at all.
#
# Called from CI, with the PR number as argument:
#
#   ./check-pr-issue-link.sh "$PR_NUMMER"
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
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

set -uo pipefail

pr_nummer="${1:?gebruik: check-pr-issue-link.sh <pr-nummer>}"

if ! command -v gh >/dev/null 2>&1; then
  echo "check-pr-issue-link: gh is missing — can't check link 3." >&2
  exit 1
fi

aantal="$(gh pr view "$pr_nummer" --json closingIssuesReferences \
  --jq '.closingIssuesReferences | length' 2>/dev/null)"

# Anything other than a clean non-negative number counts as "couldn't
# consult" — including empty output and an unexpected value like "null".
# Without this validation, the comparison below fails silently (bash
# reports an integer-expression error but `set -e` is off), and the script
# then runs through to the last line: exactly the fail-open path this
# file's header rules out for the one hard block.
case "$aantal" in
  ''|*[!0-9]*)
    echo "check-pr-issue-link: couldn't consult PR #$pr_nummer." >&2
    exit 1 ;;
esac

if [ "$aantal" -eq 0 ]; then
  echo "check-pr-issue-link: PR #$pr_nummer references no issue at all (link 3) — add 'Closes #<issue>' or link the issue in the PR sidebar." >&2
  exit 1
fi

exit 0
