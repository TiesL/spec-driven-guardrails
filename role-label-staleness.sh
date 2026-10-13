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
#                     as the latest candidate for its stage; older near-misses
#                     are superseded by newer valid records);
#                     or a lookup failed while the verdict computed from
#                     what WAS read still rests on an absence claim that
#                     lookup could have contradicted (see "Lookup
#                     failures" below)
#
# --- REST-only design (issue #315's Architect redesign comment,
# 2026-09-28, superseding the original Planning comment's GraphQL-based
# §1/§3) ---
#
# There is NO `gh api graphql` call anywhere in this file, and no
# `gh issue view`/`gh pr view` either (both are GraphQL-backed under the
# hood on this gh CLI version). Every call is `gh api` against an
# explicit REST endpoint. Two independent reasons forced this, both found
# by Reviewer on the first version of this script (PR #316):
#
#   1. From *inside a Claude Code session*, the network egress proxy
#      rejects every GraphQL-backed call outright — not only a bespoke
#      `gh api graphql` query, but `gh issue view`/`gh pr view` too, with
#      or without an exotic field. Reviewer reproduced this directly:
#      `gh issue view <n> --json labels,body` (no unusual field at all)
#      403s the same way `gh api graphql -f query='{ viewer { login } }'`
#      does. Any design that kept either command anywhere would still be
#      unusable from the very environment this script's own orchestrator
#      runs in. (This is a policy restriction of that specific runtime,
#      not a defect in the calls themselves — a human's own `gh` and a
#      GitHub Actions run both reach GraphQL normally, and it has no
#      effect on this script's own tests, AC8, which replace the whole
#      `gh` binary and never make a real network call. It also turns out
#      to affect compliance-evidence.sh and model-record-gate.sh the same
#      way — a real, separate, epic-level finding, out of this issue's
#      scope to fix; tracked as a follow-up rather than fixed here.)
#   2. Independent of the proxy, `closedByPullRequestsReferences` (and
#      its reverse, `closingIssuesReferences`) is *empty* for a PR that
#      doesn't target the repository's default branch — GitHub requires
#      merging into the default branch before it will materialize the
#      auto-close connection at all. Every epic #295 work-item PR targets
#      `release/295-multi-agent-workflow-v1`, never `main` — so the
#      original design silently found zero linked PRs for every issue it
#      was built to serve, with no failure and nothing to degrade (the
#      wrong answer was indistinguishable from AC3's "genuinely
#      not-started"/"zero PRs is normal" case). This was a correctness
#      defect independent of the proxy: it reproduces even where GraphQL
#      itself works fine.
#
# Both defects share one fix: what `closedByPullRequestsReferences`
# *materializes* — "this PR closes that issue" — is just GitHub
# recognizing a closing keyword (`close(s|d)`, `fix(es|ed)`,
# `resolve(s|d)`) followed by `#<issue-number>` in a PR's body, same
# repo. That's true regardless of target branch; the connection
# under-delivers only because GitHub additionally requires the
# *default-branch-merge* precondition before it will auto-close — a
# merge-time gate on top of the same keyword mechanism, not a different,
# weaker signal. So this script re-derives the keyword match directly
# over REST, without that gate: not a heuristic approximation, the actual
# same mechanism, minus the restriction that was hiding real PRs from it.
# (Same-repo only — a cross-repo `owner/repo#N` closing reference is
# accepted debt for v1, same spirit as live_text()'s own documented
# non-goal-1 residues, not silently unhandled: every other reference this
# repo's tooling resolves is same-repo too.)
#
# Algorithm:
#   1. Candidates — every PR that cross-references the issue at all
#      (`GET .../issues/<issue>/timeline`, `cross-referenced` events whose
#      `source.issue.pull_request` is set). This step deliberately
#      over-includes (a PR can mention an issue in prose with no closing
#      intent at all, e.g. epic #295's own umbrella issue turning up as a
#      cross-reference on every one of its W-items) — only step 1's job
#      is "don't miss a candidate", never "pick the right one".
#   2. Filter — fetch each candidate's *current* title AND body
#      (`GET .../pulls/<pr>`, never the timeline event's own cached
#      snapshot, which can predate a later edit that added or removed the
#      closing keyword) and keep only the ones where the closing-keyword
#      ERE matches against this issue's number in EITHER field. Both
#      fields matter in practice, not just in principle: PR #316's own
#      round-2 review found that this repo's release-branch work-item
#      PRs (e.g. #314 "Closes #313: ...") carry the closing keyword only
#      in the PR *title*, never the body — reading the body alone missed
#      exactly the PRs this script exists to find. GitHub's own
#      auto-close mechanism accepts the keyword in either field, so
#      matching both isn't a heuristic broadening, it's parity with what
#      GitHub itself does. A candidate that matches neither field is
#      discarded silently — not a failure, just not a closing PR — and
#      never gets a comments/reviews call (cheap: one single-object REST
#      call per candidate before any paginated one).
#   3. Evidence — for each *kept* PR, two more calls:
#      `GET .../issues/<pr>/comments` (PR conversation comments live on
#      the issues endpoint, since a PR *is* an issue under the hood) and
#      `GET .../pulls/<pr>/reviews` (this pipeline's Review stage posts
#      its model-record marker as a PR *review*'s own body — GitHub's
#      review mechanism, distinct from both a plain comment and from
#      `/pulls/<pr>/comments`'s inline per-line review comments, which
#      is a third, still-unread endpoint no marker is ever posted to).
#      Missing the reviews call was round-2's F-6 finding: without it,
#      every Review-stage marker posted the way this pipeline actually
#      posts it was invisible. The title/body already fetched in step 2
#      is reused for the body's evidence — no second body fetch.
#   4. Raw bodies are sorted by creation/submission time, with source
#      order breaking ties, then framed and read by one cached
#      rec_scan_bundle call. Quoted candidates do not evidence a stage.
#      Description edits are unseen: descriptions use created_at (A37).
#
# Lookup failures — three independent flags, split because REST breaks
# the original single-call shape into several independently-failing
# calls (this script's structurally new failure surface relative to
# compliance-evidence.sh, same as the original design, just split
# three ways now):
#   - ISSUE_COMMENTS_FAILED — the issue's own comments call failed. The
#     issue body/labels (a separate, non-paginated call) are still known.
#   - PR_DISCOVERY_FAILED — the timeline call itself failed. This must
#     NEVER be read as "zero linked PRs" — a timeline failure means PRs
#     might exist and this run couldn't find out, which is a materially
#     different claim than "confirmed there are none" (AC3's zero-PRs
#     case, still legitimate and un-degraded when the timeline call
#     genuinely succeeds with nothing in it).
#   - PR_LOOKUP_FAILED — a *kept* candidate's title/body fetch (step 2),
#     comments fetch, or reviews fetch (step 3) failed. When the
#     title/body fetch itself fails, whether that PR even closes this
#     issue is unknown, not "no" — it is never silently dropped as a
#     non-match. A PR can fail one of its two evidence calls
#     (comments/reviews) while the other succeeds; each is independent,
#     and the PR is named at most once in the detail message either way
#     (mark_pr_failed()'s dedup).
#
# Degradation rule (unchanged in spirit from the original single-flag
# design, mechanically identical once any of the three flags above is
# set): any verdict that would otherwise be `not-started`, or a
# `stale`/`in-sync` call resting on "this is the latest evidence there
# is" while not already at the ceiling stage, degrades to
# `indeterminate`. A verdict that is already `stale` from evidence
# already in hand is NEVER weakened by a failure elsewhere — evidence is
# only ever additive (a missing lookup can push the true latest stage
# later, never earlier), so an already-stale verdict can only stay stale
# or become "more stale", never get undone into in-sync by evidence
# nobody read. Same asymmetric-degradation discipline
# compliance-evidence.sh's BUNDLE_ISSUE_LOOKUP_FAILED already applies.
#
# Exit codes, same numbers/meanings as compliance-evidence.sh's own scheme:
#   0 — a verdict was produced, including `indeterminate` (a finding, not
#       an error)
#   1 — internal error: the computed verdict fell outside the closed
#       four-value vocabulary (never expected; see valid_status())
#   2 — usage error (no issue number given)
#   3 — gh not found on PATH, or lib/model-record.sh (next to this
#       script) is missing
#   4 — the issue itself couldn't be read (the non-paginated issue-body
#       call failed) — no honest verdict is possible without it. Every
#       other call failing only sets its own flag and degrades its own
#       verdict per the rule above; the run still exits 0.
#
# It is read-only: no gh write subcommand anywhere in this file (no
# `issue edit`, `issue comment`, `pr edit`, `pr comment`, `pr merge`, any
# `gh ... label` subcommand, `gh api -X`/`gh api --method`) — verified the
# same two ways compliance-evidence.sh's AC5/AC7 already established: a
# `fake_gh_bin` fallthrough witness that is actually reachable (issue
# #315 PR #316's Reviewer found the first version's witness dead code —
# fixed in the test file, with a positive control proving it now fires),
# and a source-level grep assertion (test/cases/s152_role_label_
# staleness.sh).
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
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}. Every
# multi-value collection here (candidate/kept PR numbers, role labels
# found, failed PR numbers) is a plain newline-delimited string, never a
# bash array — the same choice compliance-evidence.sh's BUNDLE_ISSUES
# already made, and for the same reason: iterating `"${arr[@]}"` on a
# possibly-EMPTY array trips a real bash-3.2 `set -u` "unbound variable"
# bug (hit and reverted once already in compliance-evidence.sh's own
# history, see resolve_stage_marker()'s comment) — a plain string with
# `[ -n "$x" ]` guarding a `while read` loop never can. The two fixed
# 5-element arrays below (STAGES, ROLE_LABELS) are the only bash arrays
# in this file, and are only ever indexed by a literal numeral 0-4, never
# expanded with `[@]` — safe under `set -u` unconditionally, empty-array
# bug or not.
#
# No eval: issue/PR body and comment text is not under this script's own
# control.
#
# awk requirement (issue #319): `live_text()` below has no special awk
# requirement left — every awk it has been run under (mawk 1.3.4
# 20200120, mawk 1.3.4 20240123, gawk) parses and executes its fence
# regex the same way. Getting there dodged two independent, unrelated
# mawk defects rather than working around either in an mawk-specific
# code path: mawk's REcompile() panics on a grouped alternation combined
# with an unbounded-lower-bound interval (`(`{3,}|~{3,})`), and,
# separately, mawk 1.3.4 20200120 and earlier (Ubuntu 22.04's default
# `awk`, among others) doesn't parse a bounded interval (`{0,3}`) at all
# — it reads the four characters literally instead of as "0 to 3". See
# the copy of this function's own inline comment for the mechanism, and
# test/cases/s153_live_text_mawk_portability.sh.

