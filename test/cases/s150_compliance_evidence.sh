#!/usr/bin/env bash
# S150 — The compliance-evidence collector reports what the artifacts
# actually show (issue #296).
# Covers: F34

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

script="$TEST_REPO_ROOT/compliance-evidence.sh"
[ -x "$script" ] || { fail "S150 — compliance-evidence.sh is missing or not executable"; test_done; }

sandbox_create
trap sandbox_destroy EXIT

# --- The three gh argv strings this collector's implementation issues,
# kept in one place each (Architect's fixture-hygiene rule): a drift in
# any --json field list or --jq expression is then a one-line fix here,
# not a rewrite of every arm. Captured by observing compliance-evidence.sh's
# actual argv against a recording fake gh, not retyped from the plan by
# hand.
CALL_A_ARGS='pr view 279 --json body,comments,closingIssuesReferences,headRefOid,mergedAt,mergedBy,state --jq "HEAD\t"+(.headRefOid//""),"STATE\t"+(.state//""),"MERGEDAT\t"+(.mergedAt//""),"MERGEDBY\t"+((.mergedBy.login)//""),(.closingIssuesReferences[]? | "ISSUE\t"+(.number|tostring)),("TEXT\t"+((.body//"")|gsub("\n";" "))),(.comments[]? | "TEXT\t"+((.body//"")|gsub("\n";" ")))'
CALL_B_ARGS='pr checks 279 --json name,state,bucket --jq .[] | .name+"\t"+.state+"\t"+.bucket'
CALL_C265_ARGS='issue view 265 --json comments --jq .comments[]? | "TEXT\t"+((.body//"")|gsub("\n";" "))'
CALL_C266_ARGS='issue view 266 --json comments --jq .comments[]? | "TEXT\t"+((.body//"")|gsub("\n";" "))'

pattern_a="'$CALL_A_ARGS'"
pattern_b="'$CALL_B_ARGS'"
pattern_c265="'$CALL_C265_ARGS'"
pattern_c266="'$CALL_C266_ARGS'"

# Reads a heredoc-style fake-gh script body from stdin — never wrapped in
# $(...) at the call site. A heredoc containing a literal ')' (unavoidable
# here: case-arm syntax, and this collector's own jq expressions, are full
# of them) breaks bash's parser when nested inside a command substitution
# — the parser treats the first such ')' as closing the substitution,
# before the heredoc terminator is ever reached, well before anything
# runs. Redirecting to a file instead of capturing via $(...) sidesteps
# that entirely. __CALL_A__/__CALL_B__/__CALL_C265__/__CALL_C266__ are
# replaced with the exact argv patterns above via plain substring
# replacement (also apostrophe/quote-safe: heredoc content is never
# re-parsed as shell syntax).
FAKEGH_OUT="$SANDBOX/fakegh-out"
run_build_fake_gh() {
  local body
  body="$(cat)"
  body="${body//__CALL_A__/$pattern_a}"
  body="${body//__CALL_B__/$pattern_b}"
  body="${body//__CALL_C265__/$pattern_c265}"
  body="${body//__CALL_C266__/$pattern_c266}"
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

# =========================================================================
# AC1 — reproduces the decided worked example (PR #279 / issue #265),
# referentially: each row cites the same underlying artifact the
# hand-written PRD §6 example cites.
#
# Fixture header: a recording of PR #279's real `gh pr view` / `gh pr
# checks` / `gh issue view` answers, as of 2026-09-26. Round-1's stale
# Review marker's exception text is paraphrased here to drop an
# apostrophe the live text has (single-quoted printf arguments below
# can't survive one) — its content, not its exact wording, is what every
# assertion here depends on.
# =========================================================================
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tMERGED\n'
    printf 'MERGEDAT\t2026-09-20T17:31:36Z\n'
    printf 'MERGEDBY\tTiesL\n'
    printf 'ISSUE\t265\n'
    printf 'TEXT\t<!-- model-record: stage=Discovery model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Planning model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Test model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Review model="claude-sonnet-5" effort="medium" same-model-exception="the fork session inherits its parent model; no other model was available to run this review" -->\n'
    printf 'TEXT\t<!-- pre-merge-review:done sha=472bc8f574c4aea3fc58161d1924b7b05329172f -->\n'
    printf 'TEXT\t<!-- model-record: stage=Review model="claude-sonnet-5" effort="medium" same-model-exception="fork/agent invocation for this review round runs on the same model as Implementation; no other model was made available for this review" -->\n'
    printf 'TEXT\t<!-- pre-merge-review:done sha=6e00a8c38bf18f19cd53084b5c77ae476c1e74e6 -->\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
  __CALL_C265__)
    printf ''
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_ac1="$(cat "$FAKEGH_OUT")"

