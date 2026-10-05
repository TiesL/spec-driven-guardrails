#!/usr/bin/env bash
# S223-S226 — The macOS job starts with a tool-identity step that fails,
# naming the tool, when awk is not BWK, grep is not BSD, bash is not 3.2 or
# the UTF-8 locale is missing; it never skips (#422, A35a, AC2).
# Covers: F43
#
# A35a names no path for the check, so it is taken to be the job's step whose
# name says "identity" (inline YAML). Its run: script is extracted and run
# behaviourally with PATH shims that report the wrong tool; each shim records
# that it was invoked (a vacuous pass is red, R6/D10). The behavioural arms
# need a macOS host (bash 3.2 and BSD tools are what a PASS is judged
# against); elsewhere only the content arms run. Assumption: the step reads
# the tool banners through PATH (`awk --version`, `grep --version`, `bash`
# or $BASH_VERSION, `locale`), not through absolute paths, because the leg's
# point is to judge the tools the suite will resolve.
# CI_YML_UNDER_TEST points the assertions at a scratch candidate.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../ci-workflow-lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../ci-workflow-lib.sh"

sandbox_create
trap sandbox_destroy EXIT

yml="$(ci_yml_path)"
[ -f "$yml" ] || { fail "S223 — $yml is missing"; test_done; }
mac="$(ci_job_block macos-latest)"
if [ -z "$mac" ]; then
  fail "S223 — no job with runs-on: macos-latest in $yml"
  test_done
fi

# --- S223: an identity step exists, runs first, and can fail ---------------
ident_idx="$(printf '%s\n' "$mac" | ci_step_find 'identity' name)"
suite_idx="$(printf '%s\n' "$mac" | ci_step_find '([.]/check|test/run[.]sh)' all)"
ident_text=""
if [ -z "$ident_idx" ]; then
  fail "S223 — the macOS job has no step whose name says 'identity'"
else
  ident_text="$(printf '%s\n' "$mac" | ci_step_text "$ident_idx")"
  if [ -n "$suite_idx" ] && [ "$ident_idx" -ge "$suite_idx" ]; then
    fail "S223 — the identity step (#$ident_idx) does not run before the suite step (#$suite_idx)"
  fi
  lc="$(printf '%s\n' "$ident_text" | tr '[:upper:]' '[:lower:]')"
  for tool in awk grep bash; do
    case "$lc" in
      *"$tool"*) ;;
      *) fail "S223 — the identity step does not look at $tool" ;;
    esac
  done
  case "$lc" in
    *locale*|*utf-8*|*utf8*) ;;
    *) fail "S223 — the identity step does not look at the locale" ;;
  esac
  grep -qE '(^|[^a-z_])(exit[[:space:]]+[1-9]|false([^a-z_]|$))' <<< "$ident_text" \
    || fail "S223 — the identity step has no failing exit (exit N, N>0)"
  # Never skip, never swallowed.
  if grep -qE '(\|\|[[:space:]]*(true|:)([[:space:]]|$)|continue-on-error:[[:space:]]*true|^[[:space:]]+if:)' <<< "$ident_text"; then
    fail "S223 — the identity step can be skipped or its failure swallowed (|| true, continue-on-error, if:)"
  fi
  # Messages name the expected tool identity.
  for want in BWK BSD '3\.2'; do
    grep -qE "$want" <<< "$ident_text" \
      || fail "S223 — the identity step never names the expected identity ($want)"
  done
fi

# --- S224-S226: behavioural arms (macOS host only) -------------------------
script_file="$SANDBOX/identity-step.sh"
if [ -n "$ident_text" ]; then
  printf '%s\n' "$ident_text" | ci_step_script > "$script_file"
  [ -s "$script_file" ] || fail "S224 — the identity step has no run: script to execute"
fi

if [ "$(uname -s)" != "Darwin" ] || [ ! -x /bin/bash ] || [ ! -s "$script_file" ]; then
  echo "    note: behavioural identity arms (S224-S226) need a macOS host with an identity step; content arms only" >&2
  test_done
fi

fake="$SANDBOX/fake-bin"
base_path="/usr/bin:/bin:/usr/sbin:/sbin"

shim() { # shim <tool> <banner|-> : prints the banner for any args, records the call
  mkdir -p "$fake"
  {
    echo '#!/bin/sh'
    echo "echo called >> \"$fake/called.$1\""
    printf 'printf "%%s\\n" %s\n' "'$2'"
  } > "$fake/$1"
  chmod +x "$fake/$1"
}