set -uo pipefail
export LC_ALL=C  # A32c: every command and bash's own matching reads GitHub text as bytes; enforced by S235

if [ $# -lt 1 ] || [ -z "${1:-}" ]; then
  echo "usage: role-label-staleness.sh <issue-number>" >&2
  exit 2
fi
# issue #317 F-4: a non-numeric argument used to reach collect()'s own
# gh call, fail there, and exit 4 (internal-error-shaped) — a bad
# argument is a usage error (exit 2), the same shape as the empty-
# argument case just above, not an internal error. `0` is rejected too
# (round 1 review nit): GitHub issue numbers start at 1, so `0` is
# exactly as invalid as a non-digit argument, not a legitimate edge case
# worth accepting.
case "$1" in
  *[!0-9]*|0)
    echo "usage: role-label-staleness.sh <issue-number> (must be a positive integer)" >&2
    exit 2
    ;;
esac
issue_number="$1"

require_gh() {
  if ! command -v gh >/dev/null 2>&1; then
    echo "role-label-staleness: gh not found on PATH — cannot check role-label staleness." >&2
    exit 3
  fi
}

# rec_scan_bundle — the one model-record grammar, shared with
# compliance-evidence.sh and skills/pre-merge-review/model-record-gate.sh
# through lib/model-record.sh (#392, round 3 of the PR #397 review: the
# private `[^>]*-->` pattern this script used made a marker with a `>` in a
# quoted value invisible). Like compliance-evidence.sh, this script lives at
# the repo root next to lib/ and is dogfood-only, so sourcing the lib
# crosses no adoption boundary.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if [ ! -r "$script_dir/lib/model-record.sh" ]; then
  echo "role-label-staleness: lib/model-record.sh not found next to this script — cannot read model-record markers." >&2
  exit 3
