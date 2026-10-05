#!/usr/bin/env bash
# S219-S222 — The CI workflow has a macos-latest job that runs the full test
# suite on the platform tools (BWK awk, BSD grep, bash 3.2), installs mawk
# only for S153, names a UTF-8 locale, and leaves the Linux job as it was
# (#422, slice V1 of #411, A35a, AC1).
# Covers: F43
#
# Content tests at the workflow file: the job's real behaviour is only
# observable on a macOS runner (AC3, a human-visible CI run, not testable
# here). Directional on purpose: the assertions name tools, paths and
# effects, not the step wording. CI_YML_UNDER_TEST points the same
# assertions at a scratch candidate (mutation proofs).

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../ci-workflow-lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../ci-workflow-lib.sh"

yml="$(ci_yml_path)"
[ -f "$yml" ] || { fail "S219 — $yml is missing"; test_done; }

mac="$(ci_job_block macos-latest)"

# --- S219: the macOS job runs the full suite under /bin/bash 3.2 -----------
if [ "$(ci_job_count macos-latest)" != "1" ]; then
  fail "S219 — expected exactly one job with runs-on: macos-latest, found $(ci_job_count macos-latest)"
fi
if [ -n "$mac" ]; then
  # /bin/bash named explicitly, running test/run.sh or ./check (check runs
  # the whole suite), and no name-fragment filter after test/run.sh.
  suite_line="$(printf '%s\n' "$mac" | grep -E '/bin/bash[[:space:]]+(\./check|(\./)?test/run\.sh)' || true)"
  if [ -z "$suite_line" ]; then
    fail "S219 — no step runs the suite as '/bin/bash test/run.sh' (or '/bin/bash ./check'): bash 3.2 is not named explicitly"
  else
    case "$suite_line" in
      *test/run.sh*)
        grep -qE 'test/run\.sh[[:space:]]*($|#|&&|;)' <<< "$suite_line" \
          || fail "S219 — the suite line passes an argument to test/run.sh (a subset, not the full suite): $suite_line" ;;
    esac
  fi

  # /usr/bin first on PATH, so BWK awk (/usr/bin/awk) wins and
  # `#!/usr/bin/env bash` test scripts resolve to /bin/bash. $GITHUB_PATH
  # semantics: each write is PREPENDED, so the LAST write ends up first; an
  # explicit PATH= assignment counts by its first element.
  last_gp="$(grep -E '>>[[:space:]]*"?[$]GITHUB_PATH' <<< "$mac" | tail -n 1 || true)"
  if [ -n "$last_gp" ]; then
    grep -qE 'echo[[:space:]]+"?/usr/bin"?[[:space:]]*>>' <<< "$last_gp" \
      || fail "S219 — the LAST write to \$GITHUB_PATH ends up first on PATH and is not /usr/bin: $last_gp"
  else
    grep -qE 'PATH[=:][[:space:]]*"?/usr/bin:' <<< "$mac" \
      || fail "S219 — the macOS job does not put /usr/bin first on PATH"
  fi
  # No condition anywhere in the job: a skipped suite step leaves the job
  # green (and the merge guard treats a skip as passing).
  if grep -qE '^[[:space:]]*(- )?if:' <<< "$mac"; then
    fail "S219 — the macOS job has an if: (job or step): a skipped step could leave the job green without running the suite"
  fi

  # The job log shows the identity of awk, grep and bash it used.
  ident_idx="$(printf '%s\n' "$mac" | ci_step_find 'identity' name)"
  [ -n "$ident_idx" ] || fail "S219 — the macOS job has no step whose name says 'identity'"
else
  fail "S219 — no job with runs-on: macos-latest in $yml"
fi

