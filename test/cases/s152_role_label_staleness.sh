#!/usr/bin/env bash
# S152 — role-label-staleness.sh detects role:<name> label staleness for
# one issue (issue #315, epic #295 W3).
# Covers: F35
#
# Single-file, S130-style inline fixtures (QA's own call in issue #315's
# Test comment: this script has one call shape family — issue + N
# candidate PRs — and one output line, not compliance-evidence.sh's six
# gates/three call shapes, so a separate shared *-fixture.sh file
# doesn't buy anything here).
#
# Rewritten twice for the REST-only redesign and its round-2 correctness
# fixes (Architect's issue #315 comment, 2026-09-28; Reviewer's PR #316
# round-2 review, same day): every call is `gh api` against an explicit
# REST endpoint — issue body+labels, issue comments, the issue's
# timeline for candidate PRs, each candidate's current PR title+body for
# the closing-keyword filter, and each kept PR's comments AND reviews
# (the latter added for F-6 — this pipeline posts Review-stage markers
# as a PR review body, not a plain comment).
#
# Every fixture below fixes the issue number at #400 (never a real issue
# in this repo) and candidate PR numbers at #501/#502. The exact argv
# strings (CALL_*_ARGS below) were captured by observing role-label-
# staleness.sh's own real argv against a recording fake gh, never
# retyped from the source by hand (Architect's fixture-hygiene rule,
# #296/#302) — a drift in the script's endpoints or --jq expressions
# shows up here as a fallthrough failure, not a silent false pass.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

script="$TEST_REPO_ROOT/role-label-staleness.sh"
[ -x "$script" ] || { fail "S152 — role-label-staleness.sh is missing or not executable"; test_done; }

sandbox_create
trap sandbox_destroy EXIT

# --- Fixed argv patterns (captured, not retyped — see header). Every
# case arm below is single-quoted defensively (none of these actually
# contain a literal `$`, unlike the old GraphQL-based design, but the
# convention costs nothing and keeps every future edit to this file
# safe by construction if one ever does).
CALL_ISSUE_ARGS='api repos/{owner}/{repo}/issues/400 --jq ("BODY\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001"))),(.labels[]? | "LABEL\t"+.name)'
CALL_ISSUE_COMMENTS_ARGS='api repos/{owner}/{repo}/issues/400/comments --paginate --jq .[] | "TEXT\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001"))'
# issue #317 F-8: a new, unconditional call the script makes once per
# run (right before the timeline call, regardless of the comments
# call's own outcome) — this repo's own identity, used to filter
# cross-repo timeline events out of PR discovery. Every fixture below
# that reaches this point answers it with the same fixed fake identity
# ("owner/repo"), which CALL_TIMELINE_ARGS' own jq filter now embeds
# literally, exactly as the real script splices its own fetched value
# into its timeline jq expression.
CALL_REPO_IDENTITY_ARGS='api repos/{owner}/{repo} --jq .full_name'
CALL_TIMELINE_ARGS='api repos/{owner}/{repo}/issues/400/timeline --paginate --jq .[] | select(.event=="cross-referenced" and .source.issue.pull_request != null and .source.issue.repository.full_name == "owner/repo") | "PR\t"+(.source.issue.number|tostring)'
# The fallback shape the script sends when the repo-identity call
# itself fails (fail-open per F-8's own design): the ORIGINAL,
# unfiltered timeline jq expression, with no repository clause at all
# — captured the same way, by observing the real script's argv against
# a recording fake gh with only the identity call answered to fail.
CALL_TIMELINE_UNFILTERED_ARGS='api repos/{owner}/{repo}/issues/400/timeline --paginate --jq .[] | select(.event=="cross-referenced" and .source.issue.pull_request != null) | "PR\t"+(.source.issue.number|tostring)'
CALL_PR501_TITLEBODY_ARGS='api repos/{owner}/{repo}/pulls/501 --jq ("TITLE\t"+((.title//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001"))),("BODY\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001")))'
CALL_PR501_COMMENTS_ARGS='api repos/{owner}/{repo}/issues/501/comments --paginate --jq .[] | "TEXT\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001"))'
CALL_PR501_REVIEWS_ARGS='api repos/{owner}/{repo}/pulls/501/reviews --paginate --jq .[] | "TEXT\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001"))'
CALL_PR502_TITLEBODY_ARGS='api repos/{owner}/{repo}/pulls/502 --jq ("TITLE\t"+((.title//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001"))),("BODY\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001")))'
CALL_PR502_COMMENTS_ARGS='api repos/{owner}/{repo}/issues/502/comments --paginate --jq .[] | "TEXT\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001"))'
CALL_PR502_REVIEWS_ARGS='api repos/{owner}/{repo}/pulls/502/reviews --paginate --jq .[] | "TEXT\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001"))'

pattern_issue="'$CALL_ISSUE_ARGS'"
pattern_issue_comments="'$CALL_ISSUE_COMMENTS_ARGS'"
pattern_repo_identity="'$CALL_REPO_IDENTITY_ARGS'"
pattern_timeline="'$CALL_TIMELINE_ARGS'"
pattern_timeline_unfiltered="'$CALL_TIMELINE_UNFILTERED_ARGS'"
pattern_pr501_titlebody="'$CALL_PR501_TITLEBODY_ARGS'"
pattern_pr501_comments="'$CALL_PR501_COMMENTS_ARGS'"
pattern_pr501_reviews="'$CALL_PR501_REVIEWS_ARGS'"
pattern_pr502_titlebody="'$CALL_PR502_TITLEBODY_ARGS'"
pattern_pr502_comments="'$CALL_PR502_COMMENTS_ARGS'"
pattern_pr502_reviews="'$CALL_PR502_REVIEWS_ARGS'"

FAKEGH_OUT="$SANDBOX/fakegh-out"
WITNESS="$SANDBOX/witness"

# Reads a heredoc-style list of case ARMS (not a full case statement) from
# stdin — never wrapped in $(...) at the call site (a literal ')' inside
# the heredoc, unavoidable in case-arm syntax and this script's own --jq
# expressions, would otherwise close the surrounding command substitution
# before the heredoc terminator is ever reached). __CALL_ISSUE__ etc. are
# replaced with the exact argv patterns above via plain substring
# replacement — quote-safe, since heredoc content is never re-parsed as
# shell syntax at substitution time.
#
# F-2 fix (PR #316 Reviewer, round 1): the ONE `case "$*" in ... esac` and
# the witness-plus-exit-1 fallthrough are supplied ONCE, here, centrally —
# never per-fixture. A fixture below supplies only the arms it wants to
# answer; any call it has no arm for correctly falls through to the
# witness line and exit 1 (a fixture's own missing arm is how a call is
# made to "fail" for that test, same as every other fake_gh_bin fixture
# in this repo). An earlier version had each fixture supply its own
# trailing `esac; exit 1` *after* which the witness line was appended —
# unreachable, since a case statement's own `exit 1` inside the fixture
# already terminated the process first. This version's witness line
# sits *inside* the one case statement's fallthrough, so it's reached by
# construction whenever no arm matches, and never otherwise (a matched
# arm's own `exit 0 ;;` always exits the script before the fallthrough
# is reached, since a case arm's `exit` ends the whole process, not the
# case statement). Reviewer's round-2 review re-verified this by
# mutation (injecting an unexpected write call) and confirmed it's now
# genuinely reachable.
run_build_fake_gh() {
  local arms body
  arms="$(cat)"
  arms="${arms//__CALL_ISSUE__/$pattern_issue}"
  arms="${arms//__CALL_ISSUE_COMMENTS__/$pattern_issue_comments}"
  arms="${arms//__CALL_REPO_IDENTITY__/$pattern_repo_identity}"
  arms="${arms//__CALL_TIMELINE_UNFILTERED__/$pattern_timeline_unfiltered}"
  arms="${arms//__CALL_TIMELINE__/$pattern_timeline}"
  arms="${arms//__CALL_PR501_TITLEBODY__/$pattern_pr501_titlebody}"
  arms="${arms//__CALL_PR501_COMMENTS__/$pattern_pr501_comments}"
  arms="${arms//__CALL_PR501_REVIEWS__/$pattern_pr501_reviews}"
  arms="${arms//__CALL_PR502_TITLEBODY__/$pattern_pr502_titlebody}"
  arms="${arms//__CALL_PR502_COMMENTS__/$pattern_pr502_comments}"
  arms="${arms//__CALL_PR502_REVIEWS__/$pattern_pr502_reviews}"

  body='case "$*" in'
  body="$body
$arms
esac
printf 'UNEXPECTED: %s\n' \"\$*\" >> '$WITNESS'
exit 1"

  : > "$WITNESS"
  fake_gh_bin "$body" > "$FAKEGH_OUT"
}

