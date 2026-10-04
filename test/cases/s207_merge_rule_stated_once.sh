#!/usr/bin/env bash
# S207 — no session-loaded text says merging is human-only without the
# main / release-branch distinction.
# Covers: F38
#
# Issue #369 (holistic review of the release, blocking finding B3).
# WORKFLOW.md and the release-branch-workflow skill let a session merge a
# work-item PR into a RELEASE branch on its own judgment (review clean, CI
# green); ORCHESTRATOR.md ("Never merge: that stays with the human.") and
# role-contracts ("Never merge, release, force-push, ... unconditionally
# human-only (A2), no exception") say merging is human-only, with no
# exception. Both are loaded into the same session. The maintainer's rule: a
# merge into MAIN always waits for the human; merging a work-item PR into a
# RELEASE branch follows the release-branch-workflow skill. Seam: the text of
# the files loaded into a session, read by unit (paragraph, list item or table
# row): any unit that states the human-only merge rule must name both `main`
# and the release-branch exception (or point to release-branch-workflow).

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/review-floor-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-floor-helpers.sh"

orch="$TEST_REPO_ROOT/skills/role-contracts/ORCHESTRATOR.md"
rc="$TEST_REPO_ROOT/skills/role-contracts/SKILL.md"
wf="$TEST_REPO_ROOT/WORKFLOW.md"
rbw="$TEST_REPO_ROOT/skills/release-branch-workflow/SKILL.md"
for f in "$orch" "$rc" "$wf" "$rbw"; do
  [ -f "$f" ] || { fail "S207 — ${f#"$TEST_REPO_ROOT"/} is missing"; test_done; }
done

# units that state the human-only merge rule
re='never merge([^a-z]|$)|human-only|stays? with the human|only the human[^.]{0,40}merge|merging[^.]{0,40}(is|are)[^.]{0,20}(human|maintainer)'
scan() { # file: prints "start of unit" for each unit stating the rule WITHOUT both main and the release-branch exception
  awk -v re="$re" '
    function flush(   t, p) {
      if (unit == "") return
      t = " " tolower(unit) " "
      gsub(/[`*_(),.:;"]/, " ", t)
      if (t ~ re || tolower(unit) ~ re) {
        if (!(t ~ /[^a-z]main[^a-z]/ && t ~ /release[- ]branch/)) {
          p = unit; gsub(/\n/, " ", p); print substr(p, 1, 150)
        }
      }
      unit = ""
    }
    /^[[:space:]]*$/ { flush(); next }
    /^[[:space:]]*([-*][[:space:]]|\||#|[0-9]+\.)/ { flush() }
    { unit = unit $0 "\n" }
    END { flush() }
  ' "$1"
}

for f in "$orch" "$rc"; do
  off="$(scan "$f")"
  [ -z "$off" ] || fail "S207/B3 — ${f#"$TEST_REPO_ROOT"/} states that merging is human-only without saying it is for main (and that a work-item PR into a release branch follows the release-branch-workflow skill): $off"
done

# the orchestrator text must carry the rule itself: roles never merge; merges
# into main wait for the human; a release branch follows release-branch-workflow
if ! para_has_all "$orch" 'merge' 'main' 'release-branch-workflow'; then
  fail "S207/B3 — ORCHESTRATOR.md must state the merge rule once: merges into main always wait for the human, merging a work-item PR into a release branch follows the release-branch-workflow skill"
fi
if ! para_has_all "$orch" 'role' '(never|not)[^.]*merge|merge[^.]*(never|not)'; then
  fail "S207/B3 — ORCHESTRATOR.md must still say the dispatched roles never merge"
fi

# green controls: the permissive side is stated where it lives, and WORKFLOW.md
# keeps its main/release distinction in the unit that states it
para_has_all "$wf" 'confirmation' '`?main`?' 'release branch' \
  || fail "S207 control — WORKFLOW.md lost its main / release-branch distinction"
para_has_all "$rbw" 'merge' 'own judgment|on its own' 'release branch' \
  || fail "S207 control — release-branch-workflow no longer says a session may merge into the release branch on its own judgment"

test_done
