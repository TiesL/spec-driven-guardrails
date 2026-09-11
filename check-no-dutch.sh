#!/usr/bin/env bash
# check-no-dutch.sh — W43 (#115): no Dutch outside layer C.
#
# Scans this repo's own *.sh/*.md files for a small, curated set of
# high-confidence Dutch-only marker words (word-boundary matched — not a
# generic dictionary, and not a spell-checker). A hit means real,
# untranslated Dutch prose/comments/messages; the word list was chosen and
# verified empirically to produce zero false positives against this repo's
# already-translated content (see PR for #115).
#
# Two kinds of exclusion, kept separate on purpose:
#
#   1. Permanent (layer C, historical, WIP, personal, frozen fixtures) —
#      these never get translated, by design (W33/#57's own layer-C
#      carve-out, or established precedent from #114/#131).
#   2. Pending (tracked in a still-open issue) — these ARE meant to become
#      English, just not yet. Remove an entry here the moment its issue
#      closes, so this check keeps tightening instead of silently staying
#      loose forever.
#
# Usage: ./check-no-dutch.sh [dir]
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

set -uo pipefail

eigen_map="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
doel="${1:-$eigen_map}"
doel="$(cd "$doel" 2>/dev/null && pwd)" || {
  echo "check-no-dutch: directory does not exist: ${1:-}" >&2
  exit 1
}

# The curated marker list. Word-boundary matched (grep -w), case-sensitive
# (these are all lowercase Dutch function words/verbs; an English sentence
# starting with one, capitalized, is not what this catches anyway).
#
# Deliberately excludes "waarschuwing"/"melding": both are also common
# Dutch identifier names (function/variable names) throughout this repo's
# already-translated scripts (e.g. templates/check-traceability.sh's own
# melding()/waarschuwing() helpers, whose actual message text is English).
# An identifier isn't prose a reader translates; the other markers below
# are verbs/prepositions/conjunctions with no such collision risk.
markers='wordt niet geen moet dus eigen worden bijvoorbeeld toch zoals vanuit gebruikt draait controleert bestaat'

# Permanent exclusions — layer C (this repo's own self-adopted, frozen
# copies, same treatment as the three external projects' equivalent
# files), historical records, the separate epic #65 WIP track, and Ties'
# own personal instruction file (not part of the shared product surface).
# check-no-dutch.sh itself is excluded: its own marker-word list is a
# necessary literal, not untranslated prose.
permanent_uitgesloten='./ARCHITECTUUR.md ./WORKFLOW-ADOPTION.md ./check-traceability.sh ./CHANGELOG.md ./CHANGES-ARCHIEF.md ./PRD-MULTI-AGENT-WIP.md ./USER-CLAUDE.md ./check-no-dutch.sh'

# Pending exclusions — real translation gaps, already tracked in an open
# issue. Remove the line the moment that issue closes.
pending_uitgesloten='./PRD.md' # #138

fout=0

cd "$doel"
while IFS= read -r -d '' bestand; do
  case " $permanent_uitgesloten " in
    *" $bestand "*) continue ;;
  esac
  case " $pending_uitgesloten " in
    *" $bestand "*) continue ;;
  esac

  if treffers="$(grep -nwE "$(echo "$markers" | tr ' ' '|')" "$bestand" 2>/dev/null)"; then
    echo "check-no-dutch: $bestand still carries Dutch text:" >&2
    printf '%s\n' "$treffers" | sed 's/^/    /' >&2
    fout=1
  fi
done < <(find . -type f \( -name '*.sh' -o -name '*.md' \) \
  -not -path './.git/*' \
  -not -path './test/fixtures/*' \
  -not -path './test/cases/*' \
  -print0)

if [ "$fout" -eq 0 ]; then
  echo "check-no-dutch: no Dutch found outside layer C and the tracked pending exclusions."
fi
exit "$fout"
