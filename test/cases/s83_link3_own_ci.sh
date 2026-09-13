#!/usr/bin/env bash
# S83 — Link 3 (PR references issue) runs in this repo's own CI.
# Covers: F17

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

path="$TEST_REPO_ROOT/.github/workflows/ci.yml"
[ -f "$path" ] || { fail "S83 — $path is missing"; test_done; }

# Then: a step that calls check-pr-issue-link.sh, only on the
# pull_request event — the same shape as "Commit on main comes from a PR"
# below uses for the push event. grep -A4: enough lines to catch if/env/
# GITHUB_TOKEN/run without picking up the next step.
step="$(grep -A4 'name: PR references issue' "$path")"
[ -n "$step" ] || fail "S83 — $path has no 'PR references issue' step"

case "$step" in
  *"if: github.event_name == 'pull_request'"*) ;;
  *) fail "S83 — the link-3 step is not tied to the pull_request event" ;;
esac

case "$step" in
  *check-pr-issue-link.sh*) ;;
  *) fail "S83 — the link-3 step does not call check-pr-issue-link.sh" ;;
esac

# And: the job still has pull-requests: read (issue #85/#91) — without
# that scope this step blocks every PR, not incidentally.
grep -qE '^\s*pull-requests:\s*read\s*$' "$path" \
  || fail "S83 — the check job is missing pull-requests: read"

# And: issues: read. closingIssuesReferences — what check-pr-issue-link.sh
# reads — is a field about the linked issue itself, not about the PR.
# Without issues:read the query under the CI token silently returns an
# empty list, even when the link genuinely exists: exactly what happened on
# PR #105 (run 34234378780) before this line was added. pull-requests:read
# alone thus turned out not to be enough for link 3, contrary to what
# #85/#91 assumed.
grep -qE '^\s*issues:\s*read\s*$' "$path" \
  || fail "S83 — the check job is missing issues: read"

test_done
