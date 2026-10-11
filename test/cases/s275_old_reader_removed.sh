#!/usr/bin/env bash
# S275 — complete retirement and reached v2 emitter round trip.
# Covers: F27, F39, F40
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create; trap sandbox_destroy EXIT
python3 - "$TEST_REPO_ROOT" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1])
names=['marker_'+'find','marker_'+'scan','marker_'+'attr','_MARKER_'+'SCAN_AWK']
hits=[]
for p in root.rglob('*'):
 if not p.is_file() or '.git' in p.parts or 'history' in p.relative_to(root).parts: continue
 try: s=p.read_text(errors='replace')
 except OSError: continue
 for name in names:
  if name in s: hits.append(str(p.relative_to(root))+': '+name)
if hits:
 print('\n'.join(hits),file=sys.stderr); sys.exit(1)
PY
[ "$?" = 0 ] || fail 'retired identifiers remain in whole working tree'
. "$TEST_REPO_ROOT/lib/model-record.sh"
for stage in Discovery Planning Test Implementation Review; do
 if [ "$stage" = Review ]; then line="$(marker_emit "$stage" claude-sonnet-5 "Same model floor")"; else line="$(marker_emit "$stage" claude-sonnet-5)"; fi
 : "$line"
 # || fail 'emit failed'
 scan="$(rec_scan model-record "$line")" || fail 'scan failed'
 [ "$scan" = $'1\tok\t'"$stage"$'\t'"$line" ] || fail "round trip $stage: $scan"
 [ "$(rec_field "$line" model)" = claude-sonnet-5 ] || fail 'field round trip'
done
# Private mutation adapters must be reached by emitter defence in depth.
mkdir -p "$SANDBOX/copy/lib" "$SANDBOX/copy/skills/pre-merge-review"
cp "$TEST_REPO_ROOT/lib/"*.sh "$SANDBOX/copy/lib/"
cp "$TEST_REPO_ROOT/skills/pre-merge-review/model-record-emit.sh" "$SANDBOX/copy/skills/pre-merge-review/"
export CV_EMIT_CALLS="$SANDBOX/emit-calls"
for fn in rec_scan rec_field; do
 cp "$TEST_REPO_ROOT/lib/model-record.sh" "$SANDBOX/copy/lib/model-record.sh"
 printf '\n%s() { printf "reached\\n" >> "$CV_EMIT_CALLS"; printf "wrong\\n"; }\n' "$fn" >> "$SANDBOX/copy/lib/model-record.sh"
 : > "$CV_EMIT_CALLS"
 /bin/bash "$SANDBOX/copy/skills/pre-merge-review/model-record-emit.sh" --stage Review --model claude-sonnet-5 --floor-basis "Same model floor" > "$SANDBOX/out" 2> "$SANDBOX/err"; rc=$?
 [ -s "$CV_EMIT_CALLS" ] || fail "emitter did not reach $fn mutation"
 [ "$rc" = 2 ] && [ ! -s "$SANDBOX/out" ] || fail "emitter accepted $fn mutant"
 grep -F 'would not read back' "$SANDBOX/err" >/dev/null || fail 'round-trip refusal diagnostic'
done
cp "$TEST_REPO_ROOT/lib/model-record.sh" "$SANDBOX/copy/lib/model-record.sh"
/bin/bash "$SANDBOX/copy/skills/pre-merge-review/model-record-emit.sh" --stage Review --model claude-sonnet-5 --floor-basis "Same model floor" > "$SANDBOX/out" 2> "$SANDBOX/err"; rc=$?
[ "$rc" = 0 ] && [ -s "$SANDBOX/out" ] || fail 'restored emitter'
test_done
