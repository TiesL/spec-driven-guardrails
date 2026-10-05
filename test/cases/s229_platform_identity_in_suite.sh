#!/usr/bin/env bash
# S229 — On the macOS CI leg the suite judges its own tool identity: this
# case runs test/platform-identity.sh in the suite's own environment (same
# PATH, same bash, same locale as every other case), prints the identity into
# the case log, and is red naming the tool or locale on a mismatch (#422,
# A35b D1, AC1/AC2).
# Covers: F43
#
# Gate: GITHUB_ACTIONS=true and RUNNER_OS=macOS, both set by the runner
# itself. Elsewhere the case prints a note and passes (the Linux leg and a
# local run on a Mac assert nothing).
#
# Two parts. The in-suite check below is the real thing and runs on the
# ambient environment. Arms (a) and (b) then re-run THIS file in a child with
# a controlled environment and a GNU awk shim first on PATH, to prove the gate
# fires (a) and the not-asserted branch does not fail (b). S229_INNER=1 makes
# the child run only the in-suite check, so there is no recursion.
# PLATFORM_IDENTITY_UNDER_TEST points at a scratch copy of the script.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

script="${PLATFORM_IDENTITY_UNDER_TEST:-$TEST_REPO_ROOT/test/platform-identity.sh}"
self="${BASH_SOURCE[0]}"
note='note: platform identity not asserted (not the macOS CI leg)'

# --- the in-suite check (the production behaviour) --------------------------
if [ "${GITHUB_ACTIONS:-}" = "true" ] && [ "${RUNNER_OS:-}" = "macOS" ]; then
  if out="$(bash "$script" 2>&1)"; then
    printf '%s\n' "$out"
  else
    printf '%s\n' "$out"
    fail "S229 — the platform identity check failed on the macOS CI leg: $out"
  fi
else
  echo "$note"
fi

if [ "${S229_INNER:-}" = "1" ]; then
  test_done
fi

# --- arms (a) and (b): the gate, under a GNU awk shim first on PATH ---------
sandbox_create
trap sandbox_destroy EXIT
fake="$SANDBOX/fake-bin"
mkdir -p "$fake"
# Only `awk --version` gets the GNU banner (and is recorded); every other call
# goes to the real awk, because lib.sh and the harness use awk themselves.
# shellcheck disable=SC2016  # the single quotes are literal shim source
{
  echo '#!/bin/sh'
  echo 'if [ "$1" = "--version" ]; then'
  echo "  echo called >> \"$fake/called.awk\""
  echo "  echo 'GNU Awk 5.1.0, API 3.0'"
  echo '  exit 0'
  echo 'fi'
  echo 'exec /usr/bin/awk "$@"'
} > "$fake/awk"
chmod +x "$fake/awk"

run_inner() { # run_inner VAR=value... -> output, then "rc=<n>"
  local out rc
  out="$(env -i HOME="$SANDBOX/home" PATH="$fake:/usr/bin:/bin:/usr/sbin:/sbin" LANG=en_US.UTF-8 \
    S229_INNER=1 PLATFORM_IDENTITY_UNDER_TEST="$script" "$@" /bin/bash "$self" 2>&1)"
  rc=$?
  printf '%s\nrc=%s\n' "$out" "$rc"
}

# (a) both CI variables set, GNU awk first on PATH: red, naming awk, and the
# script really looked at awk through PATH.
rm -f "$fake/called.awk"
out="$(run_inner GITHUB_ACTIONS=true RUNNER_OS=macOS)"
[ "${out##*rc=}" != "0" ] || fail "S229(a) — with GITHUB_ACTIONS=true and RUNNER_OS=macOS and a GNU awk first on PATH the case passed: $out"
faillines="$(printf '%s\n' "$out" | grep '^FAIL:' | tr '[:upper:]' '[:lower:]' || true)"
case "$faillines" in
  *awk*) ;;
  *) fail "S229(a) — no FAIL: line names awk: $out" ;;
esac
[ -f "$fake/called.awk" ] || fail "S229(a) — the identity script never invoked awk through PATH (vacuous)"

# (b) RUNNER_OS=Linux with the same shim: green, the note is printed.
rm -f "$fake/called.awk"
out="$(run_inner GITHUB_ACTIONS=true RUNNER_OS=Linux)"
[ "${out##*rc=}" = "0" ] || fail "S229(b) — with RUNNER_OS=Linux the case failed (it must assert nothing): $out"
case "$out" in
  *"$note"*) ;;
  *) fail "S229(b) — the not-asserted note was not printed: $out" ;;
esac
[ ! -f "$fake/called.awk" ] || fail "S229(b) — the identity script ran although RUNNER_OS=Linux"

test_done