# shellcheck disable=SC2016  # the backticks below are literal Markdown, not command substitution — single-quoted deliberately
expected_ac1='| Gate | Status | Evidence |
| --- | --- | --- |
| Per-stage model/effort recorded (Discovery, Planning, Test, Implementation) | evidenced | `model-record` markers on PR #279 for Discovery, Planning, Test, Implementation (all `claude-sonnet-5`) |
| Review used a different or at-least-as-capable model, or carries an explicit exception | evidenced | latest `stage=Review` marker on PR #279 carries `same-model-exception="fork/agent invocation for this review round runs on the same model as Implementation; no other model was made available for this review"` |
| Quality review before merge, with findings in the PR | evidenced | `<!-- pre-merge-review:done sha=6e00a8c38bf18f19cd53084b5c77ae476c1e74e6 -->` on PR #279, sha equals `headRefOid` (an earlier marker for `472bc8f574c4aea3fc58161d1924b7b05329172f` is stale) |
| CI green | evidenced | check `check`: `bucket=pass`, `state=SUCCESS` |
| Traceability link 3 (PR ↔ issue) | evidenced | `closingIssuesReferences` on PR #279 = [#265] |
| Ties'"'"' explicit merge confirmation | unverifiable-from-artifacts | not derivable from artifacts; A2 confirmation is conversational (PR merged by @TiesL at 2026-09-20T17:31:36Z, which is not the confirmation) |'

output_ac1="$(PATH="$fakebin_ac1:$PATH" "$script" 279)"
status_ac1=$?
[ "$status_ac1" -eq 0 ] || fail "S150 AC1 — expected exit 0, got $status_ac1"
[ "$output_ac1" = "$expected_ac1" ] || {
  fail "S150 AC1 — output doesn't match the worked example (referential identity, PR #279/#265):"
  diff <(printf '%s\n' "$expected_ac1") <(printf '%s\n' "$output_ac1") >&2 || true
}
assert_table_shape "S150 AC1" "$output_ac1"

# Determinism (AC6): the same fixture run twice must be byte-identical —
# catches a collector that stamps a collection timestamp into the output.
output_ac1_again="$(PATH="$fakebin_ac1:$PATH" "$script" 279)"
[ "$output_ac1" = "$output_ac1_again" ] || fail "S150 AC6 — two runs against the same fixture produced different output (not deterministic)"

# =========================================================================
# AC3 — a missing gate renders as missing, run does not abort.
# =========================================================================

# Fixture A: AC1's arm with the stage=Test marker removed.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tMERGED\n'
    printf 'MERGEDAT\t2026-09-20T17:31:36Z\n'
    printf 'MERGEDBY\tTiesL\n'
    printf 'ISSUE\t265\n'
    printf 'TEXT\t<!-- model-record: stage=Discovery model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Planning model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Review model="claude-sonnet-5" effort="medium" same-model-exception="fork/agent invocation for this review round runs on the same model as Implementation; no other model was made available for this review" -->\n'
    printf 'TEXT\t<!-- pre-merge-review:done sha=6e00a8c38bf18f19cd53084b5c77ae476c1e74e6 -->\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
  __CALL_C265__)
    printf ''
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_ac3a="$(cat "$FAKEGH_OUT")"
output_ac3a="$(PATH="$fakebin_ac3a:$PATH" "$script" 279)"
status_ac3a=$?
[ "$status_ac3a" -eq 0 ] || fail "S150 AC3a — expected exit 0 with a missing stage, got $status_ac3a"
assert_table_shape "S150 AC3a" "$output_ac3a"
[ "$(row_status "$output_ac3a" 1)" = "not-evidenced" ] || fail "S150 AC3a — expected gate 1 not-evidenced when stage=Test is missing, got '$(row_status "$output_ac3a" 1)'"
[ "$(row_status "$output_ac3a" 2)" = "evidenced" ] || fail "S150 AC3a — gate 2 should be unaffected by a missing stage 1 marker"
[ "$(row_status "$output_ac3a" 3)" = "evidenced" ] || fail "S150 AC3a — gate 3 should be unaffected"
[ "$(row_status "$output_ac3a" 4)" = "evidenced" ] || fail "S150 AC3a — gate 4 should be unaffected"

