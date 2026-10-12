#!/usr/bin/env bash
# compliance-evidence.sh — Read-only compliance-evidence collector for one
# work item (issue #296, epic #295 W1).
#
# Usage:
#   ./compliance-evidence.sh <pr-number>
#
# Given a PR number, gathers pre-existing evidence for each of the six
# decided compliance gates (OQ9, `PRD-MULTI-AGENT-WIP.md` §6) and renders
# a Gate/Status/Evidence Markdown table to stdout, in the fixed gate
# order. It reports which artifacts exist; it never judges whether that
# evidence is adequate (that stays Reviewer's and Ties' call).
#
# What it deliberately does not do: no posting, no labelling, no editing,
# no merging — it has no write path at all (AC5). It never calls `gh pr
# merge`, `gh pr comment`, `gh issue comment`, `gh issue edit`, `gh pr
# edit`, any `gh ... label` subcommand, or `gh api -X`/`gh api --method`.
#
# No `eval`: PR/issue comment text is not under this script's control.
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.
#
# Status vocabulary (closed, exactly these four, AC8):
#   evidenced                    — an artifact was found that shows the
#                                   gate actually held
#   not-evidenced                — no such artifact was found (includes a
#                                   red/absent CI check: interpretable,
#                                   but does not evidence "CI green")
#   unverifiable-from-artifacts  — a structural property of the gate
#                                   itself (the merge-confirmation gate);
#                                   never computed from absent data
#   indeterminate                — an artifact was found but cannot be
#                                   interpreted (malformed marker, unknown
#                                   CI bucket, a failed sub-lookup)
#
# Exit codes:
#   0 — a table was produced, including an all-not-evidenced one (AC3)
#   1 — internal error: a gate predicate returned a status outside the
#       closed vocabulary (never expected to trigger; see valid_status())
#   2 — usage error (no PR number given)
#   3 — gh not found on PATH, or lib/model-record.sh (next to this script)
#       is missing
#   4 — the PR itself could not be read (call A failed); no honest table
#       is possible without it
# Every other gh call's failure (PR comments/reviews, the CI check-runs
# call, a closing issue's own comments) never changes the exit code —
# it degrades its own gate to `indeterminate` and the run still exits 0.
# All diagnostics go to stderr, never interleaved into the table (the
# output's destination is a GitHub comment; a stray warning inside the
# table would break the Markdown).
#
# Not invoked by `./check` — only its tests are (test/cases/
# s150_compliance_evidence.sh). This script needs `gh`/network, and no
# gh-dependent script in this repo runs inside `./check` (issue #296 AC7):
# `./check` must stay usable with no GitHub credentials at all.

set -uo pipefail
export LC_ALL=C  # A32c: every command and bash's own matching reads GitHub text as bytes; enforced by S235

