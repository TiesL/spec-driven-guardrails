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
# the fence-tracking bullets below and test/cases/
# s153_live_text_mawk_portability.sh.
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
#   4 — the PR itself could not be read (call A failed); no honest table
#       is possible without it
# Every other gh call's failure (PR comments/reviews, the CI check-runs
# call, a closing issue's own comments) never changes the exit code —
# it degrades its own gate to `indeterminate` and the run still exits 0.
# All diagnostics go to stderr, never interleaved into the table (the
# output's destination is a GitHub comment; a stray warning inside the
# table would break the Markdown).
#
# awk requirement (issue #319): live_text() below needs an awk whose
# regex engine greedily matches an unbounded-lower-bound interval and
# tolerates alternation grouped with one; known broken under mawk. See
# that function's own comment and test/cases/
# s153_live_text_mawk_portability.sh.
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

# live_text() — issue #308. Blanks quoted spans (fenced code blocks,
# inline code spans, blockquoted lines) out of a single body so every
# existing gate_* predicate can keep greping "the text" unchanged. The
# discriminator is enclosure, not line position: a real marker sitting at
# the end of a prose line is never touched (AC3), while the identical
# shape wrapped in backticks, a fence, or a leading `>` is (AC1). Content
# is blanked rather than the line deleted — nothing downstream depends on
# line counts, and blanking can't glue two tokens together across a
# removed line.
#
# Order is load-bearing: blockquote first (a `> ```` ` line must never be
# read as toggling fence state), then fence tracking, then code-span
# stripping on whatever's left. Bash 3.2-clean, no eval, one awk pass.
#
# Fence tracking (issue #308 Planning correction, D5/D6/D7/D10 — the
# original design's parity toggle ignored CommonMark's actual closing
# rule and leaked/false-negatived accordingly):
#   - Track the OPENING fence's character (` or ~) and run length.
#   - A fence only closes on a later line whose run is the SAME
#     character with length >= the opener's (D5/D6: a longer wrapper
#     around a shorter demo fence must not "close" on the inner one).
#   - CommonMark forbids an info string on a CLOSING fence — a fence-ish
#     line that closes must have nothing but trailing whitespace after
#     the run (D10: without this, a bare ``` opener followed by a
#     ```text-tagged line reads as a close and leaks the marker after
#     it). An OPENING fence may carry any info string.
#   - Indent is capped at 3 spaces (`^ ? ? ?`, three independently-
#     optional literal spaces — not the brace-interval `{0,3}`, which an
#     older mawk build doesn't parse at all; see the #319 note below),
#     CommonMark's own cap — 4+ is an indented code block, not a fence
#     (non-goal 1, fails open: D7). Deliberately literal spaces, never
#     `[ \t]*`: a tab counts as 4 columns of indentation in CommonMark, so
#     a tab-indented fence-ish line is the same indented-code-block case
#     and must not be treated as a fence. Do not "restore" \t here.
# Fence state is per-body (this function is called once per body) — an
# unclosed fence in one PR comment must never swallow a marker in the
# next one (AC3 fence isolation).
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

# quoted_suffix() — issue #308, AC4/AC7/D8. Called only from a gate's
# negative (not-evidenced) branch, to say, truthfully, that marker-shaped
# text was seen but only in quoted form, rather than leaving a reader to
# misread "nothing found" as "nothing was ever written". $1 MUST be the
# exact same delimiter-anchored ERE ("<!--[[:space:]]*<token>...") the
# caller just greped the LIVE corpus with for this same check — never a
# looser, unanchored token (D8). That constraint is what makes the
# wording sound rather than merely safe: in a negative branch the live
# grep has already failed, so a hit on the anchored ERE in
# BUNDLE_TEXT_RAW but not in the live corpus can only mean live_text()
# removed it, i.e. it really was enclosed — never bare prose (AC7),
# which this same anchored ERE never matches in the first place.
quoted_suffix() {
  local ere="$1"
  grep -qE "$ere" <<<"$BUNDLE_TEXT_RAW" \
    && printf '%s' " — marker-shaped text matching this gate does appear on PR #$pr_number, but only inside a code span, fenced block or blockquote, so it was read as quoted illustration and not counted as live evidence"
}

