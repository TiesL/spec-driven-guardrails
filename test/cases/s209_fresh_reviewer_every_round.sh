#!/usr/bin/env bash
# S209 — every Review round is a fresh Reviewer dispatch; the orchestrator may not continue one.
# Covers: F41
#
# Issue #414, AC1 and AC2 (Architect A27). Seam: the text a session loads.
# The rule must sit in all three files; ORCHESTRATOR.md must forbid
# continuing a Reviewer by SendMessage and by the dispatch tool's fork type,
# and must not extend a SendMessage ban to other roles (that is #412).
#
# Mutations that turn this red: delete only the Reviewer's 'never the
# dispatch tool's fork type' clause (the generic 'never a fork' stays);
# reword the Dispatch opening back to 'every role is a fresh agent'; delete the rule paragraph from any one of the
# three files (its "in <file>" check fails); weaken "never continued" to a
# recommendation ("should usually"); drop SendMessage or fork from the
# ORCHESTRATOR Reviewer rule; make the SendMessage ban cover every role.
#
# Amended by #499 (AC14, A41): the ORCHESTRATOR.md half is located by ID,
# no longer by the Dispatch-paragraph sentences: OR7 (hook:no-fork), OR12
# and OR13 (judgment) each start exactly one item in part 1; OR12 names
# SendMessage and fork, OR13 names #412; every item containing SendMessage
# is OR12's. Behaviour: OB12, OB49 (fresh Reviewer, graded against
# continue_agent), OB51 (OR13).

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/review-floor-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-floor-helpers.sh"
# shellcheck source=../fixtures/fresh-reviewer-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/fresh-reviewer-helpers.sh"
# shellcheck source=../fixtures/orchestrator-core-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/orchestrator-core-helpers.sh"

fr_files
for f in "$FR_ROLES" "$FR_ORCH" "$FR_PMR"; do
  [ -f "$f" ] || { fail "S209 — ${f#"$TEST_REPO_ROOT"/} does not exist"; test_done; }
done

# AC1: one paragraph per file (the Reviewer contract and pre-merge-review)
# says every Review round is a new/fresh dispatch and a Reviewer is never
# continued/resumed/reused. Paragraph level, so scattered words in unrelated
# sections cannot satisfy it.
for f in "$FR_ROLES" "$FR_PMR"; do
  para_has_all "$f" 'reviewer|review round' '(every|each) (review )?round' \
    '(fresh|new)' '(dispatch|agent)' '(never|must not|may not|cannot)[^.]*(continu|resum|reus)' \
    || fail "S209/AC1 — no paragraph in ${f#"$TEST_REPO_ROOT"/} says every Review round is a fresh dispatch and a Reviewer is never continued or resumed"
done

# AC2: the Reviewer-specific ban names BOTH mechanisms in ONE sentence, in
# the Reviewer contract and pre-merge-review.
for f in "$FR_ROLES" "$FR_PMR"; do
  sentence_has_all "$f" 'reviewer|review round' 'SendMessage' 'fork' \
    '(never|must not|may not|forbid|not (resumed|continued)|not by)' \
    || fail "S209/AC1/AC2 — no sentence in ${f#"$TEST_REPO_ROOT"/} bans continuing a Reviewer both by SendMessage and by the dispatch tool's fork type"
done

# ORCHESTRATOR.md, by ID (#499 AC14).
oc_rule "S209/OR7" OR7 hook:no-fork 1
oc_rule "S209/OR12" OR12 judgment 1
oc_rule "S209/OR13" OR13 judgment 1
or12="$(oc_item OR12)"
grep -q 'SendMessage' <<<"$or12" || fail "S209/OR12 — OR12 does not name SendMessage"
grep -q 'fork' <<<"$or12" || fail "S209/OR12 — OR12 does not name fork"
grep -q '#412' <<<"$(oc_item OR13)" || fail "S209/OR13 — OR13 does not name #412"

# AC2: nothing about other roles. Every item that mentions SendMessage is
# OR12's (a blanket ban would pre-empt #412).
while IFS= read -r id; do
  [ "$id" = OR12 ] && continue
  if grep -q 'SendMessage' <<<"$(oc_item "$id")"; then
    fail "S209/AC2 — $id mentions SendMessage; only OR12 may (that is #412)"
  fi
done < <(python3 -I "$OC_PY" items --orch "$OC_ORCH" | cut -f1)

test_done