# --- S220: mawk is installed, only for S153, and does not displace BWK awk -
if [ -n "$mac" ]; then
  grep -qE 'brew[[:space:]]+install[^#]*mawk' <<< "$mac" \
    || fail "S220 — the macOS job does not install mawk (S153 needs it)"
  # mawk only: no other GNU/Homebrew replacement for the platform tools.
  if grep -qE 'brew[[:space:]]+install[^#]*(gawk|grep|coreutils|findutils|gnu-|bash)' <<< "$mac"; then
    fail "S220 — the macOS job installs a replacement for a platform tool (gawk, GNU grep, bash, coreutils): the leg would no longer run on BWK/BSD tools"
  fi
  # No Homebrew prefix placed ahead of /usr/bin on PATH: not as the last
  # $GITHUB_PATH write (which ends up first), not as a PATH= first element.
  last_gp="$(grep -E '>>[[:space:]]*"?[$]GITHUB_PATH' <<< "$mac" | tail -n 1 || true)"
  if grep -qE '(/opt/homebrew|/usr/local|homebrew)' <<< "$last_gp"; then
    fail "S220 — a Homebrew directory is the last \$GITHUB_PATH write, so it ends up ahead of /usr/bin: $last_gp"
  fi
  path_lines="$(grep -E 'PATH' <<< "$mac" || true)"
  if grep -qE 'PATH[=:][[:space:]]*"?(/opt/homebrew|/usr/local)' <<< "$path_lines"; then
    fail "S220 — a Homebrew directory starts PATH, ahead of /usr/bin"
  fi
else
  fail "S220 — no macOS job, so no mawk install"
fi

# --- S221: a UTF-8 locale is in effect for the suite; no failure is swallowed -
if [ -n "$mac" ]; then
  # In effect for the SUITE, not only for the identity step: set at job
  # level or on the suite step itself.
  loc_re='(LANG|LC_ALL)[=:][[:space:]]*"?[A-Za-z]{2}_[A-Za-z]{2}[.]UTF-8'
  job_level="$(awk '/^    steps:/ { exit } { print }' <<< "$mac")"
  suite_idx="$(ci_step_find '([.]/check|test/run[.]sh)' all <<< "$mac")"
  suite_text=""
  [ -n "$suite_idx" ] && suite_text="$(ci_step_text "$suite_idx" <<< "$mac")"
  if ! grep -qE "$loc_re" <<< "$job_level" && ! grep -qE "$loc_re" <<< "$suite_text"; then
    fail "S221 — no UTF-8 locale (LANG or LC_ALL = en_US.UTF-8) is set for the suite step: neither at job level nor on that step"
  fi
  # Nothing may pin the C locale for the job (LC_ALL or LC_CTYPE).
  if grep -qE '(LC_ALL|LC_CTYPE)[=:][[:space:]]*"?(C|POSIX)("|[[:space:]]|$)' <<< "$mac"; then
    fail "S221 — a step or the job pins LC_ALL or LC_CTYPE to C or POSIX"
  fi
  # Any continue-on-error, however spelled (true, ${{ true }}, an expression).
  if grep -qE 'continue-on-error:' <<< "$mac"; then
    fail "S221 — the macOS job (or a step) has continue-on-error: a failure would not turn the job red"
  fi
else
  fail "S221 — no macOS job, so no UTF-8 locale named"
fi

# --- S222: regression, the Linux job is as it was --------------------------
if [ "$(ci_job_count ubuntu-latest)" != "1" ]; then
  fail "S222 — expected exactly one job with runs-on: ubuntu-latest, found $(ci_job_count ubuntu-latest)"
fi
lin="$(ci_job_block ubuntu-latest)"
case "$lin" in
  *"- run: ./check"*) ;;
  *) fail "S222 — the Linux job no longer runs ./check" ;;
esac
case "$lin" in
  *"gitleaks git"*) ;;
  *) fail "S222 — the Linux job lost its gitleaks step" ;;
esac
case "$lin" in
  *"check-pr-issue-link.sh"*"check-main-via-pr.sh"*) ;;
  *) fail "S222 — the Linux job lost its PR-link or main-via-PR step" ;;
esac
case "$lin" in
  *"fetch-depth: 0"*) ;;
  *) fail "S222 — the Linux job lost fetch-depth: 0" ;;
esac
case "$lin" in
  *"issues: read"*"pull-requests: read"*|*"pull-requests: read"*"issues: read"*) ;;
  *) fail "S222 — the Linux job lost its issues:read / pull-requests:read permissions" ;;
esac

test_done