# Fixture B (finding (f)): AC1's arm with the ISSUE line removed
# entirely — zero closing issues. Gate 5 must go not-evidenced, call C
# must not be made at all (no __CALL_C265__ arm at all; the fallthrough
# would fire and exit 1 if the collector called it anyway), and the run
# must still emit six rows and exit 0.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tMERGED\n'
    printf 'MERGEDAT\t2026-09-20T17:31:36Z\n'
    printf 'MERGEDBY\tTiesL\n'
    printf 'TEXT\t<!-- model-record: stage=Discovery model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Planning model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Test model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
esac
echo "S150 AC3b: unexpected gh call: $*" >> "$SANDBOX/gh-witness-ac3b"
exit 1
GHEOF
fakebin_ac3b="$(cat "$FAKEGH_OUT")"
output_ac3b="$(PATH="$fakebin_ac3b:$PATH" "$script" 279)"
status_ac3b=$?
[ "$status_ac3b" -eq 0 ] || fail "S150 AC3b — expected exit 0 with zero closing issues, got $status_ac3b"
assert_table_shape "S150 AC3b" "$output_ac3b"
[ "$(row_status "$output_ac3b" 5)" = "not-evidenced" ] || fail "S150 AC3b — expected gate 5 not-evidenced with no closing issues, got '$(row_status "$output_ac3b" 5)'"
[ ! -s "$SANDBOX/gh-witness-ac3b" ] || fail "S150 AC3b — a gh call was made that shouldn't have been (likely gh issue view with an empty issue list): $(cat "$SANDBOX/gh-witness-ac3b")"

# =========================================================================
# AC4 — human-only gate (merge confirmation) is neither faked nor failed:
# always unverifiable-from-artifacts, never derived from mergedBy/mergedAt
# or from merge state, never collapsing into AC3's not-evidenced.
# =========================================================================

# Fixture A: AC1's fixture (merged, mergedBy present).
[ "$(row_status "$output_ac1" 6)" = "unverifiable-from-artifacts" ] || fail "S150 AC4a — expected gate 6 unverifiable-from-artifacts on a merged PR, got '$(row_status "$output_ac1" 6)'"

# Fixture B: every other gate not-evidenced (no markers, zero checks, no
# closing issue) — gate 6 must still be unverifiable-from-artifacts and
# textually distinct from the other five rows' not-evidenced.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\taaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n'
    printf 'STATE\tMERGED\n'
    printf 'MERGEDAT\t2026-01-01T00:00:00Z\n'
    printf 'MERGEDBY\tsomeone\n'
    exit 0 ;;
  __CALL_B__)
    echo "no checks reported on the given branch" >&2
    exit 1 ;;
esac
exit 1
GHEOF
fakebin_ac4b="$(cat "$FAKEGH_OUT")"
output_ac4b="$(PATH="$fakebin_ac4b:$PATH" "$script" 279)"
status_ac4b=$?
[ "$status_ac4b" -eq 0 ] || fail "S150 AC4b — expected exit 0 with every gate absent, got $status_ac4b"
assert_table_shape "S150 AC4b" "$output_ac4b"
for n in 1 2 3 4 5; do
  [ "$(row_status "$output_ac4b" "$n")" = "not-evidenced" ] || fail "S150 AC4b — expected gate $n not-evidenced, got '$(row_status "$output_ac4b" "$n")'"
done
[ "$(row_status "$output_ac4b" 6)" = "unverifiable-from-artifacts" ] || fail "S150 AC4b — gate 6 must stay unverifiable-from-artifacts even when everything else is not-evidenced (must not collapse into AC3), got '$(row_status "$output_ac4b" 6)'"

# Fixture C: an open (unmerged) PR — gate 6 must not flip either way.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\tbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n'
    printf 'STATE\tOPEN\n'
    printf 'MERGEDAT\t\n'
    printf 'MERGEDBY\t\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_ac4c="$(cat "$FAKEGH_OUT")"
output_ac4c="$(PATH="$fakebin_ac4c:$PATH" "$script" 279)"
assert_table_shape "S150 AC4c" "$output_ac4c"
[ "$(row_status "$output_ac4c" 6)" = "unverifiable-from-artifacts" ] || fail "S150 AC4c — gate 6 must be unverifiable-from-artifacts on an open PR too, got '$(row_status "$output_ac4c" 6)'"

