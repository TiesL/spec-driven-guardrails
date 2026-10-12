#!/usr/bin/env bash
# S273 — raw bundles, counted delegation, hostile framing and tool failure.
# Covers: F34, F40
set -uo pipefail
export LC_ALL=C
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
. "$TEST_REPO_ROOT/test/fixtures/collector-v2-helpers.sh"
mkdir -p "$SANDBOX/copy/lib"
cp "$TEST_REPO_ROOT/compliance-evidence.sh" "$SANDBOX/copy/"
cp "$TEST_REPO_ROOT/lib/"*.sh "$SANDBOX/copy/lib/"
export CV_SCAN_LOG="$SANDBOX/scan-log" CV_SCAN_TIMES="$SANDBOX/scan-times" CV_RAW_LOG="$SANDBOX/raw-bundle" CV_FAIL_SCAN=0
cat >> "$SANDBOX/copy/lib/model-record.sh" <<'WRAP'
# Private test adapter delegates the actual scanner with a file witness.
_cv_real_scan() { _rec_scan 1 "$@"; }
rec_scan_bundle() {
 local sep=$'\036' bytes count tail
 bytes="$(printf '%s' "$2" | wc -c | tr -d ' ')"
 count="$(printf '%s' "$2" | tr -cd '\036' | wc -c | tr -d ' ')"
 printf '%s\t%s\t%s\n' "$1" "$count" "$bytes" >> "$CV_SCAN_LOG"
 printf '%s' "$2" > "$CV_RAW_LOG"
 [ "$CV_FAIL_SCAN" = 0 ] || return 7
 local began ended result rc
 began="$(python3 -c 'import time; print(time.time())')"
 result="$(_cv_real_scan "$@")"; rc=$?
 python3 - "$began" >> "$CV_SCAN_TIMES" <<'TIME'
import time,sys
print('S273 delegated scan elapsed %.3f s'%(time.time()-float(sys.argv[1])))
TIME
 printf '%s\n' "$result"
 return "$rc"
}
WRAP
CV_SCRIPT="$SANDBOX/copy/compliance-evidence.sh"
# Positive direct delegation is reached, and preserves actual result.
: > "$CV_SCAN_LOG"
. "$SANDBOX/copy/lib/model-record.sh"
x="$(rec_scan_bundle model-record "$(cv_mark Review)$MARKER_SEP")" || fail 'direct scanner'
case "$x" in $'1\tok\tReview\t'*) :;; *) fail "direct scan output $x";; esac
[ "$(wc -l < "$CV_SCAN_LOG" | tr -d ' ')" = 1 ] || fail 'direct wrapper not reached'
for newest in good bad quoted; do
 cv_base
 long="$(python3 -c 'print("x"*100000,end="")')"
 args=()
 for i in $(seq 1 58); do args+=("$cv_early" "body $i"); done
 args+=("$cv_early" "$long")
 case "$newest" in good) body="$(cv_mark Review)";; bad) body='<!-- model-record: stage=Review -->';; quoted) body="\`$(cv_mark Review claude-opus-5)\`"; long="$(cv_mark Review)
$long"; args[117]="$long";; esac
 # One description plus 59 comments = 60 bodies.
 args+=("$cv_late" "$body")
 cv_rows comments "${args[@]:2}"
 : > "$CV_SCAN_LOG"
 start="$(python3 -c 'import time; print(time.time())')"
 cv_run
 python3 - "$start" <<'PY'
import sys,time
print('S273 complete collector elapsed %.3f s; macOS soft budget 2 s (reported)'%(time.time()-float(sys.argv[1])))
PY
 [ "$(wc -l < "$CV_SCAN_LOG" | tr -d ' ')" = 1 ] || fail "expected exactly one PR scan: $(cat "$CV_SCAN_LOG")"
 IFS=$'\t' read -r kind count bytes < "$CV_SCAN_LOG"
 [ "$kind" = model-record ] && [ "$count" = 60 ] && [ "$bytes" -gt 100000 ] || fail "raw scale bundle not reached: $(cat "$CV_SCAN_LOG")"
 if [ "$newest" = bad ]; then cv_status 2 indeterminate; else cv_status 2 evidenced; fi
 done
