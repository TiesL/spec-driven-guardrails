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
# repinned <dir>: postcondition of mut_repin <dir> 1 (#570 AC2): no status key, the current
# digest is pinned, and main carries the sentinel. Without it a skipped re-pin could leave
# the historical record in place and R3 would then be evaluated against the wrong record.
repinned() {
  python3 - "$1" <<'PY'
import hashlib, json, sys
from pathlib import Path
d = Path(sys.argv[1])
agents = (d / 'adapters/codex/AGENTS.md').read_text()
digest = hashlib.sha256(agents[agents.index('## Completion and fresh context'):].encode()).hexdigest()
data = json.loads((d / 'docs/completion-live-evidence.json').read_text())
ok = ('status' not in data and data['instructions_sha256'] == digest
      and any(r['case'] == 'main' and r.get('sentinel') is True for r in data['runs']))
sys.exit(0 if ok else 1)
PY
}
mut_root="$(mktemp -d "${TMPDIR:-/tmp}/s363-mut.XXXXXX")"
# R2: re-pinning the historical stop-era runs to the current hash must fail.
mut_copy "$mut_root/r2"
if mut_repin "$mut_root/r2" 0 2>"$mut_root/r2.merr"; then
  if python3 "$TEST_REPO_ROOT/test/completion-evidence.py" "$mut_root/r2" >/dev/null 2>&1; then
    fail "R2: stop-era runs re-pinned to the current hash were accepted as reminder evidence"
  fi
else
  fail "R2: mutator mut_repin aborted; R2 not evaluated: $(tail -n 1 "$mut_root/r2.merr")"
fi
# R3: a genuine reminder-run record under the current hash must pass.
mut_copy "$mut_root/r3"
if ! mut_repin "$mut_root/r3" 1 2>"$mut_root/r3.merr"; then
  fail "R3: mutator mut_repin aborted; R3 not evaluated: $(tail -n 1 "$mut_root/r3.merr")"
elif ! repinned "$mut_root/r3"; then
  fail "R3: re-pin postcondition failed; R3 not evaluated against a re-pinned record"
else
  python3 "$TEST_REPO_ROOT/test/completion-evidence.py" "$mut_root/r3" >/dev/null 2>"$mut_root/r3.err" \
    || fail "R3: a genuine reminder-run record was rejected: $(tail -n 1 "$mut_root/r3.err")"
fi
# Negative arms (#570 AC1, AC2): the guards above must be able to fire.
# (a) an un-repinned copy does not satisfy the postcondition, so a skipped re-pin cannot pass R3.
mut_copy "$mut_root/n1"
if repinned "$mut_root/n1"; then
  fail "R3 arm: repinned accepted an un-repinned (historical) copy"
fi
# (b) the #570 falsifier: main's final text changed, mut_repin must abort non-zero.
mut_copy "$mut_root/n2"
sed -i.bak 's/Merged to main\. Use/Merged into main. Use/' "$mut_root/n2/docs/completion-live-evidence.json"
if mut_repin "$mut_root/n2" 1 >/dev/null 2>&1; then
  fail "R3 arm: mut_repin exited 0 although main's final text no longer matches"
fi
rm -rf "$mut_root"
test_done