# Verdict-line shape assertion (mirrors compliance-evidence-fixture.sh's
# assert_table_shape, for this script's one-line output instead of a
# six-row table): exactly the documented format, status one of the four
# closed values, and a non-empty parenthesized detail.
assert_verdict_shape() {
  local label="$1" output="$2"
  case "$output" in
    'role-label-staleness: issue #400 — '*' ('*')')
      : ;;
    *)
      fail "$label — verdict line doesn't match the documented shape: $output"
      return 1
      ;;
  esac
  local status
  status="$(printf '%s' "$output" | sed -E 's/^role-label-staleness: issue #400 — ([a-z-]+) \(.*\)$/\1/')"
  case "$status" in
    not-started|in-sync|stale|indeterminate) : ;;
    *) fail "$label — status '$status' is outside the closed four-value vocabulary" ;;
  esac
  printf '%s' "$status"
}

# =========================================================================
# (a) AC2 — label matches the latest evidenced stage exactly -> in-sync.
# Full success: every call the script makes is answered (including the
# round-2-added reviews call, empty here), so the witness must stay
# empty.
# =========================================================================
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
__CALL_ISSUE__)
  printf 'LABEL\trole:qa\n'
  exit 0 ;;
__CALL_ISSUE_COMMENTS__)
  exit 0 ;;
__CALL_REPO_IDENTITY__)
  printf 'owner/repo\n'
  exit 0 ;;
__CALL_TIMELINE__)
  printf 'PR\t501\n'
  exit 0 ;;
__CALL_PR501_TITLEBODY__)
  printf 'TITLE\t\nBODY\tCloses #400\n'
  exit 0 ;;
__CALL_PR501_COMMENTS__)
  printf 'TEXT\t<!-- model-record: stage=Test model="claude-sonnet-5" effort="medium" -->\n'
  exit 0 ;;
__CALL_PR501_REVIEWS__)
  exit 0 ;;
GHEOF
fakebin_a="$(cat "$FAKEGH_OUT")"
output_a="$(PATH="$fakebin_a:$PATH" "$script" 400)"; status_a=$?
[ "$status_a" -eq 0 ] || fail "S152 (a) — expected exit 0, got $status_a"
[ "$(assert_verdict_shape 'S152 (a)' "$output_a")" = "in-sync" ] || fail "S152 (a) — expected in-sync (label=role:qa matches stage=Test exactly), got: $output_a"
[ -s "$WITNESS" ] && fail "S152 (a) — unexpected gh call(s): $(cat "$WITNESS")"

# =========================================================================
# (b) AC1 — label names an earlier stage than the latest evidence ->
# stale, naming both the label present and the label the evidenced stage
# implies (AC1's own worked phrasing).
# =========================================================================
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
__CALL_ISSUE__)
  printf 'LABEL\trole:architect\n'
  exit 0 ;;
__CALL_ISSUE_COMMENTS__)
  exit 0 ;;
__CALL_REPO_IDENTITY__)
  printf 'owner/repo\n'
  exit 0 ;;
__CALL_TIMELINE__)
  printf 'PR\t501\n'
  exit 0 ;;
__CALL_PR501_TITLEBODY__)
  printf 'TITLE\t\nBODY\tCloses #400\n'
  exit 0 ;;
__CALL_PR501_COMMENTS__)
  printf 'TEXT\t<!-- model-record: stage=Test model="claude-sonnet-5" effort="medium" -->\n'
  exit 0 ;;
__CALL_PR501_REVIEWS__)
  exit 0 ;;
GHEOF
fakebin_b="$(cat "$FAKEGH_OUT")"
output_b="$(PATH="$fakebin_b:$PATH" "$script" 400)"; status_b=$?
[ "$status_b" -eq 0 ] || fail "S152 (b) — expected exit 0, got $status_b"
[ "$(assert_verdict_shape 'S152 (b)' "$output_b")" = "stale" ] || fail "S152 (b) — expected stale (role:architect behind stage=Test), got: $output_b"
expected_b='role-label-staleness: issue #400 — stale (issue #400 carries role:architect, but a stage=Test marker already exists — expected role:qa)'
[ "$output_b" = "$expected_b" ] || fail "S152 (b) — exact detail text wrong (AC1's own worked phrasing):
expected: $expected_b
got:      $output_b"
[ -s "$WITNESS" ] && fail "S152 (b) — unexpected gh call(s): $(cat "$WITNESS")"

# =========================================================================
# (c) — label present, zero markers exist anywhere -> in-sync, NOT
# stale, NOT indeterminate. The sharp-edge arm QA's Test comment calls
# out by name: a fresh label with no evidence at all is the normal
# starting state.
# =========================================================================
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
__CALL_ISSUE__)
  printf 'LABEL\trole:product\n'
  exit 0 ;;
__CALL_ISSUE_COMMENTS__)
  exit 0 ;;
__CALL_REPO_IDENTITY__)
  printf 'owner/repo\n'
  exit 0 ;;
__CALL_TIMELINE__)
  exit 0 ;;
GHEOF
fakebin_c="$(cat "$FAKEGH_OUT")"
output_c="$(PATH="$fakebin_c:$PATH" "$script" 400)"; status_c=$?
[ "$status_c" -eq 0 ] || fail "S152 (c) — expected exit 0, got $status_c"
[ "$(assert_verdict_shape 'S152 (c)' "$output_c")" = "in-sync" ] || fail "S152 (c) — expected in-sync (label present, zero markers anywhere), got: $output_c"
[ -s "$WITNESS" ] && fail "S152 (c) — unexpected gh call(s): $(cat "$WITNESS")"

# =========================================================================
# (d) AC3/AC4 — no label at all: two distinct cases, plus the direct
# boundary between them (one marker appears).
# =========================================================================
# (d1) AC3 — no label, no marker anywhere -> not-started, not stale.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
__CALL_ISSUE__)
  exit 0 ;;
__CALL_ISSUE_COMMENTS__)
  exit 0 ;;
__CALL_REPO_IDENTITY__)
  printf 'owner/repo\n'
  exit 0 ;;
__CALL_TIMELINE__)
  exit 0 ;;
GHEOF
fakebin_d1="$(cat "$FAKEGH_OUT")"
output_d1="$(PATH="$fakebin_d1:$PATH" "$script" 400)"; status_d1=$?
[ "$status_d1" -eq 0 ] || fail "S152 (d1) — expected exit 0, got $status_d1"
[ "$(assert_verdict_shape 'S152 (d1)' "$output_d1")" = "not-started" ] || fail "S152 (d1) — expected not-started (no label, no marker), got: $output_d1"
[ -s "$WITNESS" ] && fail "S152 (d1) — unexpected gh call(s): $(cat "$WITNESS")"

# (d2) AC4 — no label, but at least one live marker exists (on the issue
# body itself) -> stale, not not-started. Directly exercises the
# AC3/AC4 boundary (one marker appears) rather than trusting it falls
# out of (d1)/(b) for free.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
__CALL_ISSUE__)
  printf 'BODY\t<!-- model-record: stage=Discovery model="claude-sonnet-5" effort="medium" -->\n'
  exit 0 ;;
__CALL_ISSUE_COMMENTS__)
  exit 0 ;;
__CALL_REPO_IDENTITY__)
  printf 'owner/repo\n'
  exit 0 ;;
__CALL_TIMELINE__)
  exit 0 ;;
GHEOF
fakebin_d2="$(cat "$FAKEGH_OUT")"
output_d2="$(PATH="$fakebin_d2:$PATH" "$script" 400)"; status_d2=$?
[ "$status_d2" -eq 0 ] || fail "S152 (d2) — expected exit 0, got $status_d2"
[ "$(assert_verdict_shape 'S152 (d2)' "$output_d2")" = "stale" ] || fail "S152 (d2) — expected stale (no label, one marker exists — AC3/AC4 boundary), got: $output_d2"
expected_d2='role-label-staleness: issue #400 — stale (issue #400 carries no role:<name> label, but a stage=Discovery marker already exists — expected role:product)'
[ "$output_d2" = "$expected_d2" ] || fail "S152 (d2) — exact detail text wrong:
expected: $expected_d2
got:      $output_d2"
[ -s "$WITNESS" ] && fail "S152 (d2) — unexpected gh call(s): $(cat "$WITNESS")"

# =========================================================================
# (e) — label present, timeline succeeds with zero candidate PRs -> a
# normal verdict from issue-only evidence, never indeterminate on its
# own. Distinct from PR_DISCOVERY_FAILED below: this is the timeline
# call succeeding with an empty result, not the call failing.
# =========================================================================
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
__CALL_ISSUE__)
  printf 'LABEL\trole:dev\nBODY\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
  exit 0 ;;
__CALL_ISSUE_COMMENTS__)
  exit 0 ;;
__CALL_REPO_IDENTITY__)
  printf 'owner/repo\n'
  exit 0 ;;
__CALL_TIMELINE__)
  exit 0 ;;
