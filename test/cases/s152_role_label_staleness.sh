#!/usr/bin/env bash
# S152 — role-label-staleness.sh detects role:<name> label staleness for
# one issue (issue #315, epic #295 W3).
# Covers: F35
#
# Single-file, S130-style inline fixtures (QA's own call in issue #315's
# Test comment: this script has one call shape — issue + N PRs — and one
# output line, not compliance-evidence.sh's six gates/three call shapes,
# so a separate shared *-fixture.sh file (S150/S151's own reason for
# splitting one out) buys nothing here).
#
# Every fixture below fixes the issue number at #400 (never a real issue
# in this repo) and varies only the fake gh's returned data — mirrors
# compliance-evidence-fixture.sh's own CALL_A_ARGS convention of a fixed
# PR number (#279) with varying fixture bodies. The exact argv strings
# (CALL_ISSUE_ARGS / CALL_PR5nn_ARGS below) were captured by observing
# role-label-staleness.sh's own real argv against a recording fake gh,
# never retyped from the source by hand (Architect's fixture-hygiene
# rule, #296/#302) — a drift in the script's graphql query or --jq
# expression shows up here as a fallthrough (h) failure, not a silent
# false pass.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

script="$TEST_REPO_ROOT/role-label-staleness.sh"
[ -x "$script" ] || { fail "S152 — role-label-staleness.sh is missing or not executable"; test_done; }

sandbox_create
trap sandbox_destroy EXIT

# --- Fixed argv patterns (captured, not retyped — see header). Every
# case arm below is single-quoted so the literal `$owner`/`$repo`/
# `$number` GraphQL variable syntax inside the query text is never
# mistaken by bash for a real variable expansion when the fake gh script
# itself is parsed and run.
CALL_ISSUE_ARGS='api graphql -f query=query($owner:String!,$repo:String!,$number:Int!){repository(owner:$owner,name:$repo){issue(number:$number){labels(first:20){nodes{name}}body comments(first:100){nodes{body}}closedByPullRequestsReferences(first:20){nodes{number}}}}} -F owner={owner} -F repo={repo} -F number=400 --jq .data.repository.issue | (.labels.nodes[]? | "LABEL\t"+.name),(.closedByPullRequestsReferences.nodes[]? | "PR\t"+(.number|tostring)),("TEXT\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001"))),(.comments.nodes[]? | "TEXT\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001")))'
CALL_PR501_ARGS='pr view 501 --json body,comments --jq ("TEXT\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001"))),(.comments[]? | "TEXT\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001")))'
CALL_PR502_ARGS='pr view 502 --json body,comments --jq ("TEXT\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001"))),(.comments[]? | "TEXT\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001")))'
CALL_PR503_ARGS='pr view 503 --json body,comments --jq ("TEXT\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001"))),(.comments[]? | "TEXT\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001")))'
CALL_PR504_ARGS='pr view 504 --json body,comments --jq ("TEXT\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001"))),(.comments[]? | "TEXT\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001")))'

pattern_issue="'$CALL_ISSUE_ARGS'"
pattern_pr501="'$CALL_PR501_ARGS'"
pattern_pr502="'$CALL_PR502_ARGS'"
pattern_pr503="'$CALL_PR503_ARGS'"
pattern_pr504="'$CALL_PR504_ARGS'"

# Reads a heredoc-style fake-gh script body from stdin (never wrapped in
# $(...) at the call site — same parser hazard compliance-evidence-
# fixture.sh's own run_build_fake_gh avoids: a literal ')' inside the
# heredoc, unavoidable in case-arm syntax and this script's own --jq
# expressions, would otherwise close the surrounding command
# substitution before the heredoc terminator is ever reached).
# __CALL_ISSUE__/__CALL_PR501__/__CALL_PR502__/__CALL_PR503__/
# __CALL_PR504__ are replaced with the exact argv patterns above via
# plain substring replacement — also quote-safe, since heredoc content
# is never re-parsed as shell syntax at substitution time.
#
# Every fixture also gets a fallthrough arm that appends the unexpected
# argv to a witness file and exits 1 — (h)'s read-only verification,
# built into every arm rather than opted into per-case, so a stray
# unexpected `gh` call anywhere always fails loudly instead of silently
# returning gh's own default exit-1-with-nothing-on-stdout.
FAKEGH_OUT="$SANDBOX/fakegh-out"
WITNESS="$SANDBOX/witness"
run_build_fake_gh() {
  local body
  body="$(cat)"
  body="${body//__CALL_ISSUE__/$pattern_issue}"
  body="${body//__CALL_PR501__/$pattern_pr501}"
  body="${body//__CALL_PR502__/$pattern_pr502}"
  body="${body//__CALL_PR503__/$pattern_pr503}"
  body="${body//__CALL_PR504__/$pattern_pr504}"
  body="$body
echo \"UNEXPECTED: \$*\" >> '$WITNESS'
exit 1"
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
# =========================================================================
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_ISSUE__)
    printf 'LABEL\trole:qa\n'
    printf 'PR\t501\n'
    exit 0 ;;
  __CALL_PR501__)
    printf 'TEXT\t<!-- model-record: stage=Test model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
