#!/usr/bin/env bash
# S224-S227 — test/platform-identity.sh fails, naming the tool or the locale,
# when awk is not BWK, grep is not BSD, bash is not 3.2 or the effective
# locale is not UTF-8; it never skips (#422, A35a amended by A35b D1/D4, AC2).
# Covers: F43
#
# Behavioural, macOS host only: BWK awk, BSD grep, bash 3.2 and an installed
# en_US.UTF-8 are what a PASS is judged against, so elsewhere the case prints
# a note and runs nothing. Each shim records that it was invoked (a vacuous
# pass is red). The failure message is judged on the script's own `FAIL:`
# line, not on the whole output, because the identity lines printed before it
# always mention awk, grep, bash and locale. Interface under test:
# `bash test/platform-identity.sh`, no arguments; PLATFORM_IDENTITY_UNDER_TEST
# points the case at a scratch copy (mutation proofs).

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

script="${PLATFORM_IDENTITY_UNDER_TEST:-$TEST_REPO_ROOT/test/platform-identity.sh}"
[ -f "$script" ] || { fail "S224 — $script is missing"; test_done; }

if [ "$(uname -s)" != "Darwin" ] || [ ! -x /bin/bash ]; then
  echo "    note: S224-S227 need a macOS host (BWK awk, BSD grep, bash 3.2); not run on $(uname -s)" >&2
  test_done
fi

sandbox_create
trap sandbox_destroy EXIT

fake="$SANDBOX/fake-bin"
base_path="/usr/bin:/bin:/usr/sbin:/sbin"

shim() { # shim <tool> <banner> : prints the banner for any args, records the call
  mkdir -p "$fake"
  {
    echo '#!/bin/sh'
    echo "echo called >> \"$fake/called.$1\""
    printf 'printf "%%s\\n" %s\n' "'$2'"
  } > "$fake/$1"
  chmod +x "$fake/$1"
}

# run_script <interpreter> VAR=value... -> combined output, then "rc=<n>".
# An empty environment except HOME, PATH and what the caller passes.
run_script() {
  local interp="$1" out rc
  shift
  out="$(env -i HOME="$SANDBOX/home" "$@" "$interp" "$script" 2>&1)"
  rc=$?
  printf '%s\nrc=%s\n' "$out" "$rc"
}

# assert_fails_naming <scenario> <what> <output> <shim-tool-or-empty>
# Non-zero exit, a FAIL: line that names <what>, and the shim was invoked.
assert_fails_naming() {
  local sc="$1" what="$2" out="$3" shimtool="$4" rc faillines
  rc="${out##*rc=}"
  faillines="$(printf '%s\n' "$out" | grep '^FAIL:' | tr '[:upper:]' '[:lower:]' || true)"
  [ "$rc" != "0" ] || fail "$sc — the script passed (exit 0) although $what is not the expected one: $out"
  [ -n "$faillines" ] || fail "$sc — no 'FAIL:' line in the output (a crash or a stub is not a named mismatch): $out"
  case "$faillines" in
    *"$what"*) ;;
    *) fail "$sc — no FAIL: line names $what: $out" ;;
  esac
  if [ -n "$shimtool" ] && [ ! -f "$fake/called.$shimtool" ]; then
    fail "$sc — the script never invoked $shimtool through PATH (a vacuous pass: it cannot be judging the tool the suite resolves)"
  fi
}

# S224 control: the real macOS tools pass.
rm -rf "$fake"; mkdir -p "$fake"
out="$(run_script /bin/bash PATH="$base_path" LANG=en_US.UTF-8)"
[ "${out##*rc=}" = "0" ] || fail "S224 — on the real macOS tools (BWK awk, BSD grep, bash 3.2, en_US.UTF-8) the script fails: $out"
for tool in awk grep bash locale; do
  case "$out" in
    *"$tool"*) ;;
    *) fail "S224 — on success the output has no identity line for $tool: $out" ;;
  esac
done

# S224: awk is not BWK.
rm -rf "$fake"; mkdir -p "$fake"
shim awk 'GNU Awk 5.1.0, API 3.0'
assert_fails_naming "S224" awk "$(run_script /bin/bash PATH="$fake:$base_path" LANG=en_US.UTF-8)" awk

# S224: grep is not BSD.
rm -rf "$fake"; mkdir -p "$fake"
shim grep 'grep (GNU grep) 3.11'
assert_fails_naming "S224" grep "$(run_script /bin/bash PATH="$fake:$base_path" LANG=en_US.UTF-8)" grep

# S225: bash on PATH is not 3.2 (a shim reporting bash 5).
rm -rf "$fake"; mkdir -p "$fake"
shim bash 'GNU bash, version 5.2.15(1)-release (x86_64-apple-darwin)'
assert_fails_naming "S225" bash "$(run_script /bin/bash PATH="$fake:$base_path" LANG=en_US.UTF-8)" bash

# S225: the RUNNING bash is not 3.2. A bash startup file (BASH_ENV) overrides
# $BASH_VERSION, so the arm runs on every macOS host while PATH still
# resolves the real 3.2; where a bash >= 4 is installed it is also run for real.
rm -rf "$fake"; mkdir -p "$fake"
printf '%s\n' "BASH_VERSION='5.2.15(1)-release'" > "$SANDBOX/bash-env.sh"
assert_fails_naming "S225" bash "$(run_script /bin/bash PATH="$base_path" LANG=en_US.UTF-8 BASH_ENV="$SANDBOX/bash-env.sh")" ""
newbash=""
for cand in /opt/homebrew/bin/bash /usr/local/bin/bash; do
  [ -x "$cand" ] && newbash="$cand" && break
done
if [ -n "$newbash" ]; then
  assert_fails_naming "S225" bash "$(run_script "$newbash" PATH="$base_path" LANG=en_US.UTF-8)" ""
else
  echo "    note: no bash >= 4 on this host; S225 ran only the BASH_ENV override arm for the running bash" >&2
fi

# S226: a locale that is not installed. Real tools, no shim: LANG names a
# locale this host does not have, LC_ALL unset.
rm -rf "$fake"; mkdir -p "$fake"
assert_fails_naming "S226" locale "$(run_script /bin/bash PATH="$base_path" LANG=xx_XX.UTF-8)" ""

# S227: the locale is installed but not IN EFFECT. The script must judge the
# effective locale (locale charmap), not just LANG. Real tools, no shim.
rm -rf "$fake"; mkdir -p "$fake"
assert_fails_naming "S227" locale "$(run_script /bin/bash PATH="$base_path" LANG=en_US.UTF-8 LC_ALL=C)" ""
assert_fails_naming "S227" locale "$(run_script /bin/bash PATH="$base_path" LANG=en_US.UTF-8 LC_CTYPE=C)" ""
assert_fails_naming "S227" locale "$(run_script /bin/bash PATH="$base_path" LANG=)" ""

test_done