GHEOF
fakebin_e="$(cat "$FAKEGH_OUT")"
output_e="$(PATH="$fakebin_e:$PATH" "$script" 400)"; status_e=$?
[ "$status_e" -eq 0 ] || fail "S152 (e) — expected exit 0, got $status_e"
[ "$(assert_verdict_shape 'S152 (e)' "$output_e")" = "in-sync" ] || fail "S152 (e) — expected in-sync from issue-only evidence with zero candidate PRs, got: $output_e"
[ -s "$WITNESS" ] && fail "S152 (e) — unexpected gh call(s) — zero PRs means no pulls/<n> call at all: $(cat "$WITNESS")"

# =========================================================================
# (e2) — the issue-body call itself fails -> fatal, exit 4, no verdict
# on stdout. No arm for __CALL_ISSUE__ at all, so it correctly falls
# through (this fixture's designed failure — the witness IS expected to
# record this call, since that's exactly how a missing arm simulates a
# failure in this harness; not asserted empty here).
# =========================================================================
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
GHEOF
fakebin_e2="$(cat "$FAKEGH_OUT")"
output_e2="$(PATH="$fakebin_e2:$PATH" "$script" 400 2>/dev/null)"; status_e2=$?
[ "$status_e2" -eq 4 ] || fail "S152 (e2) — expected exit 4 when the issue lookup fails, got $status_e2"
[ -z "$output_e2" ] || fail "S152 (e2) — expected nothing on stdout when the issue lookup fails, got: $output_e2"

# =========================================================================
# Failure semantics — three independent flags (Architect's redesign,
# 2026-09-28). Each is exercised on its own, plus the required positive
# controls proving no over-broad blanket degrade.
# =========================================================================

# (ISSUE_COMMENTS_FAILED) — the issue's own comments call fails; a label
# in-sync from what WAS read (issue body only) must degrade, since a
# missing comment could carry a later marker.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
__CALL_ISSUE__)
  printf 'LABEL\trole:product\n'
  exit 0 ;;
__CALL_REPO_IDENTITY__)
  printf 'owner/repo\n'
  exit 0 ;;
__CALL_TIMELINE__)
  exit 0 ;;
GHEOF
fakebin_icf="$(cat "$FAKEGH_OUT")"
output_icf="$(PATH="$fakebin_icf:$PATH" "$script" 400 2>/dev/null)"; status_icf=$?
[ "$status_icf" -eq 0 ] || fail "S152 (ISSUE_COMMENTS_FAILED) — expected exit 0, got $status_icf"
[ "$(assert_verdict_shape 'S152 (ISSUE_COMMENTS_FAILED)' "$output_icf")" = "indeterminate" ] || fail "S152 (ISSUE_COMMENTS_FAILED) — expected indeterminate (issue comments unread, label in-sync from body alone), got: $output_icf"
assert_contains "S152 (ISSUE_COMMENTS_FAILED) — names the failure" "comments couldn't be read" "$output_icf"

# (PR_DISCOVERY_FAILED) — the timeline call itself fails. This must
# NEVER be read as "zero linked PRs" (case (e) above) — it means PRs
# might exist and weren't found.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
__CALL_ISSUE__)
  printf 'LABEL\trole:product\n'
  exit 0 ;;
__CALL_ISSUE_COMMENTS__)
  exit 0 ;;
__CALL_REPO_IDENTITY__)
  printf 'owner/repo\n'
  exit 0 ;;
GHEOF
fakebin_pdf="$(cat "$FAKEGH_OUT")"
output_pdf="$(PATH="$fakebin_pdf:$PATH" "$script" 400 2>/dev/null)"; status_pdf=$?
[ "$status_pdf" -eq 0 ] || fail "S152 (PR_DISCOVERY_FAILED) — expected exit 0, got $status_pdf"
[ "$(assert_verdict_shape 'S152 (PR_DISCOVERY_FAILED)' "$output_pdf")" = "indeterminate" ] || fail "S152 (PR_DISCOVERY_FAILED) — expected indeterminate (timeline lookup failed, must not read as zero PRs), got: $output_pdf"
assert_contains "S152 (PR_DISCOVERY_FAILED) — names the failure" "timeline lookup failed" "$output_pdf"

# (PR_LOOKUP_FAILED, sub-arm: candidate title/body fetch fails) — the
# only candidate's pulls/<pr> call fails; whether it even closes the
# issue is now unknown, not "no match".
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
__CALL_ISSUE__)
  printf 'LABEL\trole:architect\n'
  exit 0 ;;
__CALL_ISSUE_COMMENTS__)
  printf 'TEXT\t<!-- model-record: stage=Planning model="claude-sonnet-5" effort="medium" -->\n'
  exit 0 ;;
__CALL_REPO_IDENTITY__)
  printf 'owner/repo\n'
  exit 0 ;;
__CALL_TIMELINE__)
  printf 'PR\t501\n'
  exit 0 ;;
GHEOF
fakebin_plf_titlebody="$(cat "$FAKEGH_OUT")"
output_plf_titlebody="$(PATH="$fakebin_plf_titlebody:$PATH" "$script" 400 2>/dev/null)"; status_plf_titlebody=$?
[ "$status_plf_titlebody" -eq 0 ] || fail "S152 (PR_LOOKUP_FAILED, title/body) — expected exit 0, got $status_plf_titlebody"
[ "$(assert_verdict_shape 'S152 (PR_LOOKUP_FAILED, title/body)' "$output_plf_titlebody")" = "indeterminate" ] || fail "S152 (PR_LOOKUP_FAILED, title/body) — expected indeterminate (the only candidate's title/body fetch failed, label in-sync from issue-only evidence), got: $output_plf_titlebody"

# (PR_LOOKUP_FAILED, sub-arm: kept PR's comments fetch fails, reviews
# succeeds empty) — isolates a comments-only failure.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
__CALL_ISSUE__)
  printf 'LABEL\trole:architect\n'
  exit 0 ;;
__CALL_ISSUE_COMMENTS__)
  exit 0 ;;
__CALL_REPO_IDENTITY__)
  printf 'owner/repo\n'
  exit 0 ;;
__CALL_TIMELINE__)
  printf 'PR\t501\n'
  exit 0 ;;
__CALL_PR501_TITLEBODY__)
  printf 'TITLE\t\nBODY\tCloses #400\n'
  exit 0 ;;
__CALL_PR501_REVIEWS__)
  exit 0 ;;
GHEOF
fakebin_plf_comments="$(cat "$FAKEGH_OUT")"
output_plf_comments="$(PATH="$fakebin_plf_comments:$PATH" "$script" 400 2>/dev/null)"; status_plf_comments=$?
[ "$status_plf_comments" -eq 0 ] || fail "S152 (PR_LOOKUP_FAILED, comments) — expected exit 0, got $status_plf_comments"
[ "$(assert_verdict_shape 'S152 (PR_LOOKUP_FAILED, comments)' "$output_plf_comments")" = "indeterminate" ] || fail "S152 (PR_LOOKUP_FAILED, comments) — expected indeterminate (kept PR's comments unread), got: $output_plf_comments"

# issue #317 AC6 (F-10, round 1 review's own correction): the ORIGINAL
# finding was specifically that a KEPT PR's comments call failing must
# never skip that same PR's reviews call — not the issue's own comments
# call (a different case, already covered above as its own AC6 test).
# Same fixture shape as (PR_LOOKUP_FAILED, comments) directly above,
# except this time the reviews call that "succeeds empty" there instead
# succeeds with real evidence reaching the ceiling stage. If a future
# regression re-adds an early `continue`/skip right after the comments
# failure branch (matching this repo's own precedent for exactly that
# mistake, PR #316's F-10 finding), this PR's reviews evidence would
# never be read and the verdict would wrongly stay indeterminate
# instead of resolving to stale at the ceiling stage.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
__CALL_ISSUE__)
  exit 0 ;;
__CALL_ISSUE_COMMENTS__)
  exit 0 ;;
__CALL_REPO_IDENTITY__)
  printf 'owner/repo\n'
  exit 0 ;;
__CALL_TIMELINE__)
  printf 'PR\t501\n'
  exit 0 ;;
__CALL_PR501_TITLEBODY__)
  printf 'TITLE\t\nBODY\tCloses #400\n'
  exit 0 ;;
__CALL_PR501_REVIEWS__)
  printf 'TEXT\t<!-- model-record: stage=Review model="claude-sonnet-5" effort="medium" -->\n'
  exit 0 ;;
GHEOF
fakebin_f10b="$(cat "$FAKEGH_OUT")"
output_f10b="$(PATH="$fakebin_f10b:$PATH" "$script" 400 2>/dev/null)"; status_f10b=$?
[ "$status_f10b" -eq 0 ] || fail "S152 F-10b — expected exit 0, got $status_f10b"
[ "$(assert_verdict_shape 'S152 F-10b' "$output_f10b")" = "stale" ] || fail "S152 F-10b — PR #501's own comments call failing must not skip its reviews call: expected stale (no label, Review evidence at the ceiling stage), got: $output_f10b"

