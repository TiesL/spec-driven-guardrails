#!/usr/bin/env bash
# S724 — #706 promotion scenarios use the closed schema and inventory.
# Covers: F38, F60, F76
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
python3 -I "$TEST_REPO_ROOT/test/behavior/orchestrator_diff.py" check-scenarios \
  --scenarios "$TEST_REPO_ROOT/test/behavior/orchestrator-scenarios.md" \
  --orchestrator "$TEST_REPO_ROOT/skills/role-contracts/ORCHESTRATOR.md" || fail "S724/control — behavior schema"
python3 -I - "$TEST_REPO_ROOT" <<'PY'
from pathlib import Path
import re,sys
root=Path(sys.argv[1]); text=(root/'test/behavior/orchestrator-scenarios.md').read_text()
rows={c[0]:c for l in (root/'skills/role-contracts/orchestrator-rules.tsv').read_text().splitlines()[1:] if len(c:=l.split('\t'))>=5}
errors=[]
for n in range(84,92):
    m=re.search(r'^### OB'+str(n)+r' · (.*?)\n(.*?)(?=^### |^## |\Z)', text, re.M|re.S)
    assert m, 'missing QA-owned OB'+str(n)
    ors=m[1].split(', ')
    assert re.search(r'^- OB'+str(n)+r' \('+re.escape(m[1])+r'\): .*#706',text,re.M), 'missing Intended changes'
    for rid in ors:
        if 'OB'+str(n) not in rows[rid][4].split(','):
            errors.append(f'S724/OB{n}/{rid}: inventory covered_by must include the #706 promotion scenario')
for e in errors: print('FAIL: '+e)
sys.exit(bool(errors))
PY
[ "$?" -eq 0 ] || fail "S724 — promotion inventory incomplete"
test_done
