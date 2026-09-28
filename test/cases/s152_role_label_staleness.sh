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
# Rewritten for the REST-only redesign (Architect's issue #315 comment,
# 2026-09-28, after Reviewer's PR #316 findings): no `gh api graphql`,
# `gh issue view`, or `gh pr view` anywhere — every call is `gh api`
# against an explicit REST endpoint (issue body+labels, issue comments,
# the issue's timeline for candidate PRs, each candidate's current PR
# body for the closing-keyword filter, and each kept PR's comments).
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
CALL_TIMELINE_ARGS='api repos/{owner}/{repo}/issues/400/timeline --paginate --jq .[] | select(.event=="cross-referenced" and .source.issue.pull_request != null) | "PR\t"+(.source.issue.number|tostring)'
CALL_PR501_BODY_ARGS='api repos/{owner}/{repo}/pulls/501 --jq "BODY\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001"))'
CALL_PR501_COMMENTS_ARGS='api repos/{owner}/{repo}/issues/501/comments --paginate --jq .[] | "TEXT\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001"))'
CALL_PR502_BODY_ARGS='api repos/{owner}/{repo}/pulls/502 --jq "BODY\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001"))'
CALL_PR502_COMMENTS_ARGS='api repos/{owner}/{repo}/issues/502/comments --paginate --jq .[] | "TEXT\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001"))'

pattern_issue="'$CALL_ISSUE_ARGS'"
pattern_issue_comments="'$CALL_ISSUE_COMMENTS_ARGS'"
pattern_timeline="'$CALL_TIMELINE_ARGS'"
pattern_pr501_body="'$CALL_PR501_BODY_ARGS'"
pattern_pr501_comments="'$CALL_PR501_COMMENTS_ARGS'"
pattern_pr502_body="'$CALL_PR502_BODY_ARGS'"
pattern_pr502_comments="'$CALL_PR502_COMMENTS_ARGS'"

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
# F-2 fix (PR #316 Reviewer): the ONE `case "$*" in ... esac` and the
# witness-plus-exit-1 fallthrough are supplied ONCE, here, centrally —
# never per-fixture. A fixture below supplies only the arms it wants to
# answer; any call it has no arm for correctly falls through to the
# witness line and exit 1 (a fixture's own missing arm is how a call is
# made to "fail" for that test, same as every other fake_gh_bin fixture
# in this repo). The previous version had each fixture supply its own
# trailing `esac; exit 1` *after* which the witness line was appended —
# unreachable, since a case statement's own `exit 1` inside the fixture
# already terminated the process first. This version's witness line
# sits *inside* the one case statement's fallthrough, so it's reached by
# construction whenever no arm matches, and never otherwise (a matched
# arm's own `exit 0 ;;` always exits the script before the fallthrough
# is reached, since a case arm's `exit` ends the whole process, not the
# case statement).
run_build_fake_gh() {
  local arms body
  arms="$(cat)"
  arms="${arms//__CALL_ISSUE__/$pattern_issue}"
  arms="${arms//__CALL_ISSUE_COMMENTS__/$pattern_issue_comments}"
  arms="${arms//__CALL_TIMELINE__/$pattern_timeline}"
  arms="${arms//__CALL_PR501_BODY__/$pattern_pr501_body}"
  arms="${arms//__CALL_PR501_COMMENTS__/$pattern_pr501_comments}"
  arms="${arms//__CALL_PR502_BODY__/$pattern_pr502_body}"
  arms="${arms//__CALL_PR502_COMMENTS__/$pattern_pr502_comments}"

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
# Full success: every call the script makes is answered, so the witness
# must stay empty.
# =========================================================================
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
__CALL_ISSUE__)
  printf 'LABEL\trole:qa\n'
  exit 0 ;;
__CALL_ISSUE_COMMENTS__)
  exit 0 ;;
__CALL_TIMELINE__)
  printf 'PR\t501\n'
  exit 0 ;;
__CALL_PR501_BODY__)
  printf 'BODY\tCloses #400\n'
  exit 0 ;;
__CALL_PR501_COMMENTS__)
  printf 'TEXT\t<!-- model-record: stage=Test model="claude-sonnet-5" effort="medium" -->\n'
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
__CALL_TIMELINE__)
  printf 'PR\t501\n'
  exit 0 ;;
__CALL_PR501_BODY__)
  printf 'BODY\tCloses #400\n'
  exit 0 ;;
__CALL_PR501_COMMENTS__)
  printf 'TEXT\t<!-- model-record: stage=Test model="claude-sonnet-5" effort="medium" -->\n'
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
# New failure semantics — three independent flags (Architect's redesign,
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
GHEOF
fakebin_pdf="$(cat "$FAKEGH_OUT")"
output_pdf="$(PATH="$fakebin_pdf:$PATH" "$script" 400 2>/dev/null)"; status_pdf=$?
[ "$status_pdf" -eq 0 ] || fail "S152 (PR_DISCOVERY_FAILED) — expected exit 0, got $status_pdf"
[ "$(assert_verdict_shape 'S152 (PR_DISCOVERY_FAILED)' "$output_pdf")" = "indeterminate" ] || fail "S152 (PR_DISCOVERY_FAILED) — expected indeterminate (timeline lookup failed, must not read as zero PRs), got: $output_pdf"
assert_contains "S152 (PR_DISCOVERY_FAILED) — names the failure" "timeline lookup failed" "$output_pdf"