if [ $# -lt 1 ] || [ -z "${1:-}" ]; then
  echo "usage: compliance-evidence.sh <pr-number>" >&2
  exit 2
fi
pr_number="$1"

require_gh() {
  if ! command -v gh >/dev/null 2>&1; then
    echo "compliance-evidence: gh not found on PATH — cannot collect evidence." >&2
    exit 3
  fi
}

# The shared reader owns record grammar, quoting and fields.
collector_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if [ ! -r "$collector_dir/lib/model-record.sh" ]; then
  echo "compliance-evidence: lib/model-record.sh not found next to the collector — cannot collect evidence." >&2
  exit 3
fi
. "$collector_dir/lib/model-record.sh"

CLOSING_KEYWORD_ERE='\b(close[sd]?|fix(e[sd])?|resolve[sd]?):?[[:space:]]+#[0-9]+\b'

# TSV transport preserves CommonMark line endings and neutralizes only the two
# framing bytes. Descriptions date at creation; edits are not observable here.
_BODY_JQ='((.body//"")|gsub("\u0001";" ")|gsub("\u001e";"")|gsub("\r\n";"\n")|gsub("\r";"\n")|gsub("\n";"\u0001"))'
CALL_A_JQ='"HEAD\t"+(.head.sha//""),"STATE\t"+(if .merged then "MERGED" elif .state=="open" then "OPEN" else "CLOSED" end),"MERGEDAT\t"+(.merged_at//""),"MERGEDBY\t"+((.merged_by.login)//""),"TITLE\t"+((.title//"")|gsub("\u0001";" ")|gsub("\r";"\n")|gsub("\n";"\u0001")),"TEXT\t"+(.created_at//"1970-01-01T00:00:00Z")+"\t"+'
CALL_A_JQ="$CALL_A_JQ$_BODY_JQ"
CALL_A_COMMENTS_JQ='.[] | "TEXT\t"+(.created_at//"1970-01-01T00:00:00Z")+"\t"+'
CALL_A_COMMENTS_JQ="$CALL_A_COMMENTS_JQ$_BODY_JQ"
CALL_A_REVIEWS_JQ='.[] | "TEXT\t"+(.submitted_at//"1970-01-01T00:00:00Z")+"\t"+'
CALL_A_REVIEWS_JQ="$CALL_A_REVIEWS_JQ$_BODY_JQ"
CALL_C_JQ="$CALL_A_COMMENTS_JQ"
CALL_B_JQ='.check_runs[] | .name+"\t"+(if .status!="completed" then .status else (.conclusion//"unknown") end)+"\t"+(if .status!="completed" then "pending" elif .conclusion=="success" or .conclusion=="neutral" then "pass" elif .conclusion=="failure" or .conclusion=="timed_out" or .conclusion=="action_required" then "fail" elif .conclusion=="cancelled" then "cancel" elif .conclusion=="skipped" then "skipping" else "unknown_bucket_"+(.conclusion//"null") end)'

# Internal collection helpers share collect's dynamically scoped bundle and
# metadata. Raw bodies stay separate; done markers retain live_text semantics.
collect_rows() { # REST TSV, source rank (issue/description/comments/reviews)
  local rows="$1" rank="$2" tag rest stamp raw live
  while IFS=$'\t' read -r tag rest; do
    [ "$tag" = TEXT ] || continue
    stamp="${rest%%$'\t'*}"
    raw="${rest#*$'\t'}"
    raw="${raw//$'\001'/$'\n'}"
    raw="${raw//$MARKER_SEP/}"
    times+=("$stamp"); ranks+=("$rank")
    raw_bundle="$raw_bundle$raw$MARKER_SEP"
    BUNDLE_TEXT_RAW="$BUNDLE_TEXT_RAW
$raw"
    live="$(live_text "$raw")" || {
      BUNDLE_ISSUE_LOOKUP_FAILED=1
      [ "$rank" = 0 ] || BUNDLE_PR_LOOKUP_FAILED=1
      echo 'warning: compliance-evidence: live_text failed; evidence corpus unreadable' >&2
    }
    BUNDLE_TEXT="$BUNDLE_TEXT
$live$MARKER_SEP"
  done <<<"$rows"
}

collect_scan() {
  local scan idx cls stage text
  cached=""
  if ! scan="$(rec_scan_bundle model-record "$raw_bundle")"; then
    BUNDLE_SCAN_FAILED=1
    BUNDLE_ISSUE_LOOKUP_FAILED=1
    echo 'warning: compliance-evidence: record scan failed; evidence corpus unreadable' >&2
    return
  fi
  while IFS=$'\t' read -r idx cls stage text; do
    [ -n "$idx" ] || continue
    cached="$cached${times[$((idx-1))]}"$'\t'"${ranks[$((idx-1))]}"$'\t'"$cls"$'\t'"$stage"$'\t'"$text"$'\n'
  done <<<"$scan"
  BUNDLE_CACHE="$BUNDLE_CACHE$cached"
}

collect() {
  local pr_out tag rest pr_title_raw="" pr_body_raw="" comments reviews issue_out issue_num
  pr_out="$(gh api "repos/{owner}/{repo}/pulls/$pr_number" --jq "$CALL_A_JQ" 2>/dev/null)" || return 1
  BUNDLE_TEXT="" BUNDLE_TEXT_RAW="" BUNDLE_CACHE="" PR_CACHE=""
  BUNDLE_HEAD_SHA="" BUNDLE_STATE="" BUNDLE_MERGED_AT="" BUNDLE_MERGED_BY="" BUNDLE_ISSUES=""
  BUNDLE_ISSUE_LOOKUP_FAILED=0 BUNDLE_PR_LOOKUP_FAILED=0 BUNDLE_SCAN_FAILED=0
  ISSUE_CACHES=() ISSUE_NUMS=()
  local raw_bundle="" cached=""
  local -a times=() ranks=()
  while IFS=$'\t' read -r tag rest; do
    case "$tag" in
      HEAD) BUNDLE_HEAD_SHA="$rest";; STATE) BUNDLE_STATE="$rest";;
      MERGEDAT) BUNDLE_MERGED_AT="$rest";; MERGEDBY) BUNDLE_MERGED_BY="$rest";;
      TITLE) pr_title_raw="${rest//$'\001'/$'\n'}";;
      TEXT) pr_body_raw="${rest#*$'\t'}"; pr_body_raw="${pr_body_raw//$'\001'/$'\n'}";;
    esac
  done <<<"$pr_out"
  collect_rows "$pr_out" 1
  if ! comments="$(gh api "repos/{owner}/{repo}/issues/$pr_number/comments" --paginate --jq "$CALL_A_COMMENTS_JQ" 2>/dev/null)"; then
    BUNDLE_ISSUE_LOOKUP_FAILED=1 BUNDLE_PR_LOOKUP_FAILED=1
    echo "warning: compliance-evidence couldn't consult PR #$pr_number's comments" >&2
    comments=""
  fi
  if ! reviews="$(gh api "repos/{owner}/{repo}/pulls/$pr_number/reviews" --paginate --jq "$CALL_A_REVIEWS_JQ" 2>/dev/null)"; then
    BUNDLE_ISSUE_LOOKUP_FAILED=1 BUNDLE_PR_LOOKUP_FAILED=1
    echo "warning: compliance-evidence couldn't consult PR #$pr_number's reviews" >&2
    reviews=""
  fi
  collect_rows "$comments" 2; collect_rows "$reviews" 3
  collect_scan; PR_CACHE="$cached"
  BUNDLE_ISSUES="$(printf '%s\n%s\n' "$pr_title_raw" "$pr_body_raw" | LC_ALL=C grep -oiE "$CLOSING_KEYWORD_ERE" | LC_ALL=C grep -oE '[0-9]+' | LC_ALL=C sort -un)"
  if [ -n "$BUNDLE_ISSUES" ]; then
    while IFS= read -r issue_num; do
      if ! issue_out="$(gh api "repos/{owner}/{repo}/issues/$issue_num/comments" --paginate --jq "$CALL_C_JQ" 2>/dev/null)"; then
        BUNDLE_ISSUE_LOOKUP_FAILED=1
        echo "warning: compliance-evidence couldn't consult issue #$issue_num — gates that search its comments may render as indeterminate rather than not-evidenced." >&2
        continue
      fi
      raw_bundle=""; times=(); ranks=()
      collect_rows "$issue_out" 0; collect_scan
      ISSUE_CACHES+=("$cached"); ISSUE_NUMS+=("$issue_num")
    done <<<"$BUNDLE_ISSUES"
  fi
  if BUNDLE_CHECKS="$(gh api "repos/{owner}/{repo}/commits/$BUNDLE_HEAD_SHA/check-runs" --paginate --jq "$CALL_B_JQ" 2>/dev/null)"; then
    BUNDLE_CHECKS_OK=1
  else BUNDLE_CHECKS="" BUNDLE_CHECKS_OK=0; fi
  return 0
}