fi
# shellcheck source=lib/model-record.sh
. "$script_dir/lib/model-record.sh"

# live_text() — one definition in lib/markdown.sh (#423, from issue #308),
# sourced through lib/model-record.sh above. It strips quoted/fenced spans
# (fenced code blocks, inline code spans, blockquoted lines) out of a single
# body before any marker grep runs, so a marker merely quoted for
# illustration does not count as live evidence (issue #315). A failure of it
# means a body was not read: LIVE_FAILED, and the verdict is indeterminate,
# never in-sync or not-started on an absence nobody checked.
LIVE_FAILED=0

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

# --- The gh calls. All REST (`gh api` against an explicit endpoint,
# never `gh api graphql`/`gh issue view`/`gh pr view` — see the header's
# REST-only design note for why). `{owner}`/`{repo}` are gh's own magic
# placeholders in the endpoint path itself, filled in from the repository
# of the current directory (gh's documented behavior) — no new argument,
# no hardcoded repo name, the same implicit-repo convention every other
# script in this repo already relies on.
#
# Sentinel transport (issue #308's D9, reused verbatim in shape): each
# body's real newlines are folded into \u0001 on the way out (after
# neutralising any literal \u0001 the body might already contain, and
# dropping \r — GitHub bodies are CRLF, and a trailing \r would defeat
# live_text()'s fence-close info-string check) so the TSV framing
# survives the round trip; collect() below folds it back with
# `LC_ALL=C tr '\001' '\n'` once per body, before live_text() ever sees it. The
# --jq expressions themselves are written fresh against REST's flat-JSON
# shapes (`.[] | .body`, `.labels[].name`, a `select()` on the timeline's
# event type) — different enough from compliance-evidence.sh's
# GraphQL-nested ones (`.comments[]?`, `.closingIssuesReferences[]?`)
# that this isn't a port, just the same convention re-applied.
ISSUE_JQ='("BODY\t"+(.created_at//"")+"\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001"))),(.labels[]? | "LABEL\t"+.name)'
COMMENTS_JQ='.[] | "TEXT\t"+(.created_at//"")+"\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001"))'
REVIEWS_JQ='.[] | "TEXT\t"+(.submitted_at//"")+"\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001"))'
TIMELINE_JQ='.[] | select(.event=="cross-referenced" and .source.issue.pull_request != null) | "PR\t"+(.source.issue.number|tostring)'
# Emits BOTH the title and the body (issue #315 PR #316 round-2 review,
# 1b): this repo's own release-branch work-item PRs (#314, #316) carry
# their closing keyword only in the PR TITLE ("Closes #313: ..."), never
# the body — GitHub only needs the keyword in either place to populate
# its own closing-reference connection, but the original filter read
# only .body and so silently missed exactly the PRs this script exists
# to find. One extra field on the same already-budgeted call, no new
# request.
PR_TITLE_BODY_JQ='("TITLE\t"+((.title//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001"))),("BODY\t"+(.created_at//"")+"\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001")))'