# =========================================================================
# AC5 — read-only: no gh write call is ever made, and the source contains
# none. Strengthened per finding (g): the assertion is a conjunction
# (witness empty AND exit 0 AND full six-row table), so a script that
# does nothing at all can't pass it vacuously.
# =========================================================================
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tMERGED\n'
    printf 'MERGEDAT\t2026-09-20T17:31:36Z\n'
    printf 'MERGEDBY\tTiesL\n'
    printf 'ISSUE\t265\n'
    printf 'TEXT\t<!-- model-record: stage=Discovery model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Planning model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Test model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Review model="claude-sonnet-5" effort="medium" same-model-exception="fork/agent invocation for this review round runs on the same model as Implementation; no other model was made available for this review" -->\n'
    printf 'TEXT\t<!-- pre-merge-review:done sha=6e00a8c38bf18f19cd53084b5c77ae476c1e74e6 -->\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
  __CALL_C265__)
    printf ''
    exit 0 ;;
esac
echo "$*" >> "$SANDBOX/gh-witness-ac5"
exit 1
GHEOF
fakebin_ac5="$(cat "$FAKEGH_OUT")"
output_ac5="$(PATH="$fakebin_ac5:$PATH" "$script" 279)"
status_ac5=$?
witness_ac5=""
[ -f "$SANDBOX/gh-witness-ac5" ] && witness_ac5="$(cat "$SANDBOX/gh-witness-ac5")"
if [ -n "$witness_ac5" ] || [ "$status_ac5" -ne 0 ]; then
  fail "S150 AC5 — expected an empty witness AND exit 0; witness='$witness_ac5' exit=$status_ac5"
fi
assert_table_shape "S150 AC5 (conjunction: full table too)" "$output_ac5"

# AC5(b): source-level grep for a gh write subcommand, with comment
# lines stripped first (finding (h) — otherwise the header's own prose
# documenting "never calls gh pr comment" would false-positive, the
# same trap S113 exists to avoid).
stripped_source="$(sed -E 's/^[[:space:]]*#.*$//' "$script")"
for banned in "pr merge" "pr comment" "issue comment" "issue edit" "pr edit" "api -X" "api --method"; do
  if grep -qF -- "$banned" <<<"$stripped_source"; then
    fail "S150 AC5 — compliance-evidence.sh's source (comments stripped) contains a gh write subcommand: '$banned'"
  fi
done
# "label" checked separately as a whole word ("gh ... label"), since it's
# a common substring (e.g. inside unrelated prose) — this repo's own
# label-writing shape is "gh <noun> ... label" or "gh label".
if grep -qE '\bgh\b[^|&;]*\blabel\b' <<<"$stripped_source"; then
  fail "S150 AC5 — compliance-evidence.sh's source (comments stripped) appears to call a gh ... label subcommand"
fi

# =========================================================================
# AC6 — offline: with no gh on PATH, exits 3, nothing on stdout, a
# message on stderr. (Determinism was checked above, under AC1.)
# =========================================================================
nogh_path="$(path_without_gh)"
output_nogh="$(PATH="$nogh_path" "$script" 279 2>/tmp/s150_stderr_nogh.$$)"
status_nogh=$?
stderr_nogh="$(cat /tmp/s150_stderr_nogh.$$ 2>/dev/null)"
rm -f /tmp/s150_stderr_nogh.$$
[ "$status_nogh" -eq 3 ] || fail "S150 AC6 — expected exit 3 with no gh on PATH, got $status_nogh"
[ -z "$output_nogh" ] || fail "S150 AC6 — expected empty stdout with no gh on PATH, got: $output_nogh"
[ -n "$stderr_nogh" ] || fail "S150 AC6 — expected a message on stderr with no gh on PATH"

# =========================================================================
# AC7 — discoverable, correctly wired: not check-prefixed, not invoked
# by ./check (finding (b) — Architect's contract had no arm for this at
# all).
# =========================================================================
[ -x "$script" ] || fail "S150 AC7 — compliance-evidence.sh must exist at repo root and be executable"
case "$(basename "$script")" in
  check-*) fail "S150 AC7 — compliance-evidence.sh must not be named with a check- prefix (it's not a ./check gate, AC7)" ;;
