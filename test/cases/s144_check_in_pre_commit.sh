#!/usr/bin/env bash
# S144 — hooks/pre-commit runs the project's declared check-commit within a budget, and never ./check (#263, #378).
# Covers: F17
#
# #378 (A21-A23): the hook runs an executable `check-commit` at the project
# root (blocking on a real failure within the budget, letting a timeout
# through with a warning), prints one CI-pointer line when only `./check`
# exists, and NEVER runs `./check`. Every fixture `./check` here exits 1 and
# writes a marker, so a hook that still calls it shows up as a marker (and
# usually a block), not as a lucky pass.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# A project with the workflow adopted and one commit on main, then a feature
# branch. $1 name; $2 body of ./check-commit ("" = none, "noexec" = present
# but not executable via third arg); every project also gets a full ./check
# that exits 1 and leaves $SANDBOX/<name>-full-ran.
make_project() {
  local name="$1" commit_body="$2" with_check="${3:-yes}" project
  project="$(fresh_project "$name")"
  adopt "$project"
  # The first commit goes in before any check file exists, so a fixture's
  # own red check-commit cannot block the setup.
  git -C "$project" commit -q --allow-empty -m "first commit"
  git -C "$project" checkout -q -b feature/1-something
  if [ "$with_check" = "yes" ]; then
    cat > "$project/check" <<EOT
#!/usr/bin/env bash
touch "$SANDBOX/$name-full-ran"
echo "FULL CHECK RAN"
exit 1
EOT
    chmod +x "$project/check"
  fi
  if [ -n "$commit_body" ]; then
    printf '#!/usr/bin/env bash\n%s\n' "$commit_body" > "$project/check-commit"
    chmod +x "$project/check-commit"
  fi
  echo "$project"
}

commit_in() { # $1 project; remaining args: env assignments for the commit
  local project="$1"; shift
  (cd "$project" && env "$@" git commit -q --allow-empty -m "second commit" 2>&1)
}

# Case 1: a green check-commit lets the commit through; the full ./check is not run.
p="$(make_project c1 "touch \"$SANDBOX/c1-quick-ran\"; exit 0")"
out="$(commit_in "$p" X=1)"; st=$?
[ "$st" -eq 0 ] || fail "S144 case 1 — blocked despite a green check-commit: $out"
[ -e "$SANDBOX/c1-quick-ran" ] || fail "S144 case 1 — the declared check-commit was not run"
[ ! -e "$SANDBOX/c1-full-ran" ] || fail "S144 case 1 — the full ./check ran at commit time"

# Case 2: a red check-commit blocks, shows its own output; the full ./check is not run.
p="$(make_project c2 'echo "FAKE QUICK FAILURE"; exit 1')"
out="$(commit_in "$p" X=1)"; st=$?
[ "$st" -ne 0 ] || fail "S144 case 2 — not blocked despite a red check-commit"
assert_contains "S144 case 2 — check-commit's own output is shown" "FAKE QUICK FAILURE" "$out"
assert_contains "S144 case 2 — the block names check-commit" "check-commit" "$out"
[ ! -e "$SANDBOX/c2-full-ran" ] || fail "S144 case 2 — the full ./check ran at commit time"
[ "$(git -C "$p" rev-list --count HEAD)" = "1" ] || fail "S144 case 2 — a commit landed despite the block"

# Case 2b: a failure that takes a while but stays inside the budget still blocks
# (a timeout and a slow real failure must not be confused).
p="$(make_project c2b 'sleep 1; echo "SLOW QUICK FAILURE"; exit 1')"
out="$(commit_in "$p" COMMIT_CHECK_BUDGET=10)"; st=$?
[ "$st" -ne 0 ] || fail "S144 case 2b — a slow failure within the budget did not block"
assert_contains "S144 case 2b — output shown" "SLOW QUICK FAILURE" "$out"

# Case 3 (AC5, AC6): only ./check (red, writes a marker) -> commit goes through,
# exactly one warning line naming CI, ./check never invoked.
p="$(make_project c3 "")"
out="$(commit_in "$p" X=1)"; st=$?
[ "$st" -eq 0 ] || fail "S144 case 3 — blocked with only a ./check present: $out"
[ ! -e "$SANDBOX/c3-full-ran" ] || fail "S144 case 3 — the full ./check ran at commit time"
ci_lines="$(printf '%s\n' "$out" | grep -c 'runs in CI')"
[ "$ci_lines" -eq 1 ] || fail "S144 case 3 — expected exactly one line saying the full check runs in CI, got $ci_lines: $out"
assert_contains "S144 case 3 — the line points at the entry" "ci-commit-check" "$out"
case "$out" in *"FULL CHECK RAN"*) fail "S144 case 3 — ./check output leaked into the commit" ;; esac

