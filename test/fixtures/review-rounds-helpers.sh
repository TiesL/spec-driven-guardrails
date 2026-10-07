#!/usr/bin/env bash
# test/fixtures/review-rounds-helpers.sh — fixtures for review-rounds.sh
# (S216, S217, #410). Source after test/lib.sh, pipeline-371-helpers.sh
# (fake_gh_rest, json_*) and review-floor-helpers.sh (marker), and after
# sandbox_create. Bash 3.2: no declare -A, no mapfile.
#
# The data is shaped like the REST API: a PR comment has created_at, a PR
# review has submitted_at, both with an ISO 8601 UTC time. PR 246 closes
# issue 239. Every gh call is also logged to $RR_LOG, so a test can show
# what the script called (and that it called anything).

RR_PR=246
RR_ISSUE=239

# rr_setup: fake gh (recording), data dir, an empty cwd. Sets RR_BIN, RR_CWD, RR_LOG.
rr_setup() {
  export FAKE_GH_DATA="$SANDBOX/rr-data"
  mkdir -p "$FAKE_GH_DATA"
  local rest
  rest="$(fake_gh_rest "$FAKE_GH_DATA")"
  RR_BIN="$SANDBOX/rr-bin"
  RR_LOG="$SANDBOX/rr-calls.log"
  mkdir -p "$RR_BIN"
  : > "$RR_LOG"
  cat > "$RR_BIN/gh" <<GHEOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$RR_LOG"
exec "$rest/gh" "\$@"
GHEOF
  chmod +x "$RR_BIN/gh"
  RR_CWD="$SANDBOX/rr-cwd"
  mkdir -p "$RR_CWD"
}

# rr_json <outfile> <timefield> <time> <body> [<time> <body> ...]: a JSON
# array of {id, body, <timefield>} in the order given (NOT sorted: the
# script must order by time itself).
rr_json() {
  local out="$1" field="$2" i=0 t b items=""
  shift 2
  while [ $# -ge 2 ]; do
    t="$1"; b="$2"; shift 2
    i=$((i + 1))
    items="$items$(jq -cn --argjson id "$i" --arg f "$field" --arg t "$t" --arg b "$b" '{id: $id, body: $b} + {($f): $t}')"$'\n'
  done
  printf '%s' "$items" | jq -s '.' > "$out"
}

# rr_reset: the PR closes the issue, nothing else is there yet.
rr_reset() {
  rm -f "${FAKE_GH_DATA:?}"/*.json
  json_pr "$FAKE_GH_DATA/pr-$RR_PR.json" "Fix #$RR_ISSUE: something" "Closes #$RR_ISSUE"
  rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at
  rr_json "$FAKE_GH_DATA/reviews-$RR_PR.json" submitted_at
  rr_json "$FAKE_GH_DATA/comments-$RR_ISSUE.json" created_at
}

# markers
rr_review() { marker Review claude-opus-5 high 'floor-basis="stronger than Implementation"'; }
rr_planning() { marker Planning claude-opus-5 high; }
rr_stage() { marker "$1" claude-sonnet-5 medium; }

# rr_run [<args>...]: runs the script from an empty cwd with the fake gh.
# Sets rr_out (stdout), rr_err (stderr), rr_status.
# shellcheck disable=SC2034  # read by the sourcing cases
rr_run() {
  local errf="$SANDBOX/rr-stderr"
  rr_out="$(cd "$RR_CWD" && PATH="$RR_BIN:$PATH" "$RR_SCRIPT" "$@" 2>"$errf")"
  rr_status=$?
  rr_err="$(cat "$errf")"
}

# rr_lines <ere>: the stdout lines that match.
rr_lines() { printf '%s\n' "$rr_out" | grep -E -- "$1" || true; }
# rr_lines_i <ere>: the same, case-insensitively.
rr_lines_i() { printf '%s\n' "$rr_out" | grep -E -i -- "$1" || true; }

# --- #426 (V5 of #411): fixtures for the one Review round definition ----------
# rr_done: a legacy done marker (the HTML-comment form with a 40-hex sha).
RR_SHA40="dddddddddddddddddddddddddddddddddddddddd"
rr_done() { printf '<!-- pre-merge-review:done sha=%s -->' "$RR_SHA40"; }
# rr_finding <slug> <open|resolved>: a finding marker.
rr_finding() { printf '<!-- finding:%s status=%s -->' "$1" "$2"; }
# rr_pr_json <created_at> <description>: the PR object, with the time a gate
# would need if it (wrongly) counted the description as a round.
rr_pr_json() {
  jq -n --arg c "$1" --arg b "$2" --arg t "Fix #$RR_ISSUE: something" '{title: $t, body: $b, created_at: $c}' > "$FAKE_GH_DATA/pr-$RR_PR.json"
}
# rr_script_run <script> [<args>...]: rr_run for another script (the carry-forward gate takes the PR number only).
rr_script_run() {
  RR_SCRIPT="$1"
  shift
  rr_run "$@"
}
# rr_gate_lines: the stdout lines of the gate that report a finding, one per line, sorted.
rr_gate_lines() { printf '%s\n' "$rr_out" | LC_ALL=C grep -a '^finding-carryforward: ' | LC_ALL=C sort || true; }
# rr_gate_slugs: the slugs those lines report, one per line, sorted (each line must start
# `finding-carryforward: <slug> was open in the previous round and is missing from this one`).
rr_gate_slugs() {
  printf '%s\n' "$rr_out" | LC_ALL=C sed -n -E 's/^finding-carryforward: ([^ ]+) was open in the previous round and is missing from this one.*$/\1/p' | LC_ALL=C sort
}