esac
if grep -q 'compliance-evidence' "$TEST_REPO_ROOT/check"; then
  fail "S150 AC7 — ./check must not reference compliance-evidence.sh (it needs gh/network; ./check must stay usable offline)"
fi

# =========================================================================
# AC8 — the four-state status vocabulary, per gate.
# =========================================================================

# AC8a — an unparseable review marker (malformed sha) renders
# indeterminate, distinct from AC8c's not-evidenced.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tMERGED\n'
    printf 'TEXT\t<!-- pre-merge-review:done sha=abc123 -->\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_ac8a="$(cat "$FAKEGH_OUT")"
output_ac8a="$(PATH="$fakebin_ac8a:$PATH" "$script" 279)"
assert_table_shape "S150 AC8a" "$output_ac8a"
[ "$(row_status "$output_ac8a" 3)" = "indeterminate" ] || fail "S150 AC8a — expected gate 3 indeterminate for a malformed sha, got '$(row_status "$output_ac8a" 3)'"
evidence_ac8a="$(row_evidence "$output_ac8a" 3)"
[ -n "$(printf '%s' "$evidence_ac8a" | sed -E 's/^ +| +$//g')" ] || fail "S150 AC8a — Evidence cell for the indeterminate row must not be empty (AC2)"

# AC8b — an unknown CI bucket renders indeterminate, never evidenced.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tMERGED\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tWEIRD\tsomething-new\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_ac8b="$(cat "$FAKEGH_OUT")"
output_ac8b="$(PATH="$fakebin_ac8b:$PATH" "$script" 279)"
assert_table_shape "S150 AC8b" "$output_ac8b"
[ "$(row_status "$output_ac8b" 4)" = "indeterminate" ] || fail "S150 AC8b — expected gate 4 indeterminate for an unrecognized bucket, got '$(row_status "$output_ac8b" 4)'"

# AC8c — a stale review marker (sha != headRefOid) is not-evidenced, NOT
# indeterminate: it's a recognized, interpretable artifact that just
# evidences a review of a different commit.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tMERGED\n'
    printf 'TEXT\t<!-- pre-merge-review:done sha=472bc8f574c4aea3fc58161d1924b7b05329172f -->\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_ac8c="$(cat "$FAKEGH_OUT")"
output_ac8c="$(PATH="$fakebin_ac8c:$PATH" "$script" 279)"
assert_table_shape "S150 AC8c" "$output_ac8c"
[ "$(row_status "$output_ac8c" 3)" = "not-evidenced" ] || fail "S150 AC8c — expected gate 3 not-evidenced for a stale (sha-mismatched) marker, got '$(row_status "$output_ac8c" 3)'"

# AC8d (finding (c), highest-value gap) — a red CI check is not-evidenced,
# never evidenced. The single most likely wrong implementation
# ("checks parsed -> evidenced") reports a red build as compliant; this
# is the arm that catches it.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tMERGED\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tFAILURE\tfail\n'
    exit 1 ;;
esac
exit 1
GHEOF
fakebin_ac8d="$(cat "$FAKEGH_OUT")"
output_ac8d="$(PATH="$fakebin_ac8d:$PATH" "$script" 279)"
status_ac8d=$?
[ "$status_ac8d" -eq 0 ] || fail "S150 AC8d — expected exit 0 with a red CI check, got $status_ac8d"
assert_table_shape "S150 AC8d" "$output_ac8d"
[ "$(row_status "$output_ac8d" 4)" = "not-evidenced" ] || fail "S150 AC8d — expected gate 4 not-evidenced for a red (bucket=fail) check, got '$(row_status "$output_ac8d" 4)'"
case "$(row_evidence "$output_ac8d" 4)" in
  *check*) : ;;
  *) fail "S150 AC8d — the failing check should be named in the Evidence cell (AC2): $(row_evidence "$output_ac8d" 4)" ;;
esac

# AC8e (finding (d)) — a pending CI check is indeterminate: the check
# exists, its outcome is not yet knowable.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tOPEN\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tPENDING\tpending\n'
    exit 8 ;;
esac
exit 1
GHEOF
fakebin_ac8e="$(cat "$FAKEGH_OUT")"
output_ac8e="$(PATH="$fakebin_ac8e:$PATH" "$script" 279)"
assert_table_shape "S150 AC8e" "$output_ac8e"
[ "$(row_status "$output_ac8e" 4)" = "indeterminate" ] || fail "S150 AC8e — expected gate 4 indeterminate for bucket=pending, got '$(row_status "$output_ac8e" 4)'"

