#!/usr/bin/env bash
# S274 — syntax-aware bounded lint through the existing check Interface.
# Covers: F27, F40
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create; trap sandbox_destroy EXIT
mkdir -p "$SANDBOX/tree"
python3 - "$TEST_REPO_ROOT" "$SANDBOX/tree" <<'PY'
import shutil,sys
shutil.copytree(sys.argv[1],sys.argv[2],dirs_exist_ok=True,ignore=shutil.ignore_patterns('.git','__pycache__'))
PY
lint() { CHECK_SKIP_SHELLCHECK=1 PYTHONPYCACHEPREFIX="$SANDBOX/pycache" /bin/bash "$TEST_REPO_ROOT/check" --no-tests "$SANDBOX/tree" > "$SANDBOX/lint-output" 2>&1; lint_rc=$?; }
green() { lint; [ "$lint_rc" = 0 ] || fail "baseline lint: $(tail -20 "$SANDBOX/lint-output")"; }
red() {
 lint
 [ "$lint_rc" -ne 0 ] || fail "lint missed $1 in $2"
 grep -F "one-definition: $1" "$SANDBOX/lint-output" >/dev/null || fail "category $1 not reached"
 witness_count="$(grep -cF "one-definition: $1: $2:" "$SANDBOX/lint-output")"
 [ "$witness_count" = 1 ] || fail "scratch inspection counter for $2 is $witness_count, expected1"
}
green
for arm in pattern matcher helper effort; do
 file=scratch-429.sh
 case "$arm" in
 pattern) printf '%s\n' '#!/bin/bash' 'p="model-record:[[:blank:]]*stage=(Review)"' > "$SANDBOX/tree/$file";;
 matcher) printf '%s\n' '#!/bin/bash' "grep -E 'model-record' input" > "$SANDBOX/tree/$file";;
 helper) printf '%s\n' '#!/bin/bash' 'live_text() { :; }' > "$SANDBOX/tree/$file";;
 effort) file=skills/role-contracts/429-instruction.md; printf '%s\n' 'Pass `--effort` to the emitter.' > "$SANDBOX/tree/$file";;
 esac
 red "$arm" "$file"
 # A skipped-file control would be falsely green; red() requires path/category.
 python3 - "$SANDBOX/tree/$file" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).unlink()
PY
 green
done
# Helper ownership applies to executable shell files without an extension too.
printf '%s\n' '#!/bin/bash' 'live_text() { :; }' > "$SANDBOX/tree/scratch-429"
red helper scratch-429
python3 - "$SANDBOX/tree/scratch-429" <<'PYEXT'
from pathlib import Path
import sys
Path(sys.argv[1]).unlink()
PYEXT
green
# Actual matcher syntax and helper definitions, rather than token presence.
for code in "awk '/model-record/' input" "sed '/model-record/d' input" "[[ \$body =~ 'model-record' ]]" 'md_strip_fences() { :; }' 'rr_rounds() { :; }'; do
 printf '%s\n' '#!/bin/bash' "$code" > "$SANDBOX/tree/scratch-429.sh"
 case "$code" in *'()'*) category=helper;; *) category=matcher;; esac
 red "$category" scratch-429.sh
 python3 - "$SANDBOX/tree/scratch-429.sh" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).unlink()
PY
 done
green
printf '%s\n' '#!/bin/bash' "printf '%s\\n' 'model-record: missing Review'" '# Example: grep model-record input' > "$SANDBOX/tree/scratch-429.sh"
printf '%s\n' 'Example only:' '```bash' "grep 'model-record' example" '```' 'The ignored --effort flag is historical.' > "$SANDBOX/tree/429-example.md"
green
grep -F 'this lint can be evaded' "$SANDBOX/lint-output" >/dev/null || fail 'lint limit not stated'
test_done
