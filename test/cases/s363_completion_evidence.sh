#!/usr/bin/env bash
# S363-S364 — validate the recorded live observations and explicit reset gaps.
# Covers: F56
set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
# This validates recorded evidence, never reruns paid/live sessions in CI.
python3 "$TEST_REPO_ROOT/test/completion-evidence.py" "$TEST_REPO_ROOT" || fail "completion evidence"

# Mutation checks (#561, Architect redesign step): the evidence test must tie each
# record era to its own run expectations. Scratch copies of the four inputs are
# mutated and the real test is pointed at them.
mut_copy() {
  local d="$1"
  mkdir -p "$d/adapters/codex" "$d/docs"
  cp "$TEST_REPO_ROOT/adapters/codex/AGENTS.md" "$d/adapters/codex/AGENTS.md"
  cp "$TEST_REPO_ROOT/docs/completion-live-evidence.json" "$d/docs/"
  cp "$TEST_REPO_ROOT/docs/completion-runtime-evidence.md" "$d/docs/"
  cp "$TEST_REPO_ROOT/TEST-SCENARIOS.md" "$d/"
}
# mut_repin <dir> <reminder-run:0|1>: drop status/superseded_by, set the current digest in
# JSON and report; with reminder-run=1 also make main/release-main genuine reminder runs.
mut_repin() {
  python3 - "$1" "$2" <<'PY'
import hashlib, json, sys
from pathlib import Path
d, reminder = Path(sys.argv[1]), sys.argv[2] == '1'
agents = (d / 'adapters/codex/AGENTS.md').read_text()
digest = hashlib.sha256(agents[agents.index('## Completion and fresh context'):].encode()).hexdigest()
jp, rp = d / 'docs/completion-live-evidence.json', d / 'docs/completion-runtime-evidence.md'
data = json.loads(jp.read_text())
old = data['instructions_sha256']
data.pop('status', None)
data.pop('superseded_by', None)
data['instructions_sha256'] = digest
if reminder:
    for run in data['runs']:
        if run['case'] in ('main', 'release-main'):
            run['sentinel'] = True
            run['commands'].append({'command': "/bin/zsh -lc 'touch sentinel'", 'exit_code': 0})
            assert 'Merged to main. Use /clear or /new before the next work item' in ' '.join(run['final'])
        else:
            assert 'Merged to main' not in ' '.join(run['final']), run['case']
jp.write_text(json.dumps(data, indent=1))
rp.write_text(rp.read_text().replace(old, digest))
PY
}
mut_root="$(mktemp -d "${TMPDIR:-/tmp}/s363-mut.XXXXXX")"
# R2: re-pinning the historical stop-era runs to the current hash must fail.
mut_copy "$mut_root/r2"; mut_repin "$mut_root/r2" 0
if python3 "$TEST_REPO_ROOT/test/completion-evidence.py" "$mut_root/r2" >/dev/null 2>&1; then
  fail "R2: stop-era runs re-pinned to the current hash were accepted as reminder evidence"
fi
# R3: a genuine reminder-run record under the current hash must pass.
mut_copy "$mut_root/r3"; mut_repin "$mut_root/r3" 1
python3 "$TEST_REPO_ROOT/test/completion-evidence.py" "$mut_root/r3" >/dev/null 2>"$mut_root/r3.err" \
  || fail "R3: a genuine reminder-run record was rejected: $(tail -n 1 "$mut_root/r3.err")"
rm -rf "$mut_root"
test_done
