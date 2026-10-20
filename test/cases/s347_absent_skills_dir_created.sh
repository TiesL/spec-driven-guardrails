#!/usr/bin/env bash
# S347 — an absent .claude/skills/ is created when its entries are gitignored.
# Covers: F6, F9

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../skill-links-fixture.sh
. "$(dirname "${BASH_SOURCE[0]}")/../skill-links-fixture.sh"

sandbox_create
trap sandbox_destroy EXIT

sl_make s347 alpha beta
rm -rf "$SL_PROJECT/.claude/skills"

# The trap, asserted so the fixture cannot rot: the directory-only entry
# does not match the absent bare directory, but does match a path below it.
if git -C "$SL_PROJECT" check-ignore -q .claude/skills; then
  fail "S347 — fixture: bare absent .claude/skills is already reported ignored"
fi
git -C "$SL_PROJECT" check-ignore -q .claude/skills/alpha \
  || fail "S347 — fixture: .claude/skills/alpha is not ignored"

before="$(sl_porcelain)"
sl_run

[ -d "$SL_PROJECT/.claude/skills" ] && [ ! -L "$SL_PROJECT/.claude/skills" ] \
  || fail "S347 — .claude/skills is not a real directory"
sl_assert_created "S347" alpha
sl_assert_created "S347" beta
sl_assert_no_warning "S347"
[ "$(sl_porcelain)" = "$before" ] || fail "S347 — git status changed"
sl_assert_quiet "S347"

test_done
