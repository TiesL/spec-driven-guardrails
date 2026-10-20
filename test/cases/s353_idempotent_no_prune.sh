#!/usr/bin/env bash
# S353 — a second run is silent; a skill removed upstream is neither created nor removed.
# Covers: F6, F9

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../skill-links-fixture.sh
. "$(dirname "${BASH_SOURCE[0]}")/../skill-links-fixture.sh"

sandbox_create
trap sandbox_destroy EXIT

sl_make s353 x y
rm -rf "$SL_PROJECT/.claude/skills"
echo "not a skill" > "$SL_REPO/skills/README.md"
sl_run
sl_assert_created "S353 first run" x
sl_assert_created "S353 first run" y
inode_x="$(ls -i "$SL_PROJECT/.claude/skills/x" | awk '{print $1}')"
inode_y="$(ls -i "$SL_PROJECT/.claude/skills/y" | awk '{print $1}')"

sl_run
sl_assert_nothing_created "S353 second run"
! grep -q '^New skill links' "$SL_OUT" || fail "S353 — trailing line repeated"
sl_assert_no_warning "S353 second run"
[ "$(ls -i "$SL_PROJECT/.claude/skills/x" | awk '{print $1}')" = "$inode_x" ] || fail "S353 — x recreated"
[ "$(ls -i "$SL_PROJECT/.claude/skills/y" | awk '{print $1}')" = "$inode_y" ] || fail "S353 — y recreated"
[ ! -e "$SL_PROJECT/.claude/skills/README.md" ] && [ ! -L "$SL_PROJECT/.claude/skills/README.md" ] \
  || fail "S353 — README.md was linked"
sl_assert_quiet "S353 second run"

# skill removed upstream: dangling link stays, nothing created
rm -rf "$SL_REPO/skills/x"
sl_add_skill transient
rm -rf "$SL_REPO/skills/transient"
sl_run
[ -L "$SL_PROJECT/.claude/skills/x" ] && [ ! -e "$SL_PROJECT/.claude/skills/x" ] \
  || fail "S353 — dangling x was removed or repaired"
sl_assert_nothing_created "S353 after removal"
[ ! -L "$SL_PROJECT/.claude/skills/transient" ] || fail "S353 — link for a removed transient skill"
sl_assert_quiet "S353 after removal"

test_done
