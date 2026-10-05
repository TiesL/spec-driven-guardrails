#!/usr/bin/env bash
# S209 — every Review round is a fresh Reviewer dispatch; the orchestrator may not continue one.
# Covers: F41
#
# Issue #414, AC1 and AC2 (Architect A27). Seam: the text a session loads.
# The rule must sit in all three files; ORCHESTRATOR.md must forbid
# continuing a Reviewer by SendMessage and by the dispatch tool's fork type,
# and must not extend a SendMessage ban to other roles (that is #412).
#
# Mutations that turn this red: delete the rule paragraph from any one of the
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
sentence_has_all "$FR_ORCH" 'reviewer|review round' 'SendMessage' '(never|must not|may not|forbid)' \
  || fail "S209/AC2 — ORCHESTRATOR.md has no sentence forbidding SendMessage to an earlier round's Reviewer"
para_has_all "$FR_ORCH" 'SendMessage' 'reviewer' 'fork' '(never|not)' 'round' \
  || fail "S209/AC2 — the ORCHESTRATOR.md Reviewer rule does not name both SendMessage and the fork type"

# AC2: nothing about other roles. Every sentence that mentions SendMessage
# must be about the Reviewer (a blanket ban would pre-empt #412).
while IFS= read -r s; do
  grep -q 'SendMessage' <<<"$s" || continue
  grep -qiE 'reviewer|review round' <<<"$s" \
    || fail "S209/AC2 — ORCHESTRATOR.md bans SendMessage beyond the Reviewer (that is #412): $s"
done < <(sentences_of "$FR_ORCH")

test_done