# Actual separator inside a value is removed for transport, never creates a body.
# Hostile values remain data; controls/newlines/delimiters cannot be read as models.
c0=()
for oct in $(python3 -c 'import random; r=random.Random(429); a=list(range(2,32)); r.shuffle(a); print(" ".join("%03o"%x for x in a))'); do c0+=("$(printf "x\\${oct}y")"); done
for value in "${c0[@]}" 'x<y' 'x>y' 'x"y' $'x\001y' $'x\177y' $'x\ry' $'x\r\ny' $'x\ny' $'x\ty' '$(touch SHELL_SENTINEL)' '--safe' $'multibyte-é' $'invalid-\377' $'truncated-\302' $'NEL-\302\205' $'LS-\342\200\250' $'PS-\342\200\251'; do
 transport_value="$value"
 case "$value" in *$'\377'*) transport_value="${value//$'\377'/@CV_FF@}";; *$'\302'*)
   # Only the intentionally truncated terminal octet needs raw reinsertion.
   case "$value" in truncated-*) transport_value='truncated-@CV_TR@';; esac;; esac
 bad="<!-- model-record: stage=Review model=\"$transport_value\" -->"
 cv_base; cv_rows comments "$cv_early" "$bad" "$cv_late" "$(cv_mark Review)"; : > "$CV_SCAN_LOG"; cv_run; cv_status 2 evidenced
 cv_rows comments "$cv_late" "$bad" "$cv_early" "$(cv_mark Review)"; : > "$CV_SCAN_LOG"; cv_run
 transformed="${value//$'\001'/ }"; transformed="${transformed//$'\036'/}"
 transformed="${transformed//$'\r\n'/$'\n'}"; transformed="${transformed//$'\r'/$'\n'}"
 python3 - "$CV_RAW_LOG" "$transformed" <<'BYTE'
from pathlib import Path
import os,sys
needle=b'model="'+os.fsencode(sys.argv[2])+b'"'
assert needle in Path(sys.argv[1]).read_bytes(), 'claimed hostile bytes never reached scanner'
BYTE
 [ "$?" = 0 ] || fail 'claimed hostile bytes never reached scanner'
 IFS=$'\t' read -r kind count bytes < "$CV_SCAN_LOG"
 [ "$kind" = model-record ] && [ "$count" = 3 ] || fail 'hostile value forged a body boundary'
 case "$value" in *$'\001'*|*$'\036'*) cv_status 2 unverifiable-from-artifacts;; *'<'*|*'>'*|*'"'*|*[[:cntrl:]]*) cv_status 2 indeterminate;; *) cv_status 2 unverifiable-from-artifacts;; esac
 [ ! -e SHELL_SENTINEL ] && [ ! -e "$SANDBOX/SHELL_SENTINEL" ] || fail 'shell token executed'
done
for prefix in '<!-- model-record: stage=Review model="open' $'```\n<!-- model-record: stage=Review model="quoted" -->' ' "odd <!-- model-record: stage=Review -->' '<!-- model-record: stage=Review model="x" <!-- nested -->' '<!-- model-record: stage=Review model="x" --> suffix'; do
 for start in ' ' 'letter'; do
  cv_base; cv_rows comments "$cv_early" "$prefix" "$cv_late" "$start prose
$(cv_mark Review)"; : > "$CV_SCAN_LOG"; cv_run; cv_status 2 evidenced
 done
done
cv_base; cv_rows comments "$cv_early" $'<!-- model-record: stage=Review model="x\036y" -->' "$cv_late" "$(cv_mark Review)"; : > "$CV_SCAN_LOG"; cv_run; cv_status 2 evidenced
IFS=$'\t' read -r kind count bytes < "$CV_SCAN_LOG"; [ "$count" = 3 ] || fail 'literal separator forged body'
cv_base; cv_rows comments "$cv_late" "$(cv_mark Review)$long|$(printf '\t')"; : > "$CV_SCAN_LOG"; cv_run; cv_status 2 indeterminate
[ "${#cv_out}" -lt 3000 ] || fail 'unbounded diagnostic/table'
# Codec bytes cannot manufacture a standalone Planning record or extra body.
for sentinel in $'\001' $'\036'; do
 cv_base; cv_pr "$(cv_mark Discovery)
$(cv_mark Test)
$(cv_mark Implementation)"
 cv_rows comments "$cv_late" "prose${sentinel}$(cv_mark Planning)"; : > "$CV_SCAN_LOG"; cv_run
 cv_status 1 indeterminate; cv_has 1 'not on a line of its own'
 IFS=$'\t' read -r kind count bytes < "$CV_SCAN_LOG"; [ "$count" = 2 ] || fail 'codec collision forged body'
done
# Reached failure cannot become no evidence or a model pass.
cv_base; : > "$CV_SCAN_LOG"; export CV_FAIL_SCAN=1; cv_run; cv_status 1 indeterminate; cv_status 2 indeterminate
[ -s "$CV_SCAN_LOG" ] || fail 'failing scanner never reached'
export CV_FAIL_SCAN=0; : > "$CV_SCAN_LOG"; cv_run; cv_status 1 evidenced; cv_status 2 evidenced
head -4 "$CV_SCAN_TIMES"
printf 'S273 tools: '; /bin/bash --version | head -1
/usr/bin/awk -version 2>&1 | head -1
/usr/bin/grep --version | head -1
printf '%s\n' 'S273 limit: NUL cannot be supplied in Bash arguments; emitter deny-list is stricter than reader values.'
test_done