esac
exit 1
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
: > "$WITNESS"
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_ISSUE__)
    printf 'LABEL\trole:architect\n'
    printf 'PR\t501\n'
    exit 0 ;;
  __CALL_PR501__)
    printf 'TEXT\t<!-- model-record: stage=Test model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
esac
exit 1
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
: > "$WITNESS"
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_ISSUE__)
    printf 'LABEL\trole:product\n'
    exit 0 ;;
esac
exit 1
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
: > "$WITNESS"
# (d1) AC3 — no label, no marker anywhere -> not-started, not stale.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_ISSUE__)
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_d1="$(cat "$FAKEGH_OUT")"
output_d1="$(PATH="$fakebin_d1:$PATH" "$script" 400)"; status_d1=$?
[ "$status_d1" -eq 0 ] || fail "S152 (d1) — expected exit 0, got $status_d1"
[ "$(assert_verdict_shape 'S152 (d1)' "$output_d1")" = "not-started" ] || fail "S152 (d1) — expected not-started (no label, no marker), got: $output_d1"

# (d2) AC4 — no label, but at least one live marker exists -> stale, not
# not-started. Directly exercises the AC3/AC4 boundary (one marker
# appears) rather than trusting it falls out of (d1)/(b) for free.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_ISSUE__)
    printf 'TEXT\t<!-- model-record: stage=Discovery model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_d2="$(cat "$FAKEGH_OUT")"
output_d2="$(PATH="$fakebin_d2:$PATH" "$script" 400)"; status_d2=$?
[ "$status_d2" -eq 0 ] || fail "S152 (d2) — expected exit 0, got $status_d2"
[ "$(assert_verdict_shape 'S152 (d2)' "$output_d2")" = "stale" ] || fail "S152 (d2) — expected stale (no label, one marker exists — AC3/AC4 boundary), got: $output_d2"
expected_d2='role-label-staleness: issue #400 — stale (issue #400 carries no role:<name> label, but a stage=Discovery marker already exists — expected role:product)'
[ "$output_d2" = "$expected_d2" ] || fail "S152 (d2) — exact detail text wrong:
expected: $expected_d2
got:      $output_d2"
[ -s "$WITNESS" ] && fail "S152 (d) — unexpected gh call(s): $(cat "$WITNESS")"

# =========================================================================
# (e) — label present, zero linked PRs -> a normal verdict from
# issue-only evidence, never indeterminate on its own. Distinct from
# (e3) below: this is Call 1 succeeding with an empty PR list, not a
# lookup failure.
# =========================================================================
: > "$WITNESS"
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_ISSUE__)
    printf 'LABEL\trole:dev\n'
    printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_e="$(cat "$FAKEGH_OUT")"
output_e="$(PATH="$fakebin_e:$PATH" "$script" 400)"; status_e=$?
[ "$status_e" -eq 0 ] || fail "S152 (e) — expected exit 0, got $status_e"
[ "$(assert_verdict_shape 'S152 (e)' "$output_e")" = "in-sync" ] || fail "S152 (e) — expected in-sync from issue-only evidence with zero linked PRs, got: $output_e"
[ -s "$WITNESS" ] && fail "S152 (e) — unexpected gh call(s) — zero PRs must mean no Call 2 at all: $(cat "$WITNESS")"