# AC8f (finding (d)) — zero CI checks at all is not-evidenced: nothing
# to have passed. gh pr checks itself exits non-zero here (D6's trap);
# an implementation reading the exit code first would wrongly report
# indeterminate.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tOPEN\n'
    exit 0 ;;
  __CALL_B__)
    echo "no checks reported on the given branch" >&2
    exit 1 ;;
esac
exit 1
GHEOF
fakebin_ac8f="$(cat "$FAKEGH_OUT")"
output_ac8f="$(PATH="$fakebin_ac8f:$PATH" "$script" 279)"
status_ac8f=$?
[ "$status_ac8f" -eq 0 ] || fail "S150 AC8f — expected exit 0 with zero CI checks, got $status_ac8f"
assert_table_shape "S150 AC8f" "$output_ac8f"
[ "$(row_status "$output_ac8f" 4)" = "not-evidenced" ] || fail "S150 AC8f — expected gate 4 not-evidenced with zero checks, got '$(row_status "$output_ac8f" 4)'"

# AC8g — a stage=Test marker matching tolerantly but written unquoted
# (model=Sonnet, no quotes) is indeterminate: model-record-gate.sh
# deliberately goes silent on this form, but this collector must not
# fold "present but oddly written" into either evidenced or
# not-evidenced.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tMERGED\n'
    printf 'ISSUE\t265\n'
    printf 'TEXT\t<!-- model-record: stage=Discovery model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Planning model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Test model=Sonnet effort=medium -->\n'
    printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
  __CALL_C265__)
    printf ''
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_ac8g="$(cat "$FAKEGH_OUT")"
output_ac8g="$(PATH="$fakebin_ac8g:$PATH" "$script" 279)"
assert_table_shape "S150 AC8g" "$output_ac8g"
[ "$(row_status "$output_ac8g" 1)" = "indeterminate" ] || fail "S150 AC8g — expected gate 1 indeterminate for an unquoted (malformed) stage marker, got '$(row_status "$output_ac8g" 1)'"

# --- Gate 2 negatives (finding (e)): Architect's only gate-2 exercise
# was AC1's positive (a non-empty same-model-exception). "A stage=Review
# marker exists -> evidenced" would pass the whole contracted suite
# without these.

# Same model, no exception at all.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\tcccccccccccccccccccccccccccccccccccccccc\n'
    printf 'STATE\tOPEN\n'
    printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Review model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_g2_same="$(cat "$FAKEGH_OUT")"
output_g2_same="$(PATH="$fakebin_g2_same:$PATH" "$script" 279)"
assert_table_shape "S150 gate2-negative (same model, no exception)" "$output_g2_same"
[ "$(row_status "$output_g2_same" 2)" = "not-evidenced" ] || fail "S150 gate2-negative — same model with no exception must be not-evidenced, got '$(row_status "$output_g2_same" 2)'"

# Same model, empty-reason exception (same-model-exception="") — an
# empty reason must not satisfy (PR #253's trap).
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\tcccccccccccccccccccccccccccccccccccccccc\n'
    printf 'STATE\tOPEN\n'
    printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Review model="claude-sonnet-5" effort="medium" same-model-exception="" -->\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_g2_empty="$(cat "$FAKEGH_OUT")"
output_g2_empty="$(PATH="$fakebin_g2_empty:$PATH" "$script" 279)"
assert_table_shape "S150 gate2-negative (empty-reason exception)" "$output_g2_empty"
[ "$(row_status "$output_g2_empty" 2)" = "not-evidenced" ] || fail "S150 gate2-negative — an empty-reason same-model-exception must still be not-evidenced, got '$(row_status "$output_g2_empty" 2)'"

# Genuinely the same model under different label styles ("claude-sonnet-5"
# vs "Sonnet 5") must still be flagged (#268's normalize_model, D5's
# verbatim-copy decision — if reimplemented differently the collector
# silently disagrees with the gate it reports on).
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\tcccccccccccccccccccccccccccccccccccccccc\n'
    printf 'STATE\tOPEN\n'
    printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Review model="Sonnet 5" effort="medium" -->\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_g2_label="$(cat "$FAKEGH_OUT")"
