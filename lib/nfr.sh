#!/usr/bin/env bash
# lib/nfr.sh — The NFR register: parsing and generating the PRD block.
#
# Source, don't execute. The fifteen non-functional characteristics used to
# live in two places — as spec-* entries in CHANGES.md and as ### subsections
# in templates/PRD.md — which had to be kept in sync by hand. Now both are
# consumers of this register.
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

# Reads one field from a register file's frontmatter.
nfr_field() {
  local file="$1" name="$2"
  awk -v n="$name" '
    { sub(/\r$/, "") }
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm && $0 == "---"    { exit }
    in_fm && $0 ~ "^" n "[[:space:]]*:" {
      sub(/^[^:]*:[[:space:]]*/, ""); sub(/[[:space:]]+$/, ""); print; exit
    }
  ' "$file"
}

# Reads the content of a ## section from a register file, as a single line.
nfr_section() {
  local file="$1" heading="$2"
  awk -v k="## $heading" '
    { sub(/\r$/, "") }
    $0 == k { in_sec = 1; next }
    in_sec && /^## / { exit }
    in_sec { print }
  ' "$file" | sed '/^$/d' | tr '\n' ' ' | sed 's/ *$//'
}

# The register files in order, one path per line.
#
# A missing or non-numeric `order` field is loudly reported and the file
# goes to the back — never silently skipped. An NFR that unnoticeably falls
# out of the register disappears from *all* consumers at once: it's no
# longer asked, no longer seeded, and no longer in the template block — and
# because both sides miss it, the drift check sees nothing.
nfr_files() {
  local nfr_map="$1" file order
  [ -d "$nfr_map" ] || return 0
  for file in "$nfr_map"/*.md; do
    [ -e "$file" ] || continue
    order="$(nfr_field "$file" order)"
    case "$order" in
      ''|*[!0-9]*)
        echo "warning: $file has no valid 'order' field — put at the end" >&2
        order=99999 ;;
    esac
    printf '%s\t%s\n' "$order" "$file"
  done | sort -n | cut -f2-
}

# Checks the register files for completeness. Prints every problem and
# returns 1 if something is wrong. `check` uses this: a broken register file
# should fail the build, not silently disappear.
nfr_validate() {
  local nfr_map="$1" file order id heading pred status errors=0

  [ -d "$nfr_map" ] || return 0

  for file in "$nfr_map"/*.md; do
    [ -e "$file" ] || continue
    id="$(nfr_field "$file" id)"
    heading="$(nfr_field "$file" heading)"
    order="$(nfr_field "$file" order)"
    pred="$(nfr_field "$file" applies-if)"
    status="$(nfr_field "$file" status)"

    [ -n "$id" ]      || { echo "$file: field 'id' is missing"; errors=$((errors + 1)); }
    [ -n "$heading" ] || { echo "$file: field 'heading' is missing"; errors=$((errors + 1)); }
    [ -n "$pred" ]    || { echo "$file: field 'applies-if' is missing"; errors=$((errors + 1)); }
    [ -n "$status" ]  || { echo "$file: field 'status' is missing"; errors=$((errors + 1)); }
    case "$order" in
      ''|*[!0-9]*) echo "$file: field 'order' is missing or not numeric"; errors=$((errors + 1)) ;;
    esac
    if [ -n "$id" ] && [ "$(basename "$file" .md)" != "$id" ]; then
      echo "$file: filename and id ('$id') don't match"
      errors=$((errors + 1))
    fi
  done

  [ "$errors" -eq 0 ]
}

# Walks the active register files, by `order`, and calls <callback> with
# <id> <default> <predicate>. Same signature as iterate_entries' callback,
# so a caller can treat both sources the same way.
#
# `status: retired` skips the file. That's the retirement form for these
# fifteen: a field instead of moving the file.
iterate_nfr() {
  local nfr_map="$1" callback="$2"
  local file id default predicate status errors=0

  [ -d "$nfr_map" ] || return 0

  # Sorting on the order field, not on filename: the order belongs to the
  # content (it determines the PRD block), not to what the file is called.
  local list
  list="$(nfr_files "$nfr_map")"

  while IFS= read -r file; do
    [ -n "$file" ] || continue
    status="$(nfr_field "$file" status)"
    [ "$status" = "retired" ] && continue

    id="$(nfr_field "$file" id)"
    default="$(nfr_field "$file" default)"
    predicate="$(nfr_field "$file" applies-if)"

    if [ -z "$id" ] || [ -z "$predicate" ]; then
      echo "warning: $file is missing an id or applies-if" >&2
      continue
    fi

    if ! "$callback" "$id" "$default" "$predicate"; then
      echo "warning: processing NFR '$id' produced an error" >&2
      errors=$((errors + 1))
    fi
  done <<EOF
$list
EOF

  [ "$errors" -eq 0 ]
}

# The question text of one characteristic, as a single line.
# pending-changes.sh shows it for a pending change; since the spec-*
# entries were removed from CHANGES.md, this register is the only place it
# lives.
nfr_question() {
  local nfr_map="$1" id="$2"
  local file="$nfr_map/$id.md"
  [ -f "$file" ] || return 0
  nfr_section "$file" Question
}

# #156: five NFR filenames/IDs were renamed from Dutch to English
# (spec-data-integriteit -> spec-data-integrity, spec-documentatie ->
# spec-documentation, spec-kostenbeheersing -> spec-cost-management,
# spec-performance-schaal -> spec-performance-scale, spec-backup-herstel
# -> spec-backup-recovery). A project that already answered under an old
# ID keeps that row exactly as it is — same "never rewrite what a project
# already recorded" principle as W42/#114's ja/nee support — so callers
# need to recognize both. These two lookups are the only place that
# mapping is spelled out; add a case to both when a future rename needs
# the same treatment.

# Given any ID (old or new, or unrelated), the current one. Old IDs no
# longer have a file in nfr/, so this is how a caller finds the real file
# from a possibly-stale ID read out of a project's own WORKFLOW-ADOPTION.md.
nfr_current_id() {
  case "$1" in
    spec-data-integriteit) echo spec-data-integrity ;;
    spec-documentatie) echo spec-documentation ;;
    spec-kostenbeheersing) echo spec-cost-management ;;
    spec-performance-schaal) echo spec-performance-scale ;;
    spec-backup-herstel) echo spec-backup-recovery ;;
    *) echo "$1" ;;
  esac
}

# Given a *current* ID, the pre-rename ID it used to have — empty if it
# was never renamed. The reverse lookup, for checking whether a project's
# answer file has a row under the old name for a question asked by its
# current ID.
nfr_old_id() {
  case "$1" in
    spec-data-integrity) echo spec-data-integriteit ;;
    spec-documentation) echo spec-documentatie ;;
    spec-cost-management) echo spec-kostenbeheersing ;;
    spec-performance-scale) echo spec-performance-schaal ;;
    spec-backup-recovery) echo spec-backup-herstel ;;
  esac
}

# Prints the NFR block as it should appear in templates/PRD.md. The ID
# appears as an HTML comment in the output: pre-merge-review (W13) keys on
# that to link the review scope to the answered spec-* rows.
nfr_block() {
  local nfr_map="$1"
  local file heading id status list

  list="$(nfr_files "$nfr_map")"

  while IFS= read -r file; do
    [ -n "$file" ] || continue
    status="$(nfr_field "$file" status)"
    [ "$status" = "retired" ] && continue
    heading="$(nfr_field "$file" heading)"
    id="$(nfr_field "$file" id)"
    echo
    echo "### $heading"
    echo "<!-- nfr: $id -->"
    # Wrapping at the same width as the rest of the template, so the block
    # reads as hand-written markdown and the diff on a change stays small.
    printf '<%s>\n' "$(nfr_section "$file" Guidance)" | fold -s -w 79 | sed 's/ *$//'

  done <<EOF
$list
EOF
}

# Turns an NFR block into one line per characteristic, with the ID up front.
# That way a diff between two blocks naturally names which characteristic
# differs, instead of only which line numbers.
nfr_records() {
  awk '
    BEGIN { RS = ""; FS = "\n" }
    {
      id = "unknown"
      for (i = 1; i <= NF; i++) {
        if ($i ~ /<!-- nfr: /) {
          id = $i
          sub(/.*<!-- nfr: */, "", id)
          sub(/ *-->.*/, "", id)
        }
      }
      line = $0
      gsub(/\n/, " ", line)
      print id "\t" line
    }
  ' | sort
}

