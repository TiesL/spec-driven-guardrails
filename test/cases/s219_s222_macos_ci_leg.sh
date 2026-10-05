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
  # `#!/usr/bin/env bash` test scripts resolve to /bin/bash.
  # shellcheck disable=SC2016
  grep -qE '(PATH[=:][[:space:]]*"?/usr/bin:|echo[[:space:]]+"?/usr/bin"?[[:space:]]*>>[[:space:]]*"?\$GITHUB_PATH)' <<< "$mac" \
    || fail "S219 — the macOS job does not put /usr/bin first on PATH"

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
  # No Homebrew prefix placed ahead of /usr/bin on PATH.
  path_lines="$(grep -E 'PATH' <<< "$mac" || true)"
  if grep -qE '(/opt/homebrew|/usr/local)[^[:space:]]*:[^[:space:]]*/usr/bin|GITHUB_PATH.*(homebrew|/usr/local)' <<< "$path_lines"; then
    fail "S220 — a Homebrew directory is placed ahead of /usr/bin on PATH"
  fi
else
  fail "S220 — no macOS job, so no mawk install"
fi

# --- S221: a UTF-8 locale is named; it is never conditional ----------------
if [ -n "$mac" ]; then
  grep -qE '(LANG|LC_ALL)[=:][[:space:]]*"?[A-Za-z]{2}_[A-Za-z]{2}\.UTF-8' <<< "$mac" \
    || fail "S221 — the macOS job sets no UTF-8 locale (LANG or LC_ALL = en_US.UTF-8)"
  if grep -qE 'continue-on-error:[[:space:]]*true' <<< "$mac"; then
    fail "S221 — the macOS job (or a step) is continue-on-error: a failure would not turn the job red"
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
