#!/usr/bin/env bash
# S162 — Installed skill and workflow policy paths resolve from an adopted project.
# Covers: F37
#
# Issue #369, the human decision that pre-merge-review's classify-review-depth.sh
# path is fixed in this work item (Architect finding V4: the installed skill
# said ./classify-review-depth.sh, which no adopted project has). Seam: the
# installed skills, read through .claude/skills/ in a freshly adopted
# project, checked against what exists in that project and in the clone.
#
# Scan installed SKILL.md files and policy/WORKFLOW.md: ./ script paths,
# $SPEC_DRIVEN_GUARDRAILS_DIR checkout paths, bare skills/ and templates/
# references, and installed .claude/skills/ paths. Scripts must be executable;
# template files/directories must exist. Clone-qualified prose and explicit
# checkout conventions resolve in the physical clone; local scripts in the project.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

clone="$(sandbox_copy_repo clone)"
# A directory with .git is enough for adoption; no git writes are needed.
project="$SANDBOX/adopter"
mkdir -p "$project/.git/objects" "$project/.git/refs"
printf 'ref: refs/heads/main\n' > "$project/.git/HEAD"
SPEC_DRIVEN_GUARDRAILS_DIR="$clone" "$clone/adopt.sh" "$project" >"$SANDBOX/adopt.log" 2>&1
[ "$?" -eq 0 ] || { cat "$SANDBOX/adopt.log"; fail "S162 — adoption failed"; test_done; }
[ -d "$project/.claude/skills/pre-merge-review" ] || fail "S162 — no installed skills"
python3 "$TEST_REPO_ROOT/test/fixtures/adopter-docs-622.py" paths "$TEST_REPO_ROOT" "$project" "$clone" \
  || fail "S162 — a documented installed-skill or workflow-policy path dangles"
python3 "$TEST_REPO_ROOT/test/fixtures/adopter-docs-622.py" path-controls "$TEST_REPO_ROOT" \
  || fail "S162 — path mutation controls failed"

# Policy scope controls use the same paths-mode CLI as the real scan.
# Each mutation must be detected in the policy, even when installed skills pass.
policy="$clone/policy/WORKFLOW.md"
cp "$policy" "$SANDBOX/policy.good"
for mutant in './wait-for-ci.sh' 'templates/missing-622.md'; do
  cp "$SANDBOX/policy.good" "$policy"
  printf '\nRun `%s`.\n' "$mutant" >> "$policy"
  if python3 "$TEST_REPO_ROOT/test/fixtures/adopter-docs-622.py" paths "$TEST_REPO_ROOT" "$project" "$clone" >"$SANDBOX/mutation.log" 2>&1; then
    fail "S162 — workflow-policy mutation escaped: $mutant"
  elif ! grep -F 'policy/WORKFLOW.md: unresolved invocations:' "$SANDBOX/mutation.log" >/dev/null; then
    cat "$SANDBOX/mutation.log"
    fail "S162 — mutation failed outside workflow policy: $mutant"
  fi
done
cp "$SANDBOX/policy.good" "$policy"

# And: pre-merge-review still tells the reviewer to run the classifier,
# now by a path that resolves (rather than by dropping the step).
pmr="$project/.claude/skills/pre-merge-review/SKILL.md"
if ! grep -qE '\$\{?SPEC_DRIVEN_GUARDRAILS_DIR\}?/classify-review-depth\.sh' "$pmr"; then
  fail "S162 — pre-merge-review no longer runs classify-review-depth.sh from \$SPEC_DRIVEN_GUARDRAILS_DIR"
fi

test_done
