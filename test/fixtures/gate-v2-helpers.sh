#!/usr/bin/env bash
# Private test fixtures at the existing gate CLI/hook Seams. Literal oracles;
# timestamped REST data, with real jq (never the record reader as an oracle).
. "$TEST_REPO_ROOT/test/fixtures/pipeline-371-helpers.sh"
. "$TEST_REPO_ROOT/test/fixtures/review-floor-helpers.sh"
sandbox_create
trap sandbox_destroy EXIT
export FAKE_GH_DATA="$SANDBOX/data"
mkdir -p "$FAKE_GH_DATA"
v2_bin="$(fake_gh_merge_rest "$FAKE_GH_DATA")"
v2_plain="$SANDBOX/plain"; mkdir -p "$v2_plain"
v2_yes="$(fresh_project opted-in)"
write_adoption "$v2_yes/WORKFLOW-ADOPTION.md" process-multi-agent-roles yes
v2_gate="$TEST_REPO_ROOT/skills/pre-merge-review/model-record-gate.sh"
v2_hook="$TEST_REPO_ROOT/hooks/git-guardrails"
# Every supplied body is a separate REST object; order deliberately can differ
# from time in v2_times. Reviews have submitted_at, comments created_at.
v2_comments() {
  local file="$1"; shift
  jq -n '$ARGS.positional | to_entries | map({body:.value, created_at:("2026-10-01T00:00:" + ((.key+10)|tostring) + "Z"), submitted_at:("2026-10-01T00:00:" + ((.key+10)|tostring) + "Z")})' --args "$@" > "$FAKE_GH_DATA/$file"
}
v2_times() { # file, timestamp, body pairs
  local file="$1"; shift
  jq -n '$ARGS.positional as $a | [range(0; ($a|length); 2) as $i | {created_at:$a[$i],submitted_at:$a[$i],body:$a[$i+1]}]' --args "$@" > "$FAKE_GH_DATA/$file"
}
v2_pr() { jq -n --arg t "$1" --arg b "$2" --arg c "${3:-2026-09-01T00:00:00Z}" '{title:$t,body:$b,created_at:$c,updated_at:"2026-12-01T00:00:00Z"}' > "$FAKE_GH_DATA/pr-246.json"; }
v2_base() {
  rm -f "$FAKE_GH_DATA"/*.json
  v2_pr 'Fix #239' ''
  v2_comments comments-239.json "$(mr Discovery)"
  v2_comments comments-246.json "$(mr Planning)" "$(mr Test)" "$(mr Implementation)"
  v2_comments reviews-246.json "$(mr Review)"
}
v2_run() {
  v2_out="$(cd "${1:-$v2_plain}" && PATH="${v2_path:-$v2_bin:$PATH}" "$v2_gate" 246 2>"$SANDBOX/err")"; v2_status=$?
  v2_err="$(cat "$SANDBOX/err")"
  [ "$v2_status" -eq 0 ] || fail "gate exit $v2_status: $v2_err"
}
v2_merge() {
  local input
  input="$(jq -n --arg cwd "${1:-$v2_yes}" '{tool_name:"Bash",cwd:$cwd,tool_input:{command:"gh pr merge 246"}}')"
  v2_out="$(PATH="${v2_path:-$v2_bin:$PATH}" "$v2_hook" <<<"$input" 2>"$SANDBOX/err")"; v2_status=$?
  v2_err="$(cat "$SANDBOX/err")"
}
has() { assert_contains "$1" "$1" "$v2_out"; }
absent() { case "$v2_out" in *"$1"*) fail "unexpected '$1': $v2_out";; esac; }
count() { local n; n="$(grep -cF -- "$1" <<<"$v2_out" || true)"; [ "$n" = "$2" ] || fail "'$1' count $n != $2: $v2_out"; }
clean() { [ -z "$v2_out" ] || fail "expected clean gate: $v2_out"; }
missing='role-played: stages missing: Discovery, Planning, Test, Implementation, Review'
early=2026-10-01T00:00:01Z
late=2026-10-02T00:00:01Z