# =========================================================================
# (e2) — Call 1 (the issue lookup) itself fails -> fatal, exit 4, no
# verdict on stdout.
# =========================================================================
: > "$WITNESS"
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
GHEOF
fakebin_e2="$(cat "$FAKEGH_OUT")"
output_e2="$(PATH="$fakebin_e2:$PATH" "$script" 400 2>/dev/null)"; status_e2=$?
[ "$status_e2" -eq 4 ] || fail "S152 (e2) — expected exit 4 when the issue lookup fails, got $status_e2"
[ -z "$output_e2" ] || fail "S152 (e2) — expected nothing on stdout when the issue lookup fails, got: $output_e2"

# =========================================================================
# (e3) — a PR lookup failure. Two sub-arms, kept explicitly separate
# (QA's Test comment): the degrade case, and its required positive
# control (a sound verdict from what WAS read must not be dragged into
# indeterminate just because a lookup somewhere failed).
# =========================================================================
: > "$WITNESS"
# (e3a) — the only linked PR's lookup fails while issue-side evidence
# already places the label in-sync from what was read; a missing PR
# could still reveal a later stage, so this must degrade.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_ISSUE__)
    printf 'LABEL\trole:architect\n'
    printf 'PR\t501\n'
    printf 'TEXT\t<!-- model-record: stage=Planning model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_e3a="$(cat "$FAKEGH_OUT")"
output_e3a="$(PATH="$fakebin_e3a:$PATH" "$script" 400 2>/dev/null)"; status_e3a=$?
[ "$status_e3a" -eq 0 ] || fail "S152 (e3a) — expected exit 0 (a degrade, not a fatal error), got $status_e3a"
[ "$(assert_verdict_shape 'S152 (e3a)' "$output_e3a")" = "indeterminate" ] || fail "S152 (e3a) — expected indeterminate (only linked PR's lookup failed, label in-sync from issue-only evidence, could flip to stale), got: $output_e3a"

# (e3b) positive control — two linked PRs, one's lookup fails, but the
# other's evidence alone already settles the verdict at the ceiling
# stage (role:reviewer/Review — nothing a missing PR could reveal can
# ever place the true latest stage past Review), so PR_LOOKUP_FAILED
# must NOT drag this into indeterminate.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_ISSUE__)
    printf 'LABEL\trole:reviewer\n'
    printf 'PR\t501\n'
    printf 'PR\t502\n'
    exit 0 ;;
  __CALL_PR501__)
    printf 'TEXT\t<!-- model-record: stage=Review model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_e3b="$(cat "$FAKEGH_OUT")"
output_e3b="$(PATH="$fakebin_e3b:$PATH" "$script" 400 2>/dev/null)"; status_e3b=$?
[ "$status_e3b" -eq 0 ] || fail "S152 (e3b) — expected exit 0, got $status_e3b"
[ "$(assert_verdict_shape 'S152 (e3b)' "$output_e3b")" = "in-sync" ] || fail "S152 (e3b) positive control — expected in-sync (label already at the ceiling stage from the PR that WAS read; PR #502's failure can't change that), got: $output_e3b"

# (e3c) second positive control — a verdict already correctly `stale`
# from evidence that WAS read must not degrade either: absence is only
# ever additive (a missing PR can push the true latest stage later,
# never earlier), so an already-stale verdict can only stay stale, never
# get undone into in-sync, by evidence nobody has read yet.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_ISSUE__)
    printf 'LABEL\trole:architect\n'
    printf 'PR\t501\n'
    printf 'PR\t502\n'
    exit 0 ;;
  __CALL_PR501__)
    printf 'TEXT\t<!-- model-record: stage=Test model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_e3c="$(cat "$FAKEGH_OUT")"
output_e3c="$(PATH="$fakebin_e3c:$PATH" "$script" 400 2>/dev/null)"; status_e3c=$?
[ "$status_e3c" -eq 0 ] || fail "S152 (e3c) — expected exit 0, got $status_e3c"
[ "$(assert_verdict_shape 'S152 (e3c)' "$output_e3c")" = "stale" ] || fail "S152 (e3c) second positive control — expected stale (already behind from evidence read; PR #502's failure can only deepen that, never undo it), got: $output_e3c"

