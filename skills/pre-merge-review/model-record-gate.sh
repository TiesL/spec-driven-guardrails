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
# three for either: where a stage's report lands is not fixed).
#
# Role-played runs (#371, A18): only in a project that answers
# process-multi-agent-roles yes (answered_yes, lib/changes.sh, read from
# the clone this script lives in), it also flags a run where one session
# played every role instead of the pipeline dispatching them. That is:
# one text (a comment, a review or the PR description) carrying live
# markers for two or more different stages, or any of the five stages
# missing. A valid human override record on the issue or PR,
#   <!-- pipeline-override: decided-by="..." scope="single-session|skip=<Stage>" reason="..." -->
# (live text, every field non-empty, scope from that closed list) waives
# it: single-session waives every finding, skip=<Stage> only that stage's
# absence. The merge guard (hooks/git-guardrails) refuses `gh pr merge` on
# any `role-played: ` line, so this script owns the rule and the guard only
# reads the prefix. A project that didn't answer yes sees no change.
# Accepted limit: a session that forges five separate stage comments isn't
# detected (same non-adversarial trust model as every gate here).
#
# Found via #238 (portfolio-mgt-agents): only the Review stage ever
# recorded a model in practice — Discovery/Planning/Test/Implementation
# never did, and nothing made that visible before this gate.
#
# Fail-open without gh or network: warn, don't block — same ground rule
# as every other gate here (scenario-gate.sh, check-pr-issue-link.sh).
#
# REST-only (issue #318, reusing role-label-staleness.sh's/
# compliance-evidence.sh's already-reviewed design rather than
# re-deriving it independently): every `gh pr view --json ...`/`gh issue
# view --json ...` call this script used to make is GraphQL-backed under
# the hood and 403s from inside a Claude Code session — confirmed live,
# where this gate's own fail-open design meant it never crashed, just
# silently skipped the check on every single run rather than performing
# it (a correctness gap distinct from, and worse in a different way
# than, an outright failure). `closingIssuesReferences` has a second,
# separate defect even outside that block: GitHub only populates it for
# a PR whose base is the repository's default branch, so it silently
# missed every closing issue on a release-branch PR — exactly the shape
# that would make this gate wrongly report "no Discovery record found"
# when Discovery's marker sits on the issue this gate never looked at.
#
# Every call below is `gh api repos/{owner}/{repo}/...` against an
# explicit REST endpoint, confirmed working from inside a Claude Code
# session. Closing-issue discovery replaces `closingIssuesReferences`
# with the same closing-keyword scan against the PR's own title+body
# compliance-evidence.sh uses (title included — this repo's own
# release-branch PRs carry the keyword only there).
#
# Output on stdout: one line per missing stage:
#   "model-record: no record found for stage <Stage> (missing model-choice marker)"
# plus, when Review and Implementation both have a marker (#244 AC2):
#   "model-record: Review and Implementation recorded the same model (\"<model>\") with no same-model-exception (#244)"
# plus, opted in only (#371), one line per role-play finding:
#   "role-played: stages in one text: <Stage>, <Stage> (<source>)"
#   "role-played: stages missing: <Stage>, ..."
# and, when a valid override waived them, a note that never starts with
# "role-played: ". Exit status stays 0: findings are output.
#
# No `eval`. PR/issue comment text isn't under this script's control.
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

set -uo pipefail

pr_number="${1:?usage: model-record-gate.sh <pr-number>}"

if ! command -v gh >/dev/null 2>&1; then
  echo "warning: model-record-gate can't find gh and is skipping the model-record check." >&2
  exit 0
fi

# #371: is this project opted in to the five-role pipeline? Read from the
# project this runs in (its git root, else the working directory), with
# the shared answered_yes rule from the clone this script lives in (pwd -P:
# in an adopted project this directory is a symlink into the clone, same
# resolution as scope.sh). No lib, no opt-in: fail open.
own_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(git rev-parse --show-toplevel 2>/dev/null)" || project_root="$(pwd)"
opted_in=0
if [ -r "$own_dir/../../lib/changes.sh" ]; then
  # shellcheck source=../../lib/changes.sh
  . "$own_dir/../../lib/changes.sh"
  answered_yes "$project_root" process-multi-agent-roles && opted_in=1
fi

# Opted in, each comment/review body is framed with U+001E so the
# role-play check can tell one text from the next; the existing checks
# below read the same text with the separators removed. Not opted in, the
# calls are exactly what they were.
body_jq='.[].body'
[ "$opted_in" -eq 1 ] && body_jq='.[] | (.body // "") + "\u001e"'

