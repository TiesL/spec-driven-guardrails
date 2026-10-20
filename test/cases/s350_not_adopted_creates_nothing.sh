#!/usr/bin/env bash
# S350 — a project not adopted into this checkout gets nothing created.
# Covers: F6, F9

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../skill-links-fixture.sh
. "$(dirname "${BASH_SOURCE[0]}")/../skill-links-fixture.sh"

sandbox_create
trap sandbox_destroy EXIT

other="$(sandbox_copy_repo other-checkout)"

check_not_adopted() {
  local label="$1" before
  rm -rf "$SL_PROJECT/.claude/skills"
  before="$(sl_porcelain)"
  sl_run
  [ ! -e "$SL_PROJECT/.claude/skills" ] || fail "$label — .claude/skills appeared"
  sl_assert_nothing_created "$label"
  [ "$(sl_porcelain)" = "$before" ] || fail "$label — git status changed"
  sl_assert_warns "$label" "alpha"
  sl_assert_quiet "$label"
}

# (a) settings.json absent
sl_make s350a alpha
rm -f "$SL_PROJECT/.claude/settings.json"
check_not_adopted "S350a"

# (b) settings.json a regular file
sl_make s350b alpha
rm -f "$SL_PROJECT/.claude/settings.json"
echo '{}' > "$SL_PROJECT/.claude/settings.json"
check_not_adopted "S350b"

# (c) settings.json a symlink into another checkout
sl_make s350c alpha
rm -f "$SL_PROJECT/.claude/settings.json"
ln -s "$other/settings/session-hooks.json" "$SL_PROJECT/.claude/settings.json"
check_not_adopted "S350c"

# (d) positive control: relative symlink resolving into this checkout
sl_make s350d alpha
rm -f "$SL_PROJECT/.claude/settings.json"
rel="$(cd "$SL_PROJECT/.claude" && python3 -c 'import os,sys;print(os.path.relpath(sys.argv[1]))' "$SL_REPO/settings/session-hooks.json" 2>/dev/null)"
if [ -n "$rel" ]; then
  ln -s "$rel" "$SL_PROJECT/.claude/settings.json"
  rm -rf "$SL_PROJECT/.claude/skills"
  sl_run
  sl_assert_created "S350d" alpha
  sl_assert_quiet "S350d"
else
  echo "    skipped (d): no python3 to compute a relative path" >&2
fi

test_done
