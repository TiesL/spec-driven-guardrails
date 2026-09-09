#!/usr/bin/env bash
# templates/check-main-via-pr.sh — CI detects commits on main that didn't
# come from a PR (W27, F17). Detection, not prevention: the command has
# already run by then. The local hooks (W10, W26) prevent; this catches
# what slips through on a different machine or with a different tool — the
# only mechanism that works without GitHub Pro/a public repo (server-side
# branch protection is then unavailable).
#
# Called from CI, on the push-to-main event, with the SHA as argument:
#
#   ./check-main-via-pr.sh "$GITHUB_SHA"
#
# Judges only *this* push, no audit over history — same reason as
# check-pr-issue-link.sh (W19b): a retrofit that's red on day one teaches
# you to ignore the message.
#
# No fail-open: if the origin can't be established (no API answer, missing
# permissions), the check fails with the reason attached. That's
# deliberately the opposite of the local git hooks (S58): a local hook that
# fails blocks work that could already be entirely legitimate, a CI check
# that silently turns green reports "nothing wrong" while it knows nothing.
#
# Requires gh + a token with read access; on GitHub Actions, GITHUB_TOKEN is
# available for free.
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

set -uo pipefail

sha="${1:?gebruik: check-main-via-pr.sh <sha>}"

if ! command -v gh >/dev/null 2>&1; then
  echo "check-main-via-pr: gh ontbreekt — kan de herkomst van $sha niet vaststellen." >&2
  exit 1
fi

aantal="$(gh api "repos/{owner}/{repo}/commits/$sha/pulls" --jq 'length' 2>/dev/null)"

# Anything other than a clean non-negative number is "couldn't establish"
# — including empty output. Without this check, the comparison below fails
# silently (bash reports an integer-expression error, but set -e is off)
# and the script runs through to exit 0 — exactly the fail-open path this
# script rules out.
case "$aantal" in
  ''|*[!0-9]*)
    echo "check-main-via-pr: kon de herkomst van commit $sha niet vaststellen." >&2
    exit 1 ;;
esac

if [ "$aantal" -eq 0 ]; then
  echo "check-main-via-pr: commit $sha op main komt niet uit een pull request." >&2
  exit 1
fi

exit 0
