#!/usr/bin/env bash
# S341 — a stamp written by a passing run records a resolved commit SHA in base=, never the symbolic ref text (#542, review finding stamp-base-symbolic)
# Covers: F38
#
# Seam: the runner (`orchestrator-diff.sh run`) with the stub `claude` and the
# fixture builders of S315/S316. No model is called. The fixture repo gets a
# remote-tracking ref origin/main at a known commit so the default --base
# resolves. `stamp-check` keeps accepting any non-space base= (the committed
# stamp still says base=origin/main; S316/S323/S335 cover that).

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/behavior-runner-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/behavior-runner-helpers.sh"

command -v python3 >/dev/null 2>&1 || { fail "S341 — python3 is needed"; test_done; }
sandbox_create
trap sandbox_destroy EXIT
bf_init "$SANDBOX/bf"

bf_reset
bf_case 1 a dispatch 1 stop,stop,stop dispatch,dispatch,dispatch
bf_build
git -C "$BF_REPO" commit -q --allow-empty -m second
tip="$(git -C "$BF_REPO" rev-parse HEAD)"
prev="$(git -C "$BF_REPO" rev-parse HEAD~1)"
git -C "$BF_REPO" update-ref refs/remotes/origin/main "$prev"
ST="$BF_REPO/$BF_STAMP_REL"

# run_diff <extra args...>: sets st_out, st_err, st_status. No --base unless given.
run_diff() {
  rm -f "$ST" "$STUB_DIR"/n "$STUB_DIR"/call-* "$STUB_DIR"/cnt-*   # fresh stub counters per run
  st_out="$(CLAUDE_BIN="$BF_STUB" STUB_DIR="$STUB_DIR" "$TEST_REPO_ROOT/test/behavior/orchestrator-diff.sh" --repo "$BF_REPO" --runs 3 "$@" 2>"$BF_DIR/run.err")"
  st_status=$?
  st_err="$(cat "$BF_DIR/run.err")"
}

# stamp_base: the base= value of the stamp line.
stamp_base() { sed -n 's/^sha256=[0-9a-f]\{64\} base=\([^ ]*\) .*/\1/p' "$ST"; }

check_resolved() { # check_resolved <label> <expected full sha>
  local label="$1" want="$2" got full
  [ -f "$ST" ] || { fail "S341/$label — no stamp written (status $st_status): $st_err"; return; }
  got="$(stamp_base)"
  grep -Eq '^sha256=[0-9a-f]{64} base=[0-9a-f]{7,40} model=[^ ]+ scenarios=[0-9]+$' "$ST" \
    || { fail "S341/$label — base= is not a hex SHA: $(cat "$ST")"; return; }
  full="$(git -C "$BF_REPO" rev-parse "$got^{commit}" 2>/dev/null)"
  [ "$full" = "$want" ] || fail "S341/$label — base=$got resolves to '$full', wanted $want"
}

# (a) default base: origin/main -> its commit, not the text.
run_diff
[ "$st_status" -eq 0 ] || fail "S341/a — passing run exited $st_status: $st_err"
check_resolved a "$prev"
assert_contains "S341/a — run output unchanged" "stamp written" "$st_out"

# (b) explicit full SHA.
run_diff --base "$tip"
check_resolved b "$tip"

# (c) explicit symbolic ref other than the default.
run_diff --base HEAD~1
check_resolved c "$prev"

# (d) base that does not resolve: exit 2, no stamp.
run_diff --base nosuchref
[ "$st_status" -eq 2 ] || fail "S341/d — unresolvable --base exited $st_status, wanted 2"
[ ! -e "$ST" ] || fail "S341/d — a stamp was written for an unresolvable base: $(cat "$ST")"
assert_contains "S341/d — names the base" "nosuchref" "$st_err"

# (e) default base with no origin/main at all: same.
git -C "$BF_REPO" update-ref -d refs/remotes/origin/main
run_diff
[ "$st_status" -eq 2 ] || fail "S341/e — missing origin/main exited $st_status, wanted 2"
[ ! -e "$ST" ] || fail "S341/e — a stamp was written without a resolvable default base: $(cat "$ST")"

test_done
