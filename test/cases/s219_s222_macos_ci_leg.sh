#!/usr/bin/env bash
# S219, S222 — The CI workflow has exactly one macos-latest job whose suite
# step is pinned to one exact form, and the Linux job is as it was (#422,
# slice V1 of #411, A35a amended by A35b D3, AC1).
# Covers: F43
#
# Closed world on purpose (A35b): this test keeps NO list of bad spellings.
# The suite step must be exactly `run: /bin/bash test/run.sh` with no other
# key than name, and the job's and the workflow's key sets are closed, so any
# other form is red. The environment half (tools, locale) is judged at run
# time by S229, not here. A single command is the step's last command, so its
# exit status is the step's status whatever shell flags apply.
# CI_YML_UNDER_TEST points the same assertions at a scratch candidate
# (mutation proofs).

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../ci-workflow-lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../ci-workflow-lib.sh"

yml="$(ci_yml_path)"
[ -f "$yml" ] || { fail "S219 — $yml is missing"; test_done; }

pinned='/bin/bash test/run.sh'
job_keys_allowed=" runs-on permissions env steps timeout-minutes "

# --- S219: one macos-latest job, closed key set, pinned suite step ---------
if [ "$(ci_job_count macos-latest)" != "1" ]; then
  fail "S219 — expected exactly one job with runs-on: macos-latest, found $(ci_job_count macos-latest)"
fi
# Any other runs-on that mentions macOS (a quoted, list or other spelling)
# is a second macOS job the count above cannot see.
if [ "$(grep -v '^[[:space:]]*#' "$yml" | grep -ciE '^[[:space:]]+runs-on:.*macos')" != "1" ]; then
  fail "S219 — expected exactly one runs-on that names macOS, in any spelling"
fi
if [ "$(ci_top_keys | tr ' ' '\n' | grep -c '^defaults$')" != "0" ]; then
  fail "S219 — the workflow has a top-level defaults: (it would change the suite step's shell)"
fi

mac="$(ci_job_block macos-latest)"
if [ -n "$mac" ] && [ "$(ci_job_count macos-latest)" = "1" ]; then
  for k in $(printf '%s\n' "$mac" | ci_job_keys); do
    case "$job_keys_allowed" in
      *" $k "*) ;;
      *) fail "S219 — the macOS job has the key '$k' (allowed: runs-on, permissions, env, steps, timeout-minutes)" ;;
    esac
  done
  case " $(printf '%s\n' "$mac" | ci_job_keys) " in
    *" steps "*) ;;
    *) fail "S219 — the macOS job has no steps" ;;
  esac

  # Exactly one step mentions the suite; it is the pinned form.
  total="$(printf '%s\n' "$mac" | ci_step_count || true)"
  hits=0
  suite_step=""
  i=1
  while [ "$i" -le "${total:-0}" ]; do
    text="$(printf '%s\n' "$mac" | ci_step_text "$i")"
    if grep -qE 'test/run\.sh|\./check' <<< "$text"; then
      hits=$((hits + 1))
      suite_step="$text"
    fi
    i=$((i + 1))
  done
  if [ "$hits" != "1" ]; then
    fail "S219 — expected exactly one macOS step that mentions test/run.sh or ./check, found $hits"
  fi
  if [ -n "$suite_step" ]; then
    keys="$(printf '%s\n' "$suite_step" | ci_step_keys)"
    for k in $keys; do
      case "$k" in
        name|run) ;;
        *) fail "S219 — the suite step has the key '$k' (only name and run are allowed): it could skip, filter or swallow the suite" ;;
      esac
    done
    case " $keys " in
      *" run "*) ;;
      *) fail "S219 — the suite step has no run: key" ;;
    esac
    script="$(printf '%s\n' "$suite_step" | ci_step_script)"
    [ "$script" = "$pinned" ] \
      || fail "S219 — the suite step's script is not exactly '$pinned', it is: $script"
  fi
else
  fail "S219 — no single job with runs-on: macos-latest in $yml"
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
