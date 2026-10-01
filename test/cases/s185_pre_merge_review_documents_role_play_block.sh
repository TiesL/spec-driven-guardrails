#!/usr/bin/env bash
# S185 — The pre-merge-review skill says a role-played run blocks the merge.
# Covers: F37
#
# Issue #371, AC9 and human decision 3. The gate itself only prints
# findings and exits 0 (S183); blocking is the review verdict withholding
# its approval marker, so the mechanical proxy is that the procedure the
# reviewer follows says so, including the override record and the
# fail-open case. Whether a reviewer follows it is Reviewer behaviour.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

skill="$TEST_REPO_ROOT/skills/pre-merge-review/SKILL.md"

# The paragraph(s) that mention a role-played run.
paras="$(awk 'BEGIN{RS=""; ORS="\n\n"} tolower($0) ~ /role-played/' "$skill")"
if [ -z "$paras" ]; then
  fail "S185 — pre-merge-review/SKILL.md never mentions a role-played run"
  test_done
fi
lower="$(tr '[:upper:]' '[:lower:]' <<<"$paras")"
for needle in "block" "pipeline-override" "gh"; do
  case "$lower" in
    *"$needle"*) ;;
    *) fail "S185 — the role-played paragraph does not mention '$needle'" ;;
  esac
done
# It is a blocking finding, unlike the missing-marker finding ("non-blocking").
case "$lower" in
  *"not block"*|*"non-blocking"*|*"doesn't block"*) fail "S185 — the role-played finding is described as non-blocking" ;;
esac

test_done
