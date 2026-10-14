#!/usr/bin/env bash
# model-record-gate.sh <pr-number> — A31a/A32a/A34a/A37, #427.
#
# REST-only, Bash 3.2. Each fetched body is sanitized before transport framing;
# rec_scan_bundle owns quoting and grammar. One cached scan per record kind.
# Only ok records supply presence. Timestamp-latest candidates (including
# near-misses) decide; no fallback to an older ok. PR description edits are
# not tracked: its timestamp is created_at. Source ties: issue, description,
# comments, reviews; within a body the later candidate line wins.
#
# Findings are stdout, exit 0. In projects answering process-multi-agent-roles
# yes, only `role-played: ` blocks a merge. Every incomplete check emits
# `role-play-unchecked: ` and fails open; a closing-reference HTTP 404 instead
# gives a note and is ignored. The guard shows near-misses as context.
#
# Limits: cannot verify emitter provenance, model identity/capability, agent
# identity, basis honesty, override authorship or work-item attribution.
# A session forging five separate stage comments is not detected. Effort is
# neither chosen nor checked. The hook prints the warning; in the #430 AC3 run it was seen in the
# transcript only, not by the agent as command output.
set -uo pipefail
export LC_ALL=C
pr_number="${1:?usage: model-record-gate.sh <pr-number>}"
own_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(git rev-parse --show-toplevel 2>/dev/null)" || project_root="$(pwd)"
opted_in=0
if [ -r "$own_dir/../../lib/changes.sh" ]; then
  # shellcheck source=../../lib/changes.sh
  . "$own_dir/../../lib/changes.sh"
  answered_yes "$project_root" process-multi-agent-roles && opted_in=1
fi
unchecked() {
  echo "warning: model-record-gate $1; skipping the incomplete check." >&2
  [ "$opted_in" -eq 0 ] || echo "role-play-unchecked: $1"
}
reader_failed() {
  echo 'model-record: the record reader failed, so no records were read and dependent checks were skipped'
  unchecked 'record reader failed'
  exit 0
}
if ! command -v gh >/dev/null 2>&1; then
  unchecked "can't find gh"
  exit 0
fi
if [ ! -r "$own_dir/../../lib/model-record.sh" ]; then reader_failed; fi
# shellcheck source=../../lib/model-record.sh
. "$own_dir/../../lib/model-record.sh"

