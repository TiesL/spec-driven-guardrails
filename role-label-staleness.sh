#!/usr/bin/env bash
# role-label-staleness.sh — Read-only role:<name> label staleness detector
# for one issue (issue #315, epic #295 W3).
#
# Usage:
#   ./role-label-staleness.sh <issue-number>
#
# A5 (ARCHITECTURE-MULTI-AGENT-WIP.md) decided that a role:<name> label on
# a work item's issue is the traceability record of "who acted", updated
# by hand by the orchestrator as work moves between phases — never state
# an execution mechanism reads back. This script only tells a reader when
# that record has fallen behind the evidence; it never blocks, gates, or
# edits anything (AC7).
#
# A label is stale when the issue carries a role:<name> label naming an
# earlier stage than the latest stage a `model-record` marker (skills/
# model-choice/SKILL.md) actually evidences, searched on the issue itself
# and every PR that closes it (Discovery is typically issue-side; the
# other four are typically PR-side, though the real worked example on
# file — #296 — had all five on the PR, so both are searched regardless).
# A label at or ahead of the latest evidenced stage is NOT stale (A5: the
# label tracks the active phase, not the last completed one — the
# orchestrator moving the label ahead of its own marker is the normal
# case).
#
# Stage <-> role <-> label, fixed order (skills/model-choice/SKILL.md's
# own "Per-stage floors" table — reused literally, not re-derived):
#   Discovery < Planning < Test < Implementation < Review
#   role:product < role:architect < role:qa < role:dev < role:reviewer
#
# Status vocabulary (closed, exactly these four, mirroring compliance-
# evidence.sh's own AC8 discipline):
#   not-started    — no role:<name> label AND no live marker anywhere
#   in-sync        — exactly one role:<name> label, at or after the
#                     latest live-evidenced stage (including zero markers
#                     evidenced at all — a fresh label with nothing yet
#                     recorded is the normal starting state, not
#                     not-started, and not stale)
#   stale          — either (a) one role:<name> label naming a stage
#                     strictly earlier than the latest evidenced stage, or
#                     (b) no role:<name> label at all while at least one
#                     live marker exists (the label was removed, or never
#                     applied, after evidence already showed up)
#   indeterminate  — two-or-more role:<name> labels at once; a
#                     model-record marker matched the anchor but has no
#                     recognized stage= value (malformed/unrecognized,
#                     anywhere in scope — one sighting forces this for the
#                     whole run, the same blunt/conservative reading
#                     compliance-evidence.sh already prefers over a
#                     narrower "only if it could flip the verdict" rule);
#                     or a PR lookup failed while the verdict computed
#                     from what WAS read still rests on an absence claim
#                     that missing PR could have contradicted (see
#                     "PR-lookup failure" below)
#
# PR-lookup failure (the one structurally new failure surface here vs.
# compliance-evidence.sh, which runs PR-then-issues; this runs
# issue-then-PRs):
#   - The issue lookup itself failing is fatal (exit 4) — no honest
#     verdict is possible without the issue.
#   - The issue lookup succeeding with zero linked PRs is NOT a failure —
#     an issue in Discovery with no PR yet is a normal, common state; the
#     verdict is computed from issue-only evidence.
#   - A `gh pr view` failing for one of the linked PRs sets
#     PR_LOOKUP_FAILED and keeps going. That flag degrades the verdict to
#     `indeterminate` ONLY when the verdict computed from the sources
#     that WERE read still rests on an absence claim the missing PR could
#     contradict: label present and at-or-ahead of the known evidence
#     (in-sync) while not already at the last possible stage (Review) —
#     a missing PR could push the true latest stage past the label,
#     which would flip in-sync into stale; or no label and no evidence
#     read at all (not-started) — a missing PR could supply evidence,
#     which would flip it into stale (AC4). A verdict that is already
#     `stale` from the sources that WERE read is NEVER degraded: evidence
#     is only ever additive (a missing PR can push the true latest stage
#     later, never earlier), so an already-stale verdict can only stay
#     stale or become "more stale" — it can never be undone into
#     in-sync by evidence nobody has read yet. Likewise a label already
#     at role:reviewer (Review, the last stage) can never be pushed past
#     it by anything a missing PR might reveal, so that in-sync verdict
#     never needs to degrade either. This is the same asymmetric-
#     degradation discipline compliance-evidence.sh's
#     BUNDLE_ISSUE_LOOKUP_FAILED already applies, mirrored in the
#     opposite direction (there: issues off a PR; here: PRs off an
#     issue).
#
# Exit codes, same numbers/meanings as compliance-evidence.sh's own scheme:
#   0 — a verdict was produced, including `indeterminate` (a finding, not
#       an error)
#   1 — internal error: the computed verdict fell outside the closed
#       four-value vocabulary (never expected; see valid_status())
#   2 — usage error (no issue number given)
#   3 — gh not found on PATH
#   4 — the issue itself couldn't be read (`gh api graphql` failed) — no
#       honest verdict is possible without it. A PR lookup failing never
#       changes the exit code; it degrades its own verdict per the rule
#       above and the run still exits 0.
#
# It is read-only: no gh write subcommand anywhere in this file (no
# `issue edit`, `issue comment`, `pr edit`, `pr comment`, `pr merge`, any
# `gh ... label` subcommand, `gh api -X`/`gh api --method`) — verified the
# same two ways compliance-evidence.sh's AC5/AC7 already established: a
# `fake_gh_bin` fallthrough witness, and a source-level grep assertion
# (test/cases/s152_role_label_staleness.sh).
#
# Named without a `check-` prefix and placed at the repo root, alongside
# compliance-evidence.sh (issue #315 AC9 — same reasoning
# compliance-evidence.sh's own AC7 already used). Dogfood-only: not under
# skills/ or templates/, no propagation to adopted projects for this
# epic. Not invoked by `./check` — it needs `gh`/network, and per issue
# #296 AC7's own precedent, no gh-dependent script in this repo runs
# inside `./check`; only its tests do (test/run.sh, offline against
# fake_gh_bin fixtures — AC8).
#
# --- Empirical finding recorded here per issue #315's own Technical
# notes ("check for gh CLI support before inventing a bespoke GraphQL
# call") ---
#
# `gh issue view --json closedByPullRequestsReferences` is NOT a
# supported field on the gh CLI version this was written against and
# tested empirically against this repo (gh 2.45.0 — checked live against
# issues #313 and #237, both closed by real, merged PRs: gh rejects the
# field with "Unknown JSON field"). The same is true of
# `gh pr view --json closingIssuesReferences` on that same gh version —
# a pre-existing fact about compliance-evidence.sh's own Call A that
# predates this script and is out of this issue's scope to fix, but is
# recorded here since it was discovered while empirically resolving this
# exact question.
#
# This makes the choice a build-time one, not a runtime fallback: this
# script always uses a single `gh api graphql` query for the
# `closedByPullRequestsReferences` connection (same connection, same
# "no new dependency" shape Architect's Planning comment anticipated),
# never a `gh issue view --json closedByPullRequestsReferences` call that
# would only fail on this CLI version anyway. Because it's a fixed
# write-time choice and not a two-path runtime branch, there is no
# separate "unsupported field -> fallback fires" test arm (the QA Test
# comment flagged this exact distinction as the thing to confirm before
# finalizing that arm) — every test in test/cases/s152_role_label_
# staleness.sh exercises the one graphql-based call this script actually
# makes.
#
# One more environment-specific fact worth recording for whoever next
# touches this: from *inside a Claude Code session* (this one included),
# the network egress proxy rejects `gh api graphql` outright regardless
# of query content (confirmed with a trivial `{ viewer { login } }`
# query — HTTP 403, "GitHub GraphQL is not available from Claude Code
# sessions"). That is a policy restriction of that specific runtime, not
# a defect in this script or in the GraphQL query it sends: a real GitHub
# Actions run or a human's own `gh` both reach the GraphQL endpoint
# normally. It also does not affect this script's own tests (AC8): they
# replace the whole `gh` binary with `fake_gh_bin`, so no real network
# call — graphql or otherwise — is ever made while testing.
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}. Every
# multi-value collection here (linked PR numbers, role labels found,
# failed PR numbers) is a plain newline-delimited string, never a bash
# array — the same choice compliance-evidence.sh's BUNDLE_ISSUES already
# made, and for the same reason: iterating `"${arr[@]}"` on a possibly-
# EMPTY array trips a real bash-3.2 `set -u` "unbound variable" bug (hit
# and reverted once already in compliance-evidence.sh's own history, see
# resolve_stage_marker()'s comment) — a plain string with `[ -n "$x" ]`
# guarding a `while read` loop never can. The two fixed 5-element arrays
# below (STAGES, ROLE_LABELS) are the only bash arrays in this file, and
# are only ever indexed by a literal numeral 0-4, never expanded with
# `[@]` — safe under `set -u` unconditionally, empty-array bug or not.
#
# No eval: issue/PR body and comment text is not under this script's own
# control.

