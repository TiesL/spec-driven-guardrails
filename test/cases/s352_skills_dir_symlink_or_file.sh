#!/usr/bin/env bash
# S352 — a .claude/skills that is a symlink or a file is left alone.
# Covers: F6, F9

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../skill-links-fixture.sh
. "$(dirname "${BASH_SOURCE[0]}")/../skill-links-fixture.sh"

sandbox_create
trap sandbox_destroy EXIT

# (a) symlink to an empty outside directory
sl_make s352a alpha beta
rm -rf "$SL_PROJECT/.claude/skills"
mkdir "$SANDBOX/outside"
ln -s "$SANDBOX/outside" "$SL_PROJECT/.claude/skills"
before="$(sl_porcelain)"
sl_run
[ -z "$(ls -A "$SANDBOX/outside")" ] || fail "S352a — wrote through the symlink: $(ls -A "$SANDBOX/outside")"
[ "$(readlink "$SL_PROJECT/.claude/skills")" = "$SANDBOX/outside" ] || fail "S352a — symlink changed"
sl_assert_nothing_created "S352a"
sl_assert_warns "S352a" "alpha, beta"
[ "$(sl_porcelain)" = "$before" ] || fail "S352a — git status changed"
sl_assert_quiet "S352a"

# (b) regular file
sl_make s352b alpha beta
rm -rf "$SL_PROJECT/.claude/skills"
echo content > "$SL_PROJECT/.claude/skills"
before="$(sl_porcelain)"
sl_run
[ -f "$SL_PROJECT/.claude/skills" ] && [ ! -L "$SL_PROJECT/.claude/skills" ] \
  && [ "$(cat "$SL_PROJECT/.claude/skills")" = "content" ] || fail "S352b — file replaced or changed"
sl_assert_nothing_created "S352b"
sl_assert_warns "S352b" "alpha, beta"
[ "$(sl_porcelain)" = "$before" ] || fail "S352b — git status changed"
sl_assert_quiet "S352b"

test_done
