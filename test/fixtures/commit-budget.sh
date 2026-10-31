#!/usr/bin/env bash
# Local hook harness for #615. Source after test/lib.sh; never invokes git writes.
# The real hook is reached through its normal symlink seam. Git is stubbed
# only for read-only repository discovery; check-commit and the watchdog run.

budget_setup() {
  budget_mutations=0
  sandbox_create
  trap sandbox_destroy EXIT
  BUDGET_BASH="${BUDGET_BASH:-$BASH}"
  BUDGET_REAL_SLEEP="$(command -v sleep)"
  export BUDGET_BASH BUDGET_REAL_SLEEP
  mkdir -p "$SANDBOX/bin" "$SANDBOX/source/hooks" "$SANDBOX/source/lib" "$SANDBOX/project"
  cp "${BUDGET_HOOK_SOURCE:-$TEST_REPO_ROOT/hooks/pre-commit}" "$SANDBOX/source/hooks/pre-commit"
  cp "$TEST_REPO_ROOT/hooks/rules.sh" "$SANDBOX/source/hooks/rules.sh"
  cp "$TEST_REPO_ROOT/lib/git-env.sh" "$SANDBOX/source/lib/git-env.sh"
  ln -s "$SANDBOX/source/hooks/pre-commit" "$SANDBOX/pre-commit"
  cat > "$SANDBOX/bin/git" <<'GIT'
#!/usr/bin/env bash
case "$*" in
  'rev-parse --verify --quiet HEAD') exit 0 ;;
  'symbolic-ref --short HEAD') echo fix/615-watchdog-budget ;;
  'rev-parse --show-toplevel') echo "$SANDBOX/project" ;;
  'rev-parse --local-env-vars') exit 0 ;;
  *) echo "Unexpected git command: $*" >&2; exit 99 ;;
esac
GIT
  cat > "$SANDBOX/bin/sleep" <<'SLEEP'
#!/usr/bin/env bash
if [ "${BUDGET_SLEEP_FAILURE:-no}" = yes ]; then
  # Do not race check startup: fail only after the check has visibly begun.
  n=0
  while [ ! -e "$SANDBOX/ran" ] && [ "$n" -lt 5 ]; do
    "$BUDGET_REAL_SLEEP" 1
    n=$((n + 1))
  done
  echo attempted > "$SANDBOX/sleep-failed"
  exit 1
fi
exec "$BUDGET_REAL_SLEEP" "$@"
SLEEP
  chmod +x "$SANDBOX/bin/git" "$SANDBOX/bin/sleep"
  # check-commit deliberately uses the selected interpreter and real sleep,
  # so the injected watchdog failure cannot alter the check's own result.
  cat > "$SANDBOX/project/check-commit" <<'CHECK'
#!/usr/bin/env bash
: > "$SANDBOX/ran"
case "$BUDGET_CHECK_MODE" in
  success) exit 0 ;;
  failure) "$BUDGET_REAL_SLEEP" 2; echo 'B615 REAL FAILURE'; exit 7 ;;
  timeout) "$BUDGET_REAL_SLEEP" 4; exit 7 ;;
  *) exit 98 ;;
esac
CHECK
  chmod +x "$SANDBOX/project/check-commit"
  # env bash in child fixtures follows the interpreter selected by the caller.
  ln -s "$BUDGET_BASH" "$SANDBOX/bin/bash"
}

budget_run() { # budget, check mode, sleep failure (yes/no)
  rm -f "$SANDBOX/ran" "$SANDBOX/sleep-failed"
  out="$(PATH="$SANDBOX/bin:$PATH" COMMIT_CHECK_BUDGET="$1" \
    BUDGET_CHECK_MODE="$2" BUDGET_SLEEP_FAILURE="$3" \
    CLAUDE_WORKFLOW_GUARDRAILS_OFF= \
    "$BUDGET_BASH" "$SANDBOX/pre-commit" 2>&1)"
  status=$?
  ran=no; [ ! -e "$SANDBOX/ran" ] || ran=yes
  sleep_failed=no; [ ! -e "$SANDBOX/sleep-failed" ] || sleep_failed=yes
}

# Each predicate is also given its own independently corrupted observation.
# These mutation controls test the oracles, not a speculative implementation:
# status inversion, marker inversion, removed diagnostic, or false timeout.
# The live hook observation is always tested separately and left untouched.
budget_expect() { # description, predicate, expected; observation globals above
  local label="$1" predicate="$2" expected="$3" saved_out="$out"
  local saved_status="$status" saved_ran="$ran" saved_sleep="$sleep_failed"
  if ! budget_matches "$predicate" "$expected"; then
    fail "$label (status=$status ran=$ran sleep_failed=$sleep_failed): $out"
  fi
  case "$predicate" in
    status) if [ "$expected" = allow ]; then status=1; else status=0; fi ;;
    ran) if [ "$expected" = yes ]; then ran=no; else ran=yes; fi ;;
    sleep_failed) if [ "$expected" = yes ]; then sleep_failed=no; else sleep_failed=yes; fi ;;
    contains) out='mutation removed the diagnostic' ;;
    no_timeout) out='warning: check-commit exceeded the budget' ;;
  esac
  if budget_matches "$predicate" "$expected"; then
    fail "$label — observation mutation survived ($predicate)"
  fi
  budget_mutations=$((budget_mutations + 1))
  out="$saved_out"; status="$saved_status"; ran="$saved_ran"; sleep_failed="$saved_sleep"
}

budget_matches() {
  case "$1" in
    status) if [ "$2" = allow ]; then [ "$status" -eq 0 ]; else [ "$status" -ne 0 ]; fi ;;
    ran) [ "$ran" = "$2" ] ;;
    sleep_failed) [ "$sleep_failed" = "$2" ] ;;
    contains) case "$out" in *"$2"*) return 0 ;; *) return 1 ;; esac ;;
    no_timeout) case "$out" in *exceeded*) return 1 ;; *) return 0 ;; esac ;;
    *) return 2 ;;
  esac
}

budget_done() {
  echo "Observation mutation controls exercised: $budget_mutations; assertion failures: $_test_failures"
  test_done
}