# --- collect(): the gh calls; interpretation-free, fills a fixed set of
# globals. Returns 1 only when call A (the PR itself) failed — the one
# failure that makes an honest table impossible.
#
# REST-only (issue #318, reusing role-label-staleness.sh's already-
# reviewed design rather than re-deriving it independently, per that
# issue's AC3): `gh pr view --json ...`, `gh issue view --json ...`, and
# `gh pr checks` are all GraphQL-backed under the hood regardless of
# which fields are requested, and GraphQL is blocked entirely from
# inside a Claude Code session (confirmed live, #318 AC1: this script
# used to exit 4 — "could not be read" — against every real PR tried
# from such a session). `closingIssuesReferences` has a second, separate
# defect even where GraphQL isn't blocked: GitHub only populates it for
# a PR whose base is the repository's default branch, so it was silently
# empty for every one of this epic's own release-branch PRs (#318 AC2,
# confirmed via the equivalent `closed_by_pull_requests` connection
# reading 0 for #313/#314 and #315/#316 alike).
#
# Every `gh` call below is `gh api repos/{owner}/{repo}/...` against an
# explicit REST endpoint — confirmed working from inside a Claude Code
# session (unlike any `--json` flag). `{owner}/{repo}` is `gh`'s own
# placeholder syntax, resolved from the checkout's `origin` remote; no
# extra call needed to learn it.
#
# Closing-issue discovery replaces the `closingIssuesReferences` field
# with the same closing-keyword scan role-label-staleness.sh's PR
# discovery already uses (there, issue-to-PR; here, PR-to-issue is
# simpler — the PR's own title+body is already in hand, no separate
# timeline/candidate-filtering step needed): a GitHub closing keyword
# (close/closes/closed, fix/fixes/fixed, resolve/resolves/resolved,
# optionally followed by `:`, then whitespace, then `#<issue-number>`),
# scanned case-insensitively against the PR's raw title and body — title
# included because every one of this epic's own release-branch PRs
# (#311/#312/#314/#316) carries the keyword only in the title, the same
# fact that shaped #320's fix to check-pr-issue-link.sh. This is a
# broadening beyond GitHub's own documented default-branch scope (body/
# commit messages only, not title) by design, same reasoning as #320.
CLOSING_KEYWORD_ERE='\b(close[sd]?|fix(e[sd])?|resolve[sd]?):?[[:space:]]+#[0-9]+\b'

# Sentinel transport (issue #308, D9): a body's internal line structure
# has to survive the TSV hop intact — blockquote detection needs to know
# which line a `>` starts, which `gsub("\n";" ")` used to destroy. Each
# body is put through three gsubs, in order: neutralise any literal
# U+0001 the body might already contain (so a body can never forge a
# line break downstream — belt and braces, also keeps the sentinel
# round-trip total), drop `\r` (GitHub bodies are CRLF; a trailing `\r`
# would defeat fence-close matching in live_text()'s info-string check),
# then fold real newlines into U+0001. `collect()` below turns the
# sentinel back into real newlines once per body (`tr '\001' '\n'`)
# before handing it to live_text(). The one-body-per-TSV-line framing
# (IFS=$'\t' read) is untouched.
#
# REST's PR object has no "MERGED" state of its own (only open/closed,
# plus a separate `.merged` boolean) — reconstructed here to the same
# three-value shape (OPEN/CLOSED/MERGED) render()/gate_merge_confirmation()
# already expect, so nothing downstream of collect() needed to change.
CALL_A_JQ='"HEAD\t"+(.head.sha//""),"STATE\t"+(if .merged then "MERGED" elif .state=="open" then "OPEN" else "CLOSED" end),"MERGEDAT\t"+(.merged_at//""),"MERGEDBY\t"+((.merged_by.login)//""),"TITLE\t"+((.title//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001")),"TEXT\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001"))'
CALL_A_COMMENTS_JQ='.[] | "TEXT\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001"))'
# PR reviews (issue #318, folding in the same fix role-label-staleness.sh
# needed as its own F-6 finding): this pipeline posts the Review stage's
# model-record marker as a PR review's own body, not a plain conversation
# comment — a source the original `gh pr view --json comments` call
# never read either. Same jq shape as comments (both are flat arrays of
# {body}), reused rather than re-derived.
CALL_A_REVIEWS_JQ='.[] | "TEXT\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001"))'
CALL_B_JQ='.check_runs[] | .name+"\t"+(if .status!="completed" then .status else (.conclusion//"unknown") end)+"\t"+(if .status!="completed" then "pending" elif .conclusion=="success" or .conclusion=="neutral" then "pass" elif .conclusion=="failure" or .conclusion=="timed_out" or .conclusion=="action_required" then "fail" elif .conclusion=="cancelled" then "cancel" elif .conclusion=="skipped" then "skipping" else "unknown_bucket_"+(.conclusion//"null") end)'
CALL_C_JQ='.[] | "TEXT\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001"))'