# (PR_LOOKUP_FAILED, sub-arm: kept PR's REVIEWS fetch fails, comments
# succeeds empty) — isolates a reviews-only failure (F-6's own new
# failure surface — must degrade exactly like a failed comments call).
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
__CALL_ISSUE__)
  printf 'LABEL\trole:architect\n'
  exit 0 ;;
__CALL_ISSUE_COMMENTS__)
  exit 0 ;;
__CALL_REPO_IDENTITY__)
  printf 'owner/repo\n'
  exit 0 ;;
__CALL_TIMELINE__)
  printf 'PR\t501\n'
  exit 0 ;;
__CALL_PR501_TITLEBODY__)
  printf 'TITLE\t\nBODY\tCloses #400\n'
  exit 0 ;;
__CALL_PR501_COMMENTS__)
  exit 0 ;;
GHEOF
fakebin_plf_reviews="$(cat "$FAKEGH_OUT")"
output_plf_reviews="$(PATH="$fakebin_plf_reviews:$PATH" "$script" 400 2>/dev/null)"; status_plf_reviews=$?
[ "$status_plf_reviews" -eq 0 ] || fail "S152 (PR_LOOKUP_FAILED, reviews) — expected exit 0, got $status_plf_reviews"
[ "$(assert_verdict_shape 'S152 (PR_LOOKUP_FAILED, reviews)' "$output_plf_reviews")" = "indeterminate" ] || fail "S152 (PR_LOOKUP_FAILED, reviews) — expected indeterminate (kept PR's reviews unread), got: $output_plf_reviews"

# Positive control 1 — label already at the ceiling stage (role:reviewer
# /Review) from evidence that WAS read; a PR-discovery failure changes
# nothing, since nothing a missing PR could reveal can ever place the
# true latest stage past Review.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
__CALL_ISSUE__)
  printf 'LABEL\trole:reviewer\nBODY\t<!-- model-record: stage=Review model="claude-sonnet-5" effort="medium" -->\n'
  exit 0 ;;
__CALL_ISSUE_COMMENTS__)
  exit 0 ;;
__CALL_REPO_IDENTITY__)
  printf 'owner/repo\n'
  exit 0 ;;
GHEOF
fakebin_pc1="$(cat "$FAKEGH_OUT")"
output_pc1="$(PATH="$fakebin_pc1:$PATH" "$script" 400 2>/dev/null)"; status_pc1=$?
[ "$status_pc1" -eq 0 ] || fail "S152 positive control 1 — expected exit 0, got $status_pc1"
[ "$(assert_verdict_shape 'S152 positive control 1' "$output_pc1")" = "in-sync" ] || fail "S152 positive control 1 — expected in-sync (label already at the ceiling stage from evidence read; PR-discovery failure can't change that), got: $output_pc1"

# Positive control 2 — a verdict already correctly `stale` from evidence
# that WAS read must not degrade either: absence is only ever additive.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
__CALL_ISSUE__)
  printf 'LABEL\trole:architect\nBODY\t<!-- model-record: stage=Test model="claude-sonnet-5" effort="medium" -->\n'
  exit 0 ;;
__CALL_REPO_IDENTITY__)
  printf 'owner/repo\n'
  exit 0 ;;
GHEOF
fakebin_pc2="$(cat "$FAKEGH_OUT")"
output_pc2="$(PATH="$fakebin_pc2:$PATH" "$script" 400 2>/dev/null)"; status_pc2=$?
[ "$status_pc2" -eq 0 ] || fail "S152 positive control 2 — expected exit 0, got $status_pc2"
[ "$(assert_verdict_shape 'S152 positive control 2' "$output_pc2")" = "stale" ] || fail "S152 positive control 2 — expected stale (already behind from evidence read; issue-comments AND timeline both failing can only deepen that, never undo it), got: $output_pc2"

# =========================================================================
# F-6 (round-2 review) — the Review stage's model-record marker is
# posted as a PR REVIEW's own body (GitHub's PR-review mechanism), never
# a plain issue-style comment. It must be read from pulls/<pr>/reviews,
# not just issues/<pr>/comments.
# =========================================================================
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
__CALL_ISSUE__)
  printf 'LABEL\trole:dev\n'
  exit 0 ;;
__CALL_ISSUE_COMMENTS__)
  exit 0 ;;
__CALL_REPO_IDENTITY__)
  printf 'owner/repo\n'
  exit 0 ;;
__CALL_TIMELINE__)
  printf 'PR\t501\n'
  exit 0 ;;
__CALL_PR501_TITLEBODY__)
  printf 'TITLE\tCloses #400\nBODY\t\n'
  exit 0 ;;
__CALL_PR501_COMMENTS__)
  printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
  exit 0 ;;
__CALL_PR501_REVIEWS__)
  printf 'TEXT\t<!-- model-record: stage=Review model="claude-sonnet-5" effort="medium" -->\n'
  exit 0 ;;
GHEOF
fakebin_f6="$(cat "$FAKEGH_OUT")"
output_f6="$(PATH="$fakebin_f6:$PATH" "$script" 400)"; status_f6=$?
[ "$status_f6" -eq 0 ] || fail "S152 (F-6) — expected exit 0, got $status_f6"
[ "$(assert_verdict_shape 'S152 (F-6)' "$output_f6")" = "stale" ] || fail "S152 (F-6) — expected stale (role:dev behind the stage=Review marker posted as a PR review, not a comment), got: $output_f6"
expected_f6='role-label-staleness: issue #400 — stale (issue #400 carries role:dev, but a stage=Review marker already exists — expected role:reviewer)'
[ "$output_f6" = "$expected_f6" ] || fail "S152 (F-6) — exact detail text wrong (the Review marker must be read from pulls/<pr>/reviews):
expected: $expected_f6
got:      $output_f6"
[ -s "$WITNESS" ] && fail "S152 (F-6) — unexpected gh call(s): $(cat "$WITNESS")"

# =========================================================================
# Closing-keyword filter — the timeline over-includes by design
# (Architect's redesign): a cross-referencing PR that mentions the issue
# in prose, without a real closing keyword, must be excluded, and never
# even get a comments/reviews call (no arm for PR #502's comments/
# reviews below — if the implementation wrongly fetched them anyway,
# the fallthrough witness would catch it).
# =========================================================================
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
__CALL_ISSUE__)
  printf 'LABEL\trole:qa\n'
  exit 0 ;;
__CALL_ISSUE_COMMENTS__)
  exit 0 ;;
__CALL_REPO_IDENTITY__)
  printf 'owner/repo\n'
  exit 0 ;;
__CALL_TIMELINE__)
  printf 'PR\t501\nPR\t502\n'
  exit 0 ;;
__CALL_PR501_TITLEBODY__)
  printf 'TITLE\t\nBODY\tCloses #400\n'
  exit 0 ;;
__CALL_PR501_COMMENTS__)
  printf 'TEXT\t<!-- model-record: stage=Test model="claude-sonnet-5" effort="medium" -->\n'
  exit 0 ;;
__CALL_PR501_REVIEWS__)
  exit 0 ;;
__CALL_PR502_TITLEBODY__)
  printf 'TITLE\t\nBODY\tSee also #400 for related context; unrelated work otherwise.\n'
  exit 0 ;;
GHEOF
fakebin_kw="$(cat "$FAKEGH_OUT")"
output_kw="$(PATH="$fakebin_kw:$PATH" "$script" 400)"; status_kw=$?
[ "$status_kw" -eq 0 ] || fail "S152 (keyword filter) — expected exit 0, got $status_kw"
[ "$(assert_verdict_shape 'S152 (keyword filter)' "$output_kw")" = "in-sync" ] || fail "S152 (keyword filter) — expected in-sync (PR #502 merely mentions the issue, must be excluded), got: $output_kw"
[ -s "$WITNESS" ] && fail "S152 (keyword filter) — PR #502 must never get a comments/reviews call once excluded by the keyword filter: $(cat "$WITNESS")"

# Round-2 finding 1b, required arm 1 — the keyword lives ONLY in the PR
# TITLE (this repo's own real shape for #314 "Closes #313: ..."), never
# the body. Must still be kept.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
__CALL_ISSUE__)
  printf 'LABEL\trole:qa\n'
  exit 0 ;;
__CALL_ISSUE_COMMENTS__)
  exit 0 ;;
__CALL_REPO_IDENTITY__)
  printf 'owner/repo\n'
  exit 0 ;;
__CALL_TIMELINE__)
  printf 'PR\t501\n'
  exit 0 ;;
__CALL_PR501_TITLEBODY__)
  printf 'TITLE\tCloses #400: role-contracts skill\nBODY\tno keyword in here at all\n'
  exit 0 ;;
__CALL_PR501_COMMENTS__)
  printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
  exit 0 ;;
__CALL_PR501_REVIEWS__)
  exit 0 ;;
