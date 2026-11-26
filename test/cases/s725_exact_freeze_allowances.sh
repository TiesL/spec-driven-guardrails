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
duties=runpy.run_path(str(root/'test/fixtures/wip-promotion-706.py'))
duties['core_duty_controls']([new for old,new in table['changes']['skills/role-contracts/ORCHESTRATOR.md']])
errors=a['protected_a_checks'](root)
for path in table['changes']:
    before=subprocess.check_output(['git','-C',str(root),'show',table['base']+':'+path])
    expected=a['controls'](path,before)
    accepts=lambda data: data == expected
    for index,(old,new) in enumerate(table['changes'][path]):
        for label,replacement in (('omitted',old.encode()),('wrong',b'UNAUTHORIZED')):
            mutant=expected.replace(new.encode(),replacement,1)
            assert not accepts(mutant), 'S725/'+label+' pair survived: '+path
            print('KILLED: S725/'+path+'/'+label+' pair '+str(index+1))
    assert not accepts(expected+b'\n'), 'S725/extra byte survived: '+path
    print('KILLED: S725/'+path+'/extra byte')
    actual=(root/path).read_bytes()
    if not accepts(actual):
        errors.append('S725/exact-allowance: '+path+' differs from the #706 sanctioned substitutions')
for e in errors: print('FAIL: '+e)
sys.exit(bool(errors))
PY
[ "$?" -eq 0 ] || fail "S725 — #706 exact changes not implemented"
test_done
