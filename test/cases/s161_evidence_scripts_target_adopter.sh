#!/usr/bin/env bash
# S161 — The evidence scripts, run by path from the clone, address the adopted project's repo.
# Covers: F37
#
# Issue #369, AC7 (behavior half; the documentation half is S157 and S163),
# and Architect decision A15 ("violated when a script starts resolving its
# target repo from its own location"). Seam: the scripts' CLI, invoked as
# "$SPEC_DRIVEN_GUARDRAILS_DIR/<script>" with the adopted project's checkout
# as working directory, observed through a recording fake `gh` (where it
# runs, which repository it is pointed at).
#
# What a fake gh cannot show: that the real gh resolves {owner}/{repo} from
# the working directory's remote. That half was verified by hand against a
# real adopted project for issue #369 (see QA's report there).

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: a guardrails clone whose own remote is spec-driven-guardrails, and
# an adopted project whose remote is a different repository.
clone="$(sandbox_copy_repo clone)"
git -C "$clone" init -q -b main
git -C "$clone" remote add origin https://github.com/TiesL/spec-driven-guardrails.git
project="$(fresh_project adopter)"
git -C "$project" remote add origin https://github.com/example-org/adopter-app.git
SPEC_DRIVEN_GUARDRAILS_DIR="$clone" "$clone/adopt.sh" "$project" >/dev/null 2>&1
project_real="$(cd "$project" && pwd -P)"

# A fake gh that records, per call, where it ran, GH_REPO, and its argv,
# then fails the lookup (every script must still have made its first call).
log="$SANDBOX/gh-calls.log"
# shellcheck disable=SC2016  # the fake gh's own script body, expanded when it runs
fakebin="$(fake_gh_bin '
{
  printf "pwd=%s\n" "$(pwd -P)"
  printf "GH_REPO=%s\n" "${GH_REPO:-}"
  for a in "$@"; do printf "arg=%s\n" "$a"; done
  printf "end\n"
} >> "'"$log"'"
exit 1')"

for script in compliance-evidence.sh role-label-staleness.sh classify-review-depth.sh; do
  : > "$log"

  # When: the script runs by path from the clone, from the adopter's checkout.
  (
    cd "$project" || exit 1
    export SPEC_DRIVEN_GUARDRAILS_DIR="$clone" PATH="$fakebin:$PATH"
    unset GH_REPO
    "$SPEC_DRIVEN_GUARDRAILS_DIR/$script" 7
  ) >/dev/null 2>&1 || true

  # Then: it made at least one gh call...
  if ! grep -q '^end$' "$log"; then
    fail "S161 — $script made no gh call at all from the adopter's checkout"
    continue
  fi

  # ...every one of them from the adopter's checkout, not the clone...
  if grep '^pwd=' "$log" | grep -vxF "pwd=$project_real" > "$SANDBOX/bad-pwd.txt"; then
    fail "S161 — $script called gh from outside the adopter's checkout:"
    sort -u "$SANDBOX/bad-pwd.txt" >&2
  fi

  # ...with no GH_REPO override...
  if grep '^GH_REPO=.' "$log" > "$SANDBOX/bad-env.txt"; then
    fail "S161 — $script set GH_REPO for gh:"
    sort -u "$SANDBOX/bad-env.txt" >&2
  fi

  # ...never naming spec-driven-guardrails or a --repo/-R override...
  if grep -E '^arg=(.*spec-driven-guardrails.*|-R|--repo(=.*)?)$' "$log" > "$SANDBOX/bad-arg.txt"; then
    fail "S161 — $script pointed gh at a fixed repository:"
    sort -u "$SANDBOX/bad-arg.txt" >&2
  fi

  # ...and every REST path addresses either gh's own cwd-resolved
  # placeholder or the adopter's repository explicitly.
  if grep -E '^arg=/?repos/' "$log" \
      | grep -vE '^arg=/?repos/(\{owner\}/\{repo\}|example-org/adopter-app)(/|$)' > "$SANDBOX/bad-path.txt"; then
    fail "S161 — $script addressed a repository other than the adopter's:"
    sort -u "$SANDBOX/bad-path.txt" >&2
  fi
done

test_done
