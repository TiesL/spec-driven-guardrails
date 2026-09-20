#!/usr/bin/env bash
# check-scenario-file-sync.sh — #260: nothing mechanically enforced the 1:1
# correspondence between test/cases/<prefix><n>_*.sh files and their
# ### <PREFIX><n> heading in TEST-SCENARIOS.md — the exact gap that let
# #241/PR#249 and #250/PR#259 each pick a scenario number colliding with an
# unrelated pre-existing heading, caught only by hand during
# pre-merge-review, twice.
#
# Ground truth for which IDs a file covers is its own header comment (the
# line right after the shebang), not the filename: convention is
# "# <ID[, ID|ID-ID]*> — <description>" — e.g. "S19-S23" (a range, hyphen),
# "S52, S53, S59" (a discrete list, comma), "T1, T2, S30" (prefixes may
# mix). The filename itself is a human mnemonic, not authoritative:
# s19_s23_*.sh only names a range's two endpoints, while its header line
# is what actually enumerates every ID the file covers.
#
# Reports, one line per problem, and exits non-zero if any are found:
#   - a file's header names an ID with no matching heading in
#     TEST-SCENARIOS.md
#   - a heading in TEST-SCENARIOS.md with no file whose header claims it
#   - the same ID claimed by more than one file's header
#   - the same heading (### <ID>) appearing more than once in
#     TEST-SCENARIOS.md
#
# Usage: ./check-scenario-file-sync.sh [dir]
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

set -uo pipefail

own_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target="${1:-$own_dir}"
target="$(cd "$target" 2>/dev/null && pwd)" || {
  echo "check-scenario-file-sync: directory does not exist: ${1:-}" >&2
  exit 1
}

scenarios="$target/TEST-SCENARIOS.md"
cases_dir="$target/test/cases"

# Pending exclusions — same two-tier pattern as check-no-dutch.sh, kept
# empty now that #272 resolved every entry that used to be here. Add a
# line the moment a new pre-existing orphan is found; remove it the
# moment it's resolved.
pending_excluded=''

# Nothing to check for a project that hasn't scaffolded either — same
# not-applicable-here as check-traceability.sh's own gating in `check`.
[ -f "$scenarios" ] || exit 0
[ -d "$cases_dir" ] || exit 0

file_ids="$(mktemp)"
heading_ids="$(mktemp)"
trap 'rm -f "$file_ids" "$heading_ids"' EXIT

# --- Collect every ID a test file's header comment claims, one
# "<ID> <basename>" pair per line. [rst] deliberately, not a wildcard:
# R/S/T is this repo's own fixed, documented prefix set (CONTEXT.md's
# "F/S/R/T ID prefixes" — F is PRD-only). Unlike check-traceability.sh
# (link 1, F13 decision c), which deliberately never hardcodes F/S so an
# adopted project's own prefixes (tennis-admin's R/A/B/P) work unchanged,
# this check is this repo's own internal test-suite convention, not
# something scaffolded for adopted projects — a differently-prefixed
# test/cases file here would be a naming mistake to fix, not a new
# convention to silently support. Found during PR #273's pre-merge-review.
for f in "$cases_dir"/[rst][0-9]*.sh; do
  [ -e "$f" ] || continue
  base="$(basename "$f")"
  header="$(sed -n '2p' "$f")"
  ids_part="${header#\# }"
  ids_part="${ids_part%% — *}"

  old_ifs="$IFS"
  IFS=','
  set -- $ids_part
  IFS="$old_ifs"
  for token in "$@"; do
    token="$(printf '%s' "$token" | tr -d '[:space:]')"
    [ -n "$token" ] || continue
    case "$token" in
      *-*)
        prefix="${token%%[0-9]*}"
        rest="${token#"$prefix"}"
        start="${rest%%-*}"
        endpart="${rest#*-}"
        end="${endpart#[A-Za-z]}"
        case "$start" in
          ''|*[!0-9]*) echo "check-scenario-file-sync: $base's header ($header) has an unparseable range start in \"$token\"" >&2; continue ;;
        esac
        case "$end" in
          ''|*[!0-9]*) echo "check-scenario-file-sync: $base's header ($header) has an unparseable range end in \"$token\"" >&2; continue ;;
        esac
        i="$start"
        while [ "$i" -le "$end" ]; do
          echo "$prefix$i $base" >> "$file_ids"
          i=$((i + 1))
        done
        ;;
      *)
        echo "$token $base" >> "$file_ids"
        ;;
    esac
  done
done

# --- Collect every ### <ID> heading, one "<ID> <line-number>" pair per line.
while IFS=: read -r line rest; do
  id="${rest#\#\#\# }"
  echo "$id $line" >> "$heading_ids"
done < <(grep -noE '^### [A-Z][0-9]+' "$scenarios")

error=0

# A file ID with no matching heading. Process substitution, not a pipe:
# the loop body must run in this shell for `error=1` to survive it.
while read -r id base; do
  [ -n "${id:-}" ] || continue
  if ! grep -qE "^$id " "$heading_ids"; then
    echo "check-scenario-file-sync: $base claims $id, but TEST-SCENARIOS.md has no ### $id heading" >&2
    error=1
  fi
done < "$file_ids"

# A heading with no file claiming it.
while read -r id line; do
  [ -n "${id:-}" ] || continue
  case " $pending_excluded " in
    *" $id "*) continue ;;
  esac
  if ! grep -qE "^$id " "$file_ids"; then
    echo "check-scenario-file-sync: TEST-SCENARIOS.md line $line (### $id) has no test/cases file whose header claims $id" >&2
    error=1
  fi
done < "$heading_ids"

# The same ID claimed by more than one file.
while read -r dup; do
  [ -n "${dup:-}" ] || continue
  claimants="$(grep -E "^$dup " "$file_ids" | cut -d' ' -f2 | tr '\n' ' ')"
  echo "check-scenario-file-sync: $dup is claimed by more than one file: $claimants" >&2
  error=1
done < <(cut -d' ' -f1 "$file_ids" | sort | uniq -d)

# The same heading appearing more than once.
while read -r dup; do
  [ -n "${dup:-}" ] || continue
  lines="$(grep -E "^$dup " "$heading_ids" | cut -d' ' -f2 | tr '\n' ' ')"
  echo "check-scenario-file-sync: ### $dup appears more than once in TEST-SCENARIOS.md, at lines: $lines" >&2
  error=1
done < <(cut -d' ' -f1 "$heading_ids" | sort | uniq -d)

if [ "$error" -eq 0 ]; then
  echo "check-scenario-file-sync: every test/cases file and TEST-SCENARIOS.md heading correspond 1:1."
fi
exit "$error"
