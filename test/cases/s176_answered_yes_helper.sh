#!/usr/bin/env bash
# S176 — answered_yes: one shared "is this row answered yes" rule.
# Covers: F38
#
# Issue #371, A16 (the helper replaces adopt.sh's hard-coded
# issue_tracking_answered_yes). Seam: lib/changes.sh `answered_yes
# <project-dir> <id>`, exit 0 for yes/ja, exit 1 otherwise.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"
# shellcheck source=../../lib/changes.sh disable=SC1091
. "$TEST_REPO_ROOT/lib/changes.sh"

sandbox_create
trap sandbox_destroy EXIT

if ! type answered_yes >/dev/null 2>&1; then
  fail "S176 — lib/changes.sh defines no answered_yes function"
  test_done
fi

id="process-multi-agent-roles"

expect_yes() {
  local label="$1" dir="$2" the_id="${3:-$id}"
  answered_yes "$dir" "$the_id" || fail "S176 — $label: expected answered_yes to succeed"
}
expect_not_yes() {
  local label="$1" dir="$2" the_id="${3:-$id}"
  if answered_yes "$dir" "$the_id"; then fail "S176 — $label: expected answered_yes to fail"; fi
}

p="$(fresh_project yes)"
write_adoption "$p/WORKFLOW-ADOPTION.md" "$id" yes
expect_yes "yes row" "$p"

p="$(fresh_project no)"
write_adoption "$p/WORKFLOW-ADOPTION.md" "$id" no
expect_not_yes "no row" "$p"

p="$(fresh_project absent-row)"
write_adoption "$p/WORKFLOW-ADOPTION.md" process-prd yes
expect_not_yes "other row yes, this row absent" "$p"

p="$(fresh_project nofile)"
expect_not_yes "no adoption file at all" "$p"

# A row whose Notes column says "yes" must not count: only the Answer column.
p="$(fresh_project notes)"
{
  echo "| Change | Answer | Date | Notes |"
  echo "|---|---|---|---|"
  echo "| $id | no | 2026-10-01 | the answer is yes in spirit, but no for now |"
} > "$p/WORKFLOW-ADOPTION.md"
expect_not_yes "yes only in the Notes column" "$p"

# An id that merely starts with / contains the asked id is a different row.
p="$(fresh_project prefix)"
write_adoption "$p/WORKFLOW-ADOPTION.md" "${id}-extra" yes "x$id" yes
expect_not_yes "a different id sharing the text" "$p"

# The pre-migration file and vocabulary (W42/#114): ja in WORKFLOW-ADOPTIE.md.
p="$(fresh_project old)"
write_adoption "$p/WORKFLOW-ADOPTIE.md" "$id" ja
expect_yes "ja in the pre-migration file" "$p"
p="$(fresh_project oldnee)"
write_adoption "$p/WORKFLOW-ADOPTIE.md" "$id" nee
expect_not_yes "nee in the pre-migration file" "$p"

# The new file takes priority over the old one, as everywhere else.
p="$(fresh_project both)"
write_adoption "$p/WORKFLOW-ADOPTION.md" "$id" no
write_adoption "$p/WORKFLOW-ADOPTIE.md" "$id" ja
expect_not_yes "new file says no, old file says ja" "$p"

# The renamed-id alias the old helper handled: process-issue-tracking's old id.
old_id="$(changes_old_id process-issue-tracking)"
if [ -n "$old_id" ]; then
  p="$(fresh_project alias)"
  write_adoption "$p/WORKFLOW-ADOPTION.md" "$old_id" yes
  expect_yes "a row under the pre-rename id" "$p" process-issue-tracking
fi

# The helper is generic: any id, not just the multi-agent one.
p="$(fresh_project generic)"
write_adoption "$p/WORKFLOW-ADOPTION.md" process-prd yes
expect_yes "another id" "$p" process-prd
expect_not_yes "the asked id is not the yes one" "$p" process-diagnose-bug

# adopt.sh no longer carries its own copy of the rule (one rule, three callers).
if grep -q '^issue_tracking_answered_yes()' "$TEST_REPO_ROOT/adopt.sh"; then
  fail "S176 — adopt.sh still defines its own issue_tracking_answered_yes; it must use the shared answered_yes"
fi

test_done
