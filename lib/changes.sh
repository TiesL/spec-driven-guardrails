#!/usr/bin/env bash
# lib/changes.sh — The shared parser and predicate logic for CHANGES.md.
#
# Source, don't execute. Both adopt.sh and pending-changes.sh use this;
# before this library, the predicates lived literally twice, and so did the
# parser skeleton, letting them drift out of sync without anything
# complaining.
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

# The one and only predicate logic. Expressed as a case instead of eval of
# free text from CHANGES.md: predictable, and a typo yields "unknown"
# instead of an unintended command.
predicaat_waar() {
  local predicaat="$1" project_dir="$2"
  case "$predicaat" in
    always)
      return 0 ;;
    heeft-package-json)
      [ -f "$project_dir/package.json" ] ;;
    heeft-deploy-script)
      [ -f "$project_dir/package.json" ] &&
        grep -q '"deploy"[[:space:]]*:' "$project_dir/package.json" ;;
    *)
      return 1 ;;
  esac
}

# Walks the entries in <bron> and calls <callback> with
# <id> <standaard> <predicaat>.
#
# Only entries with an "Applies if" field lead to a call: that field
# is what makes an entry active.
#
# A `## ` heading without that field produces a warning. Since section
# separators in CHANGES.md are `###`, `## ` unconditionally means "entry",
# so such a heading is a forgotten predicate, not a subheading. Retirement
# happens by moving to CHANGES-ARCHIEF.md, not by dropping fields. The
# warning goes to stderr: visible in `check` and when run manually, and
# suppressed in the SessionStart hook, where a project can't do anything
# about it anyway.
#
# `standaard` is "yes" when the entry carries no `**Default:**` field.
#
# **Contract for the callback:** its exit status carries no meaning for
# this loop, but a non-zero status is reported and counts toward the final
# status. That's deliberate: without that handling, a callback that
# accidentally returns 1 — for example through a trailing `a && b` where
# `a` is false — would silently stop a caller running with `set -e`,
# halfway through the loop and with no report at all. adopt.sh runs with
# `set -e`, pending-changes.sh doesn't; that asymmetry makes such a mistake
# easy to make and hard to see.
#
# The caller decides what to do with `standaard` — deliberately not settled
# here. adopt.sh skips `question` (those entries are never answered
# automatically); pending-changes.sh, on the other hand, ignores the field,
# because an unanswered question stays pending regardless of its starting
# point. A flag in this library would hide that difference and make it look
# like an oversight; visible at both callers is better. See the comments
# there, which reference each other.
itereer_entries() {
  local bron="$1" callback="$2"
  local regel huidig_id="" standaard="yes" predicaat
  local fouten=0 gezien_predicaat=0

  # `|| [ -n "$regel" ]` catches a source with no trailing newline: read
  # then returns a non-zero status while the last line has still been read.
  # Without that, that line would drop — and given the warning below, an
  # entry would then be silently skipped along with a misleading message.
  while IFS= read -r regel || [ -n "$regel" ]; do
    case "$regel" in
      '## '*)
        if [ -n "$huidig_id" ] && [ "$gezien_predicaat" -eq 0 ]; then
          echo "warning: entry '$huidig_id' in $bron has no 'Applies if' field" >&2
        fi
        huidig_id="${regel#\#\# }"
        standaard="yes"
        gezien_predicaat=0 ;;
      *'**Default:**'*)
        standaard="${regel##*\*\* }"
        standaard="$(echo "$standaard" | tr -d '[:space:]')" ;;
      *'**Applies if:**'*)
        predicaat="${regel##*\*\* }"
        predicaat="$(echo "$predicaat" | tr -d '[:space:]')"
        [ -n "$huidig_id" ] || continue
        gezien_predicaat=1
        if ! "$callback" "$huidig_id" "$standaard" "$predicaat"; then
          echo "warning: processing entry '$huidig_id' produced an error" >&2
          fouten=$((fouten + 1))
        fi ;;
    esac
  done < "$bron"

  # The last entry in the file counts too.
  if [ -n "$huidig_id" ] && [ "$gezien_predicaat" -eq 0 ]; then
    echo "warning: entry '$huidig_id' in $bron has no 'Applies if' field" >&2
  fi

  [ "$fouten" -eq 0 ]
}

# The IDs of entries without an https-**PR:** field, one per line (W21,
# F15, S32). Same entry shape as itereer_entries above ("## " opens an
# entry), but without the predicate contract — this also works on
# CHANGES-ARCHIEF.md, where Default and Applies if are
# deliberately absent.
#
# No stricter URL validation than "starts with https://": the linkback must
# be findable again, not necessarily point to GitHub — a project could use
# its own forge.
pr_links_ontbrekend() {
  local bron="$1"
  [ -f "$bron" ] || return 0

  local regel huidig_id="" heeft_pr=0

  while IFS= read -r regel || [ -n "$regel" ]; do
    case "$regel" in
      '## '*)
        if [ -n "$huidig_id" ] && [ "$heeft_pr" -eq 0 ]; then
          echo "$huidig_id"
        fi
        huidig_id="${regel#\#\# }"
        heeft_pr=0 ;;
      '- **PR:** https://'*)
        heeft_pr=1 ;;
    esac
  done < "$bron"

  if [ -n "$huidig_id" ] && [ "$heeft_pr" -eq 0 ]; then
    echo "$huidig_id"
  fi
}

# Walks *both* sources: the entries in CHANGES.md and the NFR register in
# nfr/. Since W5, the fifteen non-functional characteristics no longer live
# as spec-* entries in CHANGES.md but in their own register — this function
# keeps that one thing for callers.
#
# <workflow_dir> is the directory with CHANGES.md and nfr/.
itereer_alle_entries() {
  local workflow_dir="$1" callback="$2"
  local fouten=0

  if [ -f "$workflow_dir/CHANGES.md" ]; then
    itereer_entries "$workflow_dir/CHANGES.md" "$callback" || fouten=$((fouten + 1))
  fi
  itereer_nfr "$workflow_dir/nfr" "$callback" || fouten=$((fouten + 1))

  [ "$fouten" -eq 0 ]
}