# Case 3b: a check-commit that is present but not executable is not a declaration.
p="$(make_project c3b "exit 1")"
chmod -x "$p/check-commit"
out="$(commit_in "$p" X=1)"; st=$?
[ "$st" -eq 0 ] || fail "S144 case 3b — a non-executable check-commit blocked the commit: $out"
assert_contains "S144 case 3b — treated as undeclared" "runs in CI" "$out"
[ ! -e "$SANDBOX/c3b-full-ran" ] || fail "S144 case 3b — the full ./check ran at commit time"

# Case 4: neither file -> the existing warning, and no CI pointer (it would be false).
p="$(make_project c4 "" no)"
out="$(commit_in "$p" X=1)"; st=$?
[ "$st" -eq 0 ] || fail "S144 case 4 — blocked with no check at all: $out"
assert_contains "S144 case 4 — existing warning" "no executable ./check" "$out"
case "$out" in *"runs in CI"*) fail "S144 case 4 — a CI pointer was printed for a project with no ./check" ;; esac

# Case 5: the escape hatch also covers this guard; check-commit is not even run.
p="$(make_project c5 "touch \"$SANDBOX/c5-quick-ran\"; exit 1")"
out="$(commit_in "$p" CLAUDE_WORKFLOW_GUARDRAILS_OFF=1)"; st=$?
[ "$st" -eq 0 ] || fail "S144 case 5 — the escape hatch did not let the commit through: $out"
assert_contains "S144 case 5 — warning names the disabled guard" "disabled via CLAUDE_WORKFLOW_GUARDRAILS_OFF" "$out"
[ ! -e "$SANDBOX/c5-quick-ran" ] || fail "S144 case 5 — check-commit ran although the guards were off"

# Case 6 (timeout): COMMIT_CHECK_BUDGET=2 and a check-commit that sleeps -> the
# commit goes through quickly with a budget warning, and the sleeping child
# (and its own child) is gone afterwards.
p="$(make_project c6 "echo \$\$ > \"$SANDBOX/c6-self\"; sleep 30 & echo \$! > \"$SANDBOX/c6-child\"; bash -c 'sleep 31 & echo \$! > \"$SANDBOX/c6-grandchild\"; wait' & wait")"
SECONDS=0
out="$(commit_in "$p" COMMIT_CHECK_BUDGET=2)"; st=$?
elapsed=$SECONDS
[ "$st" -eq 0 ] || fail "S144 case 6 — a timeout blocked the commit (must let it through): $out"
[ "$elapsed" -lt 15 ] || fail "S144 case 6 — the commit took ${elapsed}s with a 2 s budget"
assert_contains "S144 case 6 — a warning mentions the budget" "budget" "$out"
assert_contains "S144 case 6 — the warning points at CI" "CI" "$out"
[ ! -e "$SANDBOX/c6-full-ran" ] || fail "S144 case 6 — the full ./check ran at commit time"
[ "$(git -C "$p" rev-list --count HEAD)" = "2" ] || fail "S144 case 6 — no commit landed after the timeout"
sleep 1
for f in c6-self c6-child c6-grandchild; do
  pid="$(cat "$SANDBOX/$f" 2>/dev/null)"
  [ -n "$pid" ] || { fail "S144 case 6 — fixture did not record $f"; continue; }
  if kill -0 "$pid" 2>/dev/null; then
    fail "S144 case 6 — process $f ($pid) survived the timeout"
    kill -9 "$pid" 2>/dev/null
  fi
done

# Case 7: check-commit gets no arguments, runs at the project root, and sees none
# of git's repo-local variables.
p="$(make_project c7 "{ echo \"args=\$#\"; echo \"pwd=\$(pwd -P)\"; env; } > \"$SANDBOX/c7-seen\"")"
out="$(commit_in "$p" X=1)"; st=$?
[ "$st" -eq 0 ] || fail "S144 case 7 — blocked: $out"
seen="$SANDBOX/c7-seen"
[ -f "$seen" ] || fail "S144 case 7 — check-commit did not run"
grep -qx 'args=0' "$seen" || fail "S144 case 7 — check-commit received arguments"
grep -qx "pwd=$(cd "$p" && pwd -P)" "$seen" || fail "S144 case 7 — check-commit did not run at the project root"
for v in $(git rev-parse --local-env-vars); do
  if grep -q "^$v=" "$seen"; then fail "S144 case 7 — check-commit saw $v"; fi
done

test_done
