#!/usr/bin/env bash
# S43 — A healthy source produces nothing on stderr.
# Dekt: F6

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
  local omschrijving="$1" pad="$2"
  local fout="$SANDBOX/stderr.txt"
  "$TEST_REPO_ROOT/pending-changes.sh" "$pad" > /dev/null 2> "$fout"
  if [ -s "$fout" ]; then
    fail "S43 — $omschrijving produces output on stderr:"
    sed 's/^/      /' "$fout" >&2
  fi
}

# The four frozen baselines: a real cross-section of what exists in
# practice, including a project without an adoption table.
for project in a2t-emails tennis-admin tennis-registration tennis-invoicing; do
  controleer "fixture $project" "$TEST_REPO_ROOT/test/fixtures/nulmeting/$project"
done

# Freshly adopted: all rows still carry a provisional stamp.
vers="$(vers_project vers)"
adopteer "$vers"
controleer "freshly adopted project" "$vers"

# Everything substantiated: zero pending rows. That is exactly the
# boundary where the counting went wrong.
sed -i.bak 's/bij adoptie — vereist onderbouwing tijdens PRD\/architectuur/onderbouwd/g' \
  "$vers/WORKFLOW-ADOPTIE.md"
rm -f "$vers/WORKFLOW-ADOPTIE.md.bak"
controleer "project with no pending substantiations" "$vers"

# And a project that was never adopted.
kaal="$(vers_project kaal)"
controleer "unadopted project" "$kaal"

test_klaar
