#!/usr/bin/env bash
# S177 — session-context.sh prints a change's session-context file only for
# a project that answered that change's row yes.
# Covers: F38
#
# Issue #371, A16, AC1/AC3/AC4-by-construction. Seam: the clone-root script
# `session-context.sh <project>`. The mechanism is generic (every CHANGES.md
# entry with a `session-context: <path>` value in its Reaches session field),
# so this test builds a mini clone with invented entries; the real
# ORCHESTRATOR.md is S178/S179. A no / absent / not-applicable row must
# print nothing at all.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"

sandbox_create
trap sandbox_destroy EXIT

if [ ! -x "$TEST_REPO_ROOT/session-context.sh" ]; then
  fail "S177 — session-context.sh is missing or not executable at the clone root"
  test_done
fi

wf="$(sandbox_copy_repo wf)"
mkdir -p "$wf/skills/fixture"
printf 'ALPHA-SENTINEL-371 alpha rules for a session\n' > "$wf/skills/fixture/ALPHA.md"
printf 'BETA-SENTINEL-371 beta rules for a session\n' > "$wf/skills/fixture/BETA.md"
printf 'GAMMA-SENTINEL-371 gamma rules for a session\n' > "$wf/skills/fixture/GAMMA.md"
printf '#!/usr/bin/env bash\n# GATE-SENTINEL-371 a gate, not session text\n' > "$wf/skills/fixture/gate.sh"

entry() { # id reaches
  cat <<ENTRY

## $1

- **Question:** Does this project apply $1?
- **Default:** question
- **Applies if:** always
- **Yes means:** $1 applies.
- **Reaches session:** $2
- **PR:** https://github.com/example/example/pull/1

---
ENTRY
}
{
  echo "# Adoptable changes"
  entry alpha-feature "session-context: skills/fixture/ALPHA.md"
  entry beta-feature "session-context: skills/fixture/BETA.md"
  entry gamma-feature "session-context: skills/fixture/GAMMA.md, gate: skills/fixture/gate.sh"
  entry gate-feature "gate: skills/fixture/gate.sh"
  entry none-feature "none"
  entry ghost-feature "session-context: skills/fixture/MISSING-371.md"
} > "$wf/CHANGES.md"

run() { # project -> stdout in $out, status in $status
  # a correctly linked CLAUDE.md, so only the session-context text can show
  [ -d "$1" ] && [ ! -e "$1/CLAUDE.md" ] && ln -s "$wf/WORKFLOW.md" "$1/CLAUDE.md"
  out="$("$wf/session-context.sh" "$1" 2>/dev/null)"
  status=$?
}
count() { printf '%s\n' "$out" | grep -c "$1"; }

# 1. alpha yes, beta no, gamma never answered: only alpha's text.
p="$(fresh_project mixed)"
write_adoption "$p/WORKFLOW-ADOPTION.md" alpha-feature yes beta-feature no
run "$p"
[ "$status" -eq 0 ] || fail "S177/1 — exit $status, a SessionStart script must always exit 0"
assert_contains "S177/1 — alpha's session-context file is printed" "ALPHA-SENTINEL-371" "$out"
case "$out" in *BETA-SENTINEL-371*) fail "S177/1 — a no row's file was printed" ;; esac
case "$out" in *GAMMA-SENTINEL-371*) fail "S177/1 — an unanswered row's file was printed" ;; esac
case "$out" in *GATE-SENTINEL-371*) fail "S177/1 — a gate: path was printed as session text" ;; esac

# 2. nothing answered yes: nothing printed (no nagging beyond pending-changes).
p="$(fresh_project allno)"
write_adoption "$p/WORKFLOW-ADOPTION.md" alpha-feature no beta-feature no gate-feature yes none-feature yes
run "$p"
[ "$status" -eq 0 ] || fail "S177/2 — exit $status"
[ -z "$out" ] || fail "S177/2 — expected no output when no session-context row is yes, got: $out"

# 3. both alpha and beta yes: each printed once.
p="$(fresh_project both)"
write_adoption "$p/WORKFLOW-ADOPTION.md" alpha-feature yes beta-feature yes
run "$p"
[ "$(count ALPHA-SENTINEL-371)" -eq 1 ] || fail "S177/3 — alpha's text should appear exactly once"
[ "$(count BETA-SENTINEL-371)" -eq 1 ] || fail "S177/3 — beta's text should appear exactly once"

# 4. the pre-migration file and `ja` count as yes (the shared rule).
p="$(fresh_project old)"
write_adoption "$p/WORKFLOW-ADOPTIE.md" alpha-feature ja
run "$p"
assert_contains "S177/4 — ja in WORKFLOW-ADOPTIE.md" "ALPHA-SENTINEL-371" "$out"

