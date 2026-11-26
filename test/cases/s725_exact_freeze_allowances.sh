#!/usr/bin/env bash
# S725 — #706 freeze amendments are exact, omissions and extra bytes refuse.
# Covers: F19, F38, F60, F76
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
python3 -I - "$TEST_REPO_ROOT" <<'PY'
from pathlib import Path
import json,runpy,subprocess,sys
root=Path(sys.argv[1]); a=runpy.run_path(str(root/'test/fixtures/wip-706-substitutions.py'))
table=json.loads((root/'test/fixtures/wip-706-substitutions.json').read_text())
errors=[]
for path in table['changes']:
    before=subprocess.check_output(['git','-C',str(root),'show',table['base']+':'+path])
    expected=a['controls'](path,before)
    actual=(root/path).read_bytes()
    if actual!=expected:
        errors.append('S725/exact-allowance: '+path+' differs from the #706 sanctioned substitutions')
for e in errors: print('FAIL: '+e)
sys.exit(bool(errors))
PY
[ "$?" -eq 0 ] || fail "S725 — #706 exact changes not implemented"
test_done