# Compares the checked-in block in <template> with what the generator
# produces from <nfr_map>. Prints the differing characteristics and returns
# 1 if there's a difference.
nfr_drift() {
  local nfr_map="$1" template="$2"
  local checked_in generated differences status=0

  checked_in="$(mktemp)"
  generated="$(mktemp)"

  local block_checked_in block_generated
  block_checked_in="$(mktemp)"
  block_generated="$(mktemp)"

  awk '
    /<!-- nfr-block:begin/ { in_block = 1; next }
    /<!-- nfr-block:end/  { in_block = 0 }
    in_block { print }
  ' "$template" > "$block_checked_in"
  nfr_block "$nfr_map" > "$block_generated"

  # First the order, in document order. nfr_records sorts by ID after all,
  # so a wrong order would drop out there against the comparison.
  local order_in order_generated
  order_in="$(grep -oE '<!-- nfr: [a-z-]+' "$block_checked_in" | sed 's/.*nfr: //' | tr '\n' ' ')"
  order_generated="$(grep -oE '<!-- nfr: [a-z-]+' "$block_generated" | sed 's/.*nfr: //' | tr '\n' ' ')"
  if [ "$order_in" != "$order_generated" ]; then
    status=1
    echo "block order differs"
  fi

  nfr_records < "$block_checked_in" > "$checked_in"
  nfr_records < "$block_generated" > "$generated"
  rm -f "$block_checked_in" "$block_generated"

  if ! diff -q "$checked_in" "$generated" >/dev/null 2>&1; then
    status=1
    differences="$(diff "$checked_in" "$generated" | grep -E '^[<>]' | awk '{print $2}' | sort -u)"
    printf '%s\n' "$differences"
  fi

  rm -f "$checked_in" "$generated"
  return "$status"
}