# run_step <interpreter> -> prints combined output, then "rc=<n>"
run_step() {
  local interp="$1" out rc
  out="$(env -i HOME="$SANDBOX" LANG=en_US.UTF-8 PATH="$fake:$base_path" \
    "$interp" --noprofile --norc -eo pipefail "$script_file" 2>&1)"
  rc=$?
  printf '%s\nrc=%s\n' "$out" "$rc"
}

assert_fails_naming() { # <scenario> <tool> <output> <shim-tool-or-empty>
  local sc="$1" tool="$2" out="$3" shimtool="$4" rc lc
  rc="${out##*rc=}"
  lc="$(printf '%s' "$out" | tr '[:upper:]' '[:lower:]')"
  [ "$rc" != "0" ] || fail "$sc — the identity step passed (exit 0) although $tool is not the expected one"
  case "$lc" in
    *"$tool"*) ;;
    *) fail "$sc — the failure does not name $tool: $out" ;;
  esac
  if [ -n "$shimtool" ] && [ ! -f "$fake/called.$shimtool" ]; then
    fail "$sc — the step never invoked $shimtool through PATH (a vacuous pass: it cannot be judging the tool the suite resolves)"
  fi
}

# S224 control: the real macOS tools pass.
rm -rf "$fake"; mkdir -p "$fake"
out="$(run_step /bin/bash)"
[ "${out##*rc=}" = "0" ] || fail "S224 — on the real macOS tools (BWK awk, BSD grep, bash 3.2, en_US.UTF-8) the identity step fails: $out"

# S224: awk is not BWK.
rm -rf "$fake"; mkdir -p "$fake"
shim awk 'GNU Awk 5.1.0, API 3.0'
assert_fails_naming "S224" awk "$(run_step /bin/bash)" awk

# S224: grep is not BSD.
rm -rf "$fake"; mkdir -p "$fake"
shim grep 'grep (GNU grep) 3.11'
assert_fails_naming "S224" grep "$(run_step /bin/bash)" grep

# S225: bash is not 3.2 (needs a bash >= 4 on the host; shim for PATH-based
# probes, the other interpreter for $BASH_VERSION-based ones).
newbash=""
for cand in /opt/homebrew/bin/bash /usr/local/bin/bash; do
  [ -x "$cand" ] && newbash="$cand" && break
done
if [ -n "$newbash" ]; then
  rm -rf "$fake"; mkdir -p "$fake"
  shim bash 'GNU bash, version 5.2.15(1)-release (x86_64-apple-darwin)'
  assert_fails_naming "S225" bash "$(run_step "$newbash")" ""
elif grep -qE 'bash[^|;]*--version' "$script_file"; then
  # No second bash on this host: only a PATH-probing step can be judged.
  rm -rf "$fake"; mkdir -p "$fake"
  shim bash 'GNU bash, version 5.2.15(1)-release (x86_64-apple-darwin)'
  assert_fails_naming "S225" bash "$(run_step /bin/bash)" bash
else
  echo "    note: no bash >= 4 on this host and the step does not probe bash via PATH; S225's behavioural arm not run" >&2
fi

# S226: the UTF-8 locale is missing. `locale` reports only C/POSIX.
rm -rf "$fake"; mkdir -p "$fake"
{
  echo '#!/bin/sh'
  echo "echo called >> \"$fake/called.locale\""
  # shellcheck disable=SC2016,SC2028
  echo 'case "$1" in -a) printf "C\nPOSIX\n";; *) printf "LANG=\nLC_CTYPE=\"C\"\nLC_ALL=\n";; esac'
} > "$fake/locale"
chmod +x "$fake/locale"
out="$(env -i HOME="$SANDBOX" LANG=en_US.UTF-8 PATH="$fake:$base_path" \
  /bin/bash --noprofile --norc -eo pipefail "$script_file" 2>&1; echo "rc=$?")"
lcout="$(printf '%s' "$out" | tr '[:upper:]' '[:lower:]')"
[ "${out##*rc=}" != "0" ] || fail "S226 — a missing UTF-8 locale did not fail the identity step (it skipped or passed)"
case "$lcout" in
  *locale*|*utf-8*|*utf8*) ;;
  *) fail "S226 — the failure does not name the locale: $out" ;;
esac
[ -f "$fake/called.locale" ] || fail "S226 — the step never asked 'locale' through PATH (vacuous)"

test_done
