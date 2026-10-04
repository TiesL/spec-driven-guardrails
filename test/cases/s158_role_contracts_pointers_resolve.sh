#!/usr/bin/env bash
# S158 — Every pointer in the installed role-contracts skill resolves from an adopted project.
# Covers: F37
#
# Issue #369, AC4, and Architect decision A14(a) ("violated when a pointer
# resolves only inside this repo": a vendor/ or wip/ path, or a bare #n
# issue reference). Seam: the SKILL.md as an adopted project sees it,
# through the .claude/skills/ symlink adopt.sh leaves, checked against what
# actually exists in that project.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

clone="$(sandbox_copy_repo clone)"
project="$(fresh_project adopter)"
SPEC_DRIVEN_GUARDRAILS_DIR="$clone" "$clone/adopt.sh" "$project" >/dev/null 2>&1

skill="$project/.claude/skills/role-contracts/SKILL.md"
if [ ! -r "$skill" ]; then
  fail "S158 — no installed role-contracts skill in the adopted project (see S155)"
  test_done
fi

# Documents that exist only in the guardrails clone. A mention is allowed
# only in a paragraph that says it lives in the clone SPEC_DRIVEN_GUARDRAILS_DIR
# points at.
clone_only='PRD-MULTI-AGENT-WIP[.]md|ARCHITECTURE-MULTI-AGENT-WIP[.]md|MULTI-AGENT-WORKFLOW[.]md|wip/multi-agent-development'

# 1. No bare vendor/ path anywhere: those files are installed as the
#    grilling and codebase-design skills instead.
if grep -n 'vendor/' "$skill" > "$SANDBOX/vendor.txt"; then
  fail "S158 — the skill still points into vendor/:"
  cat "$SANDBOX/vendor.txt" >&2
fi

# 2. A clone-only document named outside a clone-marked paragraph.
awk -v RS= -v re="$clone_only" '
  $0 ~ re && $0 !~ /SPEC_DRIVEN_GUARDRAILS_DIR/ {
    line = $0; sub(/\n.*/, "", line); print "  paragraph: " substr(line, 1, 100)
  }
' "$skill" > "$SANDBOX/unmarked.txt"
if [ -s "$SANDBOX/unmarked.txt" ]; then
  fail "S158 — clone-only documents named without saying they live in the clone (\$SPEC_DRIVEN_GUARDRAILS_DIR):"
  cat "$SANDBOX/unmarked.txt" >&2
fi

# 3. Every other backticked .md/.sh path must exist in the adopted project:
#    at its root, under .claude/ (skills/<name>/...), or as a file inside an
#    installed skill. Placeholders (<slug>) and clone-marked paragraphs are
#    out of this rule's reach.
awk -v RS= -v re="$clone_only" '
  /SPEC_DRIVEN_GUARDRAILS_DIR/ { next }
  {
    rest = $0
    while (match(rest, /`[^`]*`/)) {
      tok = substr(rest, RSTART + 1, RLENGTH - 2)
      rest = substr(rest, RSTART + RLENGTH)
      if (tok ~ /\.(md|sh)$/ && tok !~ /[<> ]/ && tok !~ re) print tok
    }
  }
' "$skill" | sort -u > "$SANDBOX/paths.txt"

while IFS= read -r tok; do
  [ -n "$tok" ] || continue
  [ -e "$project/$tok" ] && continue
  [ -e "$project/.claude/$tok" ] && continue
  case "$tok" in
    */*) ;;
    *)
      found=0
      for dir in "$project"/.claude/skills/*/; do
        if [ -e "$dir$tok" ]; then found=1; break; fi
      done
      [ "$found" -eq 1 ] && continue ;;
  esac
  fail "S158 — '$tok' does not resolve in an adopted project and is not marked as living in the clone"
done < "$SANDBOX/paths.txt"

# 4. No bare #n issue reference: quoted into an adopted project's issue or
#    PR, GitHub links it to that project's own issue with the same number.
if grep -nE '(^|[^A-Za-z0-9_/-])#[0-9]+' "$skill" > "$SANDBOX/bare-refs.txt"; then
  fail "S158 — bare issue references (qualify as <owner>/spec-driven-guardrails#n, or drop):"
  cat "$SANDBOX/bare-refs.txt" >&2
fi

test_done