# (PR_LOOKUP_FAILED, sub-arm: candidate body fetch fails) — the only
# candidate's pulls/<pr> call fails; whether it even closes the issue is
# now unknown, not "no match".
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
__CALL_ISSUE__)
  printf 'LABEL\trole:architect\n'
  exit 0 ;;
__CALL_ISSUE_COMMENTS__)
  printf 'TEXT\t<!-- model-record: stage=Planning model="claude-sonnet-5" effort="medium" -->\n'
  exit 0 ;;
__CALL_TIMELINE__)
  printf 'PR\t501\n'
  exit 0 ;;
GHEOF
fakebin_plf_body="$(cat "$FAKEGH_OUT")"
output_plf_body="$(PATH="$fakebin_plf_body:$PATH" "$script" 400 2>/dev/null)"; status_plf_body=$?
[ "$status_plf_body" -eq 0 ] || fail "S152 (PR_LOOKUP_FAILED, body) — expected exit 0, got $status_plf_body"
[ "$(assert_verdict_shape 'S152 (PR_LOOKUP_FAILED, body)' "$output_plf_body")" = "indeterminate" ] || fail "S152 (PR_LOOKUP_FAILED, body) — expected indeterminate (the only candidate's body fetch failed, label in-sync from issue-only evidence), got: $output_plf_body"

# (PR_LOOKUP_FAILED, sub-arm: kept PR's comments fetch fails) — the body
# fetch succeeds and matches the closing keyword (so it's kept), but its
# comments call fails.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
__CALL_ISSUE__)
  printf 'LABEL\trole:architect\n'
  exit 0 ;;
__CALL_ISSUE_COMMENTS__)
  exit 0 ;;
__CALL_TIMELINE__)
  printf 'PR\t501\n'
  exit 0 ;;
__CALL_PR501_BODY__)
  printf 'BODY\tCloses #400\n'
  exit 0 ;;
GHEOF
fakebin_plf_comments="$(cat "$FAKEGH_OUT")"
output_plf_comments="$(PATH="$fakebin_plf_comments:$PATH" "$script" 400 2>/dev/null)"; status_plf_comments=$?
[ "$status_plf_comments" -eq 0 ] || fail "S152 (PR_LOOKUP_FAILED, comments) — expected exit 0, got $status_plf_comments"
[ "$(assert_verdict_shape 'S152 (PR_LOOKUP_FAILED, comments)' "$output_plf_comments")" = "indeterminate" ] || fail "S152 (PR_LOOKUP_FAILED, comments) — expected indeterminate (kept PR's comments unread), got: $output_plf_comments"

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
GHEOF
fakebin_pc2="$(cat "$FAKEGH_OUT")"
output_pc2="$(PATH="$fakebin_pc2:$PATH" "$script" 400 2>/dev/null)"; status_pc2=$?
[ "$status_pc2" -eq 0 ] || fail "S152 positive control 2 — expected exit 0, got $status_pc2"
[ "$(assert_verdict_shape 'S152 positive control 2' "$output_pc2")" = "stale" ] || fail "S152 positive control 2 — expected stale (already behind from evidence read; issue-comments AND timeline both failing can only deepen that, never undo it), got: $output_pc2"

# =========================================================================
# Closing-keyword filter — the timeline over-includes by design
# (Architect's redesign): a cross-referencing PR that mentions the issue
# in prose, without a real closing keyword, must be excluded, and never
# even get a comments call (no arm for PR #502's comments below — if the
# implementation wrongly fetched them anyway, the fallthrough witness
# would catch it).
# =========================================================================
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
__CALL_ISSUE__)
  printf 'LABEL\trole:qa\n'
  exit 0 ;;
__CALL_ISSUE_COMMENTS__)
  exit 0 ;;
__CALL_TIMELINE__)
  printf 'PR\t501\nPR\t502\n'
  exit 0 ;;
__CALL_PR501_BODY__)
  printf 'BODY\tCloses #400\n'
  exit 0 ;;
__CALL_PR501_COMMENTS__)
  printf 'TEXT\t<!-- model-record: stage=Test model="claude-sonnet-5" effort="medium" -->\n'
  exit 0 ;;
__CALL_PR502_BODY__)
  printf 'BODY\tSee also #400 for related context; unrelated work otherwise.\n'
  exit 0 ;;
