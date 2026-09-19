#!/usr/bin/env bash
# skills/pre-merge-review/model-record-gate.sh — #241 AC1: makes
# process-model-choice mechanically checkable instead of resting on an
# agent remembering to follow the model-choice skill's prose instruction.
#
# Usage:
#   model-record-gate.sh <pr-number>
#
# Checks that all five pipeline stages (Discovery, Planning, Test,
# Implementation, Review) have at least one machine-readable
#   <!-- model-record: stage=<Stage> model="..." effort="..." -->
# marker, searched across the PR's own comments, the PR's own description,
# and the comments of every issue it closes (Discovery is typically
# recorded on the issue, the other four on the PR — but this searches all
# three for either, since model-choice's own "single session" note allows
# one session to do every stage and record all of them wherever it's
# writing at the time).
#
# Found via #238 (portfolio-mgt-agents): only the Review stage ever
# recorded a model in practice — Discovery/Planning/Test/Implementation
# never did, and nothing made that visible before this gate.
#
# Fail-open without gh or network: warn, don't block — same ground rule
# as every other gate here (scenario-gate.sh, check-pr-issue-link.sh).
#
# Output on stdout: one line per missing stage:
#   "model-record: no record found for stage <Stage> (missing model-choice marker)"
# plus, when Review and Implementation both have a marker (#244 AC2):
#   "model-record: Review and Implementation recorded the same model (\"<model>\") with no same-model-exception (#244)"
#
# No `eval`. PR/issue comment text isn't under this script's control.
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

set -uo pipefail

pr_number="${1:?usage: model-record-gate.sh <pr-number>}"

if ! command -v gh >/dev/null 2>&1; then
  echo "warning: model-record-gate can't find gh and is skipping the model-record check." >&2
  exit 0
fi

comments_part="$(gh pr view "$pr_number" --json comments --jq '.comments[].body' 2>&1)"
status=$?
if [ "$status" -ne 0 ]; then
  echo "warning: model-record-gate couldn't consult PR #$pr_number's comments (no network or no access) and is skipping the model-record check." >&2
  echo "$comments_part" >&2
  exit 0
fi

# Found during PR #251's pre-merge-review: a marker posted directly in
# the PR's own description (common when a work item's Planning/Test/
# Implementation markers are added at PR-creation time, before any
# comment exists) was invisible to this gate — it only ever scanned
# comments. The description is as durable an artifact as a comment.
description_part="$(gh pr view "$pr_number" --json body --jq '.body' 2>&1)"
status=$?
if [ "$status" -ne 0 ]; then
  echo "warning: model-record-gate couldn't consult PR #$pr_number's description (no network or no access) and is skipping the model-record check." >&2
  echo "$description_part" >&2
  exit 0
fi

issue_numbers="$(gh pr view "$pr_number" --json closingIssuesReferences --jq '.closingIssuesReferences[].number' 2>&1)"
status=$?
if [ "$status" -ne 0 ]; then
  echo "warning: model-record-gate couldn't consult PR #$pr_number's closing issues (no network or no access) and is skipping the model-record check." >&2
  echo "$issue_numbers" >&2
  exit 0
fi

issue_text=""
if [ -n "$issue_numbers" ]; then
  while IFS= read -r issue_num; do
    [ -n "$issue_num" ] || continue
    issue_body="$(gh issue view "$issue_num" --json comments --jq '.comments[].body' 2>&1)"
    issue_status=$?
    if [ "$issue_status" -ne 0 ]; then
      # Found during PR #249's pre-merge-review (round 2): silently
      # swallowing this would misreport "no Discovery record" as if the
      # stage were genuinely missing, rather than "couldn't check" — a
      # transient failure here must warn, same as every other gh call in
      # this script, not degrade to a false negative.
      echo "warning: model-record-gate couldn't consult issue #$issue_num (no network or no access) and is skipping its comments." >&2
      echo "$issue_body" >&2
      continue
    fi
    issue_text="$issue_text