collect() {
  local pr_out pr_status

  pr_out="$(gh api "repos/{owner}/{repo}/pulls/$pr_number" \
    --jq "$CALL_A_JQ" 2>/dev/null)"
  pr_status=$?
  if [ "$pr_status" -ne 0 ]; then
    return 1
  fi

  # Quoting-aware collection (issue #308, fixing F34's debt entry from
  # #296). BUNDLE_TEXT below is now LIVE text only: every body passes
  # through live_text() first, which blanks fenced code blocks, inline
  # code spans and blockquoted lines before the text is ever appended.
  # Every existing gate_* predicate keeps greping this exactly as before
  # — the discriminator is enclosure (fence/span/blockquote), never line
  # position, so a real marker posted inline next to prose still
  # evidences (AC3), while the same marker shape merely quoted for
  # illustration no longer does (AC1). See live_text() below for the
  # mechanism and its known fail-open residue (PRD.md Technical debt).
  #
  # BUNDLE_TEXT_RAW is the unstripped counterpart: every body's text
  # before live_text() runs, concatenated with no per-source split. It
  # exists only so a gate's negative branch can say, truthfully, "this
  # was seen but only in quoted form" (AC4) via quoted_suffix() below,
  # rather than the plain "nothing found" a reader would otherwise
  # misread as "no marker was ever written". D8b (Architect, #308):
  # this soundness argument depends on BUNDLE_TEXT_RAW's scope matching
  # every gate that consults it — today every gate greps bundle-wide
  # BUNDLE_TEXT (or PR_TEXT/ISSUE_TEXTS via resolve_stage_marker(), also
  # bundle-wide in aggregate), and BUNDLE_TEXT_RAW is bundle-wide too, so
  # the elimination argument ("a RAW hit with no live hit means
  # live_text() removed it, i.e. it was genuinely enclosed") holds. A
  # future gate scoped to a narrower corpus (e.g. PR_TEXT alone) paired
  # with this bundle-wide RAW would wrongly call a marker "quoted" when
  # it's actually live elsewhere in the bundle — keep the scopes matched
  # if that ever changes.
  BUNDLE_TEXT=""
  BUNDLE_TEXT_RAW=""
  BUNDLE_HEAD_SHA=""
  BUNDLE_STATE=""
  BUNDLE_MERGED_AT=""
  BUNDLE_MERGED_BY=""
  BUNDLE_ISSUES=""
  # Soundness rule for every gate that reads BUNDLE_TEXT: when this flag
  # is 1 the corpus is provably incomplete, so no gate may return
  # `not-evidenced` on the strength of having found nothing — that
  # verdict must degrade to `indeterminate` (issue #299). Gate 4's CI
  # verdicts are a separate call with their own degradation and stay as
  # they are.
  #
  # Corrected invariant (issue #302 — the wording that used to live here
  # claimed gate 2's same-model `not-evidenced` never needed this guard
  # because "both markers were read". That holds only when at most one
  # closing issue is involved. `collect()` used to accumulate every named
  # issue's text into one shared blob, in `BUNDLE_ISSUES` order, before
  # prepending it to the PR text — so with >=2 closing issues, a *later*
  # issue's marker could silently outrank an *earlier* one (or a PR-side
  # one) purely by accumulation position, in either direction, including
  # a marker in an issue this flag says was never successfully fetched.
  # That's what P2-1 (META-REVIEW-PILOT-2.md) reproduced: the exact same
  # "both markers were read" corpus rendered `not-evidenced` or
  # `evidenced` depending only on whether a *second*, unread issue's
  # content happened to differ.
  #
  # Fixed two ways, per source (PR text, and each closing issue's own
  # text, kept apart in PR_TEXT/ISSUE_TEXTS/ISSUE_NUMS below) rather than
  # by accumulation order:
  #   1. gate_review_model (gate 2) resolves each stage's marker
  #      per-source. The PR-side marker, when present, always wins over
  #      a disagreeing issue-side one (issue #253 precedent: the PR
  #      records what actually happened, an issue can record an earlier
  #      plan) — that is not a conflict. Only disagreement BETWEEN two
  #      or more issues (the PR silent or absent) is a genuine,
  #      unresolvable conflict, reported `indeterminate` — a detected
  #      conflict, not a coin flip decided by which issue happened to
  #      be listed first.
  #   2. gate_review_model additionally degrades its same-model
  #      `not-evidenced` verdict to `indeterminate` when this flag is set
  #      AND more than one closing issue is named: an unread issue could
  #      still have supplied a marker that would have created exactly
  #      the kind of conflict (1) now catches.
  # Consulted by: gate_stage_models, gate_review_model, gate_review_marker.
  #
  # gate_review_marker (gate 3) never needed either fix: it already
  # resolves "which marker counts" by matching each candidate's `sha=`
  # against `headRefOid` across the whole corpus (R-B, #296's Architect
  # report) rather than by `tail -1` position, so accumulation order
  # never changes its answer, lookup failure or not. gate_review_model
  # (gate 2) has no such anchor available — `model-record` markers carry
  # no `sha=` to compare against `headRefOid` — so accumulation order
  # stayed a real risk there until fixed above.
  BUNDLE_ISSUE_LOOKUP_FAILED=0
  # Per-source text, kept apart precisely so gate_review_model never has
  # to trust accumulation order to know "which marker counts" (see the
  # comment above). PR_TEXT is the PR's own body+comments+reviews,
  # appended in that fixed order (body, then every comment, then every
  # review) — NOT true chronological order despite that once having
  # been true here (issue #336 round 1: reviews are a newer source than
  # this comment predates, and a review can genuinely postdate a later
  # comment; PRD.md's Technical debt table has the row). ISSUE_TEXTS/
  # ISSUE_NUMS are parallel arrays, one entry per successfully-fetched
  # closing issue, in the order fetched — an order gate_review_model must
  # not, and does not, treat as a recency signal.
  PR_TEXT=""
  ISSUE_TEXTS=()
  ISSUE_NUMS=()

  local tag rest raw_body live_body pr_title_raw=""
  while IFS=$'\t' read -r tag rest; do
    case "$tag" in
      HEAD) BUNDLE_HEAD_SHA="$rest" ;;
      STATE) BUNDLE_STATE="$rest" ;;
      MERGEDAT) BUNDLE_MERGED_AT="$rest" ;;
      MERGEDBY) BUNDLE_MERGED_BY="$rest" ;;
      TITLE) pr_title_raw="$(printf '%s' "$rest" | tr '\001' '\n')" ;;
      TEXT)
        raw_body="$(printf '%s' "$rest" | tr '\001' '\n')"
        live_body="$(live_text "$raw_body")"
        BUNDLE_TEXT="$BUNDLE_TEXT
