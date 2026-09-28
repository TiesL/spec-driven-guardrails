#!/usr/bin/env bash
# test/compliance-evidence-fixture.sh — shared fixture constants + shape
# helpers for S150 (test/cases/s150_compliance_evidence.sh) and S151
# (test/cases/s151_compliance_evidence_quoting.sh), issue #308 (QA's
# fixture-hygiene rule extended, Architect's own rule for #296/#302).
#
# Extracted so a drift in compliance-evidence.sh's gh endpoint or --jq
# expression is a one-line fix here instead of a synchronized edit
# across both test files. Source, don't execute — expects sandbox_create
# (test/lib.sh) to already have run, so $SANDBOX is set.
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

# --- The gh argv strings compliance-evidence.sh's implementation issues
# (issue #318: REST-only — `gh pr view`/`gh pr checks`/`gh issue view`
# are all GraphQL-backed and 403 from inside a Claude Code session,
# confirmed live), captured by running the real script against a
# recording fake gh, never retyped from the source by hand (Architect's
# fixture-hygiene rule, #296/#302 — the REST rewrite for #318 is exactly
# the kind of drift this file exists to absorb in one place).
#
# Call A used to be one call (`gh pr view --json body,comments,
# closingIssuesReferences,headRefOid,mergedAt,mergedBy,state`); it is
# now three separate REST calls below (the PR object, its comments, and
# its reviews — reviews are a new evidence source, #318's own F-6 fix,
# folding in the same gap role-label-staleness.sh's review already
# found: this pipeline posts the Review stage's marker as a PR review's
# own body, which nothing here read before). `closingIssuesReferences`
# no longer exists at all: closing-issue discovery is a keyword scan
# (CLOSING_KEYWORD_ERE in compliance-evidence.sh) against the PR's own
# title+body, done in bash after Call A's response comes back, not a
# separate gh call — so a fixture's PR title (or body) must itself carry
# the closing keyword text for #265/#266 discovery to fire; there is no
# `ISSUE\t<n>` tag to emit directly any more.
CALL_A_ARGS='api repos/{owner}/{repo}/pulls/279 --jq "HEAD\t"+(.head.sha//""),"STATE\t"+(if .merged then "MERGED" elif .state=="open" then "OPEN" else "CLOSED" end),"MERGEDAT\t"+(.merged_at//""),"MERGEDBY\t"+((.merged_by.login)//""),"TITLE\t"+((.title//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001")),"TEXT\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001"))'
CALL_A_COMMENTS_ARGS='api repos/{owner}/{repo}/issues/279/comments --paginate --jq .[] | "TEXT\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001"))'
CALL_A_REVIEWS_ARGS='api repos/{owner}/{repo}/pulls/279/reviews --paginate --jq .[] | "TEXT\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001"))'
CALL_C265_ARGS='api repos/{owner}/{repo}/issues/265/comments --paginate --jq .[] | "TEXT\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001"))'
CALL_C266_ARGS='api repos/{owner}/{repo}/issues/266/comments --paginate --jq .[] | "TEXT\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001"))'

# Call B's endpoint is commit-scoped, not PR-scoped the way `gh pr
# checks <pr>` was — a structural difference from every other call
# above, which stays keyed to a fixed PR/issue number in every case.
# CALL_B_TAIL is the sha-independent remainder; run_build_fake_gh's
# optional sha argument (below) is what lets each case's __CALL_B__
# placeholder resolve against whatever HEAD sha that same case's own
# __CALL_A__ arm returns, without every case needing its own bespoke
# placeholder name.
CALL_B_TAIL='--paginate --jq .check_runs[] | .name+"\t"+(if .status!="completed" then .status else (.conclusion//"unknown") end)+"\t"+(if .status!="completed" then "pending" elif .conclusion=="success" or .conclusion=="neutral" then "pass" elif .conclusion=="failure" or .conclusion=="timed_out" or .conclusion=="action_required" then "fail" elif .conclusion=="cancelled" then "cancel" elif .conclusion=="skipped" then "skipping" else "unknown_bucket_"+(.conclusion//"null") end)'
DEFAULT_HEAD_SHA="6e00a8c38bf18f19cd53084b5c77ae476c1e74e6"

pattern_a="'$CALL_A_ARGS'"
pattern_a_comments="'$CALL_A_COMMENTS_ARGS'"
pattern_a_reviews="'$CALL_A_REVIEWS_ARGS'"
pattern_c265="'$CALL_C265_ARGS'"
pattern_c266="'$CALL_C266_ARGS'"
pattern_b_for_sha() {
  printf "'api repos/{owner}/{repo}/commits/%s/check-runs %s'" "$1" "$CALL_B_TAIL"
}

