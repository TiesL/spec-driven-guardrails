#!/usr/bin/env bash
# S719 — AC5 preservation: checkpoint hooks move only WIP; SHA push moves PR.
# Covers: F18, F76
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
project="$(fresh_project checkpoint-706)"
remote="$SANDBOX/origin.git"
git init -q --bare "$remote"
git -C "$project" remote add origin "$remote"
git -C "$project" commit -q --allow-empty -m initial
initial="$(git -C "$project" rev-parse HEAD)"
git -C "$project" push -q origin HEAD:refs/heads/feature/706-example
git -C "$project" checkout -q -b wip/706-example
mkdir -p "$SANDBOX/elsewhere"
remote_sha() { git --git-dir="$remote" rev-parse "refs/heads/$1"; }
# All gh activity is local stubbing; the guard never inherits a real gh.
nogh="$(path_without_gh)"
guard() {
  python3 - "$project" "$1" <<'PY' | PATH="$nogh" "$TEST_REPO_ROOT/hooks/git-guardrails" 2>&1
import json,sys
print(json.dumps({'tool_name':'Bash','cwd':sys.argv[1], 'tool_input':{'command':sys.argv[2]}}))
PY
}
# S12 main-push refusal remains a negative control, not a naming exemption.
output="$(guard 'git push origin HEAD:main')"; status=$?
[ "$status" -eq 2 ] || fail "S719/control — explicit main push no longer blocks"
for command in 'git commit -m checkpoint' 'git push origin HEAD' "git push origin $initial:feature/706-example"; do
  output="$(guard "$command")"; status=$?
  [ "$status" -eq 0 ] || fail "S719/control — WIP checkpoint/SHA push wrongly blocked: $command: $output"
done
git -C "$project" commit -q --allow-empty -m partial
checkpoint="$(git -C "$project" rev-parse HEAD)"
input="$(python3 - "$project" <<'PY'
import json,sys
print(json.dumps({'hook_event_name':'PostToolUse','tool_name':'Bash','cwd':sys.argv[1], 'tool_input':{'command':'git commit -m partial'}}))
PY
)"
(cd "$SANDBOX/elsewhere" && printf '%s' "$input" | "$TEST_REPO_ROOT/hooks/push-after-commit") >/dev/null 2>&1
[ "$(remote_sha wip/706-example)" = "$checkpoint" ] || fail "S719/control — PostToolUse did not checkpoint WIP from unrelated cwd"
[ "$(remote_sha feature/706-example)" = "$initial" ] || fail "S719/control — PostToolUse advanced PR"
git -C "$project" commit -q --allow-empty -m next-checkpoint
next="$(git -C "$project" rev-parse HEAD)"
end_command="$(python3 - "$TEST_REPO_ROOT/settings/session-hooks.json" <<'PY'
import json,sys
print(json.load(open(sys.argv[1]))['hooks']['SessionEnd'][0]['hooks'][0]['command'])
PY
)"
(cd "$SANDBOX/elsewhere" && CLAUDE_PROJECT_DIR="$project" bash -c "$end_command") >/dev/null 2>&1
[ "$(remote_sha wip/706-example)" = "$next" ] || fail "S719/control — SessionEnd did not checkpoint WIP from unrelated cwd"
[ "$(remote_sha feature/706-example)" = "$initial" ] || fail "S719/control — SessionEnd advanced PR"
# No green-push guard is promised: execute the documented explicit SHA seam.
git -C "$project" push -q origin "$checkpoint:refs/heads/feature/706-example"
[ "$(remote_sha feature/706-example)" = "$checkpoint" ] || fail "S719/control — explicit SHA promotion missed PR"
[ "$(remote_sha wip/706-example)" = "$next" ] || fail "S719/control — explicit SHA promotion changed WIP"
# A base merge on the PR ref makes a stale WIP publication non-fast-forward.
git -C "$project" checkout -q -b fixture-base-merge "$checkpoint"
git -C "$project" commit -q --allow-empty -m remote-base-merge
moved="$(git -C "$project" rev-parse HEAD)"
git -C "$project" push -q origin "$moved:refs/heads/feature/706-example"
git -C "$project" checkout -q wip/706-example
if git -C "$project" push -q origin "$next:refs/heads/feature/706-example" >/dev/null 2>&1; then
  fail "S719/control — divergent promotion was accepted"
fi
git -C "$project" merge -q --no-edit origin/feature/706-example
reconciled="$(git -C "$project" rev-parse HEAD)"
git -C "$project" push -q origin "$reconciled:refs/heads/feature/706-example"
[ "$(remote_sha feature/706-example)" = "$reconciled" ] || fail "S719/control — reconciled fast-forward failed"
[ "$(remote_sha wip/706-example)" = "$next" ] || fail "S719/control — reconciliation silently checkpointed WIP"
test_done
