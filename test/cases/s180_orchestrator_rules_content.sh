#!/usr/bin/env bash
# S180 — ORCHESTRATOR.md states the run rules, once, in the one place that
# session-context.sh injects.
# Covers: F38
#
# Issue #371, A16/A18, AC1, AC4-AC8; amended by #499 AC14 (A41): the file is
# now the two-part caveman core with `OR<n>` IDs, so each rule this scenario
# used to match by phrase is located by ID, tier and part instead. What a
# session DOES with these rules is model behaviour: it moved to OB1-OB7 and
# OB31-OB37 in test/behavior/orchestrator-scenarios.md (differential run,
# not ./check). "It stays short" (the 80-line cap) is replaced by the
# per-part character budget of S309.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/orchestrator-core-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/orchestrator-core-helpers.sh"

orch="$OC_ORCH"
skill="$TEST_REPO_ROOT/skills/role-contracts/SKILL.md"
if [ ! -f "$orch" ] || [ ! -f "$OC_TSV" ]; then
  fail "S180 — ORCHESTRATOR.md or orchestrator-rules.tsv does not exist"
  test_done
fi

# Part 1 opens with its two header lines, and the recursion guard (OR1) is
# within part 1's first five non-blank lines.
[ "$(head -n 1 "$orch")" = "# Multi-agent pipeline run rules, part 1 of 2: fundamentals" ] \
  || fail "S180 — part 1 does not open with its heading"
head5="$(grep -v '^[[:space:]]*$' "$orch" | head -5)"
grep -q '^- OR1 .*ROLE SESSION:' <<<"$head5" \
  || fail "S180/AC5 — the OR1 ROLE SESSION: guard is not within part 1's first five non-blank lines"

oc_rule "S180/AC5 fresh agents, never forks" OR7 hook:no-fork 1
oc_rule "S180/AC4 work item versus non-work-items" OR3 judgment 1
oc_rule "S180/AC1 announce, role:product first" OR4 judgment 1
oc_rule "S180/AC1 stage table" OR5 judgment 1
oc_rule "S180/AC6 never self-granted shortcuts" OR33 judgment 1
oc_rule "S180/AC6 override record" OR34 judgment 1
oc_rule "S180/AC7 cannot dispatch" OR35 judgment 1
oc_rule "S180/AC8 resume" OR36 judgment 2

# The OR5 tuples stay parseable (the S160 parse): each label with its stage.
or5="$(oc_item OR5)"
for pair in role:product:Discovery role:architect:Planning role:qa:Test role:dev:Implementation role:reviewer:Review; do
  lab="${pair%:*}"; stg="${pair##*:}"
  grep -q "/\`$lab\`/$stg\b" <<<"$or5" || fail "S180/AC1 — OR5 does not pair $lab with stage $stg"
done
grep -q '`role:product`' <<<"$(oc_item OR4)" || fail "S180/AC1 — OR4 does not set role:product first"

# Plumbing, kept verbatim and deterministic.
or34="$(oc_item OR34)"
grep -q '<!-- pipeline-override: decided-by=' <<<"$or34" || fail "S180/AC6 — OR34 lacks the pipeline-override record literal"
for field in scope reason; do
  grep -q "$field" <<<"$or34" || fail "S180/AC6 — OR34 lacks the override field $field"
done
grep -q 'role-label-staleness.sh' <<<"$(oc_item OR36)" || fail "S180/AC8 — OR36 does not name role-label-staleness.sh"

# Single source: SKILL.md points here instead of restating the run rules.
if ! grep -q 'ORCHESTRATOR.md' "$skill"; then
  fail "S180 — role-contracts/SKILL.md does not point to ORCHESTRATOR.md"
fi

test_done
