#!/usr/bin/env bash
# S348 — an existing path at a skill name is left alone; other names are still created.
# Covers: F6, F9

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../skill-links-fixture.sh
. "$(dirname "${BASH_SOURCE[0]}")/../skill-links-fixture.sh"

sandbox_create
trap sandbox_destroy EXIT

sl_make s348 a b c d e
s="$SL_PROJECT/.claude/skills"
rm -rf "$s"; mkdir -p "$s" "$SANDBOX/elsewhere" "$SANDBOX/gone"
echo x > "$SANDBOX/elsewhere/x.txt"
mkdir "$s/a"; echo keep > "$s/a/keep.txt"
echo filecontent > "$s/b"
ln -s "$SANDBOX/elsewhere" "$s/c"
ln -s "$SANDBOX/gone/missing" "$s/d"
rm -rf "$SANDBOX/gone"

before="$(sl_porcelain)"
sl_run

[ "$(ls "$s/a")" = "keep.txt" ] || fail "S348 — a/ was touched: $(ls "$s/a")"
[ ! -L "$s/a" ] || fail "S348 — a became a link"
[ "$(cat "$s/b")" = "filecontent" ] && [ ! -L "$s/b" ] || fail "S348 — file b was touched"
[ "$(readlink "$s/c")" = "$SANDBOX/elsewhere" ] || fail "S348 — c was repointed"
[ "$(ls "$SANDBOX/elsewhere")" = "x.txt" ] || fail "S348 — a link was written through c"
[ "$(readlink "$s/d")" = "$SANDBOX/gone/missing" ] || fail "S348 — dangling d was replaced"
sl_assert_created "S348" e
sl_assert_warns "S348" "d"
[ "$(sl_porcelain)" = "$before" ] || fail "S348 — git status changed"
sl_assert_quiet "S348"

test_done