# --- collect(): fills these globals. Returns 1 only when the issue-body
# call fails — the one failure that makes an honest verdict impossible.
# Every other call failure only sets its own flag (see the header's
# "Lookup failures" note) and keeps going.
ROLE_LABELS_FOUND=""       # clean list — one role:<name> label per line, as found on the issue
CORPUS_TEXT=""             # raw bodies, chronologically ordered and framed for one scan
BODY_ROWS=""               # timestamp TAB source-rank TAB arrival-index TAB encoded-body
BODY_COUNT=0
ISSUE_COMMENTS_FAILED=0
PR_DISCOVERY_FAILED=0
PR_LOOKUP_FAILED=0
FAILED_PRS=""              # clean list — candidate/kept PR numbers whose Call 4 or Call 5 failed

# Private ingestion: timestamp and source tie order are kept with each raw body.
# Newlines stay encoded until after sorting. Bodies cannot forge MARKER_SEP.
append_body() { # <timestamp TAB encoded-body> <source-rank>
  local row="$1" source="$2" timestamp encoded tab=$'\t'
  timestamp="${row%%"$tab"*}"
  encoded="${row#*"$tab"}"
  encoded="${encoded//$MARKER_SEP/}"
  BODY_COUNT=$((BODY_COUNT + 1))
  BODY_ROWS="$BODY_ROWS$timestamp$tab$source$tab$BODY_COUNT$tab$encoded"$'\n'
}