# A37: timestamps, then issue/description/comments/reviews, then later line.
# A quoted candidate never supersedes live evidence. Questions only read cache.
collector_latest() {
  local want="$1" rows="$2" time rank cls stage text best="" best_rank=-1 result=""
  while IFS=$'\t' read -r time rank cls stage text; do
    [ "$stage" = "$want" ] && [ "$cls" != quoted ] || continue
    if [ -z "$best" ] || [[ $time > $best ]] || { [ "$time" = "$best" ] && [ "$rank" -ge "$best_rank" ]; }; then
      best="$time" best_rank="$rank"
      result="$cls"$'\t'"$text"
    fi
  done <<<"$rows"
  printf '%s\n' "$result"
}

quoted_suffix() {
  local want="$1" time rank cls stage text
  while IFS=$'\t' read -r time rank cls stage text; do
    if [ "$cls" = quoted ] && [ "$stage" = "$want" ]; then
      printf '%s' " — marker-shaped text matching this gate does appear on PR #$pr_number, but only inside a code span, fenced block or blockquote, so it was read as quoted illustration and not counted as live evidence"
      return
    fi
  done <<<"$BUNDLE_CACHE"
}
# Done/finding markers remain outside record v2 (A34a).
done_quoted_suffix() {
  LC_ALL=C grep -qE "$1" <<<"$BUNDLE_TEXT_RAW" && printf '%s' " — marker-shaped text matching this gate does appear on PR #$pr_number, but only inside a code span, fenced block or blockquote, so it was read as quoted illustration and not counted as live evidence"
}

