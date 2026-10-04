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
# plus, when Review and Implementation both have a marker (#392):
#   "model-record: Review recorded lower effort (\"<r>\") than Implementation (\"<i>\") on the same model (\"<m>\") (#392)"
#   "model-record: stage=Review marker has no floor-basis (why Review's model and effort clear Implementation's) (#392)"
# plus, for each malformed marker of any stage (an unbalanced quote, no
# closing -->, a <!-- inside it, a quoted stage; lib/model-record.sh), which
# is ignored, never read (an empty or quoted stage shows as `stage=?`, #402):
#   "model-record: a stage=<Stage> marker is malformed and was ignored (<reason>: <text>) (#392)"
# plus, for the latest marker of each of the five stages whose model or
# effort is unquoted, empty or missing (#402, A26), one line per field:
#   "model-record: the latest stage=<Stage> marker has no quoted <field>=\"...\" ... (#402)"
# and, when live_text() fails on a body (no marker read, the stage and
# floor checks skipped; markers are read from live text only, #392):
#   "model-record: dropping quoted text (live_text) failed, ... (#392)"
# and, when the marker parser itself fails (lib/model-record.sh returns
# non-zero), instead of the floor checks:
#   "model-record: the marker parser (lib/model-record.sh) failed, ... (#392)"
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

# Each comment/review body is framed with U+001E, after that byte is
# removed from the body itself (a body can neither forge nor hide a
# boundary: #392, round 4 of the PR #397 review). The marker parser
# (lib/model-record.sh) keeps a malformed marker inside its own comment by
# it, and the role-play check (#371, opted in only) tells one text from the
# next by it. The grep-based checks below read the same text with the
# separators removed.
body_jq='.[] | (.body // "" | gsub("\u001e"; "")) + "\u001e"'

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
description_part="${description_part//$'\036'/}"

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

# #392, round 5 of the PR #397 review: the stage-presence and Review-floor
# checks read LIVE text only, like compliance-evidence.sh and
# role-label-staleness.sh: every body goes through live_text() on its own
# (fence state never carries from one comment into the next), so a marker
# quoted in a code span, a fence or a blockquote is an example, not a
# record. live_text() runs under LC_ALL=C here (its delimiters are ASCII;
# the same reason as the marker parser), and its failure is visible: the
# checks below are skipped with a `model-record:` finding instead of
# reporting stages missing. marker_text keeps each live body followed by
# U+001E for the marker parser (round 4). all_text (raw) is left for the
# role-play check below, whose behaviour this does not change (#400).
body_sep=$'\036'
live_failed=0
live_frame() { # framed text -> each body through live_text, re-framed
  local body live out=""
  while IFS= read -r -d $'\036' body || [ -n "$body" ]; do
    body="${body#$'\n'}"
    [ -n "$body" ] || continue
    live="$(LC_ALL=C live_text "$body")" || return 1
    out="$out
$live$body_sep"
  done <<<"$1"
  printf '%s' "$out"
}
live_issue="$(live_frame "$framed_issue_text")" || live_failed=1
live_description="$(LC_ALL=C live_text "$description_part")" || live_failed=1
live_comments="$(live_frame "$framed_comments_part")" || live_failed=1
live_reviews="$(live_frame "$framed_reviews_part")" || live_failed=1
marker_text="$live_issue
$live_description$body_sep
$live_comments
$live_reviews"
live_all_text="${marker_text//$body_sep/}"

if [ "$live_failed" -eq 1 ]; then
  echo "model-record: dropping quoted text (live_text) failed, so no marker was read and the stage and Review-floor checks were skipped (#392)"
else
  for stage in Discovery Planning Test Implementation Review; do
    # <<< here-string, not a piped producer | grep -q: SIGPIPE/pipefail
    # race, see issue #218 and check-no-sigpipe-race.sh.
    if ! grep -qE "model-record:[[:space:]]*stage=$stage\\b" <<<"$live_all_text"; then
      echo "model-record: no record found for stage $stage (missing model-choice marker)"
    fi
  done
fi