collect() {
  local issue_out issue_status row tag rest raw_body live_body

  issue_out="$(gh api "repos/{owner}/{repo}/issues/$issue_number" --jq "$ISSUE_JQ" 2>/dev/null)"
  issue_status=$?
  if [ "$issue_status" -ne 0 ]; then
    return 1
  fi

  while IFS= read -r row; do
    tag="${row%%$'\t'*}"; rest="${row#*$'\t'}"
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
      BODY)
        append_body "$rest" 0
        ;;
    esac
  done <<<"$issue_out"

  # Call 2 — the issue's own comments (paginated: REST defaults to
  # 30/page, and a marker sitting past page 1 must never be silently
  # dropped).
  local comments_out comments_status
  comments_out="$(gh api "repos/{owner}/{repo}/issues/$issue_number/comments" --paginate --jq "$COMMENTS_JQ" 2>/dev/null)"
  comments_status=$?
  if [ "$comments_status" -ne 0 ]; then
    echo "warning: role-label-staleness couldn't read issue #$issue_number's own comments (no network or no access) — a verdict resting on an absence claim they could have contradicted will degrade to indeterminate." >&2
    ISSUE_COMMENTS_FAILED=1
  else
    while IFS= read -r row; do
    tag="${row%%$'\t'*}"; rest="${row#*$'\t'}"
      [ "$tag" = "TEXT" ] || continue
      append_body "$rest" 0
    done <<<"$comments_out"
  fi

  # issue #317 F-8: a cross-referenced event's `source.issue` can belong
  # to a DIFFERENT repository (someone in another repo writing
  # "owner/repo#N" pulls up a cross-reference here, with its own
  # `.source.issue.number` — a bare number that can coincidentally
  # collide with a real PR number in THIS repo). Confirmed live against
  # this repo's own issue #319 timeline: every cross-referenced event's
  # `.source.issue.repository.full_name` is populated (same-repo events
  # included, not just cross-repo ones), so filtering on it is reliable
  # rather than a guess from field-name intuition. `{owner}/{repo}`
  # (gh's own magic placeholder, resolved from cwd) isn't echoed back by
  # the timeline endpoint itself, so this repo's own identity is fetched
  # once via a separate, lightweight call and spliced into the timeline
  # jq filter as a literal string — safe because GitHub repository names
  # are constrained to `[A-Za-z0-9_.-]`, never a quote or backslash that
  # could break out of the jq string literal. Fails open exactly like
  # every other call here: if the identity lookup itself fails, the
  # candidate list stays unfiltered (over-inclusive, same residual
  # exposure as before this fix, not a new failure mode) rather than
  # risk silently under-including on a run that can't tell same-repo
  # from cross-repo at all.
  local repo_full_name repo_full_name_status timeline_jq
  repo_full_name="$(gh api "repos/{owner}/{repo}" --jq '.full_name' 2>/dev/null)"
  repo_full_name_status=$?
  if [ "$repo_full_name_status" -eq 0 ] && [ -n "$repo_full_name" ]; then
    timeline_jq=".[] | select(.event==\"cross-referenced\" and .source.issue.pull_request != null and .source.issue.repository.full_name == \"$repo_full_name\") | \"PR\\t\"+(.source.issue.number|tostring)"
  else
    echo "warning: role-label-staleness couldn't confirm this repository's own identity — cross-repository timeline events won't be filtered out this run (over-inclusive, not under)." >&2
    timeline_jq="$TIMELINE_JQ"
  fi

  # Call 3 — PR discovery via the timeline (paginated). Deliberately
  # over-includes beyond the repo filter above (every SAME-REPO cross-
  # referencing PR, not only closing ones — see the header's step 1) —
  # the keyword filter below is what narrows this to real closing
  # references.
  local timeline_out timeline_status candidate_prs=""
  timeline_out="$(gh api "repos/{owner}/{repo}/issues/$issue_number/timeline" --paginate --jq "$timeline_jq" 2>/dev/null)"
  timeline_status=$?
  if [ "$timeline_status" -ne 0 ]; then
    echo "warning: role-label-staleness couldn't discover linked PRs for issue #$issue_number (the timeline lookup failed) — this means PRs might exist and weren't found, never that there are none; a verdict resting on that absence will degrade to indeterminate." >&2
    PR_DISCOVERY_FAILED=1
  else
    while IFS= read -r row; do
    tag="${row%%$'\t'*}"; rest="${row#*$'\t'}"
      [ "$tag" = "PR" ] || continue
      [ -n "$rest" ] || continue
      if [ -z "$candidate_prs" ]; then
        candidate_prs="$rest"
      else
        candidate_prs="$candidate_prs
