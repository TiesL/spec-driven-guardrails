#!/usr/bin/env bash
# S240 — the live design/spec text and the orchestrator's text no longer state the removed effort rules as current behaviour; the Pipeline log keeps its after-the-fact effort note.
# Covers: F39, F40
#
# Issue #424, review round 1 of PR #447 (findings pr447-live-docs-still-state-
# effort-rules and pr447-pipeline-log-observed-effort-dropped; A27, A33, A33a).
# Seam: the documents, read as text.
#
# SCOPE (exact):
#   ARCHITECTURE.md  the sections `### A24 ...` and `### A26 ...` (heading to the next `##`/`###`)
#   PRD.md           the sections `### F39 ...` and `### F40 ...`
#   skills/role-contracts/ORCHESTRATOR.md   the whole file
# NOT in scope: A25 (already marked superseded as a whole), A27, A33, A33a,
# the Technical debt register (S238), CHANGES*.md, wip/, test/. They may
# discuss effort freely.
#
# ORACLE (not a phrase list for the old rules): the text is cut into units, a
# unit being one list item (with its continuation lines and nested items) or
# one paragraph. A unit that states an effort RULE (it mentions effort and
# compares, passes, checks, sets, chooses or ranks one; a passing word such as
# "the dispatch tool has no effort argument" is not a rule) must SAY it is not current:
# it carries a supersession word (superseded, amended, A33, #424, no longer,
# history, legacy, retired, removed, ignored, accepted risk, neither chosen
# nor, #413, ...: S238's allow list, widened). Nested items inherit the mark of
# the item they sit under. A bare attribute name such as `effort=` or
# `effort="unknown"` in a code span is a field name, not a rule, and is
# ignored (the A24 deny-list for a floor-basis that ends in `effort=`; a
# historical `model=x effort=low` example). So a rewrite that deletes the
# sentence, rephrases it as past tense with a pointer to A33, or marks it
# amended passes; one that leaves "effort compared / field-checked / passed
# with --effort" as unmarked present tense fails whatever its wording.
#
# PIPELINE LOG (second half): ORCHESTRATOR.md's "Pipeline log" paragraph keeps
# the sentence A33 (#411 Phase 1b 3/7, "ORCHESTRATOR.md:21 bullet") and A27
# agree on: the orchestrator MAY NOTE the effort the platform transcript
# shows, in prose, after the fact. Required in that one paragraph: `may note`,
# `effort`, `transcript`, `prose`, and `after the fact` (or `afterwards`); and
# the note is not a marker attribute or a check: the paragraph must not tell
# the orchestrator to put an effort in a marker. A27 itself still lists the
# observed effort, so the two documents agree.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/review-floor-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-floor-helpers.sh"

root="$TEST_REPO_ROOT"
arch="$root/ARCHITECTURE.md"
prd="$root/PRD.md"
orch="$root/skills/role-contracts/ORCHESTRATOR.md"
for f in "$arch" "$prd" "$orch"; do
  [ -f "$f" ] || { fail "S240 — ${f#"$root"/} is missing"; test_done; }
done

# S238's allow list (AC5 base) plus the words a supersession note uses.
# What makes a mention of effort a RULE rather than a passing word: the unit
# compares efforts, passes or checks an effort, or sets/chooses/ranks one.
# shellcheck disable=SC2016 # backticks are literal characters in the ERE
rule='compar|lower|--effort|<e>|unreadable|(model|stage)[`" ]*(and|or)[`" ]*effort|efforts? (is|are|value|scale)|effort per|effort (observed|known|unknown|filled|field)|rank|scale|>=|<=|(sets?|choose|chooses|pass|passes|fill|fills|filled in) [a-z ,`]*effort|the stage and effort|and effort'
mark='no longer|removed|retired|legacy|ignored|#413|is gone|dropped|superseded|amended|A33|#424|history|historical|accepted risk|neither chosen nor|deleted'

