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
# ambient environment. The arms then re-run THIS file in a child with a
# controlled environment, to prove the gate: (a) fires, with a GNU awk shim
# first on PATH; (b) RUNNER_OS=Linux, (d) RUNNER_OS=macOS without
# GITHUB_ACTIONS, (e) both variables unset, each with the same shim, do not
# fail, print the note and never call the shim; (c) on a macOS host, both
# variables set and the real tools, passes AND prints the identity lines.
# S229_INNER=1 makes the child run only the in-suite check, so there is no
# recursion.
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

# --- arms (a)-(e): the gate, mostly under a GNU awk shim first on PATH ------
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

run_inner() { # run_inner VAR=value... -> output, then "rc=<n>"; GNU awk shim first on PATH
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

# (c) macOS host only: both CI variables set, the real tools, no shim. Green,
# and the identity lines are really printed (the success branch must show them,
# or AC1's log evidence rests on one hosted run alone).
if [ "$(uname -s)" = "Darwin" ] && [ -x /bin/bash ]; then
  out="$(env -i HOME="$SANDBOX/home" PATH="/usr/bin:/bin:/usr/sbin:/sbin" LANG=en_US.UTF-8 \
    S229_INNER=1 PLATFORM_IDENTITY_UNDER_TEST="$script" GITHUB_ACTIONS=true RUNNER_OS=macOS /bin/bash "$self" 2>&1; echo "rc=$?")"
  [ "${out##*rc=}" = "0" ] || fail "S229(c) — on the real macOS tools with both CI variables set the case failed: $out"
  for id in 'awk:' 'grep:' 'bash' 'locale charmap:'; do
    grep -q "^$id" <<< "$out" || fail "S229(c) — the output has no line starting with '$id' (the identity is not printed into the log): $out"
  done
  case "$out" in
    *"$note"*) fail "S229(c) — the not-asserted note was printed although both CI variables were set: $out" ;;
  esac
else
  echo "    note: S229(c) needs a macOS host (real BWK awk, BSD grep, bash 3.2); skipped on $(uname -s)" >&2
fi

# (d) RUNNER_OS=macOS with GITHUB_ACTIONS unset, GNU awk shim: green, note,
# shim not called. (e) both unset, same shim: same. A gate that dropped
# GITHUB_ACTIONS, or became "not Linux", would be red here.
for arm in d e; do
  rm -f "$fake/called.awk"
  if [ "$arm" = "d" ]; then out="$(run_inner RUNNER_OS=macOS)"; else out="$(run_inner)"; fi
  [ "${out##*rc=}" = "0" ] || fail "S229($arm) — the gate fired without both CI variables (it must assert nothing): $out"
  case "$out" in
    *"$note"*) ;;
    *) fail "S229($arm) — the not-asserted note was not printed: $out" ;;
  esac
  [ ! -f "$fake/called.awk" ] || fail "S229($arm) — the identity script ran without both CI variables"
done

test_done