$live_body"
        BUNDLE_TEXT_RAW="$BUNDLE_TEXT_RAW
$raw_body"
        ;;
    esac
  done <<<"$pr_out"

  # Closing-issue discovery (replaces closingIssuesReferences — see the
  # collect() header comment above for why): a closing keyword scanned
  # against the PR's own raw title+body, case-insensitive, deduplicated
  # and numerically sorted so the order gh happened to return keyword
  # occurrences in can never matter (same "no accumulation-order
  # dependence" discipline issue #302 already established for the rest
  # of this function).
  BUNDLE_ISSUES="$(printf '%s\n%s\n' "$pr_title_raw" "$raw_body" \
    | grep -oiE "$CLOSING_KEYWORD_ERE" \
    | grep -oE '[0-9]+' \
    | sort -un)"

  # PR comments and reviews (issue #318: reviews are a new source this
  # script never read before — see CALL_A_REVIEWS_JQ above). Order
  # (comments then reviews) is another flat, order-dependent append to
  # BUNDLE_TEXT/BUNDLE_TEXT_RAW/PR_TEXT — the same accumulation-order
  # exemption issue #302's comment above already documents for this
  # corpus (gate_review_model resolves per-source via
  # resolve_stage_marker(), not via this blob's tail-1 position).
  #
  # Found during PR #336's own pre-merge-review (round 1): a failure of
  # either call here used to go straight to `/dev/null` with no exit-
  # status check and no flag set at all — unlike every other `gh` call
  # in this function. Before this REST rewrite, PR comments were part
  # of the same single `gh pr view` call as the PR body, so a failure
  # there already hit Call A's own `return 1`; splitting comments and
  # reviews into separate calls introduced a failure mode this function
  # had never had to handle before, and initially didn't. Reproduced:
  # with every model-record marker living only in PR comments, a comments
  # fetch failure made gates 1-3 confidently report `not-evidenced`
  # instead of degrading — precisely the false-negative issue #299
  # exists to forbid. Fixed the same way a closing-issue comments
  # failure already was: warn on stderr and set
  # BUNDLE_ISSUE_LOOKUP_FAILED, the same corpus-incompleteness flag
  # every gate below already respects (it was never PR-issue-lookup-
  # specific in what it means, only in what set it until now).
  local pr_comments_out pr_reviews_out pr_comments_status pr_reviews_status
  pr_comments_out="$(gh api "repos/{owner}/{repo}/issues/$pr_number/comments" --paginate \
    --jq "$CALL_A_COMMENTS_JQ" 2>/dev/null)"
  pr_comments_status=$?
  if [ "$pr_comments_status" -ne 0 ]; then
    echo "warning: compliance-evidence couldn't consult PR #$pr_number's comments (no network or no access) — gates that search them may render as indeterminate rather than not-evidenced." >&2
    BUNDLE_ISSUE_LOOKUP_FAILED=1
    pr_comments_out=""
  fi
  pr_reviews_out="$(gh api "repos/{owner}/{repo}/pulls/$pr_number/reviews" --paginate \
    --jq "$CALL_A_REVIEWS_JQ" 2>/dev/null)"
  pr_reviews_status=$?
  if [ "$pr_reviews_status" -ne 0 ]; then
    echo "warning: compliance-evidence couldn't consult PR #$pr_number's reviews (no network or no access) — gates that search them may render as indeterminate rather than not-evidenced." >&2
    BUNDLE_ISSUE_LOOKUP_FAILED=1
    pr_reviews_out=""
  fi
  while IFS=$'\t' read -r tag rest; do
    [ "$tag" = "TEXT" ] || continue
    raw_body="$(printf '%s' "$rest" | tr '\001' '\n')"
    live_body="$(live_text "$raw_body")"
    BUNDLE_TEXT="$BUNDLE_TEXT
