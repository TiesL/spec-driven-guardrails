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

own_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target="${1:-$own_dir}"
target="$(cd "$target" 2>/dev/null && pwd)" || {
  echo "check-no-dutch: directory does not exist: ${1:-}" >&2
  exit 1
}

# The curated marker list. Word-boundary matched (grep -w), case-sensitive
# (these are all lowercase Dutch function words/verbs; an English sentence
# starting with one, capitalized, is not what this catches anyway).
#
# "waarschuwing"/"melding" were excluded here until #167: both used to
# collide with Dutch identifier names (function names in
# check-traceability.sh/templates/check-traceability.sh). #167 renamed
# those identifiers to English (report/warn), so the collision is gone
# and both words are now active markers — the same reasoning also
# retired check-traceability.sh's own permanent exclusion below, since
# its content is now fully translated too.
#
# Deliberately excludes "onderbouwing": that word is legitimately
# preserved in several places as a direct quote of the pre-migration
# "vereist onderbouwing" stamp (e.g. pending-changes.sh's dual-format
# check, or #114/#131-style historical quotes) — adding it would flag
# intentional preservation as a violation.
#
# Known limitation, not silently ignored: this list is lowercase and
# case-sensitive on purpose (see above), which means a Dutch sentence
# starting mid-word-capitalized, like "Volg de skill ...", is invisible
# to this check even though "volg" itself would otherwise be a safe
# marker. Found via #154's pre-merge review missing exactly such a
# sentence. No fix applied here: making the match case-insensitive risks
# reopening a similar identifier collision for some future marker.
# Catching sentence-initial Dutch remains manual-review territory.
markers='wordt niet geen moet dus eigen worden bijvoorbeeld toch zoals vanuit gebruikt draait controleert bestaat wachten waarschuwing melding'

# Permanent exclusions — layer C (this repo's own self-adopted, frozen
# copies, same treatment as the three external projects' equivalent
# files), historical records, the separate epic #65 WIP track, and Ties'
# own personal instruction file (not part of the shared product surface).
# check-no-dutch.sh itself is excluded: its own marker-word list is a
# necessary literal, not untranslated prose.
permanent_excluded='./CHANGELOG.md ./CHANGES-ARCHIEF.md ./PRD-MULTI-AGENT-WIP.md ./USER-CLAUDE.md ./check-no-dutch.sh'

# Pending exclusions — real translation gaps, tracked in an open issue.
# Add a line the moment a new gap is found; remove it the moment that
# issue closes. Empty now: #136/#137/#138 (the gaps that motivated this
# list) are all done.
pending_excluded=''

error=0

cd "$target"
while IFS= read -r -d '' file; do
  case " $permanent_excluded " in
    *" $file "*) continue ;;
  esac
  case " $pending_excluded " in
    *" $file "*) continue ;;
  esac

  if matches="$(grep -nwE "$(echo "$markers" | tr ' ' '|')" "$file" 2>/dev/null)"; then
    echo "check-no-dutch: $file still carries Dutch text:" >&2
    printf '%s\n' "$matches" | sed 's/^/    /' >&2
    error=1
  fi
done < <(find . -type f \( -name '*.sh' -o -name '*.md' \) \
  -not -path './.git/*' \
  -not -path './test/fixtures/*' \
  -not -path './test/cases/*' \
  -print0)

if [ "$error" -eq 0 ]; then
  echo "check-no-dutch: no Dutch found outside layer C and the tracked pending exclusions."
fi
exit "$error"