$issue_body"
  done <<<"$issue_numbers"
fi

# Ordered issue -> description -> comments: a heuristic match to the
# typical stage lifecycle (Discovery on the issue first, then the PR
# opens with its description, then PR comments accumulate through
# Planning/Test/Implementation/Review), not a true global timestamp sort
# — gh's comment JSON does carry createdAt, but nothing here reads it yet.
# Found during PR #253's pre-merge-review (round 2): the previous order
# (comments, then description, then issue) put issue comments *last*,
# so `tail -1` could prefer a stray older marker on the issue over a
# genuinely newer one on the PR — backwards from the typical case this
# reorders toward. Recorded as Technical debt (PRD.md) rather than chasing
# full generality here.
all_text="$issue_text
$description_part
$comments_part"

for stage in Discovery Planning Test Implementation Review; do
  # <<< here-string, not a piped producer | grep -q: SIGPIPE/pipefail
  # race, see issue #218 and check-no-sigpipe-race.sh.
  if ! grep -qE "model-record:[[:space:]]*stage=$stage\\b" <<<"$all_text"; then
    echo "model-record: no record found for stage $stage (missing model-choice marker)"
  fi
done

# #244 AC2: Review must use a different model than Implementation unless
# an explicit same-model-exception is recorded — the contradiction #244
# resolved between CHANGES.md and this skill is otherwise just as
# unenforced as it was before. Only checked when both markers are present
# (the loop above already reports either one missing).
#
# Found during PR #253's pre-merge-review (Opus, genuinely different
# model from Implementation):
# - `tail -1`, not `head -1` — a later review round's marker must win;
#   `head -1` let a round-1 different-model marker mask a round-2
#   same-model violation, and could never clear a round-1 same-model
#   flag no matter what a later round recorded.
# - Extraction only trusts the quoted `model="..."` form. An unquoted
#   marker (`model=Sonnet`) previously made the old sed silently return
#   the *whole line* unchanged (its pattern simply didn't match) — two
#   malformed markers could then spuriously compare "equal" on garbage,
#   or two different garbage lines could wrongly compare "different".
#   Now: no quoted match -> empty model, comparison skipped entirely
#   (silence, not a false claim either way) — malformed input is a
#   distinct failure mode from "same model", not folded into it.
# - `same-model-exception="..."` must have a non-empty reason;
#   `same-model-exception=""` no longer satisfies the exception.
# - Comparison is case-insensitive after trimming — "Claude Sonnet 5" and
#   "claude sonnet 5" are the same model spelled differently, not two
#   different ones. This does not catch every possible respelling (e.g.
#   an abbreviated vs. full name); it catches exact-modulo-case, which is
#   the actual failure mode worth guarding against here.
impl_line="$(grep -oE '<!--[[:space:]]*model-record:[[:space:]]*stage=Implementation[^>]*-->' <<<"$all_text" | tail -1)"
review_line="$(grep -oE '<!--[[:space:]]*model-record:[[:space:]]*stage=Review[^>]*-->' <<<"$all_text" | tail -1)"
if [ -n "$impl_line" ] && [ -n "$review_line" ]; then
  impl_model="$(grep -oE 'model="[^"]*"' <<<"$impl_line" | head -1 | sed 's/^model="//; s/"$//')"
  review_model="$(grep -oE 'model="[^"]*"' <<<"$review_line" | head -1 | sed 's/^model="//; s/"$//')"
  impl_model_norm="$(printf '%s' "$impl_model" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  review_model_norm="$(printf '%s' "$review_model" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  if [ -n "$impl_model_norm" ] && [ -n "$review_model_norm" ] \
    && [ "$impl_model_norm" = "$review_model_norm" ] \
    && ! grep -qE 'same-model-exception="[^"]+"' <<<"$review_line"; then
    echo "model-record: Review and Implementation recorded the same model (\"$review_model\") with no same-model-exception (#244)"
  fi
fi
