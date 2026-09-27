#!/usr/bin/env bash
# test/compliance-evidence-fixture.sh — shared fixture constants + shape
# helpers for S150 (test/cases/s150_compliance_evidence.sh) and S151
# (test/cases/s151_compliance_evidence_quoting.sh), issue #308 (QA's
# fixture-hygiene rule extended, Architect's own rule for #296/#302).
#
# Extracted so a drift in compliance-evidence.sh's --json field list or
# --jq expression is a one-line fix here instead of a synchronized edit
# across both test files. Source, don't execute — expects sandbox_create
# (test/lib.sh) to already have run, so $SANDBOX is set.
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

# --- The four gh argv strings compliance-evidence.sh's implementation
# issues, captured by observing its actual argv against a recording fake
# gh, never retyped from the source by hand (Architect's fixture-hygiene
# rule, #296/#302; the sentinel transport rewrite for #308 is exactly the
# kind of drift this file exists to absorb in one place).
CALL_A_ARGS='pr view 279 --json body,comments,closingIssuesReferences,headRefOid,mergedAt,mergedBy,state --jq "HEAD\t"+(.headRefOid//""),"STATE\t"+(.state//""),"MERGEDAT\t"+(.mergedAt//""),"MERGEDBY\t"+((.mergedBy.login)//""),(.closingIssuesReferences[]? | "ISSUE\t"+(.number|tostring)),("TEXT\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001"))),(.comments[]? | "TEXT\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001")))'
CALL_B_ARGS='pr checks 279 --json name,state,bucket --jq .[] | .name+"\t"+.state+"\t"+.bucket'
CALL_C265_ARGS='issue view 265 --json comments --jq .comments[]? | "TEXT\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001"))'
CALL_C266_ARGS='issue view 266 --json comments --jq .comments[]? | "TEXT\t"+((.body//"")|gsub("\u0001";" ")|gsub("\r";"")|gsub("\n";"\u0001"))'

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
