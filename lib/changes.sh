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
predicate_true() {
  local predicate="$1" project_dir="$2"
  case "$predicate" in
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

# Walks the entries in <source> and calls <callback> with
# <id> <default> <predicate>.
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
# `default` is "yes" when the entry carries no `**Default:**` field.
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
# The caller decides what to do with `default` — deliberately not settled
# here. adopt.sh skips `question` (those entries are never answered
# automatically); pending-changes.sh, on the other hand, ignores the field,
# because an unanswered question stays pending regardless of its starting
# point. A flag in this library would hide that difference and make it look
# like an oversight; visible at both callers is better. See the comments
# there, which reference each other.
iterate_entries() {
  local source="$1" callback="$2"
  local line current_id="" default="yes" predicate
  local errors=0 seen_predicate=0

  # `|| [ -n "$line" ]` catches a source with no trailing newline: read
  # then returns a non-zero status while the last line has still been read.
  # Without that, that line would drop — and given the warning below, an
  # entry would then be silently skipped along with a misleading message.
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      '## '*)
        if [ -n "$current_id" ] && [ "$seen_predicate" -eq 0 ]; then
          echo "warning: entry '$current_id' in $source has no 'Applies if' field" >&2
        fi
        current_id="${line#\#\# }"
        default="yes"
        seen_predicate=0 ;;
      *'**Default:**'*)
        default="${line##*\*\* }"
        default="$(echo "$default" | tr -d '[:space:]')" ;;
      *'**Applies if:**'*)
        predicate="${line##*\*\* }"
        predicate="$(echo "$predicate" | tr -d '[:space:]')"
        [ -n "$current_id" ] || continue
        seen_predicate=1
        if ! "$callback" "$current_id" "$default" "$predicate"; then
          echo "warning: processing entry '$current_id' produced an error" >&2
          errors=$((errors + 1))
        fi ;;
    esac
  done < "$source"

  # The last entry in the file counts too.
  if [ -n "$current_id" ] && [ "$seen_predicate" -eq 0 ]; then
    echo "warning: entry '$current_id' in $source has no 'Applies if' field" >&2
  fi

  [ "$errors" -eq 0 ]
}

# The IDs of entries without an https-**PR:** field, one per line (W21,
# F15, S32). Same entry shape as iterate_entries above ("## " opens an
# entry), but without the predicate contract — this also works on
# CHANGES-ARCHIEF.md, where Default and Applies if are
# deliberately absent.
#
# No stricter URL validation than "starts with https://": the linkback must
# be findable again, not necessarily point to GitHub — a project could use
# its own forge.
pr_links_missing() {
  local source="$1"
  [ -f "$source" ] || return 0

  local line current_id="" has_pr=0

  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      '## '*)
        if [ -n "$current_id" ] && [ "$has_pr" -eq 0 ]; then
          echo "$current_id"
        fi
        current_id="${line#\#\# }"
        has_pr=0 ;;
      '- **PR:** https://'*)
        has_pr=1 ;;
    esac
  done < "$source"

  if [ -n "$current_id" ] && [ "$has_pr" -eq 0 ]; then
    echo "$current_id"
  fi
}

# Walks *both* sources: the entries in CHANGES.md and the NFR register in
# nfr/. Since W5, the fifteen non-functional characteristics no longer live
# as spec-* entries in CHANGES.md but in their own register — this function
# keeps that one thing for callers.
#
# <workflow_dir> is the directory with CHANGES.md and nfr/.
iterate_all_entries() {
  local workflow_dir="$1" callback="$2"
  local errors=0

  if [ -f "$workflow_dir/CHANGES.md" ]; then
    iterate_entries "$workflow_dir/CHANGES.md" "$callback" || errors=$((errors + 1))
  fi
  iterate_nfr "$workflow_dir/nfr" "$callback" || errors=$((errors + 1))

  [ "$errors" -eq 0 ]
}
