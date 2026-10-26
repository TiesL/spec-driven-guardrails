#!/usr/bin/env bash
# S377 — a record from pipeline-override.sh satisfies the real merge gate, and only when the gate can see it.
# Covers: F38
#
# Issue #564, AC6, AC9 and AC10 counter-arm (ii). Seam: the script's
# --dry-run body (what it would post on the issue) as a comment on the work
# item's issue in the data-driven fake `gh` (fixtures/pipeline-371-helpers.sh),
# read by the installed skills/pre-merge-review/model-record-gate.sh run with
# the project as cwd. No network, no gh call by the script (dry-run).
#
# Falsifiers: a body the gate reads as a near-miss; a gate output that still
# has a role-played line; a docs claim that is not true (the issue is read
# only through a closing keyword in the PR title/body); a hand-typed
# near-miss that waives anything.

set -uo pipefail
# shellcheck disable=SC2016,SC2059,SC2015
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"

SCRIPT="$TEST_REPO_ROOT/pipeline-override.sh"
gate_script="$TEST_REPO_ROOT/skills/pre-merge-review/model-record-gate.sh"
[ -x "$gate_script" ] || { fail "S377 — model-record-gate.sh is missing or not executable"; test_done; }
command -v jq >/dev/null 2>&1 || { fail "S377 — jq is needed by the fake gh"; test_done; }

sandbox_create
trap sandbox_destroy EXIT

id="process-multi-agent-roles"
fakebin="$(fake_gh_rest "$SANDBOX/ghdata")"
export FAKE_GH_DATA="$SANDBOX/ghdata"
mkdir -p "$FAKE_GH_DATA"
project="$(fresh_project optin)"
write_adoption "$project/WORKFLOW-ADOPTION.md" "$id" yes

# dry_body <name> args...: the body the script would post, in $SANDBOX/<name>.body
dry_body() {
  local name="$1"
  shift
  "$SCRIPT" 239 "$@" --dry-run > "$SANDBOX/$name.body" 2> "$SANDBOX/$name.err"
  dry_rc=$?
  [ "$dry_rc" -eq 0 ] || fail "S377 — $name: dry-run exit $dry_rc (stderr: $(head -c 300 "$SANDBOX/$name.err"))"
}

# world <pr-body> <issue-comment>...: PR 246 closes #239 (or not), Implementation on
# the PR, Review in a review, Discovery on the issue; the extra issue
# comments follow. Planning and Test have no marker anywhere.
world() {
  local prbody="$1"
  shift
  rm -f "${FAKE_GH_DATA:?}"/*.json
  json_pr "$FAKE_GH_DATA/pr-246.json" "Work: something" "$prbody"
  json_comments "$FAKE_GH_DATA/comments-246.json" "$(mr Implementation)"
  json_comments "$FAKE_GH_DATA/reviews-246.json" "$(mr Review)"
  json_comments "$FAKE_GH_DATA/comments-239.json" "$(mr Discovery)" "$@"
}
gate() {
  out="$(cd "$project" && PATH="$fakebin:$PATH" "$gate_script" 246 2>/dev/null)"
  status=$?
}

# 1. AC6: the two-scope body waives exactly Planning and Test.
dry_body short --scope skip=Planning --scope skip=Test --decided-by TiesL --reason 'only specs'
world "Closes #239" "$(cat "$SANDBOX/short.body")"
gate
[ "$status" -eq 0 ] || fail "S377/1 — gate exit $status"
want='model-record: a pipeline-override waived stage absence: skip=Planning skip=Test'
# (the older "no record found for stage ..." lines stay; they are S130's)
waives() { # label: the waiver line, no role-played line, no near-miss line
  case "$out" in *"$want"*) : ;; *) fail "S377/$1 — gate output lacks '$want': $out" ;; esac
  grep -q '^role-played: ' <<<"$out" && fail "S377/$1 — a role-played line is left: $out"
  case "$out" in *near-miss*) fail "S377/$1 — the gate reports a near-miss: $out" ;; esac
}
waives 1

# 1b. A reason full of fence-looking text still gives a live record (the grammar holds it).
dry_body fence --scope skip=Planning --scope skip=Test --decided-by TiesL --reason 'a `tick` ``` ~~~ | & $HOME'
world "Closes #239" "$(cat "$SANDBOX/fence.body")"
gate
waives 1b

# 1c. single-session: all five markers in one text are waived.
dry_body single --scope single-session --decided-by TiesL --reason 'one session'
world "Closes #239" "$(cat "$SANDBOX/single.body")"
json_comments "$FAKE_GH_DATA/comments-246.json" "$(mr Discovery)
$(mr Planning)
$(mr Test)
$(mr Implementation)
$(mr Review)"
gate
case "$out" in role-played:*|*$'\n'role-played:*) fail "S377/1c — single-session left a role-played line: $out" ;; esac
case "$out" in *'(scope=single-session) waived the role-play findings'*) : ;; *) fail "S377/1c — gate did not report the single-session waiver: $out" ;; esac

# 2. AC9 counter-arm (i): the same record, a PR body with no closing keyword. The
# issue is not read, so the record is invisible and the stages are missing.
world "Work on the thing, see issue 239" "$(cat "$SANDBOX/short.body")"
gate
grep -q '^role-played: stages missing: ' <<<"$out" || fail "S377/2 — without 'Closes #239' the gate must print 'role-played: stages missing: ...', got: $out"
case "$out" in *'waived stage absence'*) fail "S377/2 — the record on an issue without a closing keyword must not waive anything: $out" ;; esac

# 3. AC10 counter-arm (ii): a hand-typed near-miss (the reason holds the human's double quotes) waives nothing.
typed() { printf '<!-- pipeline-override: decided-by="TiesL" scope="%s" reason="he said "only specs"" -->' "$1"; }
world "Closes #239" "$(typed skip=Planning)
$(typed skip=Test)"
gate
case "$out" in *'pipeline-override near-miss'*) : ;; *) fail "S377/3 — a hand-typed record with quotes in the reason must show a near-miss line, got: $out" ;; esac
grep -q '^role-played: stages missing: Planning, Test' <<<"$out" || fail "S377/3 — the near-miss must waive nothing (want 'role-played: stages missing: Planning, Test'), got: $out"
case "$out" in *'waived stage absence'*) fail "S377/3 — a near-miss waived a stage: $out" ;; esac

# 4. The script refuses the input behind that near-miss, so it never reaches an issue.
"$SCRIPT" 239 --scope skip=Planning --decided-by TiesL --reason 'he said "only specs"' --dry-run > "$SANDBOX/n.out" 2> "$SANDBOX/n.err"
rc=$?
[ "$rc" -eq 2 ] && [ ! -s "$SANDBOX/n.out" ] || fail "S377/4 — the script must refuse a reason with double quotes (exit 2, no body), got exit $rc"

test_done
