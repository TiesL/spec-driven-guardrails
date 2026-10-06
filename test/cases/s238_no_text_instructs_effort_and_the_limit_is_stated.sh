#!/usr/bin/env bash
# S238 — no text tells a role or the orchestrator to pass --effort or to ask the human about an unknown effort; the same-model-lower-effort limit and its revisit trigger are stated; the debt row for the flag is recorded.
# Covers: F39, F40
#
# Issue #424 (V3; A33/A33a), AC5, AC7 and the documentation list of the item.
# Seam: the repo's documents, read as text, by paragraph (a paragraph is a run
# of non-blank lines, so a statement cannot be satisfied by words scattered
# over unrelated sections).
#   AC5: in the skills, ORCHESTRATOR.md, README.md and the adoption texts, no
#        paragraph tells anyone to pass `--effort`, to fill it with `unknown`,
#        or to ask the human about an unknown effort. A paragraph that SAYS the
#        flag is gone (no longer, removed, retired, legacy, ignored, #413) is
#        allowed, and so is model-record-emit.sh's own code and header, which
#        still ACCEPTS the flag for one release (S236).
#   AC7: model-choice states that the same model at a lower effort meets the
#        floor because effort is neither chosen nor checked (an accepted risk,
#        A33a), with the revisit trigger "when the dispatch tool gains an
#        effort parameter"; the model-choice templates and command carry no
#        effort. (The quality-review-before-merge "Yes means" wording is S191.)
#   The next release removes the flag: a PRD technical-debt row records it.
# Excluded from the AC5 scan: wip/, CHANGELOG.md, CHANGES-ARCHIEF.md, PRD.md,
# ARCHITECTURE.md, CHANGES.md and test/ (history and decisions, which must
# mention the old text to retire it).

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"
# shellcheck source=../fixtures/review-floor-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-floor-helpers.sh"

root="$TEST_REPO_ROOT"
mc="$root/skills/model-choice/SKILL.md"
pmr="$root/skills/pre-merge-review/SKILL.md"
rc="$root/skills/role-contracts/SKILL.md"
orch="$root/skills/role-contracts/ORCHESTRATOR.md"
emit="$root/skills/pre-merge-review/model-record-emit.sh"
for f in "$mc" "$pmr" "$rc" "$orch" "$emit"; do
  [ -f "$f" ] || { fail "S238 — ${f#"$root"/} is missing"; test_done; }
done

allow='no longer|removed|retired|legacy|ignored|#413|is gone|dropped'

# scan_paragraphs <file> <label-ere> <ere...>: prints "<file>: <start>" for each
# paragraph that matches EVERY given ERE (case-insensitive) and carries no
# allow-word. A paragraph is a run of non-blank lines.
scan() {
  local file="$1" para="" line flat ere ok
  shift
  flush() {
    [ -n "$para" ] || return 0
    flat="$(printf '%s' "$para" | LC_ALL=C tr '\n' ' ')"
    ok=1
    for ere in "$@"; do grep -qiE -- "$ere" <<<"$flat" || { ok=0; break; }; done
    if [ "$ok" -eq 1 ] && ! grep -qiE -- "$allow" <<<"$flat"; then
      printf '%s: %s\n' "${file#"$root"/}" "$(printf '%s' "$flat" | cut -c1-120)"
    fi
    para=""
  }
  while IFS= read -r line || [ -n "$line" ]; do
    if [ -n "${line//[[:space:]]/}" ]; then
      para="$para$line"$'\n'
    else
      flush "$@"
    fi
  done < "$file"
  flush "$@"
}

files="$(find "$root/skills" "$root/README.md" "$root/WORKFLOW-ADOPTION.md" -name '*.md' -type f 2>/dev/null | sort)"
[ -n "$files" ] || fail "S238 — found no markdown files to scan"

# ===== AC5: nothing says to pass --effort, to fill it with unknown, or to ask about an unknown effort
while IFS= read -r f; do
  [ -n "$f" ] || continue
  off="$(scan "$f" -- '--effort')"
  [ -z "$off" ] || fail "S238/AC5 — a paragraph still tells someone to pass --effort: $off"
  off="$(scan "$f" 'effort' '(ask|asks|asking) (the |a )?(human|maintainer|user|Ties)' )"
  [ -z "$off" ] || fail "S238/AC5 — a paragraph still tells someone to ask the human about an effort: $off"
  off="$(scan "$f" 'effort' 'unknown' '(state|record|fill|set|use|write|put)')"
  [ -z "$off" ] || fail "S238/AC5 — a paragraph still tells someone to record an effort as unknown: $off"
  off="$(scan "$f" 'find out (the )?effort|effort (the role|it) (will|would) (actually )?run')"
  [ -z "$off" ] || fail "S238/AC5 — a paragraph still tells someone to find out the effort a role runs at: $off"
