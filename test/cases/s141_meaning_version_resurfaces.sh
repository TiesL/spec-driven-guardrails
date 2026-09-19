#!/usr/bin/env bash
# S141 — A materially tightened CHANGES.md row re-surfaces for a project
# that already answered it, distinct from "never answered" (#254).
# Covers: F9
#
# Found via #244: quality-review-before-merge's own "Yes means" was
# tightened (a genuinely different reviewer model, not just "at least as
# skilled") after this project itself had already answered it "yes" under
# the older, looser meaning. Nothing re-surfaced that — this project's own
# WORKFLOW-ADOPTION.md silently kept the stale answer until noticed by
# hand. quality-review-before-merge is the real, live case exercised here
# (bumped to meaning v2 in CHANGES.md as part of #254's own fix) — not a
# synthetic fixture entry.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Case 1: answered before the version bump (no "(meaning v<N>)" marker at
# all) -> resurfaces.
project="$(fresh_project stale-answer)"
git -C "$project" commit -q --allow-empty -m start
cat > "$project/WORKFLOW-ADOPTION.md" <<'EOF'
# Adoption of shared workflow changes

| Change | Answer | Date | Notes |
|---|---|---|---|
| quality-review-before-merge | yes | 2026-01-01 | answered before #244 |
EOF

output="$("$TEST_REPO_ROOT/pending-changes.sh" "$project" 2>&1)"
case "$output" in
  *"quality-review-before-merge"*"answered under meaning v1, now v2"*) : ;;
  *) fail "S141 — expected quality-review-before-merge to resurface, got: $output" ;;
esac

# And: it must not appear in the plain "Pending workflow changes" list —
# resurfacing is its own, distinct report, not folded into "never
# answered". Checked as a precise bullet-line match, not a whole-output
# substring: quality-review-before-merge legitimately appears later, in
# the resurfaced section, so a loose "does X appear anywhere after Y"
# check would pass regardless of which section it's actually in.
if grep -qE '^  - quality-review-before-merge — Must every PR' <<<"$output"; then
  fail "S141 — resurfaced row wrongly appeared in the never-answered list too, got: $output"
fi

# Case 2: re-confirmed with the current version marker -> no longer
# resurfaces (AC2's spirit: a real re-confirmation, once made, is quiet).
project_confirmed="$(fresh_project reconfirmed)"
git -C "$project_confirmed" commit -q --allow-empty -m start
cat > "$project_confirmed/WORKFLOW-ADOPTION.md" <<'EOF'
# Adoption of shared workflow changes

| Change | Answer | Date | Notes |
|---|---|---|---|
| quality-review-before-merge | yes | 2026-09-19 | re-confirmed for #244 (meaning v2) |
EOF

output_confirmed="$("$TEST_REPO_ROOT/pending-changes.sh" "$project_confirmed" 2>&1)"
case "$output_confirmed" in
  *"quality-review-before-merge"*) fail "S141 — a row re-confirmed at the current version still resurfaced, got: $output_confirmed" ;;
esac

# Case 3 (AC2): an entry never touched by a version bump (no Meaning
# version field at all) never resurfaces, regardless of how it was
# answered — a cosmetic/untouched entry must stay quiet.
project_untouched="$(fresh_project untouched-entry)"
git -C "$project_untouched" commit -q --allow-empty -m start
cat > "$project_untouched/WORKFLOW-ADOPTION.md" <<'EOF'
# Adoption of shared workflow changes

| Change | Answer | Date | Notes |
|---|---|---|---|
| ci-gate-on-merge | yes | 2026-01-01 | never touched by a version bump |
EOF

output_untouched="$("$TEST_REPO_ROOT/pending-changes.sh" "$project_untouched" 2>&1)"
case "$output_untouched" in
  *"meaning has changed"*) fail "S141 — an untouched entry wrongly triggered a resurface, got: $output_untouched" ;;
esac

test_done