$rest"
      fi
    done <<<"$timeline_out"
    # Dedupe — the same PR can generate more than one cross-reference
    # event on a busy issue. Numeric sort: harmless either way, since the
    # verdict computation is order-independent by construction (union/max
    # over stage presence — see scan_markers below).
    if [ -n "$candidate_prs" ]; then
      candidate_prs="$(printf '%s\n' "$candidate_prs" | grep '.' | sort -un)"
    fi
  fi

  # Call 4 (per candidate, filter) + Call 5/6 (per kept PR, evidence:
  # comments and reviews).
  if [ -n "$candidate_prs" ]; then
    local closing_ere pr pr_out pr_status pr_title_raw pr_body_raw
    local live_title combined_live pr_body_row
    local pr_comments_out pr_comments_status pr_reviews_out pr_reviews_status

    # GitHub's own closing-keyword grammar (issue #315 PR #316 round-2
    # review, 1b): keyword, an OPTIONAL colon directly after it, then
    # required whitespace, then #<issue>. Tightened from the original's
    # loose "any 0-20 chars in between" gap, which let unrelated prose
    # ("resolved against issue #315") pass as a closing reference — this
    # form only matches "Closes #N"/"Closes: #N"/"Fixes #N"/etc., never
    # a sentence that merely mentions the number later.
    closing_ere="\\b(close[sd]?|fix(e[sd])?|resolve[sd]?):?[[:space:]]+#${issue_number}\\b"

    while IFS= read -r pr; do
      [ -n "$pr" ] || continue

      pr_out="$(gh api "repos/{owner}/{repo}/pulls/$pr" --jq "$PR_TITLE_BODY_JQ" 2>/dev/null)"
      pr_status=$?
      if [ "$pr_status" -ne 0 ]; then
        echo "warning: role-label-staleness couldn't read PR #$pr's title/body (no network or no access) — whether it closes issue #$issue_number, and any evidence on it, is now unknown, not absent." >&2
        PR_LOOKUP_FAILED=1
        mark_pr_failed "$pr"
        continue
      fi

      pr_title_raw=""
      pr_body_raw=""
      pr_body_row=""
      while IFS= read -r row; do
    tag="${row%%$'\t'*}"; rest="${row#*$'\t'}"
        case "$tag" in
          TITLE) pr_title_raw="$(printf '%s' "$rest" | LC_ALL=C tr '\001' '\n')" ;;
          BODY) pr_body_row="$rest"; pr_body_raw="$(printf '%s' "${rest#*$'\t'}" | LC_ALL=C tr '\001' '\n')" ;;
        esac
      done <<<"$pr_out"

      # issue #317 F-7: the keyword check now runs against LIVE title+
      # body (each through live_text() before the grep), not raw — a PR
      # description that merely QUOTES "Closes #N" as an illustration
      # (inside a fenced block, inline code span, or blockquote — the
      # same shape compliance-evidence.sh's own live_text() exists to
      # discriminate for marker extraction) must not be counted as a
      # real closing reference on the strength of the quote alone. This
      # was accepted debt before (round-1 header's non-goal-1-style
      # residue); PR #316's own description hit it directly, quoting an
      # earlier round's "Closes #400" test-output snippet in a code
      # span, discovered ironically during that same PR's own review.
      # live_body is computed once here and reused below (was already
      # computed after the keyword check; moving it earlier costs
      # nothing extra). Checked against BOTH fields because this repo's
      # own release-branch work-item PRs put the keyword in the title
      # only (round-2 finding 1b) while a main-targeting PR typically
      # puts it in the body — GitHub itself accepts either. A candidate
      # that matches neither is discarded silently: cross-referencing an
      # issue in prose is common and not a failure of anything.
      pr_body_raw="${pr_body_raw//$MARKER_SEP/}" # #392: a body cannot forge a comment boundary
      live_title="$(live_text "$pr_title_raw")" || LIVE_FAILED=1
      live_body="$(live_text "$pr_body_raw")" || LIVE_FAILED=1
      combined_live="$live_title
$live_body"
      if ! LC_ALL=C grep -qiE "$closing_ere" <<<"$combined_live"; then
        continue
      fi

      append_body "$pr_body_row" 1

      pr_comments_out="$(gh api "repos/{owner}/{repo}/issues/$pr/comments" --paginate --jq "$COMMENTS_JQ" 2>/dev/null)"
      pr_comments_status=$?
      if [ "$pr_comments_status" -ne 0 ]; then
        echo "warning: role-label-staleness couldn't read PR #$pr's comments (no network or no access) — a verdict resting on an absence claim they could have contradicted will degrade to indeterminate." >&2
        PR_LOOKUP_FAILED=1
        mark_pr_failed "$pr"
      else
        while IFS= read -r row; do
    tag="${row%%$'\t'*}"; rest="${row#*$'\t'}"
          [ "$tag" = "TEXT" ] || continue
          append_body "$rest" 2
        done <<<"$pr_comments_out"
      fi

      # Call 6 — the kept PR's reviews (paginated). Round-2 review
      # finding F-6: this pipeline posts the Review-stage marker as a PR
      # REVIEW's body (GitHub's own review mechanism), never a plain
      # issue-style comment — a PR review's JSON shape is the same flat
      # array-of-objects-with-.body as issue comments, so COMMENTS_JQ is
      # reused unchanged; only the endpoint differs. Independent of
      # whether the comments call above succeeded — a PR can have its
      # comments read fine while its reviews call fails, or vice versa,
      # so this is its own call with its own failure handling, not
      # gated behind the comments call's outcome.
      pr_reviews_out="$(gh api "repos/{owner}/{repo}/pulls/$pr/reviews" --paginate --jq "$REVIEWS_JQ" 2>/dev/null)"
      pr_reviews_status=$?
      if [ "$pr_reviews_status" -ne 0 ]; then
        echo "warning: role-label-staleness couldn't read PR #$pr's reviews (no network or no access) — a verdict resting on an absence claim they could have contradicted will degrade to indeterminate." >&2
        PR_LOOKUP_FAILED=1
        mark_pr_failed "$pr"
        continue
      fi
      while IFS= read -r row; do
    tag="${row%%$'\t'*}"; rest="${row#*$'\t'}"
        [ "$tag" = "TEXT" ] || continue
        append_body "$rest" 3
      done <<<"$pr_reviews_out"
    done <<<"$candidate_prs"
  fi

  local ordered timestamp source ordinal encoded
  ordered="$(printf '%s' "$BODY_ROWS" | LC_ALL=C sort -t $'\t' -k1,1 -k2,2n -k3,3n)" || { PARSER_FAILED=1; return 0; }
  while IFS= read -r row; do
    timestamp="${row%%$'\t'*}"; row="${row#*$'\t'}"
    source="${row%%$'\t'*}"; row="${row#*$'\t'}"
    ordinal="${row%%$'\t'*}"; encoded="${row#*$'\t'}"
    [ -n "$ordinal" ] || continue
    raw_body="$(printf '%s' "$encoded" | LC_ALL=C tr '\001' '\n')"
    CORPUS_TEXT="$CORPUS_TEXT$raw_body$MARKER_SEP"
  done <<<"$ordered"
  return 0
}

