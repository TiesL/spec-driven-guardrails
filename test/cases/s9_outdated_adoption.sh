#!/usr/bin/env bash
# S9 — A stale adoption repairs itself and says so.
# Covers: F6, F9

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../skill-links-fixture.sh
. "$(dirname "${BASH_SOURCE[0]}")/../skill-links-fixture.sh"

sandbox_create
trap sandbox_destroy EXIT

# This scenario itself simulates the sequence "no skills -> skills exist, not
# yet installed". Since W9 the real checkout has a populated skills/, so
# sl_make adopts from a copy whose skills/ is emptied first, then adds the
# skills afterwards.
sl_make s9
project="$SL_PROJECT"
repo="$SL_REPO"
rm -rf "$project/.claude/skills"

# Beforehand: without skills in the repo, nothing should be reported.
sl_run
if grep -qi 'missing the skill\|Created skill link' "$SL_OUT"; then
  fail "S9 — message appeared even though this repo has no skills at all"
fi

# Given: the repo has skills, the project has not installed them.
sl_add_skill pre-merge-review
sl_add_skill deploy-guards
before="$(sl_porcelain)"

# When: a session starts.
sl_run

# Then: one link per skill, one Created line each.
for skill in pre-merge-review deploy-guards; do
  sl_assert_created "S9" "$skill"
done
[ "$(grep -c '^Created skill link' "$SL_OUT")" -eq 2 ] || fail "S9 — expected exactly two Created lines"

# And: the next-session line is printed once, after the last created link,
# and makes no promise of same-session availability.
line='New skill links may not be visible to this session; they are available from the next session start.'
[ "$(grep -cxF "$line" "$SL_OUT")" -eq 1 ] || fail "S9 — next-session line not printed exactly once"
[ "$(grep -n 'Created skill link\|^New skill links' "$SL_OUT" | tail -1 | grep -c 'New skill links')" -eq 1 ] \
  || fail "S9 — next-session line is not after the last Created line"

# And: no warning, nothing new in git status, exit 0, stderr empty.
sl_assert_no_warning "S9"
[ "$(sl_porcelain)" = "$before" ] || fail "S9 — git status changed: the links are not ignored"
sl_assert_quiet "S9"

# And: a second run prints no Created line.
sl_run
sl_assert_nothing_created "S9 second run"
sl_assert_quiet "S9 second run"

test_done