GHEOF
fakebin_titleonly="$(cat "$FAKEGH_OUT")"
output_titleonly="$(PATH="$fakebin_titleonly:$PATH" "$script" 400)"; status_titleonly=$?
[ "$status_titleonly" -eq 0 ] || fail "S152 (title-only keyword) — expected exit 0, got $status_titleonly"
[ "$(assert_verdict_shape 'S152 (title-only keyword)' "$output_titleonly")" = "stale" ] || fail "S152 (title-only keyword) — expected stale (role:qa behind stage=Implementation, found only via the PR TITLE's closing keyword — the real #314 shape), got: $output_titleonly"
assert_contains "S152 (title-only keyword) — evidences Implementation" "stage=Implementation" "$output_titleonly"

# Round-2 finding 1b, required arm 2 — a prose NEAR-MISS ("resolved
# against issue #400") that is NOT a real closing reference must still
# be excluded, even against the tightened ERE. This is exactly the
# accidental match Reviewer found on PR #316's own body against #315
# ("Deviations ... resolved against issue #315 itself") — the tightened
# grammar (keyword, optional ':', then whitespace then '#N', no free
# 0-20-char gap) must reject it.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
__CALL_ISSUE__)
  printf 'LABEL\trole:qa\n'
  exit 0 ;;
__CALL_ISSUE_COMMENTS__)
  exit 0 ;;
__CALL_REPO_IDENTITY__)
  printf 'owner/repo\n'
  exit 0 ;;
__CALL_TIMELINE__)
  printf 'PR\t501\n'
  exit 0 ;;
__CALL_PR501_TITLEBODY__)
  printf 'TITLE\tsome unrelated title\nBODY\tresolved against issue #400 itself, nothing more\n'
  exit 0 ;;
GHEOF
fakebin_nearmiss="$(cat "$FAKEGH_OUT")"
output_nearmiss="$(PATH="$fakebin_nearmiss:$PATH" "$script" 400)"; status_nearmiss=$?
[ "$status_nearmiss" -eq 0 ] || fail "S152 (prose near-miss) — expected exit 0, got $status_nearmiss"
[ "$(assert_verdict_shape 'S152 (prose near-miss)' "$output_nearmiss")" = "in-sync" ] || fail "S152 (prose near-miss) — expected in-sync ('resolved against issue #400' is prose, not a closing reference, and must be excluded), got: $output_nearmiss"
[ -s "$WITNESS" ] && fail "S152 (prose near-miss) — PR #501 must never get a comments/reviews call once excluded by the tightened keyword filter: $(cat "$WITNESS")"

# Case-insensitivity + a non-standard-but-valid keyword ("fixes"), and a
# colon-form ("Fixes: #400") — both accepted by the tightened ERE.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
__CALL_ISSUE__)
  exit 0 ;;
__CALL_ISSUE_COMMENTS__)
  exit 0 ;;
__CALL_REPO_IDENTITY__)
  printf 'owner/repo\n'
  exit 0 ;;
__CALL_TIMELINE__)
  printf 'PR\t501\n'
  exit 0 ;;
__CALL_PR501_TITLEBODY__)
  printf 'TITLE\t\nBODY\tFIXES #400\n'
  exit 0 ;;
__CALL_PR501_COMMENTS__)
  printf 'TEXT\t<!-- model-record: stage=Discovery model="claude-sonnet-5" effort="medium" -->\n'
  exit 0 ;;
__CALL_PR501_REVIEWS__)
  exit 0 ;;
GHEOF
fakebin_kw2="$(cat "$FAKEGH_OUT")"
output_kw2="$(PATH="$fakebin_kw2:$PATH" "$script" 400)"; status_kw2=$?
[ "$status_kw2" -eq 0 ] || fail "S152 (keyword case-insensitive) — expected exit 0, got $status_kw2"
[ "$(assert_verdict_shape 'S152 (keyword case-insensitive)' "$output_kw2")" = "stale" ] || fail "S152 (keyword case-insensitive) — expected stale (uppercase FIXES #400 must still match, evidencing stage=Discovery with no label), got: $output_kw2"

run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
__CALL_ISSUE__)
  exit 0 ;;
__CALL_ISSUE_COMMENTS__)
  exit 0 ;;
__CALL_REPO_IDENTITY__)
  printf 'owner/repo\n'
  exit 0 ;;
__CALL_TIMELINE__)
  printf 'PR\t501\n'
  exit 0 ;;
__CALL_PR501_TITLEBODY__)
  printf 'TITLE\tFixes: #400\nBODY\t\n'
  exit 0 ;;
__CALL_PR501_COMMENTS__)
  printf 'TEXT\t<!-- model-record: stage=Discovery model="claude-sonnet-5" effort="medium" -->\n'
  exit 0 ;;
__CALL_PR501_REVIEWS__)
  exit 0 ;;
GHEOF
fakebin_kw3="$(cat "$FAKEGH_OUT")"
output_kw3="$(PATH="$fakebin_kw3:$PATH" "$script" 400)"; status_kw3=$?
[ "$status_kw3" -eq 0 ] || fail "S152 (keyword colon form) — expected exit 0, got $status_kw3"
[ "$(assert_verdict_shape 'S152 (keyword colon form)' "$output_kw3")" = "stale" ] || fail "S152 (keyword colon form) — expected stale ('Fixes: #400' — GitHub's own optional-colon grammar — must still match), got: $output_kw3"

# =========================================================================
# (f) — multiple linked PRs, markers split across them -> union/max,
# order-independent. Run twice with the two PR lines swapped in the
# timeline's output and assert byte-identical results (direct analogue
# of S150's Arm G order-independence check).
# =========================================================================
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
__CALL_ISSUE__)
  printf 'LABEL\trole:qa\n'
  exit 0 ;;
__CALL_ISSUE_COMMENTS__)
  exit 0 ;;
__CALL_REPO_IDENTITY__)
  printf 'owner/repo\n'
  exit 0 ;;
__CALL_TIMELINE__)
  printf 'PR\t501\nPR\t502\n'
  exit 0 ;;
__CALL_PR501_TITLEBODY__)
  printf 'TITLE\t\nBODY\tCloses #400\n'
  exit 0 ;;
__CALL_PR501_COMMENTS__)
  printf 'TEXT\t<!-- model-record: stage=Discovery model="claude-sonnet-5" effort="medium" -->\n'
  exit 0 ;;
__CALL_PR501_REVIEWS__)
  exit 0 ;;
__CALL_PR502_TITLEBODY__)
  printf 'TITLE\t\nBODY\tFixes #400\n'
  exit 0 ;;
__CALL_PR502_COMMENTS__)
  printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
  exit 0 ;;
__CALL_PR502_REVIEWS__)
  exit 0 ;;
GHEOF
fakebin_f1="$(cat "$FAKEGH_OUT")"
output_f1="$(PATH="$fakebin_f1:$PATH" "$script" 400)"; status_f1=$?
[ "$status_f1" -eq 0 ] || fail "S152 (f, order A) — expected exit 0, got $status_f1"
[ "$(assert_verdict_shape 'S152 (f, order A)' "$output_f1")" = "stale" ] || fail "S152 (f, order A) — expected stale (role:qa behind the union max, stage=Implementation from PR #502), got: $output_f1"
[ -s "$WITNESS" ] && fail "S152 (f, order A) — unexpected gh call(s): $(cat "$WITNESS")"

run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
__CALL_ISSUE__)
  printf 'LABEL\trole:qa\n'
  exit 0 ;;
__CALL_ISSUE_COMMENTS__)
  exit 0 ;;
__CALL_REPO_IDENTITY__)
  printf 'owner/repo\n'
  exit 0 ;;
__CALL_TIMELINE__)
  printf 'PR\t502\nPR\t501\n'
  exit 0 ;;
__CALL_PR501_TITLEBODY__)
  printf 'TITLE\t\nBODY\tCloses #400\n'
  exit 0 ;;
__CALL_PR501_COMMENTS__)
  printf 'TEXT\t<!-- model-record: stage=Discovery model="claude-sonnet-5" effort="medium" -->\n'
  exit 0 ;;
__CALL_PR501_REVIEWS__)
  exit 0 ;;
__CALL_PR502_TITLEBODY__)
  printf 'TITLE\t\nBODY\tFixes #400\n'
  exit 0 ;;
__CALL_PR502_COMMENTS__)
  printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
  exit 0 ;;
__CALL_PR502_REVIEWS__)
  exit 0 ;;
GHEOF
fakebin_f2="$(cat "$FAKEGH_OUT")"
output_f2="$(PATH="$fakebin_f2:$PATH" "$script" 400)"; status_f2=$?
[ "$status_f2" -eq 0 ] || fail "S152 (f, order B/swapped) — expected exit 0, got $status_f2"
[ "$output_f1" = "$output_f2" ] || fail "S152 (f) — swapping the two linked PRs' call order changed the output (order-dependence regression):
order A: $output_f1
order B: $output_f2"