output_g2_label="$(PATH="$fakebin_g2_label:$PATH" "$script" 279)"
assert_table_shape "S150 gate2-negative (label normalization)" "$output_g2_label"
[ "$(row_status "$output_g2_label" 2)" = "not-evidenced" ] || fail "S150 gate2-negative — 'claude-sonnet-5' vs 'Sonnet 5' must normalize equal and be not-evidenced, got '$(row_status "$output_g2_label" 2)'"

# =========================================================================
# Finding (f): the empty-collection [] ? paths. Two closing issues — call
# C must be made for both; an implementation reading only the first would
# wrongly report Discovery missing.
# =========================================================================
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\tdddddddddddddddddddddddddddddddddddddddd\n'
    printf 'STATE\tOPEN\n'
    printf 'ISSUE\t265\n'
    printf 'ISSUE\t266\n'
    printf 'TEXT\t<!-- model-record: stage=Planning model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Test model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
  __CALL_C265__)
    printf ''
    exit 0 ;;
  __CALL_C266__)
    printf 'TEXT\t<!-- model-record: stage=Discovery model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_twoissues="$(cat "$FAKEGH_OUT")"
output_twoissues="$(PATH="$fakebin_twoissues:$PATH" "$script" 279)"
assert_table_shape "S150 two-issues" "$output_twoissues"
[ "$(row_status "$output_twoissues" 1)" = "evidenced" ] || fail "S150 two-issues — expected gate 1 evidenced only if BOTH closing issues are read (Discovery lives on the second), got '$(row_status "$output_twoissues" 1)'"

# =========================================================================
# The two failure paths (Architect's contract, unchanged) + a third:
# call A itself failing.
# =========================================================================

# Call B genuinely fails: Call A valid, Call B exits 1 with nothing
# parseable on stdout and an unrelated message on stderr (NOT the
# zero-checks message) -> gate 4 indeterminate, exit 0, other five rows
# intact, and no stderr text interleaved into stdout.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tMERGED\n'
    printf 'ISSUE\t265\n'
    printf 'TEXT\t<!-- model-record: stage=Discovery model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Planning model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Test model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
  __CALL_B__)
    echo "gh: a transient network problem occurred" >&2
    exit 1 ;;
  __CALL_C265__)
    printf ''
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_callb_fails="$(cat "$FAKEGH_OUT")"
output_callb_fails="$(PATH="$fakebin_callb_fails:$PATH" "$script" 279)"
status_callb_fails=$?
[ "$status_callb_fails" -eq 0 ] || fail "S150 call-B-fails — expected exit 0, got $status_callb_fails"
assert_table_shape "S150 call-B-fails" "$output_callb_fails"
[ "$(row_status "$output_callb_fails" 4)" = "indeterminate" ] || fail "S150 call-B-fails — expected gate 4 indeterminate on a genuine call-B failure, got '$(row_status "$output_callb_fails" 4)'"
[ "$(row_status "$output_callb_fails" 1)" = "evidenced" ] || fail "S150 call-B-fails — the other gates must be unaffected by a call-B failure"
case "$output_callb_fails" in
  *"transient network"*) fail "S150 call-B-fails — stderr text leaked into the stdout table" ;;
  *) : ;;
esac

# Call C fails for a closing issue: Discovery lives only on the issue,
# and its lookup fails transiently -> gate 1 indeterminate (not
# not-evidenced — the exact regression model-record-gate.sh had, PR #249
# round 2), exit 0, warning on stderr.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    printf 'HEAD\t6e00a8c38bf18f19cd53084b5c77ae476c1e74e6\n'
    printf 'STATE\tMERGED\n'
    printf 'ISSUE\t265\n'
    printf 'TEXT\t<!-- model-record: stage=Planning model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Test model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
  __CALL_C265__)
    echo "gh: could not resolve to an Issue" >&2
    exit 1 ;;
esac
exit 1
GHEOF
fakebin_callc_fails="$(cat "$FAKEGH_OUT")"
output_callc_fails="$(PATH="$fakebin_callc_fails:$PATH" "$script" 279 2>/tmp/s150_stderr_callc.$$)"
status_callc_fails=$?
stderr_callc_fails="$(cat /tmp/s150_stderr_callc.$$ 2>/dev/null)"
rm -f /tmp/s150_stderr_callc.$$
[ "$status_callc_fails" -eq 0 ] || fail "S150 call-C-fails — expected exit 0, got $status_callc_fails"
assert_table_shape "S150 call-C-fails" "$output_callc_fails"
[ "$(row_status "$output_callc_fails" 1)" = "indeterminate" ] || fail "S150 call-C-fails — expected gate 1 indeterminate (not not-evidenced) when a closing issue lookup fails and Discovery then looks missing, got '$(row_status "$output_callc_fails" 1)'"
assert_contains "S150 call-C-fails — a warning appears on stderr" "warning" "$stderr_callc_fails"

