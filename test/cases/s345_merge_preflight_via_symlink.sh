#!/usr/bin/env bash
# S345 — merge-preflight.sh reached through a symlinked directory still finds the guard and checks the caller's repo (A44 amendment 1)
# Covers: F8
#
# Seam: the preflight's stdin JSON into the real hooks/git-guardrails, with gh
# on PATH (fake_gh_merge_bin). The script is run the way an adopted Codex
# project does: through the directory symlink <project>/.guardrails/source,
# from a working directory that is the project, not the checkout.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

SCRIPT="$TEST_REPO_ROOT/merge-preflight.sh"
[ -x "$SCRIPT" ] || { fail "S345 — merge-preflight.sh is missing or not executable"; test_done; }
command -v python3 >/dev/null 2>&1 || { fail "S345 — python3 is needed"; test_done; }

sandbox_create
trap sandbox_destroy EXIT

project="$(fresh_project symlinked)"
git -C "$project" commit -q --allow-empty -m start
git -C "$project" checkout -q -b feature/work
mkdir -p "$project/.guardrails" "$project/sub/dir"
ln -s "$TEST_REPO_ROOT" "$project/.guardrails/source"
green='[{"name":"check","bucket":"pass"}]'

# run_in <dir> <script path> <behind>: sets out, err, st
run_in() {
  local dir="$1" script="$2" behind="$3" fb
  fb="$(fake_gh_merge_bin match "$green" "$behind" main)"
  out="$(cd "$dir" && PATH="$fb:$PATH" "$script" 41 2>"$SANDBOX/err.txt")"; st=$?
  err="$(cat "$SANDBOX/err.txt")"
}

for variant in relative absolute subdir; do
  case "$variant" in
    relative) dir="$project"; script=".guardrails/source/merge-preflight.sh" ;;
    absolute) dir="$project"; script="$project/.guardrails/source/merge-preflight.sh" ;;
    subdir)   dir="$project/sub/dir"; script="../../.guardrails/source/merge-preflight.sh" ;;
  esac
  run_in "$dir" "$script" 3
  [ "$st" -eq 2 ] || fail "S345/$variant — a behind PR was not blocked through the symlink (status $st): $out$err"
  assert_contains "S345/$variant — names the remedy" "gh pr update-branch 41" "$err"
  run_in "$dir" "$script" 0
  [ "$st" -eq 0 ] || fail "S345/$variant — an up-to-date PR was blocked (status $st): $out$err"
done

# The JSON cwd is the caller's directory, not the checkout's (stub guard beside a symlinked copy).
stub="$SANDBOX/stubrepo"
mkdir -p "$stub/hooks" "$SANDBOX/rec"
cp "$SCRIPT" "$stub/merge-preflight.sh"
cat > "$stub/hooks/git-guardrails" <<'STUB'
#!/usr/bin/env bash
cat > "$REC/stdin"
exit 0
STUB
chmod +x "$stub/hooks/git-guardrails" "$stub/merge-preflight.sh"
export REC="$SANDBOX/rec"
ln -s "$stub" "$project/.guardrails/stub"
(cd "$project" && .guardrails/stub/merge-preflight.sh 41 >/dev/null 2>&1)
got_cwd="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["cwd"])' "$REC/stdin" 2>&1)"
want_cwd="$(cd "$project" && pwd -P)"
[ "$got_cwd" = "$want_cwd" ] || fail "S345/cwd — JSON cwd is '$got_cwd', wanted the caller's '$want_cwd'"

# A lone copy with no hooks/ beside it fails loudly, not silently.
lone="$SANDBOX/lone"
mkdir -p "$lone"
cp "$SCRIPT" "$lone/merge-preflight.sh"
chmod +x "$lone/merge-preflight.sh"
lone_err="$(cd "$project" && "$lone/merge-preflight.sh" 41 2>&1 >/dev/null)"; st=$?
[ "$st" -ne 0 ] || fail "S345/lone — a script with no guard beside it exited 0"
assert_contains "S345/lone — says the guard was not found" "not found" "$lone_err"

test_done