# =========================================================================
# (g1) — live_text() reuse: a marker inside a fenced code block on the
# issue body must not count as live evidence (mirrors S151's own fixture
# shape). Label alone with the quoted marker stripped must render
# in-sync (case (c)'s shape), not in-sync-with-Test-evidenced.
# =========================================================================
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
__CALL_ISSUE__)
  printf 'LABEL\trole:product\nBODY\t```\001<!-- model-record: stage=Test model="claude-sonnet-5" effort="medium" -->\001```\n'
  exit 0 ;;
__CALL_ISSUE_COMMENTS__)
  exit 0 ;;
__CALL_REPO_IDENTITY__)
  printf 'owner/repo\n'
  exit 0 ;;
__CALL_TIMELINE__)
  exit 0 ;;
GHEOF
fakebin_g1="$(cat "$FAKEGH_OUT")"
output_g1="$(PATH="$fakebin_g1:$PATH" "$script" 400)"; status_g1=$?
[ "$status_g1" -eq 0 ] || fail "S152 (g1) — expected exit 0, got $status_g1"
[ "$(assert_verdict_shape 'S152 (g1)' "$output_g1")" = "in-sync" ] || fail "S152 (g1) — expected in-sync (the only stage=Test marker is fenced/quoted, must not count as live evidence — live_text() reuse), got: $output_g1"
case "$output_g1" in
  *"stage=Test"*) fail "S152 (g1) — the quoted/fenced marker leaked through as live evidence: $output_g1" ;;
esac
[ -s "$WITNESS" ] && fail "S152 (g1) — unexpected gh call(s): $(cat "$WITNESS")"

# =========================================================================
# (g2) — the new stage-extraction logic's own correctness: a LIVE
# (non-quoted) marker whose stage= value isn't one of the fixed five
# must render indeterminate (AC6), never silently treated as absent and
# never coerced into the nearest recognized stage.
# =========================================================================
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
__CALL_ISSUE__)
  printf 'LABEL\trole:qa\nBODY\t<!-- model-record: stage=discovery model="claude-sonnet-5" effort="medium" -->\n'
  exit 0 ;;
__CALL_ISSUE_COMMENTS__)
  exit 0 ;;
__CALL_REPO_IDENTITY__)
  printf 'owner/repo\n'
  exit 0 ;;
__CALL_TIMELINE__)
  exit 0 ;;
GHEOF
fakebin_g2="$(cat "$FAKEGH_OUT")"
output_g2="$(PATH="$fakebin_g2:$PATH" "$script" 400)"; status_g2=$?
[ "$status_g2" -eq 0 ] || fail "S152 (g2) — expected exit 0, got $status_g2"
[ "$(assert_verdict_shape 'S152 (g2)' "$output_g2")" = "indeterminate" ] || fail "S152 (g2) — expected indeterminate (live marker with unrecognized stage=discovery, wrong case), got: $output_g2"
[ -s "$WITNESS" ] && fail "S152 (g2) — unexpected gh call(s): $(cat "$WITNESS")"

# (g2b) — a marker matched by the anchor but with no stage= token at
# all (AC6's other half: "no parseable stage") must also render
# indeterminate, not silently invisible.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
__CALL_ISSUE__)
  printf 'BODY\t<!-- model-record: model="claude-sonnet-5" effort="medium" -->\n'
  exit 0 ;;
__CALL_ISSUE_COMMENTS__)
  exit 0 ;;
__CALL_REPO_IDENTITY__)
  printf 'owner/repo\n'
  exit 0 ;;
__CALL_TIMELINE__)
  exit 0 ;;
GHEOF
fakebin_g2b="$(cat "$FAKEGH_OUT")"
output_g2b="$(PATH="$fakebin_g2b:$PATH" "$script" 400)"; status_g2b=$?
[ "$status_g2b" -eq 0 ] || fail "S152 (g2b) — expected exit 0, got $status_g2b"
[ "$(assert_verdict_shape 'S152 (g2b)' "$output_g2b")" = "indeterminate" ] || fail "S152 (g2b) — expected indeterminate (model-record marker matched but has no stage= at all), got: $output_g2b"

# =========================================================================
# (g3) — one linked PR carries a malformed marker, another linked PR
# carries a well-formed marker for a later stage: overall verdict must
# still be indeterminate (the malformed sighting always wins), not
# stale/in-sync computed from the well-formed one alone.
# =========================================================================
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
__CALL_ISSUE__)
  printf 'LABEL\trole:architect\n'
  exit 0 ;;
__CALL_ISSUE_COMMENTS__)
  exit 0 ;;
__CALL_REPO_IDENTITY__)
  printf 'owner/repo\n'
  exit 0 ;;
__CALL_TIMELINE__)
  printf 'PR\t501\nPR\t502\n'
  exit 0 ;;
__CALL_PR501_TITLEBODY__)
  printf 'TITLE\t\nBODY\tCloses #400\n'
  exit 0 ;;
__CALL_PR501_COMMENTS__)
  printf 'TEXT\t<!-- model-record: stage=QA model="claude-sonnet-5" effort="medium" -->\n'
  exit 0 ;;
__CALL_PR501_REVIEWS__)
  exit 0 ;;
__CALL_PR502_TITLEBODY__)
  printf 'TITLE\t\nBODY\tFixes #400\n'
  exit 0 ;;
__CALL_PR502_COMMENTS__)
  printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
  exit 0 ;;
__CALL_PR502_REVIEWS__)
  exit 0 ;;
GHEOF
fakebin_g3="$(cat "$FAKEGH_OUT")"
output_g3="$(PATH="$fakebin_g3:$PATH" "$script" 400)"; status_g3=$?
[ "$status_g3" -eq 0 ] || fail "S152 (g3) — expected exit 0, got $status_g3"
[ "$(assert_verdict_shape 'S152 (g3)' "$output_g3")" = "indeterminate" ] || fail "S152 (g3) — expected indeterminate (malformed marker on PR #501 must force this even though PR #502 alone would read stale), got: $output_g3"
case "$output_g3" in
  *"stage=Implementation"*'expected role:dev'*) fail "S152 (g3) — computed stale from the well-formed PR alone instead of forcing indeterminate: $output_g3" ;;
esac
[ -s "$WITNESS" ] && fail "S152 (g3) — unexpected gh call(s): $(cat "$WITNESS")"

# =========================================================================
# AC5 — two-or-more role:<name> labels at once -> indeterminate, naming
# every one found. Tested with exactly two and with three.
# =========================================================================
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
__CALL_ISSUE__)
  printf 'LABEL\trole:product\nLABEL\trole:qa\n'
  exit 0 ;;
__CALL_ISSUE_COMMENTS__)
  exit 0 ;;
__CALL_REPO_IDENTITY__)
  printf 'owner/repo\n'
  exit 0 ;;
__CALL_TIMELINE__)
  exit 0 ;;
GHEOF
fakebin_ac5a="$(cat "$FAKEGH_OUT")"
output_ac5a="$(PATH="$fakebin_ac5a:$PATH" "$script" 400)"; status_ac5a=$?
[ "$status_ac5a" -eq 0 ] || fail "S152 AC5 (two labels) — expected exit 0, got $status_ac5a"
[ "$(assert_verdict_shape 'S152 AC5 (two)' "$output_ac5a")" = "indeterminate" ] || fail "S152 AC5 (two labels) — expected indeterminate, got: $output_ac5a"
assert_contains "S152 AC5 (two labels) — names role:product" "role:product" "$output_ac5a"
assert_contains "S152 AC5 (two labels) — names role:qa" "role:qa" "$output_ac5a"
[ -s "$WITNESS" ] && fail "S152 AC5 (two labels) — unexpected gh call(s): $(cat "$WITNESS")"

run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
__CALL_ISSUE__)
  printf 'LABEL\trole:product\nLABEL\trole:architect\nLABEL\trole:reviewer\n'
  exit 0 ;;
__CALL_ISSUE_COMMENTS__)
  exit 0 ;;
__CALL_REPO_IDENTITY__)
  printf 'owner/repo\n'
  exit 0 ;;
__CALL_TIMELINE__)
  exit 0 ;;
GHEOF
fakebin_ac5b="$(cat "$FAKEGH_OUT")"
output_ac5b="$(PATH="$fakebin_ac5b:$PATH" "$script" 400)"; status_ac5b=$?
[ "$status_ac5b" -eq 0 ] || fail "S152 AC5 (three labels) — expected exit 0, got $status_ac5b"
[ "$(assert_verdict_shape 'S152 AC5 (three)' "$output_ac5b")" = "indeterminate" ] || fail "S152 AC5 (three labels) — expected indeterminate, got: $output_ac5b"
assert_contains "S152 AC5 (three labels) — names role:product" "role:product" "$output_ac5b"
assert_contains "S152 AC5 (three labels) — names role:architect" "role:architect" "$output_ac5b"
assert_contains "S152 AC5 (three labels) — names role:reviewer" "role:reviewer" "$output_ac5b"

# =========================================================================
# Label filtering — an unrelated label alongside a single role:<name>
# label must not be treated as multiple (confirms filtering to the five
# known names, not a blanket "matches role:" scan).
# =========================================================================
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
__CALL_ISSUE__)
  printf 'LABEL\tbug\nLABEL\tpriority:high\nLABEL\trole:qa\nBODY\t<!-- model-record: stage=Test model="claude-sonnet-5" effort="medium" -->\n'
  exit 0 ;;