$live_body"
    BUNDLE_TEXT_RAW="$BUNDLE_TEXT_RAW
$raw_body"
  done <<<"$pr_comments_out
$pr_reviews_out"
  PR_TEXT="$BUNDLE_TEXT"

  # Closing-issue comments, gathered ahead of the PR's own text (order:
  # issue, then PR body/comments — model-record-gate.sh's PR #253 round 2
  # fix, inherited rather than re-earned: issue text ordered last let a
  # stray older marker outrank a genuinely newer one under `tail -1`).
  # BUNDLE_TEXT (built here) stays a flat, order-dependent blob — still
  # fine for gate_stage_models/gate_review_marker/gate_traceability,
  # which don't compare disagreeing per-source values the way gate 2
  # does. ISSUE_TEXTS/ISSUE_NUMS below are gate 2's own, order-safe view
  # of the same data.
  local issue_text="" issue_num issue_out issue_status
  if [ -n "$BUNDLE_ISSUES" ]; then
    while IFS= read -r issue_num; do
      [ -n "$issue_num" ] || continue
      issue_out="$(gh api "repos/{owner}/{repo}/issues/$issue_num/comments" --paginate \
        --jq "$CALL_C_JQ" 2>/dev/null)"
      issue_status=$?
      if [ "$issue_status" -ne 0 ]; then
        echo "warning: compliance-evidence couldn't consult issue #$issue_num (no network or no access) — gates that search its comments may render as indeterminate rather than not-evidenced." >&2
        BUNDLE_ISSUE_LOOKUP_FAILED=1
        continue
      fi
      local one_issue_text="" raw_body live_body
      while IFS=$'\t' read -r tag rest; do
        [ "$tag" = "TEXT" ] || continue
        raw_body="$(printf '%s' "$rest" | tr '\001' '\n')"
        live_body="$(live_text "$raw_body")"
        issue_text="$issue_text