# unmarked_effort <file> <section-heading-ere|ALL>: prints one line per unit
# that mentions effort and carries no supersession mark. BWK-awk safe.
unmarked_effort() {
  LC_ALL=C awk -v want="$2" -v mark="$mark" -v rule="$rule" '
    function flush(   t, i) {
      if (unit == "") return
      t = unit
      gsub(/`[^`]*effort=[^`]*`/, " ", t)
      gsub(/effort=[^ ]*/, " ", t)
      if (tolower(t) ~ /(^|[^a-z_])efforts?([^a-z_]|$)/ && tolower(t) ~ tolower(rule) && !(tolower(unit) ~ tolower(mark)) && !inherited) {
        printf "%s\n", substr(unit, 1, 110)
      }
      # remember this unit as a possible parent
      pmark[ind] = (tolower(unit) ~ tolower(mark)) || inherited
      unit = ""
    }
    function indent(s,   n) { n = match(s, /[^ ]/); return n ? n - 1 : 0 }
    { sub(/\r$/, "") }
    /^##+ / {
      flush()
      insec = (want == "ALL") || ($0 ~ ("^### (" want ")([^0-9A-Za-z]|$)"))
      next
    }
    want == "ALL" { insec = 1 }
    !insec { next }
    /^[ \t]*$/ { flush(); next }
    /^ *([-*]|[0-9]+\.) / {
      flush()
      ind = indent($0)
      inherited = 0
      for (k = ind - 1; k >= 0; k--) if (k in pmark) { inherited = pmark[k]; break }
      unit = $0
      next
    }
    {
      if (unit == "") { ind = 0; inherited = 0 }
      unit = unit " " $0
    }
    END { flush() }
  ' "$1"
}

report() { # <label> <output>
  local line
  [ -n "$2" ] || return 0
  while IFS= read -r line; do
    fail "S240 — $1 still states effort as live text (no supersession mark): $line"
  done <<<"$2"
}

report "ARCHITECTURE.md A24/A26" "$(unmarked_effort "$arch" 'A24|A26')"
report "PRD.md F39/F40" "$(unmarked_effort "$prd" 'F39|F40')"
report "ORCHESTRATOR.md" "$(unmarked_effort "$orch" ALL)"

# the scope really found its sections (a renamed heading must not make the scan vacuous)
for sec in A24 A26; do grep -qE "^### $sec( |$)" "$arch" || fail "S240 — ARCHITECTURE.md has no '### $sec' section: the scan would be vacuous"; done
for sec in F39 F40; do grep -qE "^### $sec( |$)" "$prd" || fail "S240 — PRD.md has no '### $sec' section: the scan would be vacuous"; done

# ===== the Pipeline log keeps the after-the-fact effort note (A27, A33) ========
plog="$(awk '/^\*\*Pipeline log\.\*\*/ { f = 1 } f { if ($0 ~ /^[ \t]*$/) exit; print }' "$orch")"
[ -n "$plog" ] || fail "S240 — ORCHESTRATOR.md has no '**Pipeline log.**' paragraph"
pflat="$(printf '%s' "$plog" | LC_ALL=C tr '\n' ' ')"
for need in 'may note' 'effort' 'transcript' 'prose' 'after the fact|afterwards'; do
  grep -qiE -- "$need" <<<"$pflat" \
    || fail "S240 — the Pipeline log paragraph must keep the sentence that the orchestrator may note the effort the platform transcript shows, in prose, after the fact (A27/A33): missing '$need'"
done
# one sentence, not words scattered: 'may note' and 'effort' sit in the same sentence
sent="$(printf '%s' "$pflat" | LC_ALL=C tr '.' '\n' | grep -iE 'may note' | head -1)"
{ grep -qiE 'effort' <<<"$sent" && grep -qiE 'transcript' <<<"$sent"; } \
  || fail "S240 — 'may note' must be one sentence with the effort and the platform transcript, got: '$sent'"
# ... and it is a note, not a record: no marker attribute, no check
! grep -qiE 'effort="|--effort|effort (check|comparison)' <<<"$pflat" \
  || fail "S240 — the Pipeline log's effort note must stay prose, not a marker attribute, flag or check: $pflat"
# A27 and the orchestrator agree: A27 still lists the observed effort
para_has_all "$arch" 'Pipeline log' 'effort observed afterwards' \
  || fail "S240 — ARCHITECTURE.md A27 no longer lists the observed effort in the Pipeline log; update it together with ORCHESTRATOR.md (A33a rationale)"

test_done
