#!/usr/bin/env bash
# S380 — the Codex permission baseline document carries the pinned content, never a bypass flag, and INSTRUCTIONS.md points to it.
# Covers: F57
#
# Issue #590, AC0, AC1, AC4, AC5, AC6, AC9, AC14 (doc-text pins; live
# enforcement is manual evidence, AC11). Falsifiers: no baseline file, a
# profile without workspace-write or verified/assumed marking, a catch-all
# gh prompt rule or a gh allow, an automatic allow for pipeline-override.sh
# or epic-auto-close.sh, no merge-confirmation limits, no needs-list link,
# the bypass flag outside a prohibition, no INSTRUCTIONS.md pointer.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

doc="$TEST_REPO_ROOT/adapters/codex/permission-baseline.md"
instr="$TEST_REPO_ROOT/adapters/codex/INSTRUCTIONS.md"
flag="--dangerously-bypass-""approvals-and-sandbox"

pin() { # description, extended regex (case-insensitive), file
  grep -Eiq -- "$2" "$3" 2>/dev/null || fail "S380 — $1 (missing: $2)"
}

if [ ! -f "$doc" ]; then
  fail "S380 — adapters/codex/permission-baseline.md does not exist"
else
  pin "AC1 workspace-write profile" 'sandbox_mode = "workspace-write"' "$doc"
  pin "AC1 approvals to the user" 'approvals_reviewer = "user"' "$doc"
  pin "AC1 keys marked verified" '\bverified\b' "$doc"
  pin "AC1 keys marked assumed" '\bassumed\b' "$doc"
  pin "AC0 write confinement is not read secrecy" 'read secrecy' "$doc"
  pin "AC0 needs list" 'needs list' "$doc"
  pin "AC9 trade-off lines" 'trade-off' "$doc"
  pin "AC9 unmatched Claude-side capabilities" 'cannot match' "$doc"
  pin "AC5 merge needs explicit confirmation" 'explicit confirmation' "$doc"
  pin "AC5 merge-preflight named" 'merge-preflight\.sh' "$doc"
  pin "AC5 prefix rule limit" 'prefix rule' "$doc"
  pin "AC14 git actions tied to needs-list item 3" 'item 3' "$doc"

  # AC4: the rules set. Lines that define rules are prefix_rule( ... ).
  rules="$(grep 'prefix_rule(' "$doc" || true)"
  gh_rules="$(grep -E 'pattern *= *\["gh"\]' <<< "$rules" || true)"
  script_rules="$(grep -E 'pipeline-override|epic-auto-close' <<< "$rules" || true)"
  if grep -q 'prompt' <<< "$gh_rules"; then
    fail "S380 — AC4 catch-all gh prompt rule"
  fi
  if grep -q 'allow' <<< "$gh_rules"; then
    fail "S380 — AC4 blanket gh allow"
  fi
  if grep -q 'allow' <<< "$script_rules"; then
    fail "S380 — AC4 automatic allow for pipeline-override.sh or epic-auto-close.sh"
  fi

  # AC6: no line inside a fenced block carries the flag.
  fenced="$(awk '/^```/{f=!f; next} f' "$doc")"
  if grep -q -- "$flag" <<< "$fenced"; then
    fail "S380 — AC6 bypass flag inside a profile, rules or example block"
  fi
fi

# AC6: anywhere in the tree (not this test, not the scenario list), a line
# with the flag must also say never, not or do not.
hits="$(grep -rIn --exclude-dir=.git --exclude-dir=test --exclude=TEST-SCENARIOS.md -- "$flag" "$TEST_REPO_ROOT" 2>/dev/null || true)"
bad_hits="$(grep -viE 'never|not' <<< "$hits" || true)"
if [ -n "$hits" ] && [ -n "$bad_hits" ]; then
  fail "S380 — AC6 flag outside a prohibition: $bad_hits"
fi

# AC14: INSTRUCTIONS.md points to the baseline and keeps the automation statement.
pin "AC14 INSTRUCTIONS.md names the baseline document" 'permission-baseline\.md' "$instr"
pin "AC14 no SessionStart/PostToolUse/SessionEnd automation" 'no SessionStart/PostToolUse/SessionEnd automation' "$instr"

test_done