$live_body"
        one_issue_text="$one_issue_text
$live_body"
        BUNDLE_TEXT_RAW="$BUNDLE_TEXT_RAW
$raw_body"
      done <<<"$issue_out"
      ISSUE_TEXTS+=("$one_issue_text")
      ISSUE_NUMS+=("$issue_num")
    done <<<"$BUNDLE_ISSUES"
  fi
  BUNDLE_TEXT="$issue_text
$BUNDLE_TEXT"

  # Call B — CI checks (issue #318: `gh pr checks` is GraphQL-backed too,
  # blocked the same as `gh pr view`/`gh issue view` — confirmed live).
  # REST's check-runs endpoint has a simpler, unambiguous exit-code
  # contract than `gh pr checks` ever did: it exits 0 whenever the API
  # call itself succeeds, whether that run has zero checks, all-passing
  # checks, or a failing one — there is no overloaded "exit code means
  # check outcome" behavior to work around here, so the elaborate
  # stderr-message sniffing the old call needed is gone; exit status
  # alone now tells call success from call failure.
  local checks_out checks_status
  checks_out="$(gh api "repos/{owner}/{repo}/commits/$BUNDLE_HEAD_SHA/check-runs" --paginate \
    --jq "$CALL_B_JQ" 2>/dev/null)"
  checks_status=$?

  if [ "$checks_status" -eq 0 ]; then
    BUNDLE_CHECKS="$checks_out"
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
  local missing_ere=""
  for stage in Discovery Planning Test Implementation; do
    # AC7 (issue #308, D4): anchored to a real HTML-comment opener. Bare
    # prose mentioning "model-record: stage=X" with no `<!--` is not a
    # marker at all and must read as not-evidenced, not indeterminate —
    # unreachable by quote-stripping since there's nothing to strip.
    if grep -qE "<!--[[:space:]]*model-record:[[:space:]]*stage=$stage\\b" <<<"$BUNDLE_TEXT"; then
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
      if [ -z "$missing_ere" ]; then
        missing_ere="<!--[[:space:]]*model-record:[[:space:]]*stage=$stage\\b"
      else
        missing_ere="$missing_ere|<!--[[:space:]]*model-record:[[:space:]]*stage=$stage\\b"
      fi
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
      printf '%s\t%s\n' "indeterminate" "stage(s) $missing appear to have no model-record marker on PR #$pr_number, but an evidence-corpus lookup failed, so absence can't be confirmed"
      return
    fi
    printf '%s\t%s\n' "not-evidenced" "no model-record marker found for stage(s) $missing, searched in PR #$pr_number's body/comments and its closing issue(s)$(quoted_suffix "$missing_ere")"
    return
  fi

  if [ "$all_same" -eq 1 ]; then
    printf '%s\t%s\n' "evidenced" "\`model-record\` markers on PR #$pr_number for Discovery, Planning, Test, Implementation (all \`$first_model\`)"
  else
    printf '%s\t%s\n' "evidenced" "\`model-record\` markers on PR #$pr_number for Discovery, Planning, Test, Implementation (${summary%,})"
  fi
}

