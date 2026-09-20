#!/usr/bin/env bash
# S136 — CI scaffolding is gated on an executable `check`, not on
# package.json, and calls ./check directly with npm setup conditional
# (#248 AC1-AC3).
# Covers: F9
#
# Found via portfolio-mgt-agents (a docs-only project, no package.json):
# adopt.sh never scaffolded ci.yml/check-pr-issue-link.sh/check-main-via-pr.sh
# at all, and even with the gate removed, templates/ci.yml ran `npm run
# check`, not ./check directly — a project whose check is a plain shell
# script would still fail CI.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# AC1/AC3: a project with an executable check but no package.json gets
# CI scaffolded — ci.yml and both stack-agnostic scripts.
project="$(fresh_project no-package-json)"
cat > "$project/check" <<'EOF'
#!/usr/bin/env bash
echo "checked"
EOF
chmod +x "$project/check"
adopt "$project"

[ -f "$project/.github/workflows/ci.yml" ] || fail "S136 — ci.yml was not scaffolded for a project with an executable check but no package.json"
[ -f "$project/check-pr-issue-link.sh" ] || fail "S136 — check-pr-issue-link.sh was not scaffolded alongside it"
[ -f "$project/check-main-via-pr.sh" ] || fail "S136 — check-main-via-pr.sh was not scaffolded alongside it"
[ -f "$project/wait-for-ci.sh" ] || fail "S136 — wait-for-ci.sh was not scaffolded alongside it (#265)"

# And: package.json alone, no executable check, does NOT trigger the
# scaffold — the real precondition is the check command, not the stack —
# and adopt.sh says why, not silently (found during PR #257's pre-merge-review:
# an npm project relying only on package.json's own "scripts.check", no
# root executable check, used to get CI scaffolded and now doesn't, with
# no message unless one is printed here).
project_pkg_only="$(fresh_project package-json-only)"
echo '{"name":"t"}' > "$project_pkg_only/package.json"
skip_output="$(SPEC_DRIVEN_GUARDRAILS_DIR="$TEST_REPO_ROOT" "$TEST_REPO_ROOT/adopt.sh" "$project_pkg_only" 2>&1)"
if [ -f "$project_pkg_only/.github/workflows/ci.yml" ]; then
  fail "S136 — ci.yml was scaffolded from package.json alone, without an executable check"
fi
assert_contains "S136 — adopt.sh explains why CI wasn't scaffolded" "Not scaffolding CI" "$skip_output"

# AC2: the scaffolded ci.yml calls ./check directly, and the npm setup
# steps are conditional, not assumed.
ci_content="$(cat "$project/.github/workflows/ci.yml")"
assert_contains "S136 — ci.yml calls ./check directly" "run: ./check" "$ci_content"
case "$ci_content" in
  *"run: npm run check"*) fail "S136 — ci.yml still calls npm run check instead of ./check directly" ;;
esac
assert_contains "S136 — the npm setup step is conditional on package.json" "hashFiles('package.json')" "$ci_content"

test_done