GHEOF
fakebin_kw="$(cat "$FAKEGH_OUT")"
output_kw="$(PATH="$fakebin_kw:$PATH" "$script" 400)"; status_kw=$?
[ "$status_kw" -eq 0 ] || fail "S152 (keyword filter) — expected exit 0, got $status_kw"
[ "$(assert_verdict_shape 'S152 (keyword filter)' "$output_kw")" = "in-sync" ] || fail "S152 (keyword filter) — expected in-sync (PR #502 merely mentions the issue, must be excluded), got: $output_kw"
[ -s "$WITNESS" ] && fail "S152 (keyword filter) — PR #502 must never get a comments call once excluded by the keyword filter: $(cat "$WITNESS")"

# Case-insensitivity + a non-standard-but-valid keyword ("fixes"), and a
# same-repo `owner/repo#N` form must NOT be mistaken for a bare `#N` —
# not in scope for v1 (accepted debt, same repo only), but confirms the
# ERE doesn't accidentally match the wrong issue.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
__CALL_ISSUE__)
  exit 0 ;;
__CALL_ISSUE_COMMENTS__)
  exit 0 ;;
__CALL_TIMELINE__)
  printf 'PR\t501\n'
  exit 0 ;;
__CALL_PR501_BODY__)
  printf 'BODY\tFIXES #400\n'
  exit 0 ;;
__CALL_PR501_COMMENTS__)
  printf 'TEXT\t<!-- model-record: stage=Discovery model="claude-sonnet-5" effort="medium" -->\n'
  exit 0 ;;
GHEOF
fakebin_kw2="$(cat "$FAKEGH_OUT")"
output_kw2="$(PATH="$fakebin_kw2:$PATH" "$script" 400)"; status_kw2=$?
[ "$status_kw2" -eq 0 ] || fail "S152 (keyword case-insensitive) — expected exit 0, got $status_kw2"
[ "$(assert_verdict_shape 'S152 (keyword case-insensitive)' "$output_kw2")" = "stale" ] || fail "S152 (keyword case-insensitive) — expected stale (uppercase FIXES #400 must still match, evidencing stage=Discovery with no label), got: $output_kw2"

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
__CALL_TIMELINE__)
  printf 'PR\t501\nPR\t502\n'
  exit 0 ;;
__CALL_PR501_BODY__)
  printf 'BODY\tCloses #400\n'
  exit 0 ;;
__CALL_PR501_COMMENTS__)
  printf 'TEXT\t<!-- model-record: stage=Discovery model="claude-sonnet-5" effort="medium" -->\n'
  exit 0 ;;
__CALL_PR502_BODY__)
  printf 'BODY\tFixes #400\n'
  exit 0 ;;
__CALL_PR502_COMMENTS__)
  printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
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
__CALL_TIMELINE__)
  printf 'PR\t502\nPR\t501\n'
  exit 0 ;;
__CALL_PR501_BODY__)
  printf 'BODY\tCloses #400\n'
  exit 0 ;;
__CALL_PR501_COMMENTS__)
  printf 'TEXT\t<!-- model-record: stage=Discovery model="claude-sonnet-5" effort="medium" -->\n'
  exit 0 ;;
__CALL_PR502_BODY__)
  printf 'BODY\tFixes #400\n'
  exit 0 ;;
__CALL_PR502_COMMENTS__)
  printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
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
__CALL_TIMELINE__)
  printf 'PR\t501\nPR\t502\n'
  exit 0 ;;
__CALL_PR501_BODY__)
  printf 'BODY\tCloses #400\n'
  exit 0 ;;
__CALL_PR501_COMMENTS__)
  printf 'TEXT\t<!-- model-record: stage=QA model="claude-sonnet-5" effort="medium" -->\n'
  exit 0 ;;
__CALL_PR502_BODY__)
  printf 'BODY\tFixes #400\n'
  exit 0 ;;
__CALL_PR502_COMMENTS__)
  printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
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
# run that answers every call the script actually makes.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
__CALL_ISSUE__)
  printf 'LABEL\trole:qa\n'
  exit 0 ;;
__CALL_ISSUE_COMMENTS__)
  exit 0 ;;
__CALL_TIMELINE__)
  printf 'PR\t501\n'
  exit 0 ;;
__CALL_PR501_BODY__)
  printf 'BODY\tCloses #400\n'
  exit 0 ;;
__CALL_PR501_COMMENTS__)
  printf 'TEXT\t<!-- model-record: stage=Test model="claude-sonnet-5" effort="medium" -->\n'
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
# F-2 finding: the first version's witness line sat after each
# fixture's own `esac; exit 1`, so it could never run — confirmed by a
# mutation probe that injected a write call and watched S152 stay
# green). This calls the fake `gh` binary DIRECTLY (not through
# role-label-staleness.sh) with an argv no arm above answers, which is
# exactly what an unanticipated call from the real script would look
# like to this harness — proving the fallthrough-plus-witness plumbing
# in run_build_fake_gh works, independently of whether the shipped
# script happens to make such a call today.
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

test_done
