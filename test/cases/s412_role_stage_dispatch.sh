#!/usr/bin/env bash
# S412 — Role-only dispatches pass and invalid forms stay fail-closed (#599 AC5, AC8)
# Covers: F40
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
# Snapshot integrity is unconditional, even when the historical Git object exists.
python3 -I - "$TEST_REPO_ROOT" <<'PY_INTEGRITY' || fail "S412 — historical snapshot integrity failed"
import hashlib
from pathlib import Path
import sys
p = Path(sys.argv[1]) / 'test/fixtures/role-stage-599-previous.py'
if not p.is_file():
    sys.exit('missing historical snapshot: role-stage-599-previous.py')
if hashlib.sha256(p.read_bytes()).hexdigest() != 'de151be376dacf6ac1dde3807bc85ae6537af5afabda98b8a8566394fbbc5e71':
    sys.exit('SHA-256 integrity mismatch: role-stage-599-previous.py')
PY_INTEGRITY
python3 -I "$TEST_REPO_ROOT/test/fixtures/role-stage-599.py" dispatch "$TEST_REPO_ROOT" "$SANDBOX" || fail "S412 — AC5, AC8 public seam assertions failed (see above)"
# Developer-only local AC1 laboratory: requires the otherwise unreachable object
# as setup evidence. Ordinary S412 never requires that object to construct a test.
if [ "${1:-}" != "--checkout-independence" ]; then
  test_done
fi
# AC1: real object stores, identical checkout bytes, no availability mocks.
python3 -I - "$TEST_REPO_ROOT" "$SANDBOX" <<'PY_CHECK' || fail "S412 — checkout independence/integrity assertions failed"
import hashlib
from pathlib import Path
import re
import shutil
import subprocess
import sys

source, scratch = map(Path, sys.argv[1:])
pin = '2d93c255f06c3f89afde70b2625c1926a09754a5'
snapshot = 'test/fixtures/role-stage-599-previous.py'
digest = 'de151be376dacf6ac1dde3807bc85ae6537af5afabda98b8a8566394fbbc5e71'
failed = []
def check(ok, label):
    print(('PASS: ' if ok else 'FAIL: ') + label, flush=True)
    if not ok:
        failed.append(label)

def git(root, *args, data=None):
    return subprocess.run(['git', '-C', str(root), *args], input=data,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)

def replay(root, name):
    result = subprocess.run(['bash', str(root / 'test/cases/s412_role_stage_dispatch.sh')], cwd=root,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)
    output = result.stdout.decode(errors='replace')
    (scratch / (name + '.log')).write_text(output)
    print('REPLAY: ' + name, flush=True)
    print(output, end='', flush=True)
    return result.returncode, output

repos = []
for name in ['without-pin', 'with-pin']:
    root = scratch / name
    cloned = subprocess.run(['git', 'clone', '--no-local', '--no-checkout', '--single-branch',
                             '--branch', 'main', str(source), str(root)],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if cloned.returncode:
        raise RuntimeError(cloned.stderr.decode())
    # Overlay the same uncommitted QA/Developer bytes; never copy .git or links
    # into the originating checkout's installed runtime configuration.
    shutil.copytree(source, root, dirs_exist_ok=True, symlinks=True,
                    ignore=shutil.ignore_patterns('.git', '.agents', '.claude', '.codex', '__pycache__'))
    check(not (root / '.git/objects/info/alternates').exists(), name + ': no alternates')
    check(git(root, 'rev-parse', '--verify', pin + '^{commit}').returncode != 0,
          name + ': ref-only transfer cannot resolve historical pin')
    repos.append(root)
# Explicit object transfer only into the second isolated repository, no remote.
pack = git(source, 'pack-objects', '--stdout', '--revs', data=(pin + '\n').encode())
if pack.returncode:
    raise RuntimeError('local historical pin needed to construct the with-pin falsifier')
unpack = git(repos[1], 'unpack-objects', data=pack.stdout)
check(unpack.returncode == 0 and git(repos[1], 'rev-parse', '--verify', pin + '^{commit}').returncode == 0,
      'with-pin: historical object explicitly supplied')
check(git(repos[0], 'rev-parse', 'HEAD', 'origin/main').stdout ==
      git(repos[1], 'rev-parse', 'HEAD', 'origin/main').stdout, 'AC1: identical HEAD/main refs')
results = []
for root in repos:
    results.append(replay(root, root.name + '-complete'))
    path = root / snapshot
    check(path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest() == digest,
          root.name + ': snapshot exists with exact provenance digest')
    original = path.read_bytes() if path.exists() else None
    for mutation in ['missing', 'one-byte-corrupt']:
        if mutation == 'missing':
            path.unlink(missing_ok=True)
        else:
            # Use authentic source bytes for the negative control even on the
            # red head; never install a valid snapshot into the working tree.
            data = original if original is not None else git(source, 'show', pin + ':hooks/agent-dispatch.py').stdout
            if hashlib.sha256(data).hexdigest() != digest:
                raise RuntimeError('corruption control requires verified historical source bytes')
            path.write_bytes(bytes([data[0] ^ 1]) + data[1:])
        status, output = replay(root, root.name + '-' + mutation)
        check(status != 0 and 'role-stage-599-previous.py' in output and
              re.search(r'missing|digest|sha.?256|corrupt|integrity', output, re.I) is not None,
              root.name + ': ' + mutation + ' fails explicitly at snapshot integrity seam')
        path.unlink(missing_ok=True)
        if original is not None:
            path.write_bytes(original)

def outcomes(output):
    # Preserve assertion totals and all group/case outcomes, ignore timing only.
    return [line for line in output.splitlines()
            if line.startswith(('Assertions:', 'RESULT:', 'FAIL:', 'OBSERVATION:', 'QUESTION:', 'SKIP:'))]
for root, (status, output) in zip(repos, results):
    check(status == 0, root.name + ': complete S412 exits zero')
    check('SKIP: round-6' not in output and 'availability skip forbidden' not in output,
          root.name + ': no historical availability skip')
    check(bool(re.search(r'^Assertions: \d+ passed, \d+ failed$', output, re.M)),
          root.name + ': complete assertion totals reported')
check(outcomes(results[0][1]) == outcomes(results[1][1]),
      'AC1: identical assertion counts and case/group outcomes')
print('AC1 assertions: %d failed' % len(failed), flush=True)
sys.exit(bool(failed))
PY_CHECK
test_done
