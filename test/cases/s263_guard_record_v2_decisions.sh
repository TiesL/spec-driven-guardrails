#!/usr/bin/env bash
# S263 — guard_record_v2_decisions; #427, independent CLI assertions (A31a/A34a/A37).
# Covers: F27, F38, F39, F40
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
. "$TEST_REPO_ROOT/test/fixtures/gate-v2-helpers.sh"

v2_base; inline='Done. <!-- model-record: stage=Planning model="m" -->'
v2_comments comments-246.json "$inline" "$(mr Test)" "$(mr Implementation)"
v2_merge
[ "$v2_status" = 2 ] || fail "inline-only must block: $v2_err"
for text in 'role-played: stages missing: Planning' 'not on a line of its own' 'model-record-emit.sh' 'pipeline-override'; do assert_contains "$text" "$text" "$v2_err"; done
v2_comments comments-246.json "$inline" "$(mr Planning)" "$(mr Test)" "$(mr Implementation)"; v2_merge; [ "$v2_status" = 0 ] || fail "near-miss alone must not block"
v2_comments comments-246.json "$(mr Planning)" "$(mr Test)" "$(mr Implementation)"; v2_merge; [ "$v2_status" = 0 ] || fail "re-post remedy must permit"
v2_comments comments-246.json "$inline" "$(mr Test)" "$(mr Implementation)" '<!-- pipeline-override: decided-by="human" scope="single-session" reason="approved" -->'; v2_merge; [ "$v2_status" = 0 ] || fail "override remedy must permit"
# A35 stub at existing CLI, only in disposable copy; literal truth table.
copy="$SANDBOX/stub"; mkdir -p "$copy/hooks" "$copy/lib" "$copy/skills/pre-merge-review"
cp "$TEST_REPO_ROOT/hooks/"* "$copy/hooks/"; cp "$TEST_REPO_ROOT/lib/"* "$copy/lib/"
cat > "$copy/skills/pre-merge-review/model-record-gate.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s' "$STUB_OUT"
EOF
chmod +x "$copy/skills/pre-merge-review/model-record-gate.sh"
v2_hook="$copy/hooks/git-guardrails"
export STUB_OUT
for arm in empty context unchecked block mixed; do
 case "$arm" in
 empty) STUB_OUT=''; want=0;; context) STUB_OUT='model-record: near-miss context'; want=0;;
 unchecked) STUB_OUT='role-play-unchecked: reviews fetch failed'; want=0;;
 block) STUB_OUT=$'role-played: stages missing: Planning\nmodel-record: near-miss context'; want=2;;
 mixed) STUB_OUT=$'role-play-unchecked: reviews fetch failed\nrole-played: stages missing: Planning\nmodel-record: near-miss context'; want=2;; esac
 v2_merge; [ "$v2_status" = "$want" ] || fail "$arm exit $v2_status != $want"
 case "$arm" in unchecked|mixed) assert_contains 'warning printed' 'role-play-unchecked: reviews fetch failed' "$v2_err";; esac
 case "$arm" in block|mixed) for text in 'role-played:' 'near-miss context' 'model-record-emit.sh' 'pipeline-override'; do assert_contains "$text" "$text" "$v2_err"; done;; esac
done
# Real gate's review fetch failure warns without a role-play block.
v2_hook="$TEST_REPO_ROOT/hooks/git-guardrails"; v2_base
rm "$FAKE_GH_DATA/reviews-246.json"; v2_merge
[ "$v2_status" = 0 ] || fail "unavailable reviews must permit"
assert_contains 'actual unchecked warning' 'role-play-unchecked:' "$v2_err"

test_done
