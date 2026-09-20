#!/usr/bin/env bash
# S10 — The production gate blocks a substantiation gap.
# Covers: F6
#
# F6's second gate (PRD.md) was decided but never actually written into
# deploy-guards/SKILL.md's own condition list — found while resolving
# #272's orphan headings. This is a documentation-content assertion, the
# same shape as S127-S129: the mechanism it describes is a skill
# instruction a project's own deploy script implements, not a shipped
# script this repo can execute directly.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

skill="$TEST_REPO_ROOT/skills/deploy-guards/SKILL.md"
[ -f "$skill" ] || { fail "S10 — skills/deploy-guards/SKILL.md is missing"; test_done; }

content="$(cat "$skill")"

assert_contains "S10 — production-gate is named as a condition" "production-gate: yes" "$content"
assert_contains "S10 — the substantiation stamp is named" "requires substantiation" "$content"
assert_contains "S10 — the condition is scoped to production, not pre-production" "Production — only from" "$content"

# The condition must actually sit in the Production paragraph, not merely
# appear somewhere in the file.
production_section="$(sed -n '/^\*\*Production/,/^$/p' "$skill")"
case "$production_section" in
  *"production-gate: yes"*) : ;;
  *) fail "S10 — production-gate condition is not inside the Production paragraph, got: $production_section" ;;
esac

test_done
