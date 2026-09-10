#!/usr/bin/env bash
# S80 — The check job has read access to pull requests and issues.
# Covers: F17

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Is "<key>: read" in effect somewhere in this file for the check job —
# at job level (under "check:") or at workflow level (before "jobs:")? Both
# count: a workflow-wide permissions: key applies to every job under it.
heeft_read_permissie() {
  local sleutel="$1" pad="$2"
  grep -qE "^[[:space:]]*${sleutel}:[[:space:]]*read[[:space:]]*\$" "$pad"
}

# check-pr-issue-link.sh (link 3, hard block) and check-main-via-pr.sh
# both need pull-requests:read to query PRs; without explicit permissions
# they get the default, minimal token scope, under which both fail — not
# incidentally, as issue #83 and #85 both showed.
#
# issues:read is a separate gap: closingIssuesReferences (what
# check-pr-issue-link.sh reads) is about the linked issue itself, not
# about the PR. Without issues:read the query silently returns an empty
# list, even when the link genuinely exists — verified on PR #105
# (issue #99, this repo's own workflow) before the same gap here for
# templates/ci.yml was closed (issue #106).
for bestand in templates/ci.yml .github/workflows/ci.yml; do
  pad="$TEST_REPO_ROOT/$bestand"

  if [ ! -f "$pad" ]; then
    fail "S80 — $bestand is missing"
    continue
  fi

  heeft_read_permissie pull-requests "$pad" \
    || fail "S80 — $bestand does not give the check job pull-requests: read"
  heeft_read_permissie issues "$pad" \
    || fail "S80 — $bestand does not give the check job issues: read"
done

test_klaar