# #392 (A24/A25), replacing #244's different-model rule: Review's model and
# effort, together, are at least as capable as Implementation's. Two checks
# on the LATEST Review marker (`tail -1`, as before: a later review round's
# marker must win), each only when both markers are present (the loop above
# already reports either one missing):
# - the same model (normalize_model, lib/model-record.sh) at a lower Review
#   effort than Implementation's is a finding. Different models are never
#   ranked here (no model table): that stays the Reviewer's recorded
#   judgment. An effort that is missing, unquoted or not low|medium|high
#   makes no comparison claim, never a false one; an unquoted, empty or
#   missing effort or model gets its own #402 line instead (below).
# - the marker must carry a non-empty quoted floor-basis (one sentence on
#   why the pair clears the floor); its text is never verified. A legacy
#   same-model-exception is ignored completely and does not stand in for it.
# Both are findings with the `model-record:` prefix, never `role-played: `,
# so the merge guard is unaffected. No lib, no comparison: fail open.
impl_line=""
review_line=""
parser_failed=0
if [ "$live_failed" -eq 0 ] && [ -r "$own_dir/../../lib/model-record.sh" ]; then
  # shellcheck source=../../lib/model-record.sh
  . "$own_dir/../../lib/model-record.sh"
  # marker_find: the one marker grammar (a quoted value may hold `>`, `<`,
  # `--`, a newline; only a quote ends a value), shared with the collector.
  # A malformed marker is never read (it would otherwise win or hide a later
  # one); marker_scan names it here instead (round 3 of the PR #397 review).
  # A parser failure is a finding, never a silent "no marker".
  impl_line="$(marker_find Implementation "$marker_text" | tail -1)" || parser_failed=1
  review_line="$(marker_find Review "$marker_text" | tail -1)" || parser_failed=1
  scan_out="$(marker_scan "$marker_text")" || parser_failed=1
  if [ "$parser_failed" -eq 0 ]; then
    # #402 (A26): a malformed marker of ANY stage is named, including an
    # empty or quoted stage (a hand-typed `stage="Planning"` reads as an
    # empty stage, shown as `stage=?`). Split on the tabs by hand: `read`
    # with a tab IFS would collapse an empty stage field.
    tab=$'\t'
    while IFS= read -r scan_line; do
      scan_status="${scan_line%%"$tab"*}"
      [ "$scan_status" = "malformed" ] || continue
      scan_rest="${scan_line#*"$tab"}"
      scan_stage="${scan_rest%%"$tab"*}"
      scan_rest="${scan_rest#*"$tab"}"
      echo "model-record: a stage=${scan_stage:-?} marker is malformed and was ignored ($scan_rest) (#392)"
    done <<<"$scan_out"
    # #402 (A26): the latest marker of each stage must carry a readable
    # (quoted, non-empty) model and effort. An unquoted, empty or missing
    # one is one finding per stage and field; effort="unknown" is quoted
    # and honest (A25), so it is no finding. A missing stage keeps only its
    # "no record found" line above.
    for stage in Discovery Planning Test Implementation Review; do
      stage_line="$(marker_find "$stage" "$marker_text" | tail -1)" || { parser_failed=1; break; }
      [ -n "$stage_line" ] || continue
      for field in model effort; do
        field_value="$(marker_attr "$stage_line" "$field")" || { parser_failed=1; break 2; }
        if [ -z "$field_value" ]; then
          echo "model-record: the latest stage=$stage marker has no quoted $field=\"...\" (unquoted, empty or missing), so it can't be read; produce a corrected marker with skills/pre-merge-review/model-record-emit.sh (#402)"
        fi
      done
    done
  fi
fi
if [ "$parser_failed" -eq 1 ]; then
  echo "model-record: the marker parser (lib/model-record.sh) failed, so the Implementation and Review markers were not read and the Review floor was not checked (#392)"
  impl_line=""
  review_line=""
fi
if [ -n "$impl_line" ] && [ -n "$review_line" ]; then
  impl_model="$(marker_attr "$impl_line" model)" || parser_failed=1
  review_model="$(marker_attr "$review_line" model)" || parser_failed=1
  impl_effort="$(marker_attr "$impl_line" effort)" || parser_failed=1
  review_effort="$(marker_attr "$review_line" effort)" || parser_failed=1
  review_fb="$(marker_attr "$review_line" floor-basis)" || parser_failed=1
  if [ "$parser_failed" -eq 1 ]; then
    echo "model-record: the marker parser (lib/model-record.sh) failed, so the Implementation and Review markers were not read and the Review floor was not checked (#392)"
  else
    impl_model_norm="$(normalize_model "$impl_model")"
    review_model_norm="$(normalize_model "$review_model")"
    if [ -n "$impl_model_norm" ] && [ "$impl_model_norm" = "$review_model_norm" ]; then
      impl_rank="$(effort_rank "$impl_effort")"
      review_rank="$(effort_rank "$review_effort")"
      if [ -n "$impl_rank" ] && [ -n "$review_rank" ] && [ "$review_rank" -lt "$impl_rank" ]; then
        echo "model-record: Review recorded lower effort (\"$review_effort\") than Implementation (\"$impl_effort\") on the same model (\"$review_model\") (#392)"
      fi
    fi
    if [ -z "$review_fb" ]; then
      echo "model-record: stage=Review marker has no floor-basis (why Review's model and effort clear Implementation's) (#392)"
    fi
  fi
fi

# --- #371 A18: role-played runs, opted-in projects only ---------------------
[ "$opted_in" -eq 1 ] || exit 0

if [ "$issue_fetch_failed" -eq 1 ]; then
  echo "warning: model-record-gate couldn't read every closing issue and is skipping the role-play check (a missing Discovery marker could be a lookup failure)." >&2
  exit 0
fi


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