gate_stage_models() {
  local stage cls text model first="" missing="" suffix="" summary="" same=1
  if [ "$BUNDLE_SCAN_FAILED" = 1 ]; then printf 'indeterminate\trecord reader failed; stage evidence could not be read\n'; return; fi
  if [ "$BUNDLE_ISSUE_LOOKUP_FAILED" = 1 ]; then
    printf 'indeterminate\tevidence-corpus lookup failed; latest stage candidates cannot be confirmed\n'
    return
  fi
  for stage in Discovery Planning Test Implementation; do
    IFS=$'\t' read -r cls text <<<"$(collector_latest "$stage" "$BUNDLE_CACHE")"
    if [ "$cls" = near-miss ]; then
      printf 'indeterminate\tlatest stage=%s near-miss: %s; no earlier record used\n' "$stage" "$text"; return
    elif [ "$cls" = ok ]; then
      model="$(rec_field "$text" model)" || { printf 'indeterminate\trecord field reader failed\n'; return; }
      if [ -z "$first" ]; then first="$model"; elif [ "$model" != "$first" ]; then same=0; fi
      summary="$summary $stage=\`$model\`,"
    else
      missing="$missing $stage"
      [ -n "$suffix" ] || suffix="$(quoted_suffix "$stage")"
    fi
  done
  if [ -n "$missing" ]; then
    if [ "$BUNDLE_ISSUE_LOOKUP_FAILED" = 1 ]; then printf 'indeterminate\tstage(s)%s absent, but an evidence-corpus lookup failed\n' "$missing"; else printf 'not-evidenced\tno model-record for stage(s)%s%s\n' "$missing" "$suffix"; fi
  elif [ "$same" = 1 ]; then
    printf 'evidenced\t`model-record` markers on PR #%s for Discovery, Planning, Test, Implementation (all `%s`)\n' "$pr_number" "$first"
  else printf 'evidenced\t`model-record` markers on PR #%s for Discovery, Planning, Test, Implementation (%s)\n' "$pr_number" "$(printf '%s' "${summary# }" | sed 's/,$//')"; fi
}

# Two closing issues still conflict on normalized model, even with a PR record.
resolve_stage_marker() {
  local stage="$1" cls line model norm first="" count=0 conflict=0 detail="" i
  if [ "$BUNDLE_SCAN_FAILED" = 1 ]; then printf 'parsefail\t\n'; return; fi
  for i in "${!ISSUE_CACHES[@]}"; do
    IFS=$'\t' read -r cls line <<<"$(collector_latest "$stage" "${ISSUE_CACHES[$i]}")"
    [ -n "$cls" ] || continue
    model=""
    if [ "$cls" = ok ]; then model="$(rec_field "$line" model)" || { printf 'parsefail\t\n'; return; }; fi
    norm="$(normalize_model "$model")"
    if [ "$count" = 0 ]; then first="$norm"; elif [ "$norm" != "$first" ]; then conflict=1; fi
    count=$((count+1))
    detail="${detail}${detail:+; }issue #${ISSUE_NUMS[$i]}: \`${model:-<malformed>}\`"
  done
  if [ "$conflict" = 1 ]; then printf 'conflict\t%s\n' "$detail"; return; fi
  IFS=$'\t' read -r cls line <<<"$(collector_latest "$stage" "$BUNDLE_CACHE")"
  case "$cls" in ok) printf 'single\t%s\n' "$line";; near-miss) printf 'malformed\tlatest stage=%s near-miss: %s; no earlier record used\n' "$stage" "$line";; *) printf 'none\t\n';; esac
}

