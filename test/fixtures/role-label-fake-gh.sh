#!/usr/bin/env bash
# test/fixtures/role-label-fake-gh.sh — the recording fake-gh builder of S152
# (role-label-staleness.sh's REST call shapes for issue #400 and candidate PR
# #501), extracted verbatim so S198 can reuse it. Source after sandbox_create.
# Bash 3.2.

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