comments_part="$(gh api "repos/{owner}/{repo}/issues/$pr_number/comments" --paginate --jq "$body_jq" 2>&1)"
status=$?
if [ "$status" -ne 0 ]; then
  echo "warning: model-record-gate couldn't consult PR #$pr_number's comments (no network or no access) and is skipping the model-record check." >&2
  echo "$comments_part" >&2
  exit 0
fi

# PR reviews (issue #318, folding in the same fix role-label-staleness.sh
# needed as its own F-6 finding): this pipeline posts the Review stage's
# marker as a PR review's own body, not a plain conversation comment —
# a source this gate never read either, under the old call or the new.
reviews_part="$(gh api "repos/{owner}/{repo}/pulls/$pr_number/reviews" --paginate --jq "$body_jq" 2>&1)"
status=$?
if [ "$status" -ne 0 ]; then
  echo "warning: model-record-gate couldn't consult PR #$pr_number's reviews (no network or no access) and is skipping the model-record check." >&2
  echo "$reviews_part" >&2
  exit 0
fi

# Found during PR #251's pre-merge-review: a marker posted directly in
# the PR's own description (common when a work item's Planning/Test/
# Implementation markers are added at PR-creation time, before any
# comment exists) was invisible to this gate — it only ever scanned
# comments. The description is as durable an artifact as a comment.
# Fetched together with the title (needed for closing-issue discovery
# below) in one call.
pr_json_part="$(gh api "repos/{owner}/{repo}/pulls/$pr_number" --jq '(.title//"")+"\u0001"+(.body//"")' 2>&1)"
status=$?
if [ "$status" -ne 0 ]; then
  echo "warning: model-record-gate couldn't consult PR #$pr_number's description (no network or no access) and is skipping the model-record check." >&2
  echo "$pr_json_part" >&2
  exit 0
fi
pr_title_part="${pr_json_part%%$'\001'*}"
description_part="${pr_json_part#*$'\001'}"

closing_keyword_ere='\b(close[sd]?|fix(e[sd])?|resolve[sd]?):?[[:space:]]+#[0-9]+\b'
issue_numbers="$(printf '%s\n%s\n' "$pr_title_part" "$description_part" \
  | grep -oiE "$closing_keyword_ere" | grep -oE '[0-9]+' | sort -un)"

issue_text=""
issue_fetch_failed=0
if [ -n "$issue_numbers" ]; then
  while IFS= read -r issue_num; do
    [ -n "$issue_num" ] || continue
    issue_body="$(gh api "repos/{owner}/{repo}/issues/$issue_num/comments" --paginate --jq "$body_jq" 2>&1)"
    issue_status=$?
    if [ "$issue_status" -ne 0 ]; then
      # Found during PR #249's pre-merge-review (round 2): silently
      # swallowing this would misreport "no Discovery record" as if the
      # stage were genuinely missing, rather than "couldn't check" — a
      # transient failure here must warn, same as every other gh call in
      # this script, not degrade to a false negative.
      echo "warning: model-record-gate couldn't consult issue #$issue_num (no network or no access) and is skipping its comments." >&2
      echo "$issue_body" >&2
      issue_fetch_failed=1
      continue
    fi
    issue_text="$issue_text
$issue_body"
  done <<<"$issue_numbers"
fi

# Ordered issue -> description -> comments -> reviews: a heuristic match
# to the typical stage lifecycle (Discovery on the issue first, then the
# PR opens with its description, then PR comments/reviews accumulate
# through Planning/Test/Implementation/Review), not a true global
# timestamp sort — gh's comment JSON does carry createdAt, but nothing
# here reads it yet. Found during PR #253's pre-merge-review (round 2):
# the previous order (comments, then description, then issue) put issue
# comments *last*, so `tail -1` could prefer a stray older marker on the
# issue over a genuinely newer one on the PR — backwards from the
# typical case this reorders toward. Recorded as Technical debt (PRD.md)
# rather than chasing full generality here.
framed_issue_text="$issue_text"
framed_comments_part="$comments_part"
framed_reviews_part="$reviews_part"
issue_text="${issue_text//$'\036'/}"
comments_part="${comments_part//$'\036'/}"
reviews_part="${reviews_part//$'\036'/}"