# Transport: time TAB body, with body LF encoded as SOH. Remove injected
# framing bytes BEFORE adding separators. Preserve tabs/CR in values for
# the reader to classify; only the first tab is the metadata delimiter.
body_filter='(.body // "" | gsub("\u001e"; "") | gsub("\u0001"; " ") | gsub("\n"; "\u0001"))'
comments_jq=".[] | (.created_at // \"\") + \"\t\" + $body_filter"
reviews_jq=".[] | (.submitted_at // \"\") + \"\t\" + $body_filter"
comments="$(gh api "repos/{owner}/{repo}/issues/$pr_number/comments" --paginate --jq "$comments_jq")" || { unchecked "couldn't consult PR #$pr_number's comments"; exit 0; }
reviews="$(gh api "repos/{owner}/{repo}/pulls/$pr_number/reviews" --paginate --jq "$reviews_jq")" || { unchecked "couldn't consult PR #$pr_number's reviews"; exit 0; }
pr_jq="((.title // \"\") | gsub(\"[\\u0000-\\u001f]\"; \" \")), ((.created_at // \"\") + \"\t\" + $body_filter)"
pr="$(gh api "repos/{owner}/{repo}/pulls/$pr_number" --jq "$pr_jq")" || { unchecked "couldn't consult PR #$pr_number's description"; exit 0; }
# A blank title is still a first line (command substitution strips only final LF).
title="${pr%%$'\n'*}"
description="${pr#*$'\n'}"
[ "$description" != "$pr" ] || { unchecked 'unreadable PR description response'; exit 0; }
description_body="${description#*$'\t'}"
closing_keyword_ere='\b(close[sd]?|fix(e[sd])?|resolve[sd]?):?[[:space:]]+#[0-9]+\b'
issue_numbers="$(LC_ALL=C grep -oiE "$closing_keyword_ere" <<<"$title ${description_body//$'\001'/$'\n'}" | LC_ALL=C grep -oE '[0-9]+' | LC_ALL=C sort -un)"

# Private implementation arrays: raw bodies never participate in a sort key.
# Numeric sequence preserves order within equal-time sources.
tab=$'\t'
seq=0
bodies=()
labels=()
keyed=''
add_bodies() { # rank, source label, time<TAB>encoded-body rows
  local rank="$1" label="$2" row ts body
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    case "$row" in *"$tab"*) :;; *) return 1;; esac
    ts="${row%%"$tab"*}"
    [ -n "$ts" ] || return 1
    body="${row#*"$tab"}"
    seq=$((seq + 1))
    bodies[$seq]="${body//$'\001'/$'\n'}"
    labels[$seq]="$label"
    keyed="$keyed$ts$tab$rank$tab$seq"$'\n'
  done <<<"$3"
}
notes=''
issue_error_file="$(mktemp)" || { unchecked 'could not capture closing-issue status'; exit 0; }
trap 'rm -f "$issue_error_file"' EXIT
while IFS= read -r issue; do
  [ -n "$issue" ] || continue
  issue_rows="$(gh api "repos/{owner}/{repo}/issues/$issue/comments" --paginate --jq "$comments_jq" 2>"$issue_error_file")"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    # The CLI reports an HTTP status alongside its message. Never classify
    # a transport/authorization/server failure merely from 'Not Found' prose.
    issue_error="$(cat "$issue_error_file")"
    case "$issue_error" in
      *'(HTTP 404)'*) notes="$notes""model-record: closing reference #$issue does not exist and was ignored"$'\n'; continue;;
      *) echo "$issue_error" >&2; unchecked "couldn't consult closing issue #$issue"; exit 0;;
    esac
  fi
  add_bodies 0 'issue comment' "$issue_rows" || { unchecked "unreadable closing issue #$issue response"; exit 0; }
done <<<"$issue_numbers"
add_bodies 1 'PR description' "$description" && add_bodies 2 'PR comment' "$comments" && add_bodies 3 'PR review' "$reviews" || { unchecked 'unreadable fetched body timestamps'; exit 0; }
ordered="$(LC_ALL=C sort -t "$tab" -k1,1 -k2,2n -k3,3n <<<"$keyed")" || reader_failed
[ -n "$ordered" ] || reader_failed
bundle=''
body_labels=()
body_count=0
while IFS="$tab" read -r _ _ original; do
  [ -n "$original" ] || continue
  body_count=$((body_count + 1))
  bundle="$bundle${bodies[$original]}$MARKER_SEP"
  body_labels[$body_count]="${labels[$original]}"
done <<<"$ordered"
scan="$(rec_scan_bundle model-record "$bundle")" || reader_failed
po_scan=''
if [ "$opted_in" -eq 1 ]; then
  po_scan="$(rec_scan_bundle pipeline-override "$bundle")" || reader_failed
fi

stages=(Discovery Planning Test Implementation Review)
present=(0 0 0 0 0)
latest_class=('' '' '' '' '')
latest_line=('' '' '' '' '')
body_present=()
findings="$notes"
# No record patterns here: classification/stage/fields come only from lib.
stage_index() {
  case "$1" in Discovery) echo 0;; Planning) echo 1;; Test) echo 2;; Implementation) echo 3;; Review) echo 4;; *) return 1;; esac
}
while IFS= read -r row; do
  [ -n "$row" ] || continue
  idx="${row%%"$tab"*}"; rest="${row#*"$tab"}"
  cls="${rest%%"$tab"*}"; rest="${rest#*"$tab"}"
  stage="${rest%%"$tab"*}"; line="${rest#*"$tab"}"
  [ "$cls" != quoted ] || continue
  if [ "$cls" = near-miss ]; then
    findings="$findings""model-record: a stage=$stage record is a near-miss ($line)"$'\n'
  fi
  s="$(stage_index "$stage")" || continue
  latest_class[$s]="$cls"
  latest_line[$s]="$line"
  if [ "$cls" = ok ]; then
    present[$s]=1
    body_present[$((idx * 5 + s))]=1
  fi
