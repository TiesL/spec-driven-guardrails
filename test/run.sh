#!/usr/bin/env bash
# test/run.sh — Runs all test cases in test/cases/, in parallel.
#
# Each test case is a standalone script that sources test/lib.sh and exits
# with status 0 on success. They each run in their own process, with their
# own sandbox (test/lib.sh's sandbox_create — a fresh mktemp -d, its own
# HOME/SPEC_DRIVEN_GUARDRAILS_DIR/git identity), so nothing about a test
# itself depends on running alone. The only thing that used to force serial
# execution was this script's own bookkeeping: a single, reused HOME-leak
# sentinel directory. That's now one sentinel per test (AC2, issue #216).
#
# Usage: ./test/run.sh [name fragment]
# TEST_JOBS overrides the worker count (default: CPU core count). Set
# TEST_JOBS=1 to force serial execution, e.g. while chasing a flaky test.

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
filter="${1:-}"

# nproc (GNU coreutils, present on GitHub's ubuntu-latest) or sysctl (macOS)
# — whichever this machine has, capped at 4. Not "one worker per core": each
# test case itself briefly spawns a burst of subprocesses (git, tar, sed,
# python3, ...), and it's the *sum* of those bursts across concurrent
# workers that competes for the OS's per-user process ceiling (`ulimit -u`),
# not CPU time. Measured directly on an 8-core machine: 8 workers produced
# sporadic, different-test-each-run failures (a subprocess spawn losing the
# race under load); 4 workers ran the full suite clean, repeatedly, at
# close to the same wall-clock time as 8. A machine with more cores would
# only make an uncapped default worse, not better, since the process
# ceiling doesn't scale with core count.
cores="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"
if [ "$cores" -gt 4 ] 2>/dev/null; then
  cores=4
fi
jobs="${TEST_JOBS:-$cores}"

real_home="$HOME"
results_dir="$(mktemp -d)"
trap 'rm -rf "$results_dir"' EXIT

# Collected up front, in the same glob order test/run.sh always used, so
# the final summary prints in a stable, predictable order regardless of
# which worker happens to finish first.
names=()
for case_file in "$here"/cases/*.sh; do
  [ -e "$case_file" ] || continue
  name="$(basename "$case_file" .sh)"
  if [ -n "$filter" ]; then
    case "$name" in
      *"$filter"*) ;;
      *) continue ;;
    esac
  fi
  names+=("$name")
done

# Runs one test case into $results_dir/<name>.log (its full stdout/stderr,
# AC3) and $results_dir/<name>.status (its exit code). Own HOME-leak
# sentinel per call (AC2) — safe to run many of these at once, unlike the
# single shared sentinel this replaces.
run_one() {
  local name="$1" case_file="$here/cases/$1.sh" sentinel status
  sentinel="$(mktemp -d)"
  if TEST_REAL_HOME="$real_home" HOME="$sentinel" bash "$case_file" >"$results_dir/$name.log" 2>&1; then
    status=0
  else
    status=1
  fi
  if [ -n "$(ls -A "$sentinel" 2>/dev/null)" ]; then
    echo "    warning: $name wrote into HOME without sandbox_create" >>"$results_dir/$name.log"
  fi
  rm -rf "$sentinel"
  echo "$status" >"$results_dir/$name.status"
}
export -f run_one
export here results_dir real_home

if [ "${#names[@]}" -gt 0 ]; then
  printf '%s\n' "${names[@]}" | xargs -P "$jobs" -I{} bash -c 'run_one "$@"' _ {}
fi

passed=0
failed=0
failed_names=""

# "${names[@]}" on a zero-element array trips `set -u` on bash 3.2 (macOS's
# stock /bin/bash) — the "${#names[@]}" guard sidesteps that instead of
# relying on a newer bash's fixed behavior.
if [ "${#names[@]}" -gt 0 ]; then
  for name in "${names[@]}"; do
    echo "  $name"
    cat "$results_dir/$name.log"
    if [ "$(cat "$results_dir/$name.status" 2>/dev/null)" = "0" ]; then
      passed=$((passed + 1))
    else
      failed=$((failed + 1))
      failed_names="$failed_names $name"
    fi
  done
fi

echo
if [ "$failed" -gt 0 ]; then
  echo "Tests: $passed passed, $failed failed —$failed_names" >&2
  exit 1
fi

if [ "$passed" -eq 0 ]; then
  echo "Tests: not a single test case ran — that's not green." >&2
  exit 1
fi

echo "Tests: $passed passed."
