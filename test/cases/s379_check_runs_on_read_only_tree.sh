#!/usr/bin/env bash
# S379 — ./check runs ok on a read-only tree without writing bytecode, and still reports a syntax error with file and line.
# Covers: F57
#
# Issue #590, AC3. Seam: the real `check` run on a tiny sandbox project.
# Falsifiers: an explicit `python3 -m py_compile` (writes a .pyc, fails on a
# read-only tree), PYTHONDONTWRITEBYTECODE=1 missing from check, a syntax
# error reported without its file or line.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap 'chmod -R u+w "$SANDBOX" 2>/dev/null; sandbox_destroy' EXIT

mk_project() {
  mkdir -p "$1/settings"
  echo '{}' > "$1/settings/session-hooks.json"
}

# Given: a project with one valid Python file, every directory read-only.
ok="$SANDBOX/ok"
mk_project "$ok"
printf 'x = 1\n' > "$ok/good.py"
chmod a-w "$ok" "$ok/settings"

# When: ./check runs (no test suite).
if touch "$ok/probe" 2>/dev/null; then
  rm -f "$ok/probe"
  echo "S379: directories stay writable here (running as root?), read-only part skipped" >&2
else
  out="$("$TEST_REPO_ROOT/check" --no-tests "$ok" 2>&1)"
  status=$?
  # Then: it finishes ok, no bytecode was written.
  [ "$status" -eq 0 ] || fail "S379 — check failed on a read-only tree: $out"
  [ -z "$(find "$ok" -name '*.pyc' -o -name __pycache__)" ] || fail "S379 — bytecode appeared in a read-only tree"
fi
chmod -R u+w "$ok"

# Given: a Python file with a syntax error on line 2.
bad="$SANDBOX/bad"
mk_project "$bad"
printf 'x = 1\ndef broken(:\n' > "$bad/bad.py"
out="$("$TEST_REPO_ROOT/check" --no-tests "$bad" 2>&1)"
status=$?
# Then: check fails and names the file and the line.
[ "$status" -ne 0 ] || fail "S379 — check passed a Python syntax error"
assert_contains "S379 file" "bad.py" "$out"
assert_contains "S379 line" "line 2" "$out"

# And: a recording python3 shim shows what check asks of Python. (On macOS
# the system Python keeps bytecode outside the tree, so a read-only tree alone
# cannot go red there.)
real_py="$(command -v python3)"
mkdir -p "$SANDBOX/bin"
cat > "$SANDBOX/bin/python3" <<SHIM
#!/usr/bin/env bash
a2="\${2:-}"; a2="\${a2:0:30}"; a2="\${a2//\$'\\n'/ }"
echo "\${1:-} \$a2 | PYTHONDONTWRITEBYTECODE=\${PYTHONDONTWRITEBYTECODE:-unset}" >> "$SANDBOX/py.log"
exec "$real_py" "\$@"
SHIM
chmod +x "$SANDBOX/bin/python3"
: > "$SANDBOX/py.log"
PATH="$SANDBOX/bin:$PATH" "$TEST_REPO_ROOT/check" --no-tests "$ok" >/dev/null 2>&1
grep -q 'py_compile' "$SANDBOX/py.log" && fail "S379 — check asked Python to py_compile (writes bytecode)"
grep -q 'PYTHONDONTWRITEBYTECODE=unset' "$SANDBOX/py.log" && fail "S379 — check ran python3 without PYTHONDONTWRITEBYTECODE=1"
[ -s "$SANDBOX/py.log" ] || fail "S379 — check never ran python3 on the project's Python file"

# And (#595 AC1, L2): every python3 call in check is covered, not only the
# syntax step. The other calls (json.tool, the SIGPIPE and quote-break
# checks, the one-definition lint) only run on a tree that carries those
# scripts, so run check on a copy of this repo with the same recording shim.
full="$(sandbox_copy_repo full)"
: > "$SANDBOX/py.log"
PATH="$SANDBOX/bin:$PATH" CHECK_SKIP_SHELLCHECK=1 "$TEST_REPO_ROOT/check" --no-tests "$full" >/dev/null 2>&1
# A call counts as covered with the variable set or with python3's -B flag.
unset_calls="$(grep 'PYTHONDONTWRITEBYTECODE=unset' "$SANDBOX/py.log" | grep -v '^-B ' || true)"
[ -z "$unset_calls" ] || fail "S379 — python3 calls in check without PYTHONDONTWRITEBYTECODE=1: $unset_calls"
# (json.tool only runs when jq is absent, so it is not required here.)
grep -q -- 'one-definition-lint' "$SANDBOX/py.log" || fail "S379 — the full-tree run never reached the python3 call for one-definition-lint"

# And: the fix lives in check itself.
grep -q 'PYTHONDONTWRITEBYTECODE=1' "$TEST_REPO_ROOT/check" || fail "S379 — check does not set PYTHONDONTWRITEBYTECODE=1"
check_code="$(grep -v '^[[:space:]]*#' "$TEST_REPO_ROOT/check")"
if grep -q 'py_compile' <<< "$check_code"; then
  fail "S379 — check still compiles with py_compile (writes bytecode)"
fi

test_done