set -uo pipefail

if [ $# -lt 1 ] || [ -z "${1:-}" ]; then
  echo "usage: role-label-staleness.sh <issue-number>" >&2
  exit 2
fi
issue_number="$1"

require_gh() {
  if ! command -v gh >/dev/null 2>&1; then
    echo "role-label-staleness: gh not found on PATH — cannot check role-label staleness." >&2
    exit 3
  fi
}

# live_text() — copied verbatim from compliance-evidence.sh (issue #308),
# not sourced/imported: a shared lib would cross the dogfood-only
# boundary the same way compliance-evidence.sh's own header already
# explains for its copy of normalize_model() (skills/ ships to adopted
# projects via adopt.sh; neither collector does). Strips quoted/fenced
# spans (fenced code blocks, inline code spans, blockquoted lines) out of
# a single body before any marker grep ever runs, so a marker merely
# quoted for illustration in a PR/issue comment doesn't count as live
# evidence — the same false-positive class issue #308 fixed for
# compliance-evidence.sh, and exactly the class issue #315's Technical
# notes call out by name. See compliance-evidence.sh's own copy for the
# full mechanism notes (fence-open/close rule, blockquote-first ordering,
# per-body fence isolation); unmodified here, so those notes still apply
# verbatim.
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
      if (match(line, /^ {0,3}(`{3,}|~{3,})/)) {
        m = substr(line, RSTART, RLENGTH); sub(/^ +/, "", m)
        ch = substr(m, 1, 1); len = length(m)
        rest = substr(line, RSTART + RLENGTH)
        if (fch == "") {                                  # open: any info string allowed
          fch = ch; flen = len; print ""; next
        } else if (ch == fch && len >= flen && rest ~ /^[ \t]*$/) {
          fch = ""; flen = 0; print ""; next               # close: no info string allowed (D10)
        }
      }
      if (fch != "") { print ""; next }
      print drop_spans(line)
    }
  '
}

# --- Stage <-> role-label mapping, fixed order. Indexed by literal 0-4
# only, never `[@]` (see the bash-3.2 note above) — these two arrays are
# never empty, but the discipline is kept uniform throughout this file.
STAGES=(Discovery Planning Test Implementation Review)
ROLE_LABELS=(role:product role:architect role:qa role:dev role:reviewer)
LAST_RANK=4  # index of Review/role:reviewer — the ceiling stage.

# Prints $1's 0-based rank (0-4) on stdout and returns 0 if $1 is one of
# the five fixed stage names; returns 1 with nothing printed otherwise
# (an unrecognized/malformed stage token — AC6).
stage_rank() {
  local name="$1" i
  for i in 0 1 2 3 4; do
    if [ "${STAGES[$i]}" = "$name" ]; then
      echo "$i"
      return 0
    fi
  done
  return 1
}

stage_name_at() { echo "${STAGES[$1]}"; }
label_at() { echo "${ROLE_LABELS[$1]}"; }

# Prints $1's 0-based rank on stdout and returns 0 if $1 is one of the
# five role:<name> labels; returns 1 otherwise.
label_rank() {
  local label="$1" i
  for i in 0 1 2 3 4; do
    if [ "${ROLE_LABELS[$i]}" = "$label" ]; then
      echo "$i"
      return 0
    fi
  done
  return 1
}

# --- The two gh calls. Sentinel transport (issue #308's D9, reused
# verbatim in shape): each body's real newlines are folded into \u0001 on
# the way out (after neutralising any literal \u0001 the body might
# already contain, and dropping \r — GitHub bodies are CRLF, and a
# trailing \r would defeat live_text()'s fence-close info-string check)
# so the TSV framing survives the round trip; collect() below folds it
# back with `tr '\001' '\n'` once per body, before live_text() ever sees
# it.
#
# Call 1 (always, exactly one call): a single `gh api graphql` query for
# everything issue-side in one round trip — labels, body/comment text,
# and the linked PR number(s) — the GraphQL connection
# `closedByPullRequestsReferences` mirrors `closingIssuesReferences` in
# reverse. See the empirical-finding note above for why this is a
# graphql call and not `gh issue view --json closedByPullRequestsReferences`.
# `{owner}`/`{repo}` are gh's own magic placeholders, filled in from the
# repository of the current directory (gh's documented behavior for
# `-f`/`-F` field values) — the same as every other script in this repo
# lets `gh` resolve the repo implicitly rather than hardcoding
# TiesL/spec-driven-guardrails.
ISSUE_GRAPHQL_QUERY='query($owner:String!,$repo:String!,$number:Int!){repository(owner:$owner,name:$repo){issue(number:$number){labels(first:20){nodes{name}}body comments(first:100){nodes{body}}closedByPullRequestsReferences(first:20){nodes{number}}}}}'
ISSUE_JQ='.data.repository.issue | (.labels.nodes[]? | "LABEL\t"+.name),(.closedByPullRequestsReferences.nodes[]? | "PR\t"+(.number|tostring)),("TEXT\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001"))),(.comments.nodes[]? | "TEXT\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001")))'

# Call 2 (zero or more, one per PR number Call 1 returned): plain fields,
# both supported on the gh CLI version this was checked against (unlike
# closingIssuesReferences — not needed here; this detector never compares
# which PR closes which issue, only marker text).
PR_JQ='("TEXT\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001"))),(.comments[]? | "TEXT\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001")))'

# --- collect(): fills these globals. Returns 1 only when Call 1 (the
# issue lookup) fails — the one failure that makes an honest verdict
# impossible. A Call 2 failure never makes collect() itself fail; it
# only sets PR_LOOKUP_FAILED and records which PR (FAILED_PRS), same
# shape as compliance-evidence.sh's BUNDLE_ISSUE_LOOKUP_FAILED.
ROLE_LABELS_FOUND=""   # clean list (no leading blank line) — one role:<name> label per line, as found on the issue
PR_NUMS=""             # clean list — one PR number per line, as Call 1 returned them (order never matters — see scan_markers below)
FAILED_PRS=""          # clean list — one PR number per line, for PRs whose Call 2 failed
CORPUS_TEXT=""         # every live-text()-processed body (issue + every successfully-fetched PR), concatenated
PR_LOOKUP_FAILED=0

collect() {
  local issue_out issue_status
  issue_out="$(gh api graphql -f query="$ISSUE_GRAPHQL_QUERY" -F owner='{owner}' -F repo='{repo}' -F number="$issue_number" --jq "$ISSUE_JQ" 2>/dev/null)"
  issue_status=$?
  if [ "$issue_status" -ne 0 ]; then
    return 1
  fi

  local tag rest raw_body live_body
  while IFS=$'\t' read -r tag rest; do
    case "$tag" in
      LABEL)
        case "$rest" in
          role:product|role:architect|role:qa|role:dev|role:reviewer)
            if [ -z "$ROLE_LABELS_FOUND" ]; then
              ROLE_LABELS_FOUND="$rest"
            else
              ROLE_LABELS_FOUND="$ROLE_LABELS_FOUND
$rest"
            fi
            ;;
          # Any other label (e.g. `bug`, `priority:high`) is irrelevant
          # here and deliberately not collected — filtering to the five
          # known role:<name> names only, per Architect's Planning
          # comment, not a blanket "matches role:" prefix scan.
        esac
        ;;
      PR)
        if [ -z "$PR_NUMS" ]; then
          PR_NUMS="$rest"
        else
          PR_NUMS="$PR_NUMS
$rest"
        fi
        ;;
      TEXT)
        raw_body="$(printf '%s' "$rest" | tr '\001' '\n')"
        live_body="$(live_text "$raw_body")"
        CORPUS_TEXT="$CORPUS_TEXT
$live_body"
        ;;
    esac
  done <<<"$issue_out"

  if [ -n "$PR_NUMS" ]; then
    local pr pr_out pr_status
    while IFS= read -r pr; do
      [ -n "$pr" ] || continue
      pr_out="$(gh pr view "$pr" --json body,comments --jq "$PR_JQ" 2>/dev/null)"
      pr_status=$?
      if [ "$pr_status" -ne 0 ]; then
        echo "warning: role-label-staleness couldn't consult PR #$pr (no network or no access) — a verdict resting on an absence claim that PR could have contradicted will degrade to indeterminate." >&2
        PR_LOOKUP_FAILED=1
        if [ -z "$FAILED_PRS" ]; then
          FAILED_PRS="$pr"
        else
          FAILED_PRS="$FAILED_PRS
$pr"
        fi
        continue
      fi
      while IFS=$'\t' read -r tag rest; do
        [ "$tag" = "TEXT" ] || continue
        raw_body="$(printf '%s' "$rest" | tr '\001' '\n')"
        live_body="$(live_text "$raw_body")"
        CORPUS_TEXT="$CORPUS_TEXT
$live_body"
      done <<<"$pr_out"
    done <<<"$PR_NUMS"
  fi

  return 0
}

# --- Marker scanning. New relative to compliance-evidence.sh (Architect's
# Planning comment: "the inverse of gate_stage_models()'s loop, which
# checks one *known* stage name per iteration and never needs to look at
# an unrecognized value") — this extracts whatever stage= token is
# actually there and classifies it, rather than checking presence of one
# fixed name at a time.
#
# Anchored the same way compliance-evidence.sh's own gates are (issue
# #308 AC7/D4): a real `<!--...-->` HTML-comment opener, not bare prose —
# bare text that merely mentions "model-record: stage=X" with no `<!--`
# is not a marker at all and is invisible here, same reasoning as
# gate_stage_models(). Deliberately anchored on `model-record:` alone
# (not `model-record:[[:space:]]*stage=`, unlike compliance-evidence.sh's
# per-stage gates): a marker that matched the anchor but has NO stage=
# token at all must still be seen and classified as malformed (AC6),
# never silently invisible the way a tighter anchor would make it.
#
# Updates two globals: KNOWN_MAX_RANK (highest recognized stage rank
# found anywhere in $1, or stays -1 if none) and MALFORMED_FOUND/
# MALFORMED_LINE (set the first time a marker matches the anchor but its
# stage= token is missing or not one of the five recognized names).
# Never coerces an unrecognized token to the nearest recognized stage,
# and never silently drops it as if absent (AC6) — either would risk
# flipping a real stale/in-sync answer silently, which is exactly what
# indeterminate exists to prevent.
KNOWN_MAX_RANK=-1
MALFORMED_FOUND=0
MALFORMED_LINE=""

scan_markers() {
  local text="$1" marker_lines line token rank
  marker_lines="$(grep -oE '<!--[[:space:]]*model-record:[^>]*-->' <<<"$text")"
  [ -n "$marker_lines" ] || return 0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    token="$(grep -oE 'stage=[^[:space:]>]+' <<<"$line" | head -1 | sed 's/^stage=//')"
    if [ -n "$token" ] && rank="$(stage_rank "$token" 2>/dev/null)"; then
      if [ "$rank" -gt "$KNOWN_MAX_RANK" ]; then
        KNOWN_MAX_RANK="$rank"
      fi
    else
      MALFORMED_FOUND=1
      if [ -z "$MALFORMED_LINE" ]; then
        MALFORMED_LINE="$line"
      fi
    fi
  done <<<"$marker_lines"
}

valid_status() {
  case "$1" in
    not-started|in-sync|stale|indeterminate) return 0 ;;
    *) return 1 ;;
  esac
}

# Builds a human-readable ", "-joined list from a clean newline-delimited
# string, one token per line, each printed through $1's printf format
# (e.g. "#%s" for PR numbers, "%s" for label names already spelled
# role:<name>). Mirrors compliance-evidence.sh's gate_traceability() own
# small loop, generalized to take a format.
joined_list() {
  local fmt="$1" list="$2" out="" first=1 line
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if [ "$first" -eq 1 ]; then
      out="$(printf "$fmt" "$line")"
      first=0
    else
      out="$out, $(printf "$fmt" "$line")"
    fi
  done <<<"$list"
  printf '%s' "$out"
}

# --- Main ---------------------------------------------------------------

require_gh

if ! collect; then
  echo "role-label-staleness: could not read issue #$issue_number (gh api graphql failed — no network, no access, or the issue doesn't exist) — no verdict can be produced." >&2
  exit 4
fi

role_label_count=0
if [ -n "$ROLE_LABELS_FOUND" ]; then
  role_label_count="$(printf '%s\n' "$ROLE_LABELS_FOUND" | grep -c '.')"
fi

verdict=""
detail=""

if [ "$role_label_count" -gt 1 ]; then
  # AC5 — never pick one as authoritative; name every one found.
  labels_list="$(joined_list '%s' "$ROLE_LABELS_FOUND")"
  verdict="indeterminate"
  detail="issue #$issue_number carries more than one role:<name> label at once ($labels_list) — exactly one should track the active phase, never zero-or-picked-arbitrarily"
else
  scan_markers "$CORPUS_TEXT"

  if [ "$MALFORMED_FOUND" -eq 1 ]; then
    # AC6 — one sighting anywhere in scope forces this for the whole
    # run (the blunt, conservative reading Architect's Planning comment
    # recommended over a narrower "only if it could flip the verdict"
    # rule) — g3 depends on this taking priority over a well-formed,
    # later marker found elsewhere in the same corpus.
    verdict="indeterminate"
    detail="a model-record marker on issue #$issue_number or a linked PR matched but has no recognized stage=<Discovery|Planning|Test|Implementation|Review> value: $MALFORMED_LINE"
  else
    label_r=-1
    single_label=""
    if [ "$role_label_count" -eq 1 ]; then
      single_label="$ROLE_LABELS_FOUND"
      label_r="$(label_rank "$single_label")"
    fi

    # PR-lookup-failure degrade — see the header comment for the full
    # asymmetric-degradation rule this implements. Only the two verdicts
    # that rest on "nothing more exists beyond what was read" are
    # vulnerable: in-sync (label at/ahead of known evidence) while not
    # already at the ceiling stage, or not-started (nothing at all).
    # A verdict that is already stale from what WAS read never degrades
    # — more evidence can only deepen staleness, never undo it.
    vulnerable=0
    if [ "$PR_LOOKUP_FAILED" -eq 1 ]; then
      if [ "$label_r" -eq -1 ] && [ "$KNOWN_MAX_RANK" -eq -1 ]; then
        vulnerable=1
      elif [ "$label_r" -ge 0 ] && [ "$label_r" -ge "$KNOWN_MAX_RANK" ] && [ "$label_r" -lt "$LAST_RANK" ]; then
        vulnerable=1
      fi
    fi

    if [ "$vulnerable" -eq 1 ]; then
      failed_list="$(joined_list '#%s' "$FAILED_PRS")"
      verdict="indeterminate"
      detail="PR lookup failed for $failed_list on issue #$issue_number, and the evidence read so far doesn't rule out a later stage there that would make the current label stale"
    elif [ "$label_r" -eq -1 ] && [ "$KNOWN_MAX_RANK" -eq -1 ]; then
      # AC3 — a conjunction: no label AND no marker anywhere in scope.
      verdict="not-started"
      detail="no role:<name> label and no model-record marker found on issue #$issue_number or any linked PR"
    elif [ "$label_r" -eq -1 ]; then
      # AC4 — evidence exists but the label is absent entirely.
      expected_label="$(label_at "$KNOWN_MAX_RANK")"
      expected_stage="$(stage_name_at "$KNOWN_MAX_RANK")"
      verdict="stale"
      detail="issue #$issue_number carries no role:<name> label, but a stage=$expected_stage marker already exists — expected $expected_label"
    elif [ "$label_r" -lt "$KNOWN_MAX_RANK" ]; then
      # AC1 — label present but behind the latest evidenced stage.
      present_label="$single_label"
      expected_label="$(label_at "$KNOWN_MAX_RANK")"
      expected_stage="$(stage_name_at "$KNOWN_MAX_RANK")"
      verdict="stale"
      detail="issue #$issue_number carries $present_label, but a stage=$expected_stage marker already exists — expected $expected_label"
    else
      # AC2 (and AC3's "label alone already leaves not-started" case) —
      # label at or ahead of the latest evidenced stage, including zero
      # markers evidenced yet at all.
      present_label="$single_label"
      verdict="in-sync"
      if [ "$KNOWN_MAX_RANK" -eq -1 ]; then
        detail="issue #$issue_number carries $present_label, with no model-record marker evidenced yet anywhere in scope — a label ahead of the latest evidenced stage is expected, not stale"
      else
        evidenced_stage="$(stage_name_at "$KNOWN_MAX_RANK")"
        detail="issue #$issue_number carries $present_label, at or ahead of the latest evidenced stage (stage=$evidenced_stage)"
      fi
    fi
  fi
fi

if ! valid_status "$verdict"; then
  echo "role-label-staleness: internal error — computed an invalid status '$verdict' for issue #$issue_number" >&2
  exit 1
fi

printf 'role-label-staleness: issue #%s — %s (%s)\n' "$issue_number" "$verdict" "$detail"
exit 0