# --- Cached record-v2 candidates (A31a/A32a/A37). Raw bodies have already
# been sorted chronologically; row order then supplies body/line tie order.
# A model is mandatory. Latest near-misses make the verdict indeterminate,
# while newer valid candidates supersede older near-misses for that stage.
KNOWN_MAX_RANK=-1
MALFORMED_FOUND=0
MALFORMED_LINE=""
PARSER_FAILED=0

# Cache the one scan. Newest candidate per readable stage wins; unknown-stage
# candidates have their own slot and remain unreadable. Quoted rows never vote.
scan_markers() {
  local text="$1" scan_out idx status token rest rank slot i
  local latest_status=("" "" "" "" "" "") latest_reason=("" "" "" "" "" "")
  if [ "$PARSER_FAILED" -eq 1 ] || ! scan_out="$(rec_scan_bundle model-record "$text")"; then
    PARSER_FAILED=1
    return 0
  fi
  while IFS=$'\t' read -r idx status token rest; do
    [ -n "$idx" ] || continue
    [ "$status" != quoted ] || continue
    slot=5
    if rank="$(stage_rank "$token" 2>/dev/null)"; then slot="$rank"; fi
    latest_status[$slot]="$status"
    latest_reason[$slot]="stage=$token: $rest"
  done <<<"$scan_out"
  for i in 0 1 2 3 4 5; do
    if [ "${latest_status[$i]}" = near-miss ]; then
      MALFORMED_FOUND=1
      [ -n "$MALFORMED_LINE" ] || MALFORMED_LINE="${latest_reason[$i]}"
    elif [ "${latest_status[$i]}" = ok ] && [ "$i" -lt 5 ]; then
      KNOWN_MAX_RANK="$i"
    fi
  done
}

