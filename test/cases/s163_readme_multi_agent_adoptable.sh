#!/usr/bin/env bash
# S163 — The README says the multi-agent workflow is adoptable, and what adopting it takes.
# Covers: F37
#
# Issue #369, AC8, plus the README half of AC7's "documented" clause. Seam:
# README.md as a reader sees it. Checks the three false sentences v0.2.0
# shipped are gone, that what an adopter gets, does not get, and needs is
# stated, and that no orphan sentence fragment is left behind by the edit.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

readme="$TEST_REPO_ROOT/README.md"

# Then: none of v0.2.0's "not adoptable yet" sentences remain.
for stale in \
  "isn't part of what an adopted project gets yet" \
  "None of this reaches an adopted project yet" \
  "Neither is part of the adoptable workflow yet"; do
  if grep -nF "$stale" "$readme" > /dev/null; then
    fail "S163 — README still says: '$stale'"
  fi
done

# And: how to run the evidence scripts from an adopted project (AC7).
# shellcheck disable=SC2016  # a literal \$VAR name, not an expansion
grep -qF '$SPEC_DRIVEN_GUARDRAILS_DIR/compliance-evidence.sh' "$readme" \
  || fail "S163 — README does not show running \$SPEC_DRIVEN_GUARDRAILS_DIR/compliance-evidence.sh from an adopted project"

# And: what an adopter gets — the role-contracts skill and the opt-in question.
grep -qF 'process-multi-agent-roles' "$readme" \
  || fail "S163 — README does not name the opt-in question process-multi-agent-roles"
grep -qF 'role-contracts' "$readme" \
  || fail "S163 — README does not name the role-contracts skill"

# And: what an adopter does not get — no orchestrator, no release-branch
# tier, and the evidence scripts are not installed into the project.
grep -qi 'orchestrator' "$readme" \
  || fail "S163 — README does not say an adopter gets no orchestrator"
grep -qiE 'release[- ]branch' "$readme" \
  || fail "S163 — README does not mention the release-branch tier"
awk -v RS= '/compliance-evidence\.sh/ && tolower($0) ~ /not installed/ { found = 1 } END { exit !found }' "$readme" \
  || fail "S163 — README never says, next to the evidence scripts, that they are not installed into an adopted project"

# And: the README does not overstate what the skill depends on. It also
# sends Reviewer to Claude Code built-ins (security-review, code-review),
# which adopt.sh does not install, so "only installed skills" is false.
if grep -E 'only (at|to) (the )?(installed )?skills|only installed skills' "$readme" | grep -qvi 'built-in'; then
  fail "S163 — README says the skill points only at installed skills; it also names built-in Claude Code skills"
fi
# And: the several-remotes caveat is where an adopter reads it.
grep -qF 'gh repo set-default' "$readme" \
  || fail "S163 — README does not mention 'gh repo set-default' for a checkout with several remotes"
# And: the prerequisites — gh, SPEC_DRIVEN_GUARDRAILS_DIR, and creating the
# role:<name> labels in the project's own repo.
# shellcheck disable=SC2016  # literal backticks, not a command substitution
grep -qF '`gh`' "$readme" || fail "S163 — README does not list gh as a prerequisite"
grep -qF 'SPEC_DRIVEN_GUARDRAILS_DIR' "$readme" || fail "S163 — README does not mention SPEC_DRIVEN_GUARDRAILS_DIR"
awk -v RS= '/role:/ && tolower($0) ~ /creat/ && tolower($0) ~ /label/ { found = 1 } END { exit !found }' "$readme" \
  || fail "S163 — README does not say the adopting project must create the role:<name> labels"

# And: no orphan fragment — a line starting lower-case right after a line
# that ended a sentence (the shape the draft left: "... need \`gh\`." then
# "contracts this way is tracked in #369.").
orphans="$(awk '
  prev ~ /[.!?]$/ && prev !~ /(e\.g\.|i\.e\.|etc\.)$/ && $0 ~ /^[a-z]/ { print "    line " NR ": " $0 }
  { prev = $0 }
' "$readme")"
if [ -n "$orphans" ]; then
  fail "S163 — README has an orphan sentence fragment:"
  printf '%s\n' "$orphans" >&2
fi

test_done