# #134 — Warns about a yes-answered spec-* row whose PRD.md subsection
# doesn't exist yet. Observed during tennis-invoicing's adoption catch-up
# (PR TiesL/tennis-invoicing#18/#19): a row was answered "yes" a day
# before its PRD.md subsection was actually written, and the gap only
# stayed visible because someone happened to add a Notes explanation
# pointing at an open issue — a human habit, not a mechanical check.
# Deliberately a warning, not an error (see nfr_missing_subsection's
# caller in `check`): a freshly-answered "yes" deserves a short, visible
# grace period, same spirit as check-traceability.sh's own soft warnings.
#
# Prints one line per missing subsection: "<id>: no PRD.md subsection for
# '<heading>' yet". Never suppressed by a Notes explanation (AC3) — that's
# the point: the check no longer depends on someone adding one.
nfr_missing_subsection() {
  local nfr_map="$1" project_dir="$2"
  local answers="$project_dir/WORKFLOW-ADOPTION.md"
  [ -f "$answers" ] || answers="$project_dir/WORKFLOW-ADOPTIE.md"
  [ -f "$answers" ] || return 0
  local prd="$project_dir/PRD.md"
  [ -f "$prd" ] || return 0

  local id answer heading anchor
  while IFS='|' read -r _ raw_id raw_answer _; do
    id="$(printf '%s' "$raw_id" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    case "$id" in spec-*) ;; *) continue ;; esac
    answer="$(printf '%s' "$raw_answer" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ "$answer" = "yes" ] || [ "$answer" = "ja" ] || continue

    anchor="<!-- nfr: $id -->"
    grep -qF "$anchor" "$prd" 2>/dev/null && continue

    heading="$(nfr_current_id "$id")"
    heading="$(nfr_field "$nfr_map/$heading.md" heading)"
    [ -n "$heading" ] || heading="$id"
    grep -qxF "### $heading" "$prd" 2>/dev/null && continue

    echo "$id: no PRD.md subsection for '$heading' yet"
  done < "$answers"
}
