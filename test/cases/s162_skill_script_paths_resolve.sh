#!/usr/bin/env bash
# S162 — Every script an installed skill tells the agent to run exists where the skill says.
# Covers: F37
#
# Issue #369, the human decision that pre-merge-review's classify-review-depth.sh
# path is fixed in this work item (Architect finding V4: the installed skill
# said ./classify-review-depth.sh, which no adopted project has). Seam: the
# installed skills, read through .claude/skills/ in a freshly adopted
# project, checked against what exists in that project and in the clone.
#
# A ./<name>.sh invocation must exist at the adopted project's root; a
# $SPEC_DRIVEN_GUARDRAILS_DIR/<name>.sh one must exist, executable, in the
# clone.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

clone="$(sandbox_copy_repo clone)"
project="$(fresh_project adopter)"
SPEC_DRIVEN_GUARDRAILS_DIR="$clone" "$clone/adopt.sh" "$project" >/dev/null 2>&1

found_any=0
for skill in "$project"/.claude/skills/*/SKILL.md; do
  [ -r "$skill" ] || continue
  found_any=1
  name="$(basename "$(dirname "$skill")")"

  # ./<name>.sh, not preceded by a path character (so a/b/./x.sh or
  # $VAR/./x.sh don't count as a bare relative invocation).
  grep -oE '(^|[^A-Za-z0-9_./$}-])\./[A-Za-z0-9_-]+\.sh' "$skill" \
    | sed 's/^[^.]*\.\///' | sort -u > "$SANDBOX/rel.txt"
  while IFS= read -r script; do
    [ -n "$script" ] || continue
    [ -x "$project/$script" ] \
      || fail "S162 — skill '$name' runs ./$script, which an adopted project does not have"
  done < "$SANDBOX/rel.txt"

  # $SPEC_DRIVEN_GUARDRAILS_DIR/<path>.sh or ${SPEC_DRIVEN_GUARDRAILS_DIR}/<path>.sh
  grep -oE '\$\{?SPEC_DRIVEN_GUARDRAILS_DIR\}?/[A-Za-z0-9_./-]+\.sh' "$skill" \
    | sed 's/^[^/]*\///' | sort -u > "$SANDBOX/clone.txt"
  while IFS= read -r script; do
    [ -n "$script" ] || continue
    [ -x "$clone/$script" ] \
      || fail "S162 — skill '$name' runs \$SPEC_DRIVEN_GUARDRAILS_DIR/$script, which the clone does not have"
  done < "$SANDBOX/clone.txt"
done

[ "$found_any" -eq 1 ] || fail "S162 — no installed skills found in the adopted project"

# And: pre-merge-review still tells the reviewer to run the classifier,
# now by a path that resolves (rather than by dropping the step).
pmr="$project/.claude/skills/pre-merge-review/SKILL.md"
if ! grep -qE '\$\{?SPEC_DRIVEN_GUARDRAILS_DIR\}?/classify-review-depth\.sh' "$pmr"; then
  fail "S162 — pre-merge-review no longer runs classify-review-depth.sh from \$SPEC_DRIVEN_GUARDRAILS_DIR"
fi

test_done
