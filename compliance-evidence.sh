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
#   3 — gh not found on PATH
#   4 — the PR itself could not be read (gh pr view failed); no honest
#       table is possible without it
# Call B (gh pr checks) and call C (gh issue view) failures never change
# the exit code — they degrade their own gate to `indeterminate` and the
# run still exits 0. All diagnostics go to stderr, never interleaved into
# the table (the output's destination is a GitHub comment; a stray
# warning inside the table would break the Markdown).
#
# Not invoked by `./check` — only its tests are (test/cases/
# s150_compliance_evidence.sh). This script needs `gh`/network, and no
# gh-dependent script in this repo runs inside `./check` (issue #296 AC7):
# `./check` must stay usable with no GitHub credentials at all.

set -uo pipefail

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

# normalize_model() — copied verbatim from
# skills/pre-merge-review/model-record-gate.sh (#268), not sourced/
# imported: a shared lib would cross the dogfood-only boundary (skills/
# ships to adopted projects via adopt.sh; this collector doesn't).
# Accepted debt, recorded in PRD.md's Technical debt register — unify if/
# when this collector is ever propagated.
normalize_model() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/^[[:space:]]*claude[- ]*//' \
    | sed -E 's/-[0-9]{8}$//' \
    | sed -E 's/[^a-z0-9]+/ /g' \
    | sed -E 's/^[[:space:]]+|[[:space:]]+$//g'
}

# --- collect(): the three gh calls; interpretation-free, fills a fixed
# set of globals. Returns 1 only when call A (gh pr view) failed — the
# one failure that makes an honest table impossible.

CALL_A_JQ='"HEAD\t"+(.headRefOid//""),"STATE\t"+(.state//""),"MERGEDAT\t"+(.mergedAt//""),"MERGEDBY\t"+((.mergedBy.login)//""),(.closingIssuesReferences[]? | "ISSUE\t"+(.number|tostring)),("TEXT\t"+((.body//"")|gsub("\n";" "))),(.comments[]? | "TEXT\t"+((.body//"")|gsub("\n";" ")))'
CALL_B_JQ='.[] | .name+"\t"+.state+"\t"+.bucket'
CALL_C_JQ='.comments[]? | "TEXT\t"+((.body//"")|gsub("\n";" "))'

collect() {
  local pr_out pr_status

  pr_out="$(gh pr view "$pr_number" \
    --json body,comments,closingIssuesReferences,headRefOid,mergedAt,mergedBy,state \
    --jq "$CALL_A_JQ" 2>/dev/null)"
  pr_status=$?
  if [ "$pr_status" -ne 0 ]; then
    return 1
  fi

  # Known limitation / technical debt (F34, issue #296; PRD.md's Technical
  # debt table has the full writeup). BUNDLE_TEXT below is a flat
  # concatenation of the PR body, every PR/issue comment, and closing-issue
  # text, with no distinction between a marker that *is* live evidence and
  # the identical marker shape merely quoted in running prose, a fenced
  # code block, or a Markdown blockquote. Every gate_* predicate greps this
  # blob directly, so a quoted marker reads exactly like a real one. This
  # is not theoretical: PR #298's own description quotes a prior run's
  # output verbatim, including a real sha, and the collector prints a false
  # statement about it as a result. The dangerous direction: gate 3 (and
  # gates 1/2 the same way) can render "evidenced" purely because this
  # collector's own prior output was pasted into the very PR being
  # evaluated — an echo evidencing a review that never happened. This is
  # exactly the shape W4 (epic #295) is being built to produce routinely,
  # so the risk is real and growing, not a limited-damage edge case.
  # NOT fixed here — deliberately out of scope for issue #296.
  BUNDLE_TEXT=""
  BUNDLE_HEAD_SHA=""
  BUNDLE_STATE=""
  BUNDLE_MERGED_AT=""
  BUNDLE_MERGED_BY=""
  BUNDLE_ISSUES=""
  # Soundness rule for every gate that reads BUNDLE_TEXT: when this flag
  # is 1 the corpus is provably incomplete, so no gate may return
  # `not-evidenced` on the strength of having found nothing — that
  # verdict must degrade to `indeterminate` (issue #299). It does not
  # apply to a `not-evidenced` reached from data actually in hand: gate
  # 2's same-model verdict (both markers were read) and gate 4's
  # CI verdicts (a separate call with its own degradation) stay as they
  # are. Consulted by: gate_stage_models, gate_review_model,
  # gate_review_marker.
  BUNDLE_ISSUE_LOOKUP_FAILED=0

  local tag rest
  while IFS=$'\t' read -r tag rest; do
    case "$tag" in
      HEAD) BUNDLE_HEAD_SHA="$rest" ;;
      STATE) BUNDLE_STATE="$rest" ;;
      MERGEDAT) BUNDLE_MERGED_AT="$rest" ;;
      MERGEDBY) BUNDLE_MERGED_BY="$rest" ;;
      ISSUE)
        if [ -z "$BUNDLE_ISSUES" ]; then
          BUNDLE_ISSUES="$rest"
        else
          BUNDLE_ISSUES="$BUNDLE_ISSUES
