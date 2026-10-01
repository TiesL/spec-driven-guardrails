#!/usr/bin/env bash
# S173 — a check-commit that ignores TERM cannot hang the commit: the watchdog escalates to KILL (#378, review finding 1+2).
# Covers: F17
#
# After the budget the watchdog sends TERM, then after a short grace period
# KILL, to the whole process group. The fixtures below ignore TERM (an
# ignored disposition is inherited across exec and by children), so TERM
# alone leaves them running for 25 s; only KILL ends them early.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

make_project() { # $1 name; $2 body of ./check-commit
  local name="$1" project
  project="$(fresh_project "$name")"
  adopt "$project"
  git -C "$project" commit -q --allow-empty -m "first commit"
  git -C "$project" checkout -q -b feature/1-something
  printf '#!/usr/bin/env bash\n%s\n' "$2" > "$project/check-commit"
  chmod +x "$project/check-commit"
  echo "$project"
}

reap() { # kill any recorded pid still alive, so a red run leaves nothing behind
  local f pid
  for f in "$@"; do
    pid="$(cat "$SANDBOX/$f" 2>/dev/null)"
    [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null
  done
  return 0
}

# Case 1: the check itself ignores TERM (and so does its child sleep).
p="$(make_project k1 "trap '' TERM; echo \$\$ > \"$SANDBOX/k1-self\"; sleep 25; exit 1")"
SECONDS=0
out="$(cd "$p" && COMMIT_CHECK_BUDGET=2 git commit -q --allow-empty -m "second commit" 2>&1)"; st=$?
elapsed=$SECONDS
[ "$st" -eq 0 ] || fail "S173 case 1 — a timeout blocked the commit (must let it through): $out"
[ "$elapsed" -lt 15 ] || fail "S173 case 1 — the commit took ${elapsed}s with a 2 s budget: a check-commit that ignores TERM hung the commit (no KILL fallback)"
assert_contains "S173 case 1 — the warning mentions the budget" "budget" "$out"
[ "$(git -C "$p" rev-list --count HEAD)" = "2" ] || fail "S173 case 1 — no commit landed after the timeout"
pid="$(cat "$SANDBOX/k1-self" 2>/dev/null)"
[ -n "$pid" ] || fail "S173 case 1 — fixture did not record its pid"
sleep 1
if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then fail "S173 case 1 — the TERM-ignoring check-commit ($pid) survived the timeout"; fi
reap k1-self

# Case 2: the check respects TERM but a grandchild ignores it.
p="$(make_project k2 "echo \$\$ > \"$SANDBOX/k2-self\"; bash -c 'trap \"\" TERM; echo \$\$ > \"$SANDBOX/k2-grandchild\"; sleep 25' & sleep 25; exit 1")"
SECONDS=0
out="$(cd "$p" && COMMIT_CHECK_BUDGET=2 git commit -q --allow-empty -m "second commit" 2>&1)"; st=$?
elapsed=$SECONDS
[ "$st" -eq 0 ] || fail "S173 case 2 — a timeout blocked the commit (must let it through): $out"
[ "$elapsed" -lt 15 ] || fail "S173 case 2 — the commit took ${elapsed}s with a 2 s budget"
sleep 1
for f in k2-self k2-grandchild; do
  pid="$(cat "$SANDBOX/$f" 2>/dev/null)"
  [ -n "$pid" ] || { fail "S173 case 2 — fixture did not record $f"; continue; }
  if kill -0 "$pid" 2>/dev/null; then fail "S173 case 2 — process $f ($pid) survived the timeout (a grandchild that ignores TERM outlives the commit)"; fi
done
reap k2-self k2-grandchild

test_done