# =========================================================================
# (f) — multiple linked PRs, markers split across them -> union/max,
# order-independent. Run twice with the two PR lines swapped in Call 1's
# output and assert byte-identical results (direct analogue of S150's
# Arm G order-independence check).
# =========================================================================
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_ISSUE__)
    printf 'LABEL\trole:qa\n'
    printf 'PR\t501\n'
    printf 'PR\t502\n'
    exit 0 ;;
  __CALL_PR501__)
    printf 'TEXT\t<!-- model-record: stage=Discovery model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
  __CALL_PR502__)
    printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_f1="$(cat "$FAKEGH_OUT")"
output_f1="$(PATH="$fakebin_f1:$PATH" "$script" 400)"; status_f1=$?
[ "$status_f1" -eq 0 ] || fail "S152 (f, order A) — expected exit 0, got $status_f1"
[ "$(assert_verdict_shape 'S152 (f, order A)' "$output_f1")" = "stale" ] || fail "S152 (f, order A) — expected stale (role:qa behind the union max, stage=Implementation from PR #502), got: $output_f1"

run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_ISSUE__)
    printf 'LABEL\trole:qa\n'
    printf 'PR\t502\n'
    printf 'PR\t501\n'
    exit 0 ;;
  __CALL_PR501__)
    printf 'TEXT\t<!-- model-record: stage=Discovery model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
  __CALL_PR502__)
    printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
esac
exit 1
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
# shape — a marker-shaped occurrence, quoted, next to an unrelated live
# label). Label alone with the quoted marker stripped must render
# in-sync (case (c)'s shape), not in-sync-with-Test-evidenced.
# =========================================================================
: > "$WITNESS"
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_ISSUE__)
    printf 'LABEL\trole:product\n'
    printf 'TEXT\t```\001<!-- model-record: stage=Test model="claude-sonnet-5" effort="medium" -->\001```\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_g1="$(cat "$FAKEGH_OUT")"
output_g1="$(PATH="$fakebin_g1:$PATH" "$script" 400)"; status_g1=$?
[ "$status_g1" -eq 0 ] || fail "S152 (g1) — expected exit 0, got $status_g1"
[ "$(assert_verdict_shape 'S152 (g1)' "$output_g1")" = "in-sync" ] || fail "S152 (g1) — expected in-sync (the only stage=Test marker is fenced/quoted, must not count as live evidence — live_text() reuse), got: $output_g1"
case "$output_g1" in
  *"stage=Test"*) fail "S152 (g1) — the quoted/fenced marker leaked through as live evidence: $output_g1" ;;
esac

# =========================================================================
# (g2) — the new stage-extraction logic's own correctness: a LIVE
# (non-quoted) marker whose stage= value isn't one of the fixed five
# must render indeterminate (AC6), never silently treated as absent and
# never coerced into the nearest recognized stage. Distinct from (g1):
# this exercises the new extraction code, not the borrowed live_text()
# guard.
# =========================================================================
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_ISSUE__)
    printf 'LABEL\trole:qa\n'
    printf 'TEXT\t<!-- model-record: stage=discovery model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_g2="$(cat "$FAKEGH_OUT")"
output_g2="$(PATH="$fakebin_g2:$PATH" "$script" 400)"; status_g2=$?
[ "$status_g2" -eq 0 ] || fail "S152 (g2) — expected exit 0, got $status_g2"
[ "$(assert_verdict_shape 'S152 (g2)' "$output_g2")" = "indeterminate" ] || fail "S152 (g2) — expected indeterminate (live marker with unrecognized stage=discovery, wrong case), got: $output_g2"

# (g2b) — a marker matched by the anchor but with no stage= token at
# all (AC6's other half: "no parseable stage") must also render
# indeterminate, not silently invisible.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_ISSUE__)
    printf 'TEXT\t<!-- model-record: model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_g2b="$(cat "$FAKEGH_OUT")"
output_g2b="$(PATH="$fakebin_g2b:$PATH" "$script" 400)"; status_g2b=$?
[ "$status_g2b" -eq 0 ] || fail "S152 (g2b) — expected exit 0, got $status_g2b"
[ "$(assert_verdict_shape 'S152 (g2b)' "$output_g2b")" = "indeterminate" ] || fail "S152 (g2b) — expected indeterminate (model-record marker matched but has no stage= at all), got: $output_g2b"