done <<<"$scan"
for s in 0 1 2 3 4; do
  stage="${stages[$s]}"
  if [ "${present[$s]}" -eq 0 ]; then
    findings="$findings""model-record: no record found for stage $stage (missing model-choice marker)"$'\n'
  fi
  if [ "${latest_class[$s]}" = near-miss ]; then
    findings="$findings""model-record: the latest stage=$stage record is unreadable, so no earlier record is used"$'\n'
  fi
done
# Review's own basis is required even without Implementation. Different
# models cannot be ranked by the gate; same-model legacy effort is ignored.
if [ "${latest_class[4]}" = ok ]; then
  basis="$(rec_field "${latest_line[4]}" floor-basis)" || reader_failed
  case "$basis" in *[![:space:]]*) :;; *) findings="$findings""model-record: stage=Review marker has no floor-basis (why Review's model clears Implementation's)"$'\n';; esac
fi

waive_all=0
skipped=' '
while IFS= read -r row; do
  [ -n "$row" ] || continue
  rest="${row#*"$tab"}"; cls="${rest%%"$tab"*}"; rest="${rest#*"$tab"}"; line="${rest#*"$tab"}"
  [ "$cls" != quoted ] || continue
  if [ "$cls" = ok ]; then
    who="$(rec_field "$line" decided-by)" && reason="$(rec_field "$line" reason)" && scope="$(rec_field "$line" scope)" || reader_failed
    valid=1
    case "$who" in *[![:space:]]*) :;; *) valid=0;; esac
    case "$reason" in *[![:space:]]*) :;; *) valid=0;; esac
    case "$scope" in single-session|skip=Discovery|skip=Planning|skip=Test|skip=Implementation|skip=Review) :;; *) valid=0;; esac
    if [ "$valid" -eq 1 ]; then
      if [ "$scope" = single-session ]; then waive_all=1; else skipped="$skipped${scope#skip=} "; fi
      continue
    fi
    line="non-blank decided-by and reason, and a valid scope are required: $line"
  fi
  findings="$findings""model-record: a pipeline-override near-miss ($line)"$'\n'
done <<<"$po_scan"
printf '%s' "$findings"
[ "$opted_in" -eq 1 ] || exit 0

in_one_text=''
for ((idx=1; idx<=body_count; idx++)); do
  names=''; n=0
  for s in 0 1 2 3 4; do
    [ "${body_present[$((idx * 5 + s))]:-0}" -eq 1 ] || continue
    names="$names${names:+, }${stages[$s]}"; n=$((n + 1))
  done
  if [ "$n" -ge 2 ]; then in_one_text="$in_one_text$names (${body_labels[$idx]})"$'\n'; fi
done
missing=''; waived=''
for s in 0 1 2 3 4; do
  [ "${present[$s]}" -eq 0 ] || continue
  stage="${stages[$s]}"
  case "$skipped" in *" $stage "*) waived="$waived skip=$stage";; *) missing="$missing${missing:+, }$stage";; esac
done
if [ "$waive_all" -eq 1 ]; then
  if [ -n "$in_one_text$missing$waived" ]; then echo 'model-record: a pipeline-override (scope=single-session) waived the role-play findings'; fi
  exit 0
fi
while IFS= read -r text; do
  [ -z "$text" ] || echo "role-played: stages in one text: $text"
done <<<"$in_one_text"
[ -z "$missing" ] || echo "role-played: stages missing: $missing"
[ -z "$waived" ] || echo "model-record: a pipeline-override waived stage absence:$waived"
exit 0