gate_review_model() {
  local impl_status impl_line review_status review_line
  local impl_model review_model impl_norm review_norm
  # A37: an unread source can supersede either candidate, including a
  # readable different-model pair. Done markers keep their own gate semantics.
  if [ "$BUNDLE_ISSUE_LOOKUP_FAILED" = 1 ]; then
    printf 'indeterminate\tevidence-corpus lookup failed; latest Implementation and Review candidates cannot be confirmed\n'
    return
  fi

  IFS=$'\t' read -r impl_status impl_line <<<"$(resolve_stage_marker Implementation)"
  IFS=$'\t' read -r review_status review_line <<<"$(resolve_stage_marker Review)"

  # #392 (round 3 of the PR #397 review): a parser failure or a stage whose
  # only markers are malformed is indeterminate, never "none"/a verdict.
  if [ "$impl_status" = "parsefail" ] || [ "$review_status" = "parsefail" ]; then
    printf '%s\t%s\n' "indeterminate" "the model-record marker parser (lib/model-record.sh) failed on PR #$pr_number's evidence corpus, so the Implementation and Review markers could not be read"
    return
  fi
  if [ "$impl_status" = "malformed" ] || [ "$review_status" = "malformed" ]; then
    local bad_detail=""
    [ "$impl_status" = "malformed" ] && bad_detail="Implementation — $impl_line"
    if [ "$review_status" = "malformed" ]; then
      [ -n "$bad_detail" ] && bad_detail="$bad_detail; "
      bad_detail="${bad_detail}Review — $review_line"
    fi
    printf '%s\t%s\n' "indeterminate" "the only \`stage=Implementation\`/\`stage=Review\` model-record marker found on PR #$pr_number for a stage is malformed and was not read ($bad_detail)"
    return
  fi

  if [ "$impl_status" = "conflict" ] || [ "$review_status" = "conflict" ]; then
    local which detail
    if [ "$impl_status" = "conflict" ] && [ "$review_status" = "conflict" ]; then
      which="stage=Implementation and stage=Review"
      detail="Implementation — $impl_line; Review — $review_line"
    elif [ "$impl_status" = "conflict" ]; then
      which="stage=Implementation"
      detail="$impl_line"
    else
      which="stage=Review"
      detail="$review_line"
    fi
    printf '%s\t%s\n' "indeterminate" "conflicting \`$which\` model-record markers found on PR #$pr_number across sources ($detail) — read in full, but with no ordering signal between sources, which one is authoritative can't be told"
    return
  fi


  if [ "$impl_status" = "none" ] || [ "$review_status" = "none" ]; then
    if [ "$BUNDLE_ISSUE_LOOKUP_FAILED" -eq 1 ]; then
      printf '%s\t%s\n' "indeterminate" "no \`stage=Review\` and/or \`stage=Implementation\` model-record marker found on PR #$pr_number, but an evidence-corpus lookup failed, so absence can't be confirmed"
      return
    fi
    local suffix=""
    [ "$impl_status" != none ] || suffix="$(quoted_suffix Implementation)"
    [ -n "$suffix" ] || { [ "$review_status" != none ] || suffix="$(quoted_suffix Review)"; }
    printf '%s\t%s\n' "not-evidenced" "no stage=Review and/or stage=Implementation model-record marker on PR #$pr_number$suffix"
    return
  fi

  local attrs_ok=1 fb=""
  impl_model="$(rec_field "$impl_line" model)" || attrs_ok=0
  review_model="$(rec_field "$review_line" model)" || attrs_ok=0
  fb="$(rec_field "$review_line" floor-basis)" || attrs_ok=0
  if [ "$attrs_ok" -eq 0 ]; then
    printf '%s\t%s\n' "indeterminate" "the model-record marker parser (lib/model-record.sh) failed on PR #$pr_number's evidence corpus, so the Implementation and Review markers could not be read"
    return
  fi

  if [ -z "$impl_model" ] || [ -z "$review_model" ]; then
    printf '%s\t%s\n' "indeterminate" "the \`stage=Review\` or \`stage=Implementation\` marker on PR #$pr_number has no quoted \`model=\"...\"\` to compare"
    return
  fi

  impl_norm="$(normalize_model "$impl_model")"
  review_norm="$(normalize_model "$review_model")"

  # #392 (A24/A25): different models are never ranked here (no model table),
  # so the verdict is structural, not a lookup question: nothing an unread
  # marker could say would change what this collector can claim.
  if [ "$impl_norm" != "$review_norm" ]; then
    local fb_text
    if [ -n "$fb" ]; then
      fb_text="floor-basis: \"$fb\""
    else
      fb_text="no floor-basis recorded"
    fi
    printf '%s\t%s\n' "unverifiable-from-artifacts" "Review (\`$review_model\`) and Implementation (\`$impl_model\`) on PR #$pr_number record different models; their capability ordering isn't machine-checked. $fb_text"
    return
  fi

  printf '%s\t%s\n' "evidenced" "same model \`$review_model\`; the floor is judged on the model alone, on self-reported model strings (effort is not compared)"
}