$rest"
        fi
        ;;
      TEXT)
        BUNDLE_TEXT="$BUNDLE_TEXT
$rest"
        ;;
    esac
  done <<<"$pr_out"

  # Closing-issue comments, gathered ahead of the PR's own text (order:
  # issue, then PR body/comments — model-record-gate.sh's PR #253 round 2
  # fix, inherited rather than re-earned: issue text ordered last let a
  # stray older marker outrank a genuinely newer one under `tail -1`).
  local issue_text="" issue_num issue_out issue_status
  if [ -n "$BUNDLE_ISSUES" ]; then
    while IFS= read -r issue_num; do
      [ -n "$issue_num" ] || continue
      issue_out="$(gh issue view "$issue_num" --json comments \
        --jq "$CALL_C_JQ" 2>/dev/null)"
      issue_status=$?
      if [ "$issue_status" -ne 0 ]; then
        echo "warning: compliance-evidence couldn't consult issue #$issue_num (no network or no access) — gates that search its comments render as indeterminate rather than not-evidenced." >&2
        BUNDLE_ISSUE_LOOKUP_FAILED=1
        continue
      fi
      while IFS=$'\t' read -r tag rest; do
        [ "$tag" = "TEXT" ] || continue
        issue_text="$issue_text
$rest"
      done <<<"$issue_out"
    done <<<"$BUNDLE_ISSUES"
  fi
  BUNDLE_TEXT="$issue_text
$BUNDLE_TEXT"

  # Call B — CI checks. `gh pr checks`'s own exit code reports check
  # outcome, not call success: exit 8 means "pending", a failing check
  # exits 1, and a PR with zero checks also exits non-zero with its own
  # "no checks reported" message. So: zero or more parsed name/state/
  # bucket lines on stdout means the call succeeded, regardless of exit
  # status. Only empty stdout with a stderr message that ISN'T the
  # zero-checks one counts as a genuine failure.
  local checks_out checks_status checks_err_file checks_err
  checks_err_file="$(mktemp)" || checks_err_file=""
  if [ -n "$checks_err_file" ]; then
    checks_out="$(gh pr checks "$pr_number" --json name,state,bucket \
      --jq "$CALL_B_JQ" 2>"$checks_err_file")"
    checks_status=$?
    checks_err="$(cat "$checks_err_file" 2>/dev/null)"
    rm -f "$checks_err_file"
  else
    checks_out="$(gh pr checks "$pr_number" --json name,state,bucket \
      --jq "$CALL_B_JQ" 2>/dev/null)"
    checks_status=$?
    checks_err=""
  fi

  if [ -n "$checks_out" ]; then
    BUNDLE_CHECKS="$checks_out"
    BUNDLE_CHECKS_OK=1
  elif grep -qi 'no checks reported' <<<"$checks_err"; then
    BUNDLE_CHECKS=""
    BUNDLE_CHECKS_OK=1
  elif [ "$checks_status" -eq 0 ]; then
    BUNDLE_CHECKS=""
    BUNDLE_CHECKS_OK=1
  else
    BUNDLE_CHECKS=""
    BUNDLE_CHECKS_OK=0
  fi

  return 0
}

