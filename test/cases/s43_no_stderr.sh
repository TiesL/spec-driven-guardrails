#!/usr/bin/env bash
# S43 — A healthy source produces nothing on stderr.
# Covers: F6

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# This check exists because the hook sends stderr to /dev/null and every
# other test does too. A shell error in the script therefore stayed
# structurally invisible — one occurred daily in three of the four
# real projects without anything complaining.
controleer() {
  local description="$1" path="$2"
  local error="$SANDBOX/stderr.txt"
  "$TEST_REPO_ROOT/pending-changes.sh" "$path" > /dev/null 2> "$error"
  if [ -s "$error" ]; then
    fail "S43 — $description produces output on stderr:"
    sed 's/^/      /' "$error" >&2
  fi
}

# The four frozen baselines: a real cross-section of what exists in
# practice, including a project without an adoption table.
for project in a2t-emails tennis-admin tennis-registration tennis-invoicing; do
  controleer "fixture $project" "$TEST_REPO_ROOT/test/fixtures/nulmeting/$project"
done

# Freshly adopted: all rows still carry a provisional stamp.
fresh="$(fresh_project fresh)"
adopt "$fresh"
controleer "freshly adopted project" "$fresh"

# Everything substantiated: zero pending rows. That is exactly the
# boundary where the counting went wrong.
sed -i.bak 's/at adoption — requires substantiation during PRD\/architecture/onderbouwd/g' \
  "$fresh/WORKFLOW-ADOPTION.md"
rm -f "$fresh/WORKFLOW-ADOPTION.md.bak"
controleer "project with no pending substantiations" "$fresh"

# And a project that was never adopted.
bare="$(fresh_project bare)"
controleer "unadopted project" "$bare"

test_done