# Appends $1 (a PR number) to FAILED_PRS exactly once, even if more than
# one of that PR's calls fails (comments AND reviews, say) — a dedup
# guard so the detail message never names the same PR twice.
mark_pr_failed() {
  local pr="$1"
  if [ -z "$FAILED_PRS" ]; then
    FAILED_PRS="$pr"
  elif ! grep -qxF "$pr" <<<"$FAILED_PRS"; then
    FAILED_PRS="$FAILED_PRS
$pr"
  fi
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
  echo "role-label-staleness: could not read issue #$issue_number (no network, no access, or the issue doesn't exist) — no verdict can be produced." >&2
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

  if [ "$LIVE_FAILED" -eq 1 ]; then
    # #423: dropping quoted text (live_text) failed on at least one body, so
    # what was read is incomplete; any verdict would rest on an absence
    # nobody checked.
    verdict="indeterminate"
    detail="reading the quoted text of a body on issue #$issue_number or a linked PR failed (live_text), so the model-record markers could not be read completely"
  elif [ "$PARSER_FAILED" -eq 1 ]; then
    # #392: the marker parser failed, so no marker was read; any verdict
    # would rest on an absence nobody checked.
    verdict="indeterminate"
    detail="the model-record marker parser (lib/model-record.sh) failed, so no marker on issue #$issue_number or a linked PR could be read"
  elif [ "$MALFORMED_FOUND" -eq 1 ]; then
    # A37/AC6: no fallback to an older valid candidate at this stage.
    verdict="indeterminate"
    detail="the latest model-record candidate on issue #$issue_number or a linked PR is a near-miss ($MALFORMED_LINE), so no earlier record is used"
  else
    label_r=-1
    single_label=""
    if [ "$role_label_count" -eq 1 ]; then
      single_label="$ROLE_LABELS_FOUND"
      label_r="$(label_rank "$single_label")"
    fi

    # Lookup-failure degrade — see the header comment's "Lookup
    # failures" note for the full asymmetric-degradation rule this
    # implements, now over three independent flags instead of one (REST
    # broke the original single-call shape into several independently-
    # failing calls). Only the two verdicts that rest on "nothing more
    # exists beyond what was read" are vulnerable: in-sync (label
    # at/ahead of known evidence) while not already at the ceiling
    # stage, or not-started (nothing at all). A verdict that is already
    # stale from what WAS read never degrades — more evidence can only
    # deepen staleness, never undo it.
    lookup_incomplete=0
    if [ "$ISSUE_COMMENTS_FAILED" -eq 1 ] || [ "$PR_DISCOVERY_FAILED" -eq 1 ] || [ "$PR_LOOKUP_FAILED" -eq 1 ]; then
      lookup_incomplete=1
    fi

    vulnerable=0
    if [ "$lookup_incomplete" -eq 1 ]; then
      if [ "$label_r" -eq -1 ] && [ "$KNOWN_MAX_RANK" -eq -1 ]; then
        vulnerable=1
      elif [ "$label_r" -ge 0 ] && [ "$label_r" -ge "$KNOWN_MAX_RANK" ] && [ "$label_r" -lt "$LAST_RANK" ]; then
        vulnerable=1
      fi
    fi

    if [ "$vulnerable" -eq 1 ]; then
      degrade_reasons=""
      if [ "$ISSUE_COMMENTS_FAILED" -eq 1 ]; then
        degrade_reasons="issue #$issue_number's own comments couldn't be read"
      fi
      if [ "$PR_DISCOVERY_FAILED" -eq 1 ]; then
        if [ -z "$degrade_reasons" ]; then
          degrade_reasons="the PR-discovery timeline lookup failed (linked PRs, if any, are unknown)"
        else
          degrade_reasons="$degrade_reasons; the PR-discovery timeline lookup failed (linked PRs, if any, are unknown)"
        fi
      fi
      if [ "$PR_LOOKUP_FAILED" -eq 1 ]; then
        failed_list="$(joined_list '#%s' "$FAILED_PRS")"
        if [ -z "$degrade_reasons" ]; then
          degrade_reasons="lookup failed for PR $failed_list"
        else
          degrade_reasons="$degrade_reasons; lookup failed for PR $failed_list"
        fi
      fi
      verdict="indeterminate"
      detail="issue #$issue_number's evidence is incomplete ($degrade_reasons), and what WAS read doesn't rule out a later stage that would make the current label stale"
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