# --- Gate predicates. Each prints exactly two tab-separated fields on
# stdout: status<TAB>evidence. Internal seams only — private to this
# script, not a test API (a test that calls one directly tests past the
# argv->stdout Interface).

gate_stage_models() {
  local stage missing="" malformed="" summary="" first_model="" any_model=0 all_same=1
  for stage in Discovery Planning Test Implementation; do
    if grep -qE "model-record:[[:space:]]*stage=$stage\\b" <<<"$BUNDLE_TEXT"; then
      local line model
      line="$(grep -oE "<!--[[:space:]]*model-record:[[:space:]]*stage=${stage}[^>]*-->" <<<"$BUNDLE_TEXT" | tail -1)"
      model="$(grep -oE 'model="[^"]*"' <<<"$line" | head -1 | sed 's/^model="//; s/"$//')"
      if [ -z "$model" ]; then
        malformed="$malformed $stage"
      else
        if [ "$any_model" -eq 0 ]; then
          first_model="$model"
          any_model=1
        elif [ "$model" != "$first_model" ]; then
          all_same=0
        fi
        summary="$summary $stage=\`$model\`,"
      fi
    else
      missing="$missing $stage"
    fi
  done

  malformed="${malformed# }"
  missing="${missing# }"
  summary="${summary# }"

  if [ -n "$malformed" ]; then
    printf '%s\t%s\n' "indeterminate" "model-record marker(s) for stage(s) $malformed on PR #$pr_number matched but carry no quoted \`model=\"...\"\` (unquoted/malformed form)"
    return
  fi

  if [ -n "$missing" ]; then
    if [ "$BUNDLE_ISSUE_LOOKUP_FAILED" -eq 1 ]; then
      printf '%s\t%s\n' "indeterminate" "stage(s) $missing appear to have no model-record marker on PR #$pr_number, but a closing issue lookup failed, so absence can't be confirmed"
      return
    fi
    printf '%s\t%s\n' "not-evidenced" "no model-record marker found for stage(s) $missing, searched in PR #$pr_number's body/comments and its closing issue(s)"
    return
  fi

  if [ "$all_same" -eq 1 ]; then
    printf '%s\t%s\n' "evidenced" "\`model-record\` markers on PR #$pr_number for Discovery, Planning, Test, Implementation (all \`$first_model\`)"
  else
    printf '%s\t%s\n' "evidenced" "\`model-record\` markers on PR #$pr_number for Discovery, Planning, Test, Implementation (${summary%,})"
  fi
}

gate_review_model() {
  local impl_line review_line impl_model review_model impl_norm review_norm exception_val
  impl_line="$(grep -oE '<!--[[:space:]]*model-record:[[:space:]]*stage=Implementation[^>]*-->' <<<"$BUNDLE_TEXT" | tail -1)"
  review_line="$(grep -oE '<!--[[:space:]]*model-record:[[:space:]]*stage=Review[^>]*-->' <<<"$BUNDLE_TEXT" | tail -1)"

  if [ -z "$impl_line" ] || [ -z "$review_line" ]; then
    if [ "$BUNDLE_ISSUE_LOOKUP_FAILED" -eq 1 ]; then
      printf '%s\t%s\n' "indeterminate" "no \`stage=Review\` and/or \`stage=Implementation\` model-record marker found on PR #$pr_number, but a closing issue lookup failed, so absence can't be confirmed"
      return
    fi
    printf '%s\t%s\n' "not-evidenced" "no \`stage=Review\` and/or \`stage=Implementation\` model-record marker found on PR #$pr_number"
    return
  fi

  impl_model="$(grep -oE 'model="[^"]*"' <<<"$impl_line" | head -1 | sed 's/^model="//; s/"$//')"
  review_model="$(grep -oE 'model="[^"]*"' <<<"$review_line" | head -1 | sed 's/^model="//; s/"$//')"

  if [ -z "$impl_model" ] || [ -z "$review_model" ]; then
    printf '%s\t%s\n' "indeterminate" "the \`stage=Review\` or \`stage=Implementation\` marker on PR #$pr_number has no quoted \`model=\"...\"\` to compare"
    return
  fi

  impl_norm="$(normalize_model "$impl_model")"
  review_norm="$(normalize_model "$review_model")"

  if [ "$impl_norm" != "$review_norm" ]; then
    printf '%s\t%s\n' "evidenced" "\`stage=Review\` marker (\`$review_model\`) on PR #$pr_number differs from \`stage=Implementation\` (\`$impl_model\`)"
    return
  fi

  exception_val="$(grep -oE 'same-model-exception="[^"]*"' <<<"$review_line" | head -1 | sed 's/^same-model-exception="//; s/"$//')"
  if [ -n "$exception_val" ]; then
    printf '%s\t%s\n' "evidenced" "latest \`stage=Review\` marker on PR #$pr_number carries \`same-model-exception=\"$exception_val\"\`"
    return
  fi

  printf '%s\t%s\n' "not-evidenced" "\`stage=Review\` and \`stage=Implementation\` markers on PR #$pr_number both record \`$review_model\` with no \`same-model-exception\`"
}

gate_review_marker() {
  local strict_matches loose_present=0
  strict_matches="$(grep -oE '<!--[[:space:]]*pre-merge-review:done[[:space:]]+sha=[0-9a-fA-F]{40}[[:space:]]*-->' <<<"$BUNDLE_TEXT")"

  if grep -q 'pre-merge-review:done' <<<"$BUNDLE_TEXT"; then
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
      printf '%s\t%s\n' "indeterminate" "only a stale \`pre-merge-review:done sha=$first_sha\` marker on PR #$pr_number, which doesn't match \`headRefOid\` ($BUNDLE_HEAD_SHA), and a closing issue lookup failed, so a matching marker can't be ruled out"
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
    printf '%s\t%s\n' "indeterminate" "no \`pre-merge-review:done\` marker found on PR #$pr_number, but a closing issue lookup failed, so absence can't be confirmed"
    return
  fi

  printf '%s\t%s\n' "not-evidenced" "no \`pre-merge-review:done\` marker found on PR #$pr_number"
}

gate_ci() {
  if [ "$BUNDLE_CHECKS_OK" -eq 0 ]; then
    printf '%s\t%s\n' "indeterminate" "\`gh pr checks\` for PR #$pr_number returned no parseable output (call failed)"
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
  local lines="" sep=""

  while IFS=$'\t' read -r name state bucket; do
    [ -n "$name" ] || continue
    lines="${lines}${sep}\`$name\`: \`bucket=$bucket\`, \`state=$state\`"
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

  printf '%s\t%s\n' "evidenced" "check $lines"
}

gate_traceability() {
  if [ -n "$BUNDLE_ISSUES" ]; then
    local list="" first=1 num
    while IFS= read -r num; do
      [ -n "$num" ] || continue
      if [ "$first" -eq 1 ]; then list="#$num"; first=0; else list="$list, #$num"; fi
    done <<<"$BUNDLE_ISSUES"
    printf '%s\t%s\n' "evidenced" "\`closingIssuesReferences\` on PR #$pr_number = [$list]"
    return
  fi
  printf '%s\t%s\n' "not-evidenced" "\`closingIssuesReferences\` on PR #$pr_number is empty"
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
  row "Per-stage model/effort recorded (Discovery, Planning, Test, Implementation)" "$status" "$evidence"

  IFS=$'\t' read -r status evidence <<<"$(gate_review_model)"
  row "Review used a different or at-least-as-capable model, or carries an explicit exception" "$status" "$evidence"

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
  echo "compliance-evidence: could not read PR #$pr_number via 'gh pr view' (no network, no access, or the PR doesn't exist) — no table can be produced." >&2
  exit 4
fi

render
exit 0