gate_review_marker() {
  local strict_matches loose_present=0
  # AC7 (issue #308, D4): anchored to a real HTML-comment opener — same
  # reasoning as gate_stage_models above. loose_ere is reused below by
  # quoted_suffix() (D8: must be the identical ERE the live grep used).
  local loose_ere='<!--[[:space:]]*pre-merge-review:done'
  strict_matches="$(LC_ALL=C grep -oE '<!--[[:space:]]*pre-merge-review:done[[:space:]]+sha=[0-9a-fA-F]{40}[[:space:]]*-->' <<<"$BUNDLE_TEXT")"

  if LC_ALL=C grep -qE "$loose_ere" <<<"$BUNDLE_TEXT"; then
    loose_present=1
  fi

  if [ -n "$strict_matches" ]; then
    local line sha match_sha="" other_shas
    while IFS= read -r line; do
      sha="$(grep -oE 'sha=[0-9a-fA-F]{40}' <<<"$line" | sed 's/^sha=//')"
      if [ "$sha" = "$BUNDLE_HEAD_SHA" ]; then
        match_sha="$sha"
      fi
    done <<<"$strict_matches"

    if [ -n "$match_sha" ]; then
      local stale_note=""
      other_shas="$(grep -oE 'sha=[0-9a-fA-F]{40}' <<<"$strict_matches" | sed 's/^sha=//' | sort -u | grep -v "^$BUNDLE_HEAD_SHA\$")"
      if [ -n "$other_shas" ]; then
        stale_note=" (an earlier marker for \`$(head -1 <<<"$other_shas")\` is stale)"
      fi
      printf '%s\t%s\n' "evidenced" "\`<!-- pre-merge-review:done sha=$match_sha -->\` on PR #$pr_number, sha equals \`headRefOid\`$stale_note"
      return
    fi

    local first_sha
    first_sha="$(grep -oE 'sha=[0-9a-fA-F]{40}' <<<"$strict_matches" | sed 's/^sha=//' | head -1)"
    if [ "$BUNDLE_ISSUE_LOOKUP_FAILED" -eq 1 ]; then
      printf '%s\t%s\n' "indeterminate" "only a stale \`pre-merge-review:done sha=$first_sha\` marker on PR #$pr_number, which doesn't match \`headRefOid\` ($BUNDLE_HEAD_SHA), and an evidence-corpus lookup failed, so a matching marker can't be ruled out"
      return
    fi
    printf '%s\t%s\n' "not-evidenced" "only a stale \`pre-merge-review:done sha=$first_sha\` marker on PR #$pr_number; it doesn't match \`headRefOid\` ($BUNDLE_HEAD_SHA)"
    return
  fi

  if [ "$loose_present" -eq 1 ]; then
    printf '%s\t%s\n' "indeterminate" "a \`pre-merge-review:done\` marker exists on PR #$pr_number but not in the recognized \`sha=<40-hex>\` shape"
    return
  fi

  if [ "$BUNDLE_ISSUE_LOOKUP_FAILED" -eq 1 ]; then
    printf '%s\t%s\n' "indeterminate" "no \`pre-merge-review:done\` marker found on PR #$pr_number, but an evidence-corpus lookup failed, so absence can't be confirmed"
    return
  fi

  printf '%s\t%s\n' "not-evidenced" "no \`pre-merge-review:done\` marker found on PR #$pr_number$(done_quoted_suffix "$loose_ere")"
}

