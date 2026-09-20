#!/usr/bin/env bash
# S143 — A row whose "Applies if" predicate has narrowed re-surfaces for a
# project it no longer applies to, distinct from "meaning has changed"
# (#258, mirror image of #254/S141).
# Covers: F9
#
# Found via #248: ci-convention (and its three siblings) narrowed from
# has-package-json to has-check-command. A real adopter with only an npm
# "scripts.check" entry (no executable `check`) permanently loses these
# rows with nothing telling it so. ci-convention is the real, live case
# exercised here (bumped to meaning v2 as part of #258's own fix), not a
# synthetic fixture entry — same approach S141 took for #244.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Case 1: answered before the predicate narrowed, and this project has no
# executable `check` -> the predicate no longer holds -> narrowed, not
# "meaning has changed".
project="$(fresh_project no-longer-applies)"
git -C "$project" commit -q --allow-empty -m start
cat > "$project/WORKFLOW-ADOPTION.md" <<'EOF'
# Adoption of shared workflow changes

| Change | Answer | Date | Notes |
|---|---|---|---|
| ci-convention | yes | 2026-01-01 | answered before #248, back when a package.json was enough |
EOF

output="$("$TEST_REPO_ROOT/pending-changes.sh" "$project" 2>&1)"
case "$output" in
  *"ci-convention"*"answered under meaning v1, now v2"*"no longer matches this project"*) : ;;
  *) fail "S143 — expected ci-convention to be reported as narrowed, got: $output" ;;
esac

if grep -qE '^Answered, but the meaning has changed since' <<<"$output"; then
  fail "S143 — a narrowed row was wrongly reported under the still-applies (meaning-changed) section, got: $output"
fi

if grep -qE '^  - ci-convention — Must this project follow' <<<"$output"; then
  fail "S143 — narrowed row wrongly appeared in the never-answered list too, got: $output"
fi

# Case 2: same answer, but this project *does* still have an executable
# `check` -> the predicate still holds -> reported via the existing
# "meaning has changed" (resurfaced) path instead, not as narrowed. Same
# version bump, different bucket, decided purely by current applicability.
project_applies="$(fresh_project still-applies)"
git -C "$project_applies" commit -q --allow-empty -m start
cat > "$project_applies/check" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$project_applies/check"
cat > "$project_applies/WORKFLOW-ADOPTION.md" <<'EOF'
# Adoption of shared workflow changes

| Change | Answer | Date | Notes |
|---|---|---|---|
| ci-convention | yes | 2026-01-01 | answered before #248, still has an executable check |
EOF

output_applies="$("$TEST_REPO_ROOT/pending-changes.sh" "$project_applies" 2>&1)"
case "$output_applies" in
  *"Answered, but the meaning has changed since"*"ci-convention"*"answered under meaning v1, now v2"*) : ;;
  *) fail "S143 — expected ci-convention to resurface via the still-applies path, got: $output_applies" ;;
esac

if grep -qE '^Answered before, but this project may no longer be asked' <<<"$output_applies"; then
  fail "S143 — a still-applicable row was wrongly reported as narrowed, got: $output_applies"
fi

# Case 3: re-confirmed with the current version marker, predicate no
# longer holds -> quiet, same "a real re-confirmation stays quiet" spirit
# as S141 case 2.
project_confirmed="$(fresh_project reconfirmed-narrowed)"
git -C "$project_confirmed" commit -q --allow-empty -m start
cat > "$project_confirmed/WORKFLOW-ADOPTION.md" <<'EOF'
# Adoption of shared workflow changes

| Change | Answer | Date | Notes |
|---|---|---|---|
| ci-convention | no | 2026-09-19 | no longer applies since dropping the check command (meaning v2) |
EOF

output_confirmed="$("$TEST_REPO_ROOT/pending-changes.sh" "$project_confirmed" 2>&1)"
case "$output_confirmed" in
  *"ci-convention"*) fail "S143 — a row re-confirmed at the current version still resurfaced/narrowed, got: $output_confirmed" ;;
esac

test_done
