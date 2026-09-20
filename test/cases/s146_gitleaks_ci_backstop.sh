#!/usr/bin/env bash
# S146 — A gitleaks scan runs in CI too, independent of hooks/pre-push
# (#264) — the pre-push hook is bypassable with --no-verify, this isn't.
# Covers: F17

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

check_gitleaks_step() {
  local path="$1" label="$2"
  [ -f "$path" ] || { fail "S146 — $path is missing"; return; }

  local step
  step="$(grep -A12 "name: Secret scan (gitleaks)" "$path")"
  [ -n "$step" ] || fail "S146 — $label has no 'Secret scan (gitleaks)' step"

  case "$step" in
    *"gitleaks git"*) ;;
    *) fail "S146 — $label's gitleaks step does not call gitleaks git" ;;
  esac

  # Unconditional (#264's own decision): no `if:` gate on this step tying
  # it to event type, branch, or repo visibility.
  case "$step" in
    *"if:"*) fail "S146 — $label's gitleaks step is conditional, expected unconditional" ;;
  esac

  # Full history, not the default shallow clone — a shallow clone would
  # only ever let gitleaks see the tip commit.
  grep -qE 'fetch-depth:\s*0' "$path" \
    || fail "S146 — $label's checkout step is missing fetch-depth: 0"
}

check_gitleaks_step "$TEST_REPO_ROOT/.github/workflows/ci.yml" "this repo's own CI"
check_gitleaks_step "$TEST_REPO_ROOT/templates/ci.yml" "the ci.yml template"

test_done