gate_ci() {
  if [ "$BUNDLE_CHECKS_OK" -eq 0 ]; then
    printf '%s\t%s\n' "indeterminate" "check-runs lookup for PR #$pr_number returned no parseable output (call failed)"
    return
  fi

  if [ -z "$BUNDLE_CHECKS" ]; then
    printf '%s\t%s\n' "not-evidenced" "no CI checks reported on PR #$pr_number"
    return
  fi

  local name state bucket
  local fail_name="" fail_state="" fail_bucket=""
  local pending_name="" pending_state=""
  local unknown_name="" unknown_bucket=""
  local check_lines="" sep=""

  while IFS=$'\t' read -r name state bucket; do
    [ -n "$name" ] || continue
    check_lines="${check_lines}${sep}\`$name\`: \`bucket=$bucket\`, \`state=$state\`"
    sep="; "
    case "$bucket" in
      fail|cancel)
        if [ -z "$fail_name" ]; then fail_name="$name"; fail_state="$state"; fail_bucket="$bucket"; fi
        ;;
      pending)
        if [ -z "$pending_name" ]; then pending_name="$name"; pending_state="$state"; fi
        ;;
      pass|skipping) : ;;
      *)
        if [ -z "$unknown_name" ]; then unknown_name="$name"; unknown_bucket="$bucket"; fi
        ;;
    esac
  done <<<"$BUNDLE_CHECKS"

  if [ -n "$fail_name" ]; then
    printf '%s\t%s\n' "not-evidenced" "check \`$fail_name\`: \`bucket=$fail_bucket\`, \`state=$fail_state\` on PR #$pr_number"
    return
  fi
  if [ -n "$unknown_name" ]; then
    printf '%s\t%s\n' "indeterminate" "check \`$unknown_name\` on PR #$pr_number has an unrecognized \`bucket=$unknown_bucket\`"
    return
  fi
  if [ -n "$pending_name" ]; then
    printf '%s\t%s\n' "indeterminate" "check \`$pending_name\`: \`bucket=pending\`, \`state=$pending_state\` on PR #$pr_number, outcome not yet known"
    return
  fi

  printf '%s\t%s\n' "evidenced" "check $check_lines"
}

gate_traceability() {
  if [ -n "$BUNDLE_ISSUES" ]; then
    local list="" first=1 num
    while IFS= read -r num; do
      [ -n "$num" ] || continue
      if [ "$first" -eq 1 ]; then list="#$num"; first=0; else list="$list, #$num"; fi
    done <<<"$BUNDLE_ISSUES"
    printf '%s\t%s\n' "evidenced" "closing-keyword reference(s) on PR #$pr_number = [$list]"
    return
  fi
  printf '%s\t%s\n' "not-evidenced" "no closing-keyword reference found on PR #$pr_number's title or body"
}

