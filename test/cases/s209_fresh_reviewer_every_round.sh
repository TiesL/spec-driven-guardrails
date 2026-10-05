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

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/review-floor-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-floor-helpers.sh"
# shellcheck source=../fixtures/fresh-reviewer-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/fresh-reviewer-helpers.sh"

fr_files
for f in "$FR_ROLES" "$FR_ORCH" "$FR_PMR"; do
  [ -f "$f" ] || { fail "S209 — ${f#"$TEST_REPO_ROOT"/} does not exist"; test_done; }
done

# AC1: one paragraph per file says every Review round is a new/fresh
# dispatch and a Reviewer is never continued/resumed/reused. Paragraph level,
# so scattered words in unrelated sections cannot satisfy it.
for f in "$FR_ROLES" "$FR_ORCH" "$FR_PMR"; do
  para_has_all "$f" 'reviewer|review round' '(every|each) (review )?round' \
    '(fresh|new)' '(dispatch|agent)' '(never|must not|may not|cannot)[^.]*(continu|resum|reus)' \
    || fail "S209/AC1 — no paragraph in ${f#"$TEST_REPO_ROOT"/} says every Review round is a fresh dispatch and a Reviewer is never continued or resumed"
done

# AC2: the loophole. ORCHESTRATOR.md bans continuing a Reviewer by
# SendMessage, and the same paragraph names the dispatch tool's fork type.
# The Reviewer-specific ban names BOTH mechanisms in ONE sentence (an older
# generic 'never a fork' elsewhere in the paragraph must not satisfy it), in
# the Reviewer contract, ORCHESTRATOR.md and pre-merge-review alike.
for f in "$FR_ROLES" "$FR_ORCH" "$FR_PMR"; do
  sentence_has_all "$f" 'reviewer|review round' 'SendMessage' 'fork' \
    '(never|must not|may not|forbid|not (resumed|continued)|not by)' \
    || fail "S209/AC1/AC2 — no sentence in ${f#"$TEST_REPO_ROOT"/} bans continuing a Reviewer both by SendMessage and by the dispatch tool's fork type"
done

# The ban is about the tool's fork type, not context: fork (the two are
# opposites; the ORCHESTRATOR sentence must say which one it means).
sentence_has_all "$FR_ORCH" 'reviewer|review round' 'SendMessage' "dispatch tool.s .?fork" \
  || fail "S209/AC2 — ORCHESTRATOR.md does not say 'the dispatch tool's fork type' in the Reviewer ban"

# Decided wording (Architect, #414 round 1, finding 8): the Dispatch
# paragraph says roles are STARTED as a new agent, never the dispatch tool's
# fork type, and leaves continuing another role for a later step to #412.
sentence_has_all "$FR_ORCH" '(start|started)' 'new agent' 'never' "dispatch tool.s .?fork" \
  || fail "S209/AC2 — the ORCHESTRATOR.md Dispatch paragraph does not open by saying every role starts as a new agent, never the dispatch tool's fork type"
sentence_has_all "$FR_ORCH" 'another role|other roles' 'once started' 'continued' 'later step' \
  'not decided' '#412' \
  || fail "S209/AC2 — the ORCHESTRATOR.md Dispatch paragraph does not leave 'another role, once started, continued for a later step' to #412"

# AC2: nothing about other roles. Every sentence that mentions SendMessage
# must be about the Reviewer (a blanket ban would pre-empt #412).
while IFS= read -r s; do
  grep -q 'SendMessage' <<<"$s" || continue
  grep -qiE 'reviewer|review round' <<<"$s" \
    || fail "S209/AC2 — ORCHESTRATOR.md bans SendMessage beyond the Reviewer (that is #412): $s"
done < <(sentences_of "$FR_ORCH")

test_done