all_text="$issue_text
$description_part
$comments_part
$reviews_part"

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
# - Comparison uses normalize_model (#268, replacing a plain case-fold
#   found insufficient during PR #267's pre-merge-review, round 2:
#   "Sonnet 5" vs. "claude-sonnet-5" — same model, different label style
#   — case-folding alone didn't equate those either). Structural, not a
#   per-model alias table: strips the vendor-prefix word and a trailing
#   8-digit snapshot-date suffix, then folds every remaining separator
#   and case difference away. Exact-modulo-format, not exact-modulo-
#   spelling — an abbreviated name still wouldn't match — but it covers
#   the display-name-vs-API-id mismatch actually seen in practice without
#   ever hardcoding a model name.
normalize_model() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/^[[:space:]]*claude[- ]*//' \
    | sed -E 's/-[0-9]{8}$//' \
    | sed -E 's/[^a-z0-9]+/ /g' \
    | sed -E 's/^[[:space:]]+|[[:space:]]+$//g'
}
impl_line="$(grep -oE '<!--[[:space:]]*model-record:[[:space:]]*stage=Implementation[^>]*-->' <<<"$all_text" | tail -1)"
review_line="$(grep -oE '<!--[[:space:]]*model-record:[[:space:]]*stage=Review[^>]*-->' <<<"$all_text" | tail -1)"
if [ -n "$impl_line" ] && [ -n "$review_line" ]; then
  impl_model="$(grep -oE 'model="[^"]*"' <<<"$impl_line" | head -1 | sed 's/^model="//; s/"$//')"
  review_model="$(grep -oE 'model="[^"]*"' <<<"$review_line" | head -1 | sed 's/^model="//; s/"$//')"
  impl_model_norm="$(normalize_model "$impl_model")"
  review_model_norm="$(normalize_model "$review_model")"
  if [ -n "$impl_model_norm" ] && [ -n "$review_model_norm" ] \
    && [ "$impl_model_norm" = "$review_model_norm" ] \
    && ! grep -qE 'same-model-exception="[^"]+"' <<<"$review_line"; then
    echo "model-record: Review and Implementation recorded the same model (\"$review_model\") with no same-model-exception (#244)"
  fi
fi

# --- #371 A18: role-played runs, opted-in projects only ---------------------
[ "$opted_in" -eq 1 ] || exit 0

if [ "$issue_fetch_failed" -eq 1 ]; then
  echo "warning: model-record-gate couldn't read every closing issue and is skipping the role-play check (a missing Discovery marker could be a lookup failure)." >&2
  exit 0
fi

# live_text() — copied verbatim from compliance-evidence.sh, the same
# quoted-text rule (fenced code, inline code spans and blockquotes are
# illustration, not live markers). A copy, not a shared lib, by this repo's
# convention for scripts shipped to adopted projects (see
# role-label-staleness.sh); test/cases/s153_live_text_mawk_portability.sh
# asserts the copies stay byte-identical.
live_text() {
  printf '%s\n' "$1" | awk '
    function drop_spans(s,   out, n, tick, after, p, q, r) {
      out = ""
      while (match(s, /`+/)) {
        n = RLENGTH; tick = substr(s, RSTART, n)
        out = out substr(s, 1, RSTART - 1)
        after = substr(s, RSTART + n)
        # first backtick run in "after" of length exactly n
        p = 0; r = after; q = 0
        while (match(r, /`+/)) {
          if (RLENGTH == n) { p = q + RSTART; break }
          q += RSTART + RLENGTH - 1; r = substr(r, RSTART + RLENGTH)
        }
        if (p == 0) { out = out tick; s = after }        # unmatched run: literal
        else        { out = out " ";  s = substr(after, p + n) }
      }
      return out s
    }
    BEGIN { fch = ""; flen = 0 }
    /^[ \t]*>/ { print ""; next }                         # blockquote first, unchanged by fence state
    {
      line = $0
      # Issue #319, two independent mawk defects, neither worked around
      # with an mawk-specific code path:
      #
      # (1) the mawk regex compiler panics on an unbounded-lower-bound
      # interval `{n,}` combined with alternation in a group
      # (`(`{3,}|~{3,})`), and separately, `{n,}` alone is not greedy
      # under mawk (it matches exactly n, not "n or more") — silently
      # truncating a longer fence run and corrupting flen. Two top-level
      # alternatives using `+` (which every awk, mawk included, matches
      # greedily) dodge both. `+` alone would now also match a 1- or
      # 2-character run the original `{3,}`-anchored regex never did
      # (CommonMark fences need >= 3), so the `length(m) >= 3` guard
      # below is load-bearing, not defensive: without it, an inline code
      # span opening a line (e.g. `` `x` is code ``) would itself open an
      # unclosed fence and blank every line after it, including a real
      # marker (test/cases/s153_live_text_mawk_portability.sh G5). For a
      # run already >= 3, RSTART/RLENGTH match the original regex under
      # gawk exactly (verified: a 5-character fence run no longer
      # truncates to 3).
      #
      # (2) found afterward: the leading `{0,3}` itself does not parse at
      # all on an older mawk build (1.3.4 20200120, the default `awk` on
      # Ubuntu 22.04, among others) — that mawk build has no
      # brace-interval support and reads `{0,3}` as four literal
      # characters, so it never matches a real fence line and every
      # fence silently goes undetected. `? ? ?` (three
      # independently-optional literal spaces) is the brace-free
      # equivalent of "0 to 3 spaces", parses identically on every awk
      # this script has been run under (mawk 1.3.4 20200120, mawk 1.3.4
      # 20240123, gawk), and was verified against 800 randomized
      # fence-line inputs with zero differences from the original
      # `{0,3}` behavior under gawk.
      if (match(line, /^ ? ? ?`+/) || match(line, /^ ? ? ?~+/)) {
        m = substr(line, RSTART, RLENGTH); sub(/^ +/, "", m)
        if (length(m) >= 3) {
          ch = substr(m, 1, 1); len = length(m)
          rest = substr(line, RSTART + RLENGTH)
          if (fch == "") {                                  # open: any info string allowed
            fch = ch; flen = len; print ""; next
          } else if (ch == fch && len >= flen && rest ~ /^[ \t]*$/) {
            fch = ""; flen = 0; print ""; next               # close: no info string allowed (D10)
          }
        }
      }
      if (fch != "") { print ""; next }
      print drop_spans(line)
    }
  '
}

all_stages="Discovery Planning Test Implementation Review"
stage_ere='model-record:[[:space:]]*stage=(Discovery|Planning|Test|Implementation|Review)\b'

# Every text the markers are searched in, one live body per record.
# Separator-framed sources are split on U+001E; the PR description is one
# text on its own.
in_one_text=""
override_bodies=""
check_text() { # source label, raw body
  local label="$1" live stages count
  live="$(live_text "$2")"
  override_bodies="$override_bodies
$live"
  stages="$(grep -oE "$stage_ere" <<<"$live" | sed 's/.*stage=//')"
  # distinct, in pipeline order
  stages="$(for st in $all_stages; do grep -qx "$st" <<<"$stages" && echo "$st"; done)"
  [ -n "$stages" ] || return 0
  count="$(printf '%s\n' "$stages" | wc -l | tr -d ' ')"
  if [ "$count" -ge 2 ]; then
    in_one_text="$in_one_text$(printf '%s\n' "$stages" | paste -sd, - | sed 's/,/, /g') ($label)
"
  fi
  return 0
}
check_framed() { # label, framed text
  local label="$1" body
  while IFS= read -r -d $'\036' body || [ -n "$body" ]; do
    body="${body#$'\n'}"
    [ -n "$body" ] || continue
    check_text "$label" "$body"
  done <<<"$2"
}
check_framed "issue comment" "$framed_issue_text"
check_text "PR description" "$description_part"
check_framed "PR comment" "$framed_comments_part"
check_framed "PR review" "$framed_reviews_part"

# Valid override records: every field non-empty, scope from the closed list.
waive_all=0
skipped=""
while IFS= read -r marker; do
  [ -n "$marker" ] || continue
  grep -qE '(^|[[:space:]:])decided-by="[^"]+"' <<<"$marker" || continue
  grep -qE '(^|[[:space:]])reason="[^"]+"' <<<"$marker" || continue
  scope="$(grep -oE '(^|[[:space:]])scope="[^"]*"' <<<"$marker" | head -1 | sed 's/^[[:space:]]*scope="//; s/"$//')"
  case "$scope" in
    single-session) waive_all=1 ;;
    skip=Discovery|skip=Planning|skip=Test|skip=Implementation|skip=Review) skipped="$skipped ${scope#skip=} " ;;
  esac
done < <(grep -oE '<!--[[:space:]]*pipeline-override:[^>]*-->' <<<"$override_bodies")

missing=""
waived=""
for stage in $all_stages; do
  grep -qE "model-record:[[:space:]]*stage=$stage\b" <<<"$all_text" && continue
  case "$skipped" in
    *" $stage "*) waived="$waived skip=$stage" ;;
    *) missing="$missing${missing:+, }$stage" ;;
  esac
done

if [ "$waive_all" -eq 1 ]; then
  if [ -n "$in_one_text" ] || [ -n "$missing" ]; then
    echo "model-record: a pipeline-override (scope=single-session) is recorded; one session doing several stages is the human's decision here"
  fi
  exit 0
fi
[ -z "$waived" ] || echo "model-record: a pipeline-override is recorded for:$waived"
if [ -n "$in_one_text" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] && echo "role-played: stages in one text: $line"
  done <<<"$in_one_text"
fi
[ -z "$missing" ] || echo "role-played: stages missing: $missing"
exit 0
