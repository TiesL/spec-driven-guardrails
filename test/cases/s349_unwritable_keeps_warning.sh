#!/usr/bin/env bash
# S349 — when links cannot be created the warning stays, exit 0, empty stderr.
# Covers: F6, F9

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../skill-links-fixture.sh
. "$(dirname "${BASH_SOURCE[0]}")/../skill-links-fixture.sh"

sandbox_create
trap sandbox_destroy EXIT

if [ "$(id -u)" -eq 0 ]; then
  echo "    skipped: root ignores file modes" >&2
  test_done
  exit 0
fi
cleanup() { chmod -R u+w "$SANDBOX" 2>/dev/null; sandbox_destroy; }
trap cleanup EXIT

# (a) .claude/skills exists but is read-only
sl_make s349a p q
chmod a-w "$SL_PROJECT/.claude/skills"
sl_run
sl_assert_nothing_created "S349a"
sl_assert_warns "S349a" "p, q"
sl_assert_quiet "S349a"
chmod u+w "$SL_PROJECT/.claude/skills"

# (b) .claude/skills absent and .claude read-only
sl_make s349b p q
rm -rf "$SL_PROJECT/.claude/skills"
chmod a-w "$SL_PROJECT/.claude"
sl_run
sl_assert_nothing_created "S349b"
sl_assert_warns "S349b" "p, q"
sl_assert_quiet "S349b"
chmod u+w "$SL_PROJECT/.claude"

# (c) one ln fails for name b, the rest must still be created
sl_make s349c a b c
shim="$SANDBOX/shim"; mkdir -p "$shim"
real_ln="$(command -v ln)"
cat > "$shim/ln" <<SHIM
#!/bin/sh
for arg in "\$@"; do
  case "\$arg" in */b) exit 1 ;; esac
done
exec "$real_ln" "\$@"
SHIM
chmod +x "$shim/ln"
rm -rf "$SL_PROJECT/.claude/skills"
SL_RUNS=$((SL_RUNS + 1))
SL_OUT="$SANDBOX/hook-out.$SL_RUNS"; SL_ERR="$SANDBOX/hook-err.$SL_RUNS"
PATH="$shim:$PATH" "$SL_REPO/pending-changes.sh" "$SL_PROJECT" > "$SL_OUT" 2> "$SL_ERR"
SL_STATUS=$?
sl_assert_created "S349c" a
sl_assert_created "S349c" c
[ ! -e "$SL_PROJECT/.claude/skills/b" ] || fail "S349c — b exists"
! grep -q '^Created skill link: .*/b ' "$SL_OUT" || fail "S349c — b reported as created"
sl_assert_warns "S349c" "b"
sl_assert_quiet "S349c"

test_done
