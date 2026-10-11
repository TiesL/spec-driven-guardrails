#!/usr/bin/env bash
# S270 — one actual delegated scan, sixty bodies, 100KB prose, soft timing.
# Covers: F35
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
. "$TEST_REPO_ROOT/test/fixtures/role-label-v2-helpers.sh"
mkdir -p "$SANDBOX/tree/lib"
cp "$r_script" "$SANDBOX/tree/role-label-staleness.sh"
cp "$TEST_REPO_ROOT/lib/model-record.sh" "$TEST_REPO_ROOT/lib/markdown.sh" "$SANDBOX/tree/lib/"
export ROLE_V2_SCANS="$SANDBOX/scans" ROLE_V2_SCAN_TIME="$SANDBOX/scan-time"
cat >> "$SANDBOX/tree/lib/model-record.sh" <<'SHIM'
# Test-only instrumentation; preserve and invoke the real public scanner.
eval "$(declare -f rec_scan_bundle | sed '1s/rec_scan_bundle/role_v2_actual_scan/')"
rec_scan_bundle() {
 local start=$SECONDS result rc bodies
 bodies="$(printf '%s' "$2" | tr -cd '\036' | wc -c | tr -d ' ')"
 printf '%s %s %s\n' "$1" "$bodies" "${#2}" >> "$ROLE_V2_SCANS"
 result="$(role_v2_actual_scan "$@")"; rc=$?
 printf '%s\n' "$((SECONDS-start))" >> "$ROLE_V2_SCAN_TIME"
 printf '%s' "$result"
 return "$rc"
}
SHIM
# Direct positive control counts a real delegated scan, never canned output.
. "$SANDBOX/tree/lib/model-record.sh"
: > "$ROLE_V2_SCANS"
rec_scan_bundle model-record "$r_good$MARKER_SEP" >/dev/null
[ "$(wc -l < "$ROLE_V2_SCANS" | tr -d ' ')" = 1 ] || fail 'counter positive control did not fire'
r_script="$SANDBOX/tree/role-label-staleness.sh"
long="$(printf '%100000s' x)"
for arm in good bad quoted; do
 r_base; r_link; r_issue role:architect "$long"; r_pr '<!-- model-record: stage=Test model="m" -->'
 case "$arm" in good) last="$r_good";; bad) last="$r_bad";; quoted) last=$'```\n'"$r_bad"$'\n```';; esac
 # 58 comments plus issue and description = exactly sixty transport bodies.
 jq -n --arg good "$r_good" --arg last "$last" '[range(0;58) as $i | {created_at:(if $i==57 then "2026-10-01T11:00:00Z" else "2026-10-01T10:00:00Z" end),body:(if $i==0 then $good elif $i==57 then $last else ("prose " + ($i|tostring)) end)}]' > "$ROLE_V2_DATA/comments.json"
 : > "$ROLE_V2_SCANS"; : > "$ROLE_V2_SCAN_TIME"; start=$SECONDS
 r_run
 [ "$(wc -l < "$ROLE_V2_SCANS" | tr -d ' ')" = 1 ] || fail "expected exactly one delegated scan: $(cat "$ROLE_V2_SCANS")"
 read -r kind bodies bytes < "$ROLE_V2_SCANS" || true
 [ "${kind:-}" = model-record ] && [ "${bodies:-}" = 60 ] && [ "${bytes:-0}" -gt 100000 ] || fail "scan ingestion kind/bodies/bytes: $(cat "$ROLE_V2_SCANS")"
 if [ "$arm" = bad ]; then r_status indeterminate; r_has near-miss; else r_status stale; r_has 'expected role:reviewer'; fi
 for endpoint in pulls/501 issues/501/comments pulls/501/reviews; do grep -F "$endpoint " "$ROLE_V2_LOG" >/dev/null || fail "scale endpoint missing: $endpoint"; done
 printf 'S270 %s: end-to-end %ss; delegated marker scan %ss; 60 bodies and 100000-byte line; soft scan target 2s\n' "$arm" "$((SECONDS-start))" "$(cat "$ROLE_V2_SCAN_TIME")"
done
printf 'S270 platform: bash %s; awk %s; grep %s\n' "$(/bin/bash --version | head -1)" "$(/usr/bin/awk -version 2>&1 | head -1)" "$(/usr/bin/grep --version 2>&1 | head -1)"
# Reached awk failure must not become an absence verdict.
mkdir -p "$SANDBOX/fail-bin"
cat > "$SANDBOX/fail-bin/awk" <<'AWK'
#!/usr/bin/env bash
printf 'reached\n' >> "$ROLE_V2_AWK"
exit 2
AWK
chmod +x "$SANDBOX/fail-bin/awk"; export ROLE_V2_AWK="$SANDBOX/awk-calls"
r_base; r_rows issue-comments "$r_early" "$r_good"; r_path="$SANDBOX/fail-bin:$SANDBOX/bin:$PATH"; r_run; r_status indeterminate
[ -s "$ROLE_V2_AWK" ] || fail 'awk failure shim not reached'
test_done