# Constant, structural (AC4): reads no bundle field. render() may append
# mergedBy/mergedAt as context after calling this, but never lets it flip
# the status — A2's confirmation happens in conversation and leaves no
# artifact, merged or not.
gate_merge_confirmation() {
  printf '%s\t%s\n' "unverifiable-from-artifacts" "not derivable from artifacts; A2 confirmation is conversational"
}

# --- Rendering ---------------------------------------------------------

# Every cell goes through this before printing (earlier report's §4 risk
# 5): escape backslashes first, then pipes (order matters — reversed, the
# second substitution would double-escape what the first just added),
# then flatten whitespace, then truncate. This is copied verbatim from
# Architect's interface contract, with one correction (PR #298 review F2):
# the contract's own §3.6 prose says truncation appends an ellipsis; the
# literal code block it also gave omitted it. The prose governs (a
# truncated cell with no marker silently misleads a reader of a
# compliance table) — an ellipsis is appended whenever `cut` actually
# shortened the string, never when the string already fit.
cell() {
  local escaped truncated
  escaped="$(printf '%s' "$1" \
    | sed 's/\\/\\\\/g; s/|/\\|/g' \
    | tr '\n\r\t' '   ' \
    | sed -E 's/  +/ /g; s/^ +| +$//g')"
  truncated="$(printf '%s' "$escaped" | cut -c1-300)"
  if [ "${#truncated}" -lt "${#escaped}" ]; then
    printf '%s…' "$truncated"
  else
    printf '%s' "$truncated"
  fi
}

valid_status() {
  case "$1" in
    evidenced|not-evidenced|unverifiable-from-artifacts|indeterminate) return 0 ;;
    *) return 1 ;;
  esac
}

row() {
  local gate="$1" status="$2" evidence="$3"
  if ! valid_status "$status"; then
    echo "compliance-evidence: internal error — a gate returned an invalid status '$status' for gate '$gate'" >&2
    exit 1
  fi
  printf '| %s | %s | %s |\n' "$(cell "$gate")" "$status" "$(cell "$evidence")"
}

render() {
  echo "| Gate | Status | Evidence |"
  echo "| --- | --- | --- |"

  local status evidence

  IFS=$'\t' read -r status evidence <<<"$(gate_stage_models)"
  row "Per-stage model recorded (Discovery, Planning, Test, Implementation)" "$status" "$evidence"

  IFS=$'\t' read -r status evidence <<<"$(gate_review_model)"
  row "Review at least as capable as Implementation (same model: the floor is met on the model alone; different models: recorded judgment, not machine-checked)" "$status" "$evidence"

  IFS=$'\t' read -r status evidence <<<"$(gate_review_marker)"
  row "Quality review before merge, with findings in the PR" "$status" "$evidence"

  IFS=$'\t' read -r status evidence <<<"$(gate_ci)"
  row "CI green" "$status" "$evidence"

  IFS=$'\t' read -r status evidence <<<"$(gate_traceability)"
  row "Traceability link 3 (PR ↔ issue)" "$status" "$evidence"

  IFS=$'\t' read -r status evidence <<<"$(gate_merge_confirmation)"
  if [ "$BUNDLE_STATE" = "MERGED" ] && [ -n "$BUNDLE_MERGED_BY" ]; then
    evidence="$evidence (PR merged by @$BUNDLE_MERGED_BY at $BUNDLE_MERGED_AT, which is not the confirmation)"
  elif [ -n "$BUNDLE_STATE" ]; then
    evidence="$evidence (PR state: $BUNDLE_STATE)"
  fi
  row "Ties' explicit merge confirmation" "$status" "$evidence"
}

# --- Main ---------------------------------------------------------------

require_gh

if ! collect; then
  echo "compliance-evidence: could not read PR #$pr_number via the GitHub API (no network, no access, or the PR doesn't exist) — no table can be produced." >&2
  exit 4
fi

render
exit 0