# =========================================================================
# (g3) — one linked PR carries a malformed marker, another linked PR
# carries a well-formed marker for a later stage: overall verdict must
# still be indeterminate (the malformed sighting always wins), not
# stale/in-sync computed from the well-formed one alone — Architect's
# blunt/conservative reading.
# =========================================================================
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_ISSUE__)
    printf 'LABEL\trole:architect\n'
    printf 'PR\t501\n'
    printf 'PR\t502\n'
    exit 0 ;;
  __CALL_PR501__)
    printf 'TEXT\t<!-- model-record: stage=QA model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
  __CALL_PR502__)
    printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_g3="$(cat "$FAKEGH_OUT")"
output_g3="$(PATH="$fakebin_g3:$PATH" "$script" 400)"; status_g3=$?
[ "$status_g3" -eq 0 ] || fail "S152 (g3) — expected exit 0, got $status_g3"
[ "$(assert_verdict_shape 'S152 (g3)' "$output_g3")" = "indeterminate" ] || fail "S152 (g3) — expected indeterminate (malformed marker on PR #501 must force this even though PR #502 alone would read stale), got: $output_g3"
case "$output_g3" in
  *"stage=Implementation"*'expected role:dev'*) fail "S152 (g3) — computed stale from the well-formed PR alone instead of forcing indeterminate: $output_g3" ;;
esac

# =========================================================================
# AC5 — two-or-more role:<name> labels at once -> indeterminate, naming
# every one found. Tested with exactly two and with three.
# =========================================================================
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_ISSUE__)
    printf 'LABEL\trole:product\n'
    printf 'LABEL\trole:qa\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_ac5a="$(cat "$FAKEGH_OUT")"
output_ac5a="$(PATH="$fakebin_ac5a:$PATH" "$script" 400)"; status_ac5a=$?
[ "$status_ac5a" -eq 0 ] || fail "S152 AC5 (two labels) — expected exit 0, got $status_ac5a"
[ "$(assert_verdict_shape 'S152 AC5 (two)' "$output_ac5a")" = "indeterminate" ] || fail "S152 AC5 (two labels) — expected indeterminate, got: $output_ac5a"
assert_contains "S152 AC5 (two labels) — names role:product" "role:product" "$output_ac5a"
assert_contains "S152 AC5 (two labels) — names role:qa" "role:qa" "$output_ac5a"

run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_ISSUE__)
    printf 'LABEL\trole:product\n'
    printf 'LABEL\trole:architect\n'
    printf 'LABEL\trole:reviewer\n'
    exit 0 ;;
esac
exit 1
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
case "$*" in
  __CALL_ISSUE__)
    printf 'LABEL\tbug\n'
    printf 'LABEL\tpriority:high\n'
    printf 'LABEL\trole:qa\n'
    printf 'TEXT\t<!-- model-record: stage=Test model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_filter="$(cat "$FAKEGH_OUT")"
output_filter="$(PATH="$fakebin_filter:$PATH" "$script" 400)"; status_filter=$?
[ "$status_filter" -eq 0 ] || fail "S152 (label filtering) — expected exit 0, got $status_filter"
[ "$(assert_verdict_shape 'S152 (label filtering)' "$output_filter")" = "in-sync" ] || fail "S152 (label filtering) — unrelated labels (bug, priority:high) alongside role:qa must not read as multiple role labels, got: $output_filter"

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

# (h) — fake_gh_bin fallthrough fails loudly (recorded to a witness
# file) on any unexpected gh call. Deliberately calls with a fake gh that
# has NO matching case arm at all for either call, so if the script ever
# tried an unanticipated gh invocation shape it would hit the
# fallthrough and get witnessed.
: > "$WITNESS"
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_ISSUE__)
    printf 'LABEL\trole:qa\n'
    printf 'PR\t501\n'
    exit 0 ;;
  __CALL_PR501__)
    printf 'TEXT\t<!-- model-record: stage=Test model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
esac
exit 1
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

# The conjunction itself — neither (h) alone nor (i) alone is allowed to
# pass vacuously for the other.
if [ "$h_witness_empty" -eq 1 ] && [ "$h_exit_ok" -eq 1 ] && [ "$h_shape_ok" -eq 1 ] && [ "$i_clean" -eq 1 ]; then
  : # AC7 holds: read-only, verified both ways
else
  fail "S152 AC7 — read-only verification did not hold as a conjunction of (h) and (i)"
fi

test_done
