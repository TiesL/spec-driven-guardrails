#!/usr/bin/env bash
# S342 — merge-preflight.sh feeds the real merge guard the merge command as hook JSON and passes its verdict through (A44 2a)
# Covers: F8
#
# Seam: the hook's stdin JSON (A44). The script locates hooks/git-guardrails
# next to itself (the way review-rounds.sh and role-label-staleness.sh locate
# lib/), so the test copies the script beside a recording stub guard for the
# JSON and stream cases, and runs the repo's own copy with fake_gh_merge_bin
# for the verdict cases. It takes a PR number only; a branch name is a usage
# error (the guard resolves branch targets, the wrapper does not).

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

SCRIPT="$TEST_REPO_ROOT/merge-preflight.sh"
[ -x "$SCRIPT" ] || { fail "S342 — merge-preflight.sh is missing or not executable"; test_done; }
command -v python3 >/dev/null 2>&1 || { fail "S342 — python3 is needed"; test_done; }

sandbox_create
trap sandbox_destroy EXIT

# --- stub guard beside a copy of the script ---------------------------------
stub="$SANDBOX/stubrepo"
mkdir -p "$stub/hooks" "$SANDBOX/rec"
cp "$SCRIPT" "$stub/merge-preflight.sh"
cat > "$stub/hooks/git-guardrails" <<'STUB'
#!/usr/bin/env bash
cat > "$REC/stdin"
echo called > "$REC/called"
printf 'OUT-STUB'
printf 'BLOCKED-BY-STUB' >&2
exit "${STUB_EXIT:-2}"
STUB
chmod +x "$stub/hooks/git-guardrails" "$stub/merge-preflight.sh"
export REC="$SANDBOX/rec"

# (a) hook JSON is valid and exact, even for a cwd with a space and a double quote.
weird="$SANDBOX/repo with space/x\"y"
mkdir -p "$weird"
rm -f "$REC"/*
(cd "$weird" && "$stub/merge-preflight.sh" 41 >"$SANDBOX/o.txt" 2>"$SANDBOX/e.txt")
[ -f "$REC/stdin" ] || fail "S342/a — the guard was never called"
parsed="$(python3 -I -c '
import json, sys
d = json.load(open(sys.argv[1]))
print(d["tool_name"]); print(d["tool_input"]["command"]); print(d["cwd"])' "$REC/stdin" 2>&1)"
[ "$(printf '%s\n' "$parsed" | sed -n 1p)" = "Bash" ] || fail "S342/a — tool_name is not Bash: $parsed"
[ "$(printf '%s\n' "$parsed" | sed -n 2p)" = "gh pr merge 41" ] || fail "S342/a — command is not exactly 'gh pr merge 41': $parsed"
want_cwd="$(cd "$weird" && pwd -P)"
[ "$(printf '%s\n' "$parsed" | sed -n '3,$p')" = "$want_cwd" ] || fail "S342/a — cwd not intact: $parsed (wanted $want_cwd)"

# (h) the guard's exit code and both streams pass through, unmerged.
rm -f "$REC"/*
(cd "$weird" && "$stub/merge-preflight.sh" 41 >"$SANDBOX/o.txt" 2>"$SANDBOX/e.txt"); st=$?
[ "$st" -eq 2 ] || fail "S342/h — exit code not passed through (got $st)"
[ "$(cat "$SANDBOX/o.txt")" = "OUT-STUB" ] || fail "S342/h — stdout changed: $(cat "$SANDBOX/o.txt")"
[ "$(cat "$SANDBOX/e.txt")" = "BLOCKED-BY-STUB" ] || fail "S342/h — stderr changed: $(cat "$SANDBOX/e.txt")"
STUB_EXIT=0 "$stub/merge-preflight.sh" 41 >/dev/null 2>&1; st=$?
[ "$st" -eq 0 ] || fail "S342/h — a guard exit 0 was not passed through (got $st)"

# (e)(f) usage errors: non-zero, a usage line on stderr, the guard not called.
for args in "" "abc" "41 42" "feature/work" "-1" "0"; do
  rm -f "$REC"/*
  # shellcheck disable=SC2086
  "$stub/merge-preflight.sh" $args >"$SANDBOX/o.txt" 2>"$SANDBOX/e.txt"; st=$?
  [ "$st" -ne 0 ] || fail "S342/usage[$args] — exit 0 for a bad argument list"
  assert_contains "S342/usage[$args] — usage line" "usage" "$(cat "$SANDBOX/e.txt")"
  case "$(cat "$SANDBOX/e.txt")" in *BLOCKED-BY-STUB*) fail "S342/usage[$args] — the guard was called" ;; esac
  [ ! -e "$REC/called" ] || fail "S342/usage[$args] — the guard was called"
done

# --- the real guard with fake gh ---------------------------------------------
project="$(fresh_project preflight)"
git -C "$project" commit -q --allow-empty -m start
git -C "$project" checkout -q -b feature/work
green='[{"name":"check","bucket":"pass"}]'
calls="$SANDBOX/fakegh/calls.log"

real() { # real <behind> <PATH prefix or -exact> [env assignments...]: sets out, err, st
  local behind="$1" p="$2" fb path
  shift 2
  if [ "${p#-}" != "$p" ]; then path="${p#-}"; else fb="$(fake_gh_merge_bin match "$green" "$behind" main)"; path="$fb:$PATH"; fi
  rm -f "$calls"
  out="$(cd "$project" && env "$@" PATH="$path" "$SCRIPT" 41 2>"$SANDBOX/err.txt")"; st=$?
  err="$(cat "$SANDBOX/err.txt")"
}

real 3 +
[ "$st" -eq 2 ] || fail "S342/b — a behind PR was not blocked (status $st): $out$err"
assert_contains "S342/b — names the remedy" "gh pr update-branch 41" "$err"

real 0 +
[ "$st" -eq 0 ] || fail "S342/c — an up-to-date PR was blocked (status $st): $out$err"

real 3 + CLAUDE_WORKFLOW_MERGE_GUARD_OFF=1
[ "$st" -eq 0 ] || fail "S342/d — the escape hatch was not honored (status $st): $out$err"
assert_contains "S342/d — loud report" "explicitly skipped" "$err"

real 0 "-$(path_without_gh)"
[ "$st" -eq 0 ] || fail "S342/g — no gh did not fail open (status $st): $out$err"
assert_contains "S342/g — the guard's own warning" "warning:" "$err"

real 3 +
grep -q 'pr merge' "$calls" && fail "S342/never-merges — the preflight called gh pr merge: $(cat "$calls")"

test_done