# Reads a heredoc-style fake-gh script body from stdin — never wrapped in
# $(...) at the call site. A heredoc containing a literal ')' (unavoidable
# here: case-arm syntax, and this collector's own jq expressions, are full
# of them) breaks bash's parser when nested inside a command substitution
# — the parser treats the first such ')' as closing the substitution,
# before the heredoc terminator is ever reached, well before anything
# runs. Redirecting to a file instead of capturing via $(...) sidesteps
# that entirely. __CALL_A__/__CALL_A_COMMENTS__/__CALL_A_REVIEWS__/
# __CALL_C265__/__CALL_C266__/__CALL_B__ are replaced with the exact
# argv patterns above via plain substring replacement (also apostrophe/
# quote-safe: heredoc content is never re-parsed as shell syntax).
#
# __CALL_B__ resolves against $1 (default DEFAULT_HEAD_SHA) — pass the
# sha explicitly only when a case's own __CALL_A__ arm returns a
# different HEAD than the default (most of S150's cases do; S151's
# never do).
FAKEGH_OUT="$SANDBOX/fakegh-out"
run_build_fake_gh() {
  local sha="${1:-$DEFAULT_HEAD_SHA}"
  local body
  body="$(cat)"
  body="${body//__CALL_A__/$pattern_a}"
  body="${body//__CALL_A_COMMENTS__/$pattern_a_comments}"
  body="${body//__CALL_A_REVIEWS__/$pattern_a_reviews}"
  body="${body//__CALL_C265__/$pattern_c265}"
  body="${body//__CALL_C266__/$pattern_c266}"
  body="${body//__CALL_B__/$(pattern_b_for_sha "$sha")}"
  fake_gh_bin "$body" > "$FAKEGH_OUT"
}

# --- Cross-cutting assertions (§2.3), run against every case's output:
# the exact table shape, the closed status vocabulary, and non-empty
# Evidence cells (AC2 — which Architect's own fixture contract had no
# arm for at all).
GATE1="Per-stage model/effort recorded (Discovery, Planning, Test, Implementation)"
GATE2="Review used a different or at-least-as-capable model, or carries an explicit exception"
GATE3="Quality review before merge, with findings in the PR"
GATE4="CI green"
GATE5="Traceability link 3 (PR ↔ issue)"
GATE6="Ties' explicit merge confirmation"

assert_table_shape() {
  local label="$1" output="$2"
  local lines=() line
  while IFS= read -r line; do lines+=("$line"); done <<<"$output"

  if [ "${lines[0]:-}" != "| Gate | Status | Evidence |" ]; then
    fail "$label — header line wrong: '${lines[0]:-<missing>}'"
  fi
  if [ "${lines[1]:-}" != "| --- | --- | --- |" ]; then
    fail "$label — separator line wrong: '${lines[1]:-<missing>}'"
  fi
  if [ "${#lines[@]}" -ne 8 ]; then
    fail "$label — expected exactly 8 lines (header+separator+6 rows), got ${#lines[@]}: $output"
    return 1
  fi

  local expected=("$GATE1" "$GATE2" "$GATE3" "$GATE4" "$GATE5" "$GATE6")
  local i
  for i in 0 1 2 3 4 5; do
    local row="${lines[$((i + 2))]}"
    local gate status evidence
    gate="$(printf '%s' "$row" | sed -E 's/^\| (.*) \| ([a-z-]+) \| (.*) \|$/\1/')"
    status="$(printf '%s' "$row" | sed -E 's/^\| (.*) \| ([a-z-]+) \| (.*) \|$/\2/')"
    evidence="$(printf '%s' "$row" | sed -E 's/^\| (.*) \| ([a-z-]+) \| (.*) \|$/\3/')"

    if [ "$gate" != "${expected[$i]}" ]; then
      fail "$label — row $((i + 1)) gate label wrong: got '$gate', expected '${expected[$i]}'"
    fi
    case "$status" in
      evidenced | not-evidenced | unverifiable-from-artifacts | indeterminate) : ;;
      *) fail "$label — row $((i + 1)) status '$status' is not one of the four closed-vocabulary values (AC8)" ;;
    esac
    local trimmed
    trimmed="$(printf '%s' "$evidence" | sed -E 's/^ +| +$//g')"
    if [ -z "$trimmed" ]; then
      fail "$label — row $((i + 1)) (gate '$gate', status '$status') has an empty Evidence cell (AC2)"
    fi
  done
}

# The status column of a given gate's row (1-6), for cases that assert on
# one specific gate rather than the whole table.
row_status() {
  local output="$1" n="$2"
  printf '%s\n' "$output" | sed -n "$((n + 2))p" | sed -E 's/^\| .* \| ([a-z-]+) \| .* \|$/\1/'
}

row_evidence() {
  local output="$1" n="$2"
  printf '%s\n' "$output" | sed -n "$((n + 2))p" | sed -E 's/^\| .* \| [a-z-]+ \| (.*) \|$/\1/'
}