__CALL_ISSUE_COMMENTS__)
  exit 0 ;;
__CALL_REPO_IDENTITY__)
  printf 'owner/repo\n'
  exit 0 ;;
__CALL_TIMELINE__)
  exit 0 ;;
GHEOF
fakebin_filter="$(cat "$FAKEGH_OUT")"
output_filter="$(PATH="$fakebin_filter:$PATH" "$script" 400)"; status_filter=$?
[ "$status_filter" -eq 0 ] || fail "S152 (label filtering) — expected exit 0, got $status_filter"
[ "$(assert_verdict_shape 'S152 (label filtering)' "$output_filter")" = "in-sync" ] || fail "S152 (label filtering) — unrelated labels (bug, priority:high) alongside role:qa must not read as multiple role labels, got: $output_filter"
[ -s "$WITNESS" ] && fail "S152 (label filtering) — unexpected gh call(s): $(cat "$WITNESS")"

# =========================================================================
# No `gh` on PATH -> exit 3, nothing on stdout (mirrors S130's own
# path_without_gh() arm).
# =========================================================================
nogh_bin="$(path_without_gh)"
output_nogh="$(PATH="$nogh_bin" "$script" 400 2>/dev/null)"; status_nogh=$?
[ "$status_nogh" -eq 3 ] || fail "S152 (no gh) — expected exit 3 with no gh on PATH, got $status_nogh"
[ -z "$output_nogh" ] || fail "S152 (no gh) — expected nothing on stdout with no gh on PATH, got: $output_nogh"

# =========================================================================
# (h)+(i) — read-only verification, both required as a conjunction
# (compliance-evidence.sh's AC5/S150 own precedent: a witness-empty
# check alone can't distinguish "did nothing wrong" from "did nothing at
# all").
# =========================================================================

# (h) — the fallthrough witness stays empty across a full, successful
# run that answers every call the script actually makes (including the
# round-2-added reviews call).
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
__CALL_ISSUE__)
  printf 'LABEL\trole:qa\n'
  exit 0 ;;
__CALL_ISSUE_COMMENTS__)
  exit 0 ;;
__CALL_REPO_IDENTITY__)
  printf 'owner/repo\n'
  exit 0 ;;
__CALL_TIMELINE__)
  printf 'PR\t501\n'
  exit 0 ;;
__CALL_PR501_TITLEBODY__)
  printf 'TITLE\t\nBODY\tCloses #400\n'
  exit 0 ;;
__CALL_PR501_COMMENTS__)
  printf 'TEXT\t<!-- model-record: stage=Test model="claude-sonnet-5" effort="medium" -->\n'
  exit 0 ;;
__CALL_PR501_REVIEWS__)
  exit 0 ;;
GHEOF
fakebin_h="$(cat "$FAKEGH_OUT")"
output_h="$(PATH="$fakebin_h:$PATH" "$script" 400)"; status_h=$?
h_witness_empty=1
[ -s "$WITNESS" ] && h_witness_empty=0
h_exit_ok=0
[ "$status_h" -eq 0 ] && h_exit_ok=1
h_status="$(assert_verdict_shape 'S152 (h)' "$output_h")"
h_shape_ok=0
[ "$h_status" = "in-sync" ] && h_shape_ok=1

if [ "$h_witness_empty" -eq 1 ] && [ "$h_exit_ok" -eq 1 ] && [ "$h_shape_ok" -eq 1 ]; then
  : # (h) holds
else
  fail "S152 (h) — read-only witness check failed (witness_empty=$h_witness_empty exit_ok=$h_exit_ok shape_ok=$h_shape_ok, witness: $(cat "$WITNESS" 2>/dev/null))"
fi

# (h, positive control) — proves the witness mechanism itself actually
# fires, rather than being structurally unreachable (PR #316 Reviewer's
# round-1 F-2 finding: an earlier version's witness line sat after each
# fixture's own `esac; exit 1`, so it could never run — confirmed by a
# mutation probe that injected a write call and watched S152 stay
# green, and re-confirmed as fixed in round 2 by the same probe). This
# calls the fake `gh` binary DIRECTLY (not through role-label-
# staleness.sh) with an argv no arm above answers, which is exactly what
# an unanticipated call from the real script would look like to this
# harness — proving the fallthrough-plus-witness plumbing in
# run_build_fake_gh works, independently of whether the shipped script
# happens to make such a call today.
: > "$WITNESS"
"$fakebin_h/gh" issue close 400 --comment "unexpected write" >/dev/null 2>&1
probe_status=$?
[ "$probe_status" -eq 1 ] || fail "S152 (h, positive control) — the fake gh's own fallthrough should exit 1 for an unanswered call, got $probe_status"
[ -s "$WITNESS" ] || fail "S152 (h, positive control) — the witness did NOT fire for a genuinely unexpected call: the fallthrough-plus-witness mechanism itself is broken, which would make every other (h)-style empty-witness assertion in this file vacuous"
assert_contains "S152 (h, positive control) — witness records the unexpected call" "issue close 400" "$(cat "$WITNESS" 2>/dev/null)"

# (i) — source-level grep assertion: the script contains no gh write
# subcommand. Comment lines are stripped first (S150's own trap: a
# header comment documenting "never calls X" would otherwise
# false-positive on itself).
source_no_comments="$(grep -v '^[[:space:]]*#' "$script")"
i_clean=1
for banned in 'issue edit' 'issue comment' 'pr edit' 'pr comment' 'pr merge'; do
  if grep -qF "$banned" <<<"$source_no_comments"; then
    i_clean=0
    fail "S152 (i) — source contains banned gh subcommand shape: $banned"
  fi
done
if grep -qE '\bapi\b[^|&;]*(-X|--method)\b' <<<"$source_no_comments"; then
  i_clean=0
  fail "S152 (i) — source contains 'gh api -X'/'gh api --method' (a write call)"
fi
if grep -qE '\bgh[[:space:]]+label\b' <<<"$source_no_comments"; then
  i_clean=0
  fail "S152 (i) — source contains a 'gh label' subcommand shape"
fi
if grep -qE '\bgraphql\b' <<<"$source_no_comments"; then
  i_clean=0
  fail "S152 (i) — source contains 'gh api graphql' — the REST-only redesign must not reintroduce it"
fi
if grep -qE '\b(gh issue view|gh pr view)\b' <<<"$source_no_comments"; then
  i_clean=0
  fail "S152 (i) — source contains 'gh issue view'/'gh pr view' — both are GraphQL-backed and blocked in Claude Code sessions per the redesign"
fi

# The conjunction itself — neither (h) alone nor (i) alone is allowed to
# pass vacuously for the other.
if [ "$h_witness_empty" -eq 1 ] && [ "$h_exit_ok" -eq 1 ] && [ "$h_shape_ok" -eq 1 ] && [ "$i_clean" -eq 1 ]; then
  : # AC7 holds: read-only, verified both ways
else
  fail "S152 AC7 — read-only verification did not hold as a conjunction of (h) and (i)"
fi

# =========================================================================
# Issue #317's six deferred findings from PR #316's review.
# =========================================================================

# issue #317 AC1 (F-4) — a non-numeric argument is a usage error (exit
# 2), not an internal error (exit 4) — matching the empty-argument
# case just above it in the script, not the "issue itself unreadable"
# case. No gh call at all should be made: a bad argument is caught
# before require_gh/collect ever run. Verified directly (round 1
# review nit), not just inferred from the exit code: a fake gh that
# records any invocation at all sits on PATH, and the run must leave it
# untouched. `0` is checked alongside a genuinely non-numeric arm,
# since GitHub issue numbers start at 1 (round 1 review nit).
f4_witness="$SANDBOX/f4-witness"
: > "$f4_witness"
f4_fakebin="$(fake_gh_bin "printf 'UNEXPECTED CALL: %s\n' \"\$*\" >> '$f4_witness'; exit 1")"
for f4_arg in abc 0; do
  output_f4="$(PATH="$f4_fakebin:$PATH" "$script" "$f4_arg" 2>"$SANDBOX/f4-stderr")"; status_f4=$?
  stderr_f4="$(cat "$SANDBOX/f4-stderr" 2>/dev/null)"
  [ "$status_f4" -eq 2 ] || fail "S152 F-4 — expected exit 2 for argument '$f4_arg', got $status_f4"
  [ -z "$output_f4" ] || fail "S152 F-4 — expected nothing on stdout for argument '$f4_arg', got: $output_f4"
  [ -n "$stderr_f4" ] || fail "S152 F-4 — expected a usage message on stderr for argument '$f4_arg'"
done
[ -s "$f4_witness" ] && fail "S152 F-4 — a bad argument must never reach gh at all: $(cat "$f4_witness")"