# resolve_stage_marker() — issue #302 (R-B generalized, then corrected
# under R-1/R-3/R-4). Finds the `model-record` marker for stage $1
# independently in PR_TEXT and in each of ISSUE_TEXTS (order within
# each source is genuine chronology, from gh's own comment ordering —
# that part was never the bug), then decides which marker is
# authoritative using a real signal instead of accumulation order:
#
#   - The PR-side marker, when present, always wins over an issue-side
#     one it disagrees with. A PR marker records what actually
#     happened (e.g. which model actually ran the review); an
#     issue-side marker can be a plan recorded earlier (e.g. at
#     Planning time) that the PR then superseded — precedent from
#     issue #253. So PR-vs-issue disagreement is not a conflict.
#   - Disagreement BETWEEN two or more issues (the PR silent or absent
#     from this comparison) IS a genuine, unresolvable conflict —
#     neither issue is "the" outcome.
#   - "Disagreement" covers the normalized `model=`, the
#     `same-model-exception=` attribute, and well-formed-vs-malformed
#     (a marker that matched but has no quoted `model="..."`) alike —
#     not just the model field (R-3/R-4).
#   - When more than one issue-side marker exists and they agree, the
#     representative line is picked by sorting on issue number, not on
#     fetch order, so the result can't flip depending on which issue
#     `gh` happened to list first in `closingIssuesReferences`.
#
# Prints one tab-separated line on stdout:
#   none      <empty>                     — no source has this stage's marker
#   single    <the winning marker line>   — PR wins, or issue sources agree,
#                                            or only one source matched at all
#   conflict  <"source: `model`; ..." >   — two+ ISSUE sources matched with
#                                            genuinely different markers
resolve_stage_marker() {
  local stage="$1"
  local pr_line="" line model src_num i

  line="$(grep -oE "<!--[[:space:]]*model-record:[[:space:]]*stage=${stage}[^>]*-->" <<<"$PR_TEXT" | tail -1)"
  [ -n "$line" ] && pr_line="$line"

  # Note on order: unlike the old `tail -1`-over-the-flat-corpus code,
  # nothing below needs the issues visited in a particular order.
  # Conflict detection only asks whether the SET of issue-side values
  # agrees (order can't change that answer), and once they agree any
  # one of them is an equally valid representative to return — so no
  # sort-by-issue-number step is needed here (an earlier version tried
  # one and tripped a bash-3.2 `set -u` empty-array bug for no benefit).
  local -a marker_labels=() marker_lines=() marker_models=() marker_exceptions=()
  for i in "${!ISSUE_TEXTS[@]}"; do
    line="$(grep -oE "<!--[[:space:]]*model-record:[[:space:]]*stage=${stage}[^>]*-->" <<<"${ISSUE_TEXTS[$i]}" | tail -1)"
    if [ -n "$line" ]; then
      src_num="${ISSUE_NUMS[$i]}"
      model="$(grep -oE 'model="[^"]*"' <<<"$line" | head -1 | sed 's/^model="//; s/"$//')"
      marker_labels+=("issue #$src_num")
      marker_lines+=("$line")
      marker_models+=("$model")
      marker_exceptions+=("$(grep -oE 'same-model-exception="[^"]*"' <<<"$line" | head -1)")
    fi
  done

  if [ -z "$pr_line" ] && [ "${#marker_lines[@]}" -eq 0 ]; then
    printf '%s\t%s\n' "none" ""
    return
  fi

  # Inter-issue conflict check only — the PR is deliberately excluded
  # (R-1): PR-vs-issue disagreement is resolved by PR precedence below,
  # never treated as a conflict.
  local issues_conflict=0
  if [ "${#marker_lines[@]}" -gt 1 ]; then
    local first_norm first_exc norm exc
    first_norm="$(normalize_model "${marker_models[0]}")"
    first_exc="${marker_exceptions[0]}"
    for i in "${!marker_models[@]}"; do
      norm="$(normalize_model "${marker_models[$i]}")"
      exc="${marker_exceptions[$i]}"
      if [ "$norm" != "$first_norm" ] || [ "$exc" != "$first_exc" ]; then
        issues_conflict=1
      fi
    done
  fi

  if [ "$issues_conflict" -eq 1 ]; then
    local detail="" sep=""
    if [ -n "$pr_line" ]; then
      model="$(grep -oE 'model="[^"]*"' <<<"$pr_line" | head -1 | sed 's/^model="//; s/"$//')"
      detail="PR #$pr_number: \`${model:-<malformed>}\`"
      sep="; "
    fi
    for i in "${!marker_lines[@]}"; do
      detail="${detail}${sep}${marker_labels[$i]}: \`${marker_models[$i]:-<malformed>}\`"
      sep="; "
    done
    printf '%s\t%s\n' "conflict" "$detail"
    return
  fi

  if [ -n "$pr_line" ]; then
    printf '%s\t%s\n' "single" "$pr_line"
    return
  fi

  printf '%s\t%s\n' "single" "${marker_lines[0]}"
}

gate_review_model() {
  local impl_status impl_line review_status review_line
  local impl_model review_model impl_norm review_norm exception_val
  local total_issues=0

  IFS=$'\t' read -r impl_status impl_line <<<"$(resolve_stage_marker Implementation)"
  IFS=$'\t' read -r review_status review_line <<<"$(resolve_stage_marker Review)"

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

  if [ -n "$BUNDLE_ISSUES" ]; then
    total_issues="$(printf '%s\n' "$BUNDLE_ISSUES" | grep -c '.')"
  fi

  if [ "$impl_status" = "none" ] || [ "$review_status" = "none" ]; then
    if [ "$BUNDLE_ISSUE_LOOKUP_FAILED" -eq 1 ]; then
      printf '%s\t%s\n' "indeterminate" "no \`stage=Review\` and/or \`stage=Implementation\` model-record marker found on PR #$pr_number, but an evidence-corpus lookup failed, so absence can't be confirmed"
      return
    fi
    local none_ere=""
    if [ "$impl_status" = "none" ]; then
      none_ere="<!--[[:space:]]*model-record:[[:space:]]*stage=Implementation\\b"
    fi
    if [ "$review_status" = "none" ]; then
      if [ -z "$none_ere" ]; then
        none_ere="<!--[[:space:]]*model-record:[[:space:]]*stage=Review\\b"
      else
        none_ere="$none_ere|<!--[[:space:]]*model-record:[[:space:]]*stage=Review\\b"
      fi
    fi
    printf '%s\t%s\n' "not-evidenced" "no \`stage=Review\` and/or \`stage=Implementation\` model-record marker found on PR #$pr_number$(quoted_suffix "$none_ere")"
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

  # issue #302: unlike the checks above, this branch used to fire
  # unconditionally on "both markers found" — sound for <=1 closing
  # issue (nothing else could have contributed a marker), unsound for
  # >=2: an unread issue, OR (issue #336 round 1) a PR comments/reviews
  # fetch failure — either sets BUNDLE_ISSUE_LOOKUP_FAILED=1 now — could
  # have supplied a marker resolve_stage_marker never saw, which — had
  # it been read — might have created exactly the kind of conflict
  # caught above instead of this same-model match.
  if [ "$BUNDLE_ISSUE_LOOKUP_FAILED" -eq 1 ] && [ "$total_issues" -gt 1 ]; then
    printf '%s\t%s\n' "indeterminate" "\`stage=Review\` and \`stage=Implementation\` markers found on PR #$pr_number both record \`$review_model\` with no \`same-model-exception\`, but PR #$pr_number names more than one closing issue and an evidence-corpus lookup failed, so a superseding marker there can't be ruled out"
    return
  fi

  printf '%s\t%s\n' "not-evidenced" "\`stage=Review\` and \`stage=Implementation\` markers on PR #$pr_number both record \`$review_model\` with no \`same-model-exception\`"
}

gate_review_marker() {
  local strict_matches loose_present=0
  # AC7 (issue #308, D4): anchored to a real HTML-comment opener — same
  # reasoning as gate_stage_models above. loose_ere is reused below by
  # quoted_suffix() (D8: must be the identical ERE the live grep used).
  local loose_ere='<!--[[:space:]]*pre-merge-review:done'
  strict_matches="$(grep -oE '<!--[[:space:]]*pre-merge-review:done[[:space:]]+sha=[0-9a-fA-F]{40}[[:space:]]*-->' <<<"$BUNDLE_TEXT")"

  if grep -qE "$loose_ere" <<<"$BUNDLE_TEXT"; then
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

  printf '%s\t%s\n' "not-evidenced" "no \`pre-merge-review:done\` marker found on PR #$pr_number$(quoted_suffix "$loose_ere")"
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