done <<<"$files"

# the orchestrator's text, by name (the two sentences A33 deletes)
! grep -qiE "find out the effort|state it as unknown|ask the human before dispatching" "$orch" \
  || fail "S238/AC5 — ORCHESTRATOR.md still carries the 'find out the effort / state it as unknown / ask the human' sentences: $(grep -niE 'find out the effort|state it as unknown|ask the human before dispatching' "$orch" | cut -c1-120 | head -2)"

# the skills that give a command give it without --effort, and still give it
for f in "$pmr" "$mc" "$rc" "$orch"; do
  grep -q 'model-record-emit' "$f" || fail "S238/AC5 — ${f#"$root"/} no longer names model-record-emit.sh (the command is still how a marker is produced)"
  ! grep -q -- '--effort' "$f" || fail "S238/AC5 — ${f#"$root"/} still has --effort in it: $(grep -n -- '--effort' "$f" | cut -c1-120 | head -1)"
done
# the emitter's own usage line no longer advertises it
usage="$(grep -E '^# +model-record-emit\.sh --stage|^usage=' "$emit")"
[ -n "$usage" ] || fail "S238 — could not find the emitter's usage line"
! grep -q -- '--effort' <<<"$usage" || fail "S238/AC5 — the emitter's usage line still advertises --effort: $usage"
err="$(LC_ALL=C "$emit" 2>&1 >/dev/null)"
! grep -q -- '--effort' <<<"$err" || fail "S238/AC5 — the emitter's usage message (no arguments) still advertises --effort: $err"

# ===== README: no 'model/reasoning effort' as what the skill chooses =========
! grep -qi 'model/reasoning effort' "$root/README.md" || fail "S238 — README.md still says the model-choice skill chooses a 'model/reasoning effort'"

# ===== AC7: the limit, and when it is revisited ================================
para_has_all "$mc" 'same model' 'lower effort' '(meets|clears) the floor' 'neither chosen nor checked' 'accepted risk' \
  || fail "S238/AC7 — model-choice must say that the same model at a lower effort meets the floor because effort is neither chosen nor checked (an accepted risk, A33a)"
para_has_all "$mc" 'when the dispatch tool gains an effort parameter' \
  || fail "S238/AC7 — model-choice must carry the revisit trigger: when the dispatch tool gains an effort parameter"
para_has_all "$mc" 'self-reported' 'model' '(floor|marker)' \
  || fail "S238/AC7 — model-choice must say the floor rests on self-reported model strings (A33a)"
# nothing else in model-choice tells a role to choose or record an effort
if grep -qE 'effort="' "$mc"; then
  fail "S238/AC7 — model-choice still shows an effort attribute: $(grep -n 'effort="' "$mc" | cut -c1-120 | head -1)"
fi
if para_has_all "$mc" 'effort' '(low|medium|high)' 'ordered'; then
  fail "S238/AC7 — model-choice still documents an effort scale for markers"
fi

# ===== the next release removes the flag: a debt row says so ==================
debt="$(awk '/^## Technical debt/ { f = 1; next } f && /^## / { exit } f { print }' "$root/PRD.md")"
row="$(grep -E -- '--effort' <<<"$debt" | head -1)"
[ -n "$row" ] || fail "S238 — PRD.md's Technical debt register has no row for removing the --effort flag from model-record-emit.sh in the next release (A33a)"
grep -qiE 'next release' <<<"$row" || fail "S238 — the --effort debt row must say the next release removes the flag, got: $row"
grep -qE '#413|#424' <<<"$row" || fail "S238 — the --effort debt row must cite #413 or #424, got: $row"
# the two retired debt rows: a same-model effort check no longer exists
! grep -qiE 'effort in a .model-record. marker is self-reported' <<<"$debt" \
  || fail "S238 — PRD.md's debt register still has the retired row 'the effort in a model-record marker is self-reported'"
! grep -qiE 'same-model effort check' <<<"$debt" \
  || fail "S238 — PRD.md's debt register still talks about the same-model effort check (deleted by #424)"

test_done