# issue #317 AC2 (F-5) — a model-record marker closed with no space
# before the delimiter (`stage=Review-->`) must still be recognized as
# stage=Review, not misread as malformed (which would force
# indeterminate instead of the correct verdict below). Mutation-tested
# during development: reverting the character-class fix to exclude
# only whitespace/`>` (not `-`) makes this fail with indeterminate.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
__CALL_ISSUE__)
  printf 'LABEL\trole:reviewer\n'
  exit 0 ;;
__CALL_ISSUE_COMMENTS__)
  printf 'TEXT\t<!-- model-record: stage=Review-->\n'
  exit 0 ;;
__CALL_REPO_IDENTITY__)
  printf 'owner/repo\n'
  exit 0 ;;
__CALL_TIMELINE__)
  exit 0 ;;
GHEOF
fakebin_f5="$(cat "$FAKEGH_OUT")"
output_f5="$(PATH="$fakebin_f5:$PATH" "$script" 400)"; status_f5=$?
[ "$status_f5" -eq 0 ] || fail "S152 F-5 — expected exit 0, got $status_f5"
[ "$(assert_verdict_shape 'S152 F-5' "$output_f5")" = "in-sync" ] || fail "S152 F-5 — a no-space-before--> marker (stage=Review-->) must still be recognized as stage=Review (in-sync with role:reviewer), not malformed: $output_f5"

# issue #317 AC3 (F-7) — a PR whose title/body only QUOTES "Closes
# #400" inside an inline code span (not a real closing intent) must
# not be kept as a closing PR on the strength of the quote alone.
# Mirrors a real precedent: PR #316's own body once quoted an earlier
# round's test-output snippet exactly this way. PR #501 must be
# discarded before its comments/reviews are ever fetched — the witness
# stays empty, and this issue (with zero real evidence anywhere)
# renders not-started.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
__CALL_ISSUE__)
  exit 0 ;;
__CALL_ISSUE_COMMENTS__)
  exit 0 ;;
__CALL_REPO_IDENTITY__)
  printf 'owner/repo\n'
  exit 0 ;;
__CALL_TIMELINE__)
  printf 'PR\t501\n'
  exit 0 ;;
__CALL_PR501_TITLEBODY__)
  printf 'TITLE\t\nBODY\tSee an earlier round'"'"'s test output: `Closes #400`\n'
  exit 0 ;;
GHEOF
fakebin_f7="$(cat "$FAKEGH_OUT")"
output_f7="$(PATH="$fakebin_f7:$PATH" "$script" 400)"; status_f7=$?
[ "$status_f7" -eq 0 ] || fail "S152 F-7 — expected exit 0, got $status_f7"
[ "$(assert_verdict_shape 'S152 F-7' "$output_f7")" = "not-started" ] || fail "S152 F-7 — a quoted (inline-code-span) 'Closes #400' must not keep PR #501 as a closing PR: $output_f7"
[ -s "$WITNESS" ] && fail "S152 F-7 — unexpected gh call(s) (PR #501 should have been discarded before its comments/reviews were ever fetched): $(cat "$WITNESS")"

# issue #317 AC4 (F-8) — a cross-referenced timeline event whose source
# PR belongs to a DIFFERENT repository must be excluded from PR
# discovery. The fake-gh harness mocks the whole `gh api ... --jq`
# call and can't exercise jq's own server-side filtering, so this runs
# the real jq filter directly (extracted from CALL_TIMELINE_ARGS, the
# same literal expression the argv-matching fixtures above already
# confirm the script actually sends) against a synthetic two-event
# timeline: one same-repo PR (#501), one cross-repo PR that happens to
# share a colliding number (#999, in a foreign repository).
if command -v jq >/dev/null 2>&1; then
  timeline_jq_expr="${CALL_TIMELINE_ARGS#*--jq }"
  cross_repo_fixture="$SANDBOX/f8-timeline.json"
  cat > "$cross_repo_fixture" <<'JSONEOF'
[
  {"event":"cross-referenced","source":{"issue":{"number":501,"pull_request":{},"repository":{"full_name":"owner/repo"}}}},
  {"event":"cross-referenced","source":{"issue":{"number":999,"pull_request":{},"repository":{"full_name":"someone-else/unrelated-repo"}}}}
]
JSONEOF
  f8_result="$(jq -r "$timeline_jq_expr" "$cross_repo_fixture" 2>&1)"
  case "$f8_result" in
    'PR'*'501'*)
      case "$f8_result" in
        *999*) fail "S152 F-8 — the timeline jq filter let the cross-repo PR #999 through: $f8_result" ;;
        *) : ;;
      esac
      ;;
    *) fail "S152 F-8 — the timeline jq filter didn't keep the same-repo PR #501: $f8_result" ;;
  esac
else
  fail "S152 F-8 — jq not installed; cannot directly verify the timeline cross-repo filter"
fi

# issue #317 F-8's fail-open branch (round 1 review, should-fix): every
# fixture above answers the repo-identity call, so the branch that
# falls back to the OLD, unfiltered timeline query when that call
# itself fails was never actually exercised end to end — a regression
# that dropped every candidate on identity-lookup failure (rather than
# correctly staying over-inclusive) would have gone unnoticed. No
# __CALL_REPO_IDENTITY__ arm here at all (falls through, simulating
# that call failing); __CALL_TIMELINE_UNFILTERED__ answers the
# fallback shape the script sends once it can't confirm its own
# identity — captured the same way every other pattern in this file
# was, by observing the real script's argv against a recording fake gh.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
__CALL_ISSUE__)
  exit 0 ;;
__CALL_ISSUE_COMMENTS__)
  exit 0 ;;
__CALL_TIMELINE_UNFILTERED__)
  printf 'PR\t501\n'
  exit 0 ;;
__CALL_PR501_TITLEBODY__)
  printf 'TITLE\t\nBODY\tCloses #400\n'
  exit 0 ;;
__CALL_PR501_COMMENTS__)
  printf 'TEXT\t<!-- model-record: stage=Review model="claude-sonnet-5" effort="medium" -->\n'
  exit 0 ;;
__CALL_PR501_REVIEWS__)
  exit 0 ;;
GHEOF
fakebin_f8fo="$(cat "$FAKEGH_OUT")"
output_f8fo="$(PATH="$fakebin_f8fo:$PATH" "$script" 400 2>/tmp/s152_f8fo_stderr.$$)"; status_f8fo=$?
stderr_f8fo="$(cat /tmp/s152_f8fo_stderr.$$ 2>/dev/null)"
rm -f /tmp/s152_f8fo_stderr.$$
[ "$status_f8fo" -eq 0 ] || fail "S152 F-8 fail-open — expected exit 0, got $status_f8fo"
[ "$(assert_verdict_shape 'S152 F-8 fail-open' "$output_f8fo")" = "stale" ] || fail "S152 F-8 fail-open — a failed repo-identity lookup must fall back to the unfiltered timeline query, still finding PR #501's evidence: expected stale, got: $output_f8fo"
case "$stderr_f8fo" in
  *"won't be filtered out"*) : ;;
  *) fail "S152 F-8 fail-open — expected a warning naming the skipped cross-repo filtering on stderr, got: $stderr_f8fo" ;;
esac

# issue #317 AC6 (F-10) — the issue's own comments fetch fails, but a
# real closing PR's reviews fetch succeeds and supplies evidence all
# the way to the ceiling stage (Review). Closes the mutation-testing
# gap round 3 of PR #316's review found: putting back an early-exit-
# on-comments-failure change was the one mutation that survived
# unnoticed, because nothing pinned this exact combination. Already
# correct by construction (evidence at the ceiling stage overrides any
# residual absence-uncertainty — same asymmetric-degrade rule as the
# positive controls above), so this is coverage, not a fix.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
__CALL_ISSUE__)
  exit 0 ;;
__CALL_REPO_IDENTITY__)
  printf 'owner/repo\n'
  exit 0 ;;
__CALL_TIMELINE__)
  printf 'PR\t501\n'
  exit 0 ;;
__CALL_PR501_TITLEBODY__)
  printf 'TITLE\t\nBODY\tCloses #400\n'
  exit 0 ;;
__CALL_PR501_COMMENTS__)
  exit 0 ;;
__CALL_PR501_REVIEWS__)
  printf 'TEXT\t<!-- model-record: stage=Review model="claude-sonnet-5" effort="medium" -->\n'
  exit 0 ;;
GHEOF
fakebin_f10="$(cat "$FAKEGH_OUT")"
output_f10="$(PATH="$fakebin_f10:$PATH" "$script" 400 2>/dev/null)"; status_f10=$?
[ "$status_f10" -eq 0 ] || fail "S152 F-10 — expected exit 0, got $status_f10"
[ "$(assert_verdict_shape 'S152 F-10' "$output_f10")" = "stale" ] || fail "S152 F-10 — issue comments failed but PR #501's reviews evidence (stage=Review, the ceiling) must still render stale (no label at all), not indeterminate: $output_f10"

test_done