# 5. a comma list: the session-context value is used, the gate value is not.
p="$(fresh_project gamma)"
write_adoption "$p/WORKFLOW-ADOPTION.md" gamma-feature yes
run "$p"
assert_contains "S177/5 — gamma's session-context file" "GAMMA-SENTINEL-371" "$out"
case "$out" in *GATE-SENTINEL-371*) fail "S177/5 — the gate: value of a comma list was printed" ;; esac

# 6. a declared file that does not exist must not break the others or the exit.
p="$(fresh_project ghost)"
write_adoption "$p/WORKFLOW-ADOPTION.md" ghost-feature yes alpha-feature yes
run "$p"
[ "$status" -eq 0 ] || fail "S177/6 — exit $status for a missing declared file"
assert_contains "S177/6 — the other yes row is still printed" "ALPHA-SENTINEL-371" "$out"

# 7. similar ids are different rows; the Notes column is not the answer.
p="$(fresh_project similar)"
{
  echo "| Change | Answer | Date | Notes |"
  echo "|---|---|---|---|"
  echo "| alpha-feature-extra | yes | 2026-10-01 | other row |"
  echo "| xalpha-feature | yes | 2026-10-01 | other row |"
  echo "| alpha-feature | no | 2026-10-01 | the answer is yes in spirit |"
} > "$p/WORKFLOW-ADOPTION.md"
run "$p"
case "$out" in *ALPHA-SENTINEL-371*) fail "S177/7 — printed alpha for a similar id or a Notes-column yes" ;; esac

# 8. no adoption file, and a project path that does not exist: silent, exit 0.
p="$(fresh_project nofile)"
run "$p"
[ "$status" -eq 0 ] && [ -z "$out" ] || fail "S177/8 — no adoption file: expected silent exit 0, got status $status, output: $out"
run "$SANDBOX/does-not-exist"
[ "$status" -eq 0 ] || fail "S177/8 — nonexistent project: exit $status"

# 6b. a missing declared file warns on stderr only, prints nothing for it.
p="$(fresh_project ghost2)"
write_adoption "$p/WORKFLOW-ADOPTION.md" ghost-feature yes
run "$p"
[ -z "$out" ] || fail "S177/6b — a missing declared file produced stdout: $out"
err="$("$wf/session-context.sh" "$p" 2>&1 >/dev/null)"
[ -n "$err" ] || fail "S177/6b — expected a warning on stderr for the missing declared file"

# 10. CLAUDE.md link drift warning lives in session-context.sh (Architect's
# ruling): silent when CLAUDE.md links to the clone's WORKFLOW.md, a warning
# naming CLAUDE.md and adopt.sh when it is missing, a regular file, or
# links elsewhere; the declared-yes text is still printed with it.
p="$(fresh_project drift)"
write_adoption "$p/WORKFLOW-ADOPTION.md" alpha-feature yes
mkdir -p "$p/.claude"
ln -s "$wf/settings/session-hooks.json" "$p/.claude/settings.json"
ln -s "$wf/WORKFLOW.md" "$p/CLAUDE.md"
run "$p"
case "$out" in *CLAUDE.md*) fail "S177/10 — a correct CLAUDE.md link produced a warning: $out" ;; esac
rm -f "$p/CLAUDE.md"
out="$("$wf/session-context.sh" "$p" 2>/dev/null)"
assert_contains "S177/10 — missing link: warning names CLAUDE.md" "CLAUDE.md" "$out"
assert_contains "S177/10 — missing link: warning says to run adopt.sh" "adopt.sh" "$out"
assert_contains "S177/10 — the session-context text is still printed" "ALPHA-SENTINEL-371" "$out"
printf 'own notes\n' > "$p/CLAUDE.md"
out="$("$wf/session-context.sh" "$p" 2>/dev/null)"
assert_contains "S177/10 — regular file instead of the link" "CLAUDE.md" "$out"
rm -f "$p/CLAUDE.md"; ln -s "$SANDBOX/elsewhere.md" "$p/CLAUDE.md"
out="$("$wf/session-context.sh" "$p" 2>/dev/null)"
assert_contains "S177/10 — link to the wrong file" "CLAUDE.md" "$out"

# 9. the script reads the clone it lives in, not a path baked in: a changed
# session-context file shows up on the next run (AC11 at script level).
p="$(fresh_project reread)"
write_adoption "$p/WORKFLOW-ADOPTION.md" alpha-feature yes
printf 'ALPHA-V2-SENTINEL-371 a later release\n' >> "$wf/skills/fixture/ALPHA.md"
run "$p"
assert_contains "S177/9 — a later version of the file is what gets printed" "ALPHA-V2-SENTINEL-371" "$out"

test_done
