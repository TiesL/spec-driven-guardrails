#!/usr/bin/env bash
# S126 — Adoption postcondition gate (#239 AC1): a "yes" answer in
# WORKFLOW-ADOPTION.md is checked against its actual precondition, not
# trusted on its own word.
# Covers: F9
#
# Found via #238's portfolio-mgt-agents audit: traceability-link-1 was
# answered yes with no check-traceability.sh ever run or even present;
# ci-gate-on-merge was answered yes in a repo with no package.json and no
# CI config at all, so it structurally could not fire.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

script="$TEST_REPO_ROOT/skills/pre-merge-review/adoption-postcondition-gate.sh"
[ -x "$script" ] || { fail "S126 — skills/pre-merge-review/adoption-postcondition-gate.sh is missing or not executable"; test_done; }

sandbox_create
trap sandbox_destroy EXIT

# Case 1: both rows answered yes, neither postcondition holds.
broken="$SANDBOX/broken"
mkdir -p "$broken"
cat > "$broken/WORKFLOW-ADOPTION.md" <<'EOF'
# Adoption of shared workflow changes

| Change | Answer | Date | Notes |
|---|---|---|---|
| traceability-link-1 | yes | 2026-09-19 | seeded |
| ci-gate-on-merge | yes | 2026-09-19 | seeded |
EOF

output="$("$script" "$broken")"

case "$output" in
  *"traceability-link-1"*"does not exist"*) : ;;
  *) fail "S126 — expected a finding for the missing check-traceability.sh, got: $output" ;;
esac
case "$output" in
  *"ci-gate-on-merge"*"no CI workflow exists"*) : ;;
  *) fail "S126 — expected a finding for the missing CI workflow, got: $output" ;;
esac

# Case 2: both postconditions genuinely hold — no findings.
whole="$SANDBOX/whole"
mkdir -p "$whole/.github/workflows"
cp "$TEST_REPO_ROOT/templates/check-traceability.sh" "$whole/check-traceability.sh"
cat > "$whole/check" <<'EOF'
#!/usr/bin/env bash
./check-traceability.sh .
EOF
cat > "$whole/.github/workflows/ci.yml" <<'EOF'
name: CI
on: [push, pull_request]
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - run: ./check
EOF
cat > "$whole/WORKFLOW-ADOPTION.md" <<'EOF'
# Adoption of shared workflow changes

| Change | Answer | Date | Notes |
|---|---|---|---|
| traceability-link-1 | yes | 2026-09-19 | wired |
| ci-gate-on-merge | yes | 2026-09-19 | wired |
EOF

output2="$("$script" "$whole")"
[ -z "$output2" ] || fail "S126 — expected no findings when both postconditions hold, got: $output2"

# Case 3: a "no — not yet" row (see #239 AC3) is not checked at all — it
# never claimed the postcondition holds.
declined="$SANDBOX/declined"
mkdir -p "$declined"
cat > "$declined/WORKFLOW-ADOPTION.md" <<'EOF'
# Adoption of shared workflow changes

| Change | Answer | Date | Notes |
|---|---|---|---|
| traceability-link-1 | no — not yet, no PRD.md written | 2026-09-19 | trigger: once PRD.md exists |
EOF

output3="$("$script" "$declined")"
[ -z "$output3" ] || fail "S126 — expected no findings for a 'no — not yet' row, got: $output3"

# Case 4: a CI workflow exists but only checks out the repo, never actually
# calls `check` — found by pre-merge-review on PR #246: a plain substring
# match on "check" was silently satisfied by "actions/checkout", the most
# common line in almost any workflow, so this case never fired.
checkout_only="$SANDBOX/checkout_only"
mkdir -p "$checkout_only/.github/workflows"
cat > "$checkout_only/.github/workflows/ci.yml" <<'EOF'
name: CI
on: [push, pull_request]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm test
EOF
cat > "$checkout_only/WORKFLOW-ADOPTION.md" <<'EOF'
# Adoption of shared workflow changes

| Change | Answer | Date | Notes |
|---|---|---|---|
| ci-gate-on-merge | yes | 2026-09-19 | seeded |
EOF

output4="$("$script" "$checkout_only")"
case "$output4" in
  *"ci-gate-on-merge"*"no CI workflow appears to invoke check"*) : ;;
  *) fail "S126 — expected a finding for a checkout-only workflow that never calls check, got: $output4" ;;
esac

test_done