# Call A fails entirely: no honest table is possible -> exit 4, nothing
# on stdout, a message on stderr.
run_build_fake_gh > "$FAKEGH_OUT" <<'GHEOF'
case "$*" in
  __CALL_A__)
    echo "gh: could not resolve to a PullRequest" >&2
    exit 1 ;;
esac
exit 1
GHEOF
fakebin_calla_fails="$(cat "$FAKEGH_OUT")"
output_calla_fails="$(PATH="$fakebin_calla_fails:$PATH" "$script" 279 2>/tmp/s150_stderr_calla.$$)"
status_calla_fails=$?
stderr_calla_fails="$(cat /tmp/s150_stderr_calla.$$ 2>/dev/null)"
rm -f /tmp/s150_stderr_calla.$$
[ "$status_calla_fails" -eq 4 ] || fail "S150 call-A-fails — expected exit 4 when the PR itself can't be read, got $status_calla_fails"
[ -z "$output_calla_fails" ] || fail "S150 call-A-fails — expected no table on stdout when call A fails, got: $output_calla_fails"
[ -n "$stderr_calla_fails" ] || fail "S150 call-A-fails — expected a message on stderr"

# =========================================================================
# PR #298 review F2 — a cell that genuinely exceeds the 300-char budget
# (Architect's §3.6 prose: an ellipsis must mark the cut, matching the
# already-observed real-world shape — PR #279's gate-2 cell quoting a
# 118-char exception reason is already ~190 chars, and a longer exception
# or a multi-check gate-4 cell pushes past 300 on real input). Built with
# an over-long same-model-exception on gate 2.
# =========================================================================
long_reason="the fork session inherits its parent model and no other model was made available for this particular review round so this same-model exception documents that limitation in exhaustive detail for the record, repeated once more to push well past the three hundred character budget for this evidence cell"
run_build_fake_gh > "$FAKEGH_OUT" <<GHEOF
case "\$*" in
  __CALL_A__)
    printf 'HEAD\tcccccccccccccccccccccccccccccccccccccccc\n'
    printf 'STATE\tOPEN\n'
    printf 'TEXT\t<!-- model-record: stage=Implementation model="claude-sonnet-5" effort="medium" -->\n'
    printf 'TEXT\t<!-- model-record: stage=Review model="claude-sonnet-5" effort="medium" same-model-exception="$long_reason" -->\n'
    exit 0 ;;
  __CALL_B__)
    printf 'check\tSUCCESS\tpass\n'
    exit 0 ;;
esac
exit 1
GHEOF
fakebin_longcell="$(cat "$FAKEGH_OUT")"
output_longcell="$(PATH="$fakebin_longcell:$PATH" "$script" 279)"
assert_table_shape "S150 F2 long-cell" "$output_longcell"
evidence_longcell="$(row_evidence "$output_longcell" 2)"
[ "${#evidence_longcell}" -le 301 ] || fail "S150 F2 long-cell — evidence cell exceeds the 300-char budget plus ellipsis: ${#evidence_longcell} chars"
case "$evidence_longcell" in
  *…) : ;;
  *) fail "S150 F2 long-cell — a cell actually over 300 chars must render with a visible truncation marker (…), got: $evidence_longcell" ;;
esac

# =========================================================================
# PR #298 review F5 — bad usage (no PR number) exits 2, with nothing on
# stdout and a message on stderr.
# =========================================================================
output_badusage="$("$script" 2>/tmp/s150_stderr_badusage.$$)"
status_badusage=$?
stderr_badusage="$(cat /tmp/s150_stderr_badusage.$$ 2>/dev/null)"
rm -f /tmp/s150_stderr_badusage.$$
[ "$status_badusage" -eq 2 ] || fail "S150 F5 — expected exit 2 with no PR number given, got $status_badusage"
[ -z "$output_badusage" ] || fail "S150 F5 — expected empty stdout on bad usage, got: $output_badusage"
[ -n "$stderr_badusage" ] || fail "S150 F5 — expected a usage message on stderr"

test_done
