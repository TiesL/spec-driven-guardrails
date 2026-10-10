#!/usr/bin/env bash
# S260 — gate_unchecked_failures; #427, independent CLI assertions (A31a/A34a/A37).
# Covers: F27, F38, F39, F40
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
. "$TEST_REPO_ROOT/test/fixtures/gate-v2-helpers.sh"

# Endpoint failures use real fake-gh JSON processing for all other endpoints.
rest="$v2_bin"; shim="$SANDBOX/failing-gh"; mkdir -p "$shim"
cat > "$shim/gh" <<EOF
#!/usr/bin/env bash
if [ "\${2:-}" = "\$FAIL_EP" ]; then echo "\$FAIL_REASON" >&2; exit 1; fi
exec "$rest/gh" "\$@"
EOF
chmod +x "$shim/gh"
export FAIL_EP FAIL_REASON
v2_path="$shim:$PATH"
for ep in issues/246/comments pulls/246/reviews pulls/246 issues/239/comments; do
 for reason in 'gh: HTTP 403' 'gh: HTTP 500' 'gh: could not connect'; do
  v2_base; FAIL_EP="repos/{owner}/{repo}/$ep"; FAIL_REASON="$reason"; v2_run "$v2_yes"
  count 'role-play-unchecked: ' 1; absent 'no record found'; absent 'role-played:'; absent 'has no floor-basis'
 done
done
unset v2_path
# Counted reader-only tool failures. All unrelated invocations forwarded.
realgrep="$(command -v grep)"; realawk="$(command -v awk)"
for tool in grep awk; do
 for mode in fail empty; do
  [ "$tool:$mode" != awk:empty ] || continue
  bin="$SANDBOX/$tool-$mode"; mkdir -p "$bin"; export COUNT_FILE="$SANDBOX/count"; : > "$COUNT_FILE"
  if [ "$tool" = grep ]; then select='case "$*" in *model-record:*|*pipeline-override:*) true;; *) false;; esac'; real="$realgrep"; else select='case "$*" in *mode=rec*|*mode=find*|*mode=scan*) true;; *) false;; esac'; real="$realawk"; fi
  cat > "$bin/$tool" <<EOF
#!/usr/bin/env bash
if $select; then
 echo hit >> "\$COUNT_FILE"
 [ "$mode" = empty ] && exit 0
 exit 2
fi
exec "$real" "\$@"
EOF
  chmod +x "$bin/$tool"; v2_path="$bin:$v2_bin:$PATH"
  v2_base; v2_run "$v2_yes"
  [ -s "$COUNT_FILE" ] || fail "unused $tool/$mode shim"
  count 'model-record:' 1; has 'reader'; count 'role-play-unchecked:' 1; absent 'no record found'; absent 'role-played:'
  v2_run; count 'model-record:' 1; absent 'role-play-unchecked:'
 done
done
unset v2_path
v2_base; v2_comments comments-239.json prose; v2_comments comments-246.json prose; v2_comments reviews-246.json
v2_run "$v2_yes"; has "$missing"; absent 'reader'; absent 'role-play-unchecked:'

test_done
