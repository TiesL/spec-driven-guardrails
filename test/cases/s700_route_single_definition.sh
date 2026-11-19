#!/usr/bin/env bash
# S700 — One definition of the route, found everywhere (#707; AC1)
# Covers: F75
#
# Seam: the checker rc_route_scan (test/fixtures/route-child-helpers.sh), a
# function over a repository root whose file list is `git ls-files`; run on
# the real tree, on planted-violation trees, on an allowed-only tree, and
# (walk mode) on a project written by adopt.sh. Allowed set: route-child.sh,
# files under test/, *.md outside templates/ and skills/ (Architect report 5).

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/route-child-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/route-child-helpers.sh"

sandbox_create
trap sandbox_destroy EXIT

# --- (a) the real tree --------------------------------------------------
[ -f "$TEST_REPO_ROOT/route-child.sh" ] || fail "S700/a — route-child.sh does not exist at the repo root"
if ! out="$(rc_route_scan "$TEST_REPO_ROOT")"; then
  fail "S700/a — the real tree has route definitions outside the allowed set:"
  printf '%s\n' "$out" >&2
fi
# The one definition exists, and it is where the checker allows it.
if [ -f "$TEST_REPO_ROOT/route-child.sh" ]; then
  mkdir -p "$SANDBOX/only"
  git -C "$SANDBOX/only" init -q -b main
  cp "$TEST_REPO_ROOT/route-child.sh" "$SANDBOX/only/x.sh"
  git -C "$SANDBOX/only" add x.sh
  out="$(rc_route_scan "$SANDBOX/only")"
  for p in proxy-address base-url-assignment transform-header provider-override; do
    grep -qx "x.sh: $p" <<<"$out" || fail "S700/a — route-child.sh holds no '$p' (the single definition is missing it)"
  done
fi
# The real spec files name these strings and still pass (they are docs).
for f in ARCHITECTURE.md TEST-SCENARIOS.md; do
  grep -q '127.0.0.1:8787' "$TEST_REPO_ROOT/$f" || fail "S700/a — $f does not name the proxy address (expected: the spec names it)"
done

# --- (b) planted violations, each pattern in every forbidden location ----
fx="$SANDBOX/planted"
mkdir -p "$fx"
git -C "$fx" init -q -b main
echo "# fixture" >"$fx/README.md"
git -C "$fx" add README.md
locations="x.sh hooks/guard settings/session-hooks.json templates/ci.yml templates/README.md
skills/s/SKILL.md skills/s/run.sh lib/x.sh adopt.sh docs/x.sh docs/notes.md.sh tests/x.sh mytest/x.sh"
plant_round() { # <pattern-name> <content>
  local name="$1" content="$2" loc out
  for loc in $locations; do
    mkdir -p "$fx/$(dirname "$loc")"
    printf '%s\n' "$content" >"$fx/$loc"
    git -C "$fx" add "$loc"
  done
  if out="$(rc_route_scan "$fx")"; then
    fail "S700/b — planted '$name' ($content) passed the checker"
  fi
  for loc in $locations; do
    grep -qxF "$loc: $name" <<<"$out" || fail "S700/b — '$name' planted in $loc is not reported (content: $content)"
  done
  for loc in $locations; do
    git -C "$fx" rm -q --cached "$loc"
    rm -f "$fx/$loc"
  done
}
plant_round proxy-address 'curl http://127.0.0.1:8787/'
plant_round base-url-assignment 'export ANTHROPIC_BASE_URL=http://x'
plant_round base-url-assignment 'ANTHROPIC_BASE_URL=http://x claude -p hi'
plant_round base-url-assignment '{"env": {"ANTHROPIC_BASE_URL": "http://x"}}'
plant_round base-url-assignment 'env["ANTHROPIC_BASE_URL"] = "http://x"'
plant_round base-url-assignment "opts = {'ANTHROPIC_BASE_URL': 'http://x'}"
plant_round transform-header 'hdr="x-cave-transforms: v"'
plant_round provider-override "codex -c 'model_provider=\"openai\"' exec x"
plant_round provider-override 'model_providers.caveman.http_headers={}'

# Reads that are not assignments do not count (no over-reach on readers).
mkdir -p "$fx/lib"
printf '%s\n' 'if [ "${ANTHROPIC_BASE_URL+x}" = x ] && [ "$ANTHROPIC_BASE_URL" != y ]; then :; fi' \
  'v = os.environ.get("ANTHROPIC_BASE_URL")' >"$fx/lib/reader.sh"
git -C "$fx" add lib/reader.sh
rc_route_scan "$fx" >/dev/null || fail "S700/b — a read of ANTHROPIC_BASE_URL was reported as an assignment"
git -C "$fx" rm -q --cached lib/reader.sh

# --- (c) patterns only where allowed --------------------------------------
all='http://127.0.0.1:8787/w/claude
export ANTHROPIC_BASE_URL=x
{"ANTHROPIC_BASE_URL": "x"}
x-cave-transforms: caveman.pass-through.v1
model_provider="openai"'
for loc in route-child.sh test/x.sh test/sub/y.py PRD.md ARCHITECTURE.md TEST-SCENARIOS.md CHANGELOG.md \
  docs/model-routing.md docs/other.md docs/sub/x.md hooks/README.md; do
  mkdir -p "$fx/$(dirname "$loc")"
  printf '%s\n' "$all" >"$fx/$loc"
  git -C "$fx" add "$loc"
done
if ! out="$(rc_route_scan "$fx")"; then
  fail "S700/c — patterns in allowed places were reported:"
  printf '%s\n' "$out" >&2
fi

# --- (d) a project written by adopt.sh -------------------------------------
proj="$(fresh_project adopted)"
adopt "$proj" || fail "S700/d — adopt.sh failed on a fresh project"
if ! out="$(rc_route_scan "$proj" walk)"; then
  fail "S700/d — adopt.sh wrote route definitions into the project:"
  printf '%s\n' "$out" >&2
fi
settings_env="$(python3 -I - "$proj" <<'PY'
import json, os, sys
root = sys.argv[1]
found = 0
for d, dirs, names in os.walk(root):
    dirs[:] = [x for x in dirs if x != ".git"]
    for n in names:
        if n.endswith("settings.json") or n == "settings.local.json":
            found += 1
            p = os.path.join(d, n)
            data = json.load(open(p))
            if isinstance(data, dict) and "env" in data:
                print("env key in " + os.path.relpath(p, root))
print("settings files: %d" % found)
PY
)"
grep -q '^env key' <<<"$settings_env" && fail "S700/d — adopt.sh wrote an env key: $settings_env"
grep -q '^settings files: [1-9]' <<<"$settings_env" || fail "S700/d — no settings.json found in the adopted project (the env check checked nothing): $settings_env"

test_done
