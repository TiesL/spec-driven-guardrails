#!/usr/bin/env bash
# S177 — session-context.sh prints no declared file, for any answer.
# Covers: F38
#
# Issue #371, A16, AC1/AC3; amended by #750 (A66 D2): the core now reaches a
# session through the always-loaded instructions (S732, S733), so the hook
# prints no declared file at all. Seam: the clone-root script
# `session-context.sh <project>` on a mini clone whose entries declare
# `opt-in-loaded:` values and the retired `session-context:` keyword (alone,
# in a comma list with a gate value, and a missing file). No answer may make
# a declared file's text appear; the script still exits 0 and keeps the
# CLAUDE.md warning.

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
  entry alpha-feature "opt-in-loaded: skills/fixture/ALPHA.md"
  entry beta-feature "session-context: skills/fixture/BETA.md"
  entry gamma-feature "session-context: skills/fixture/GAMMA.md, gate: skills/fixture/gate.sh"
  entry gate-feature "gate: skills/fixture/gate.sh"
  entry none-feature "none"
  entry ghost-feature "opt-in-loaded: skills/fixture/MISSING-371.md"
} > "$wf/CHANGES.md"

run() { # project -> stdout in $out, stdout+stderr in $all, status in $status
  # a correctly linked CLAUDE.md, so no CLAUDE.md warning gets in the way
  [ -d "$1" ] && [ ! -e "$1/CLAUDE.md" ] && ln -s "$wf/WORKFLOW.md" "$1/CLAUDE.md"
  out="$("$wf/session-context.sh" "$1" 2>/dev/null)"
  status=$?
  all="$("$wf/session-context.sh" "$1" 2>&1)"
}
# no_file_text <label>: no declared file's sentinel in stdout or stderr.
no_file_text() {
  local s
  for s in ALPHA-SENTINEL-371 ALPHA-V2-SENTINEL-371 BETA-SENTINEL-371 BETA-V2-SENTINEL-371 GAMMA-SENTINEL-371 GATE-SENTINEL-371; do
    case "$all" in *"$s"*) fail "S177/$1 — a declared file's text was printed ($s)" ;; esac
  done
}

# 1. alpha (opt-in-loaded) yes, beta no, gamma never answered.
p="$(fresh_project mixed)"
write_adoption "$p/WORKFLOW-ADOPTION.md" alpha-feature yes beta-feature no
run "$p"
[ "$status" -eq 0 ] || fail "S177/1 — exit $status, a SessionStart script must always exit 0"
no_file_text 1

# 2. nothing that declares a file answered yes: no output at all.
p="$(fresh_project allno)"
write_adoption "$p/WORKFLOW-ADOPTION.md" alpha-feature no beta-feature no gate-feature yes none-feature yes
run "$p"
[ "$status" -eq 0 ] || fail "S177/2 — exit $status"
[ -z "$out" ] || fail "S177/2 — expected no output when no declaring row is yes, got: $out"

# 3. alpha and beta yes (the retired session-context: keyword too): neither
# file is printed.
p="$(fresh_project both)"
write_adoption "$p/WORKFLOW-ADOPTION.md" alpha-feature yes beta-feature yes
run "$p"
[ "$status" -eq 0 ] || fail "S177/3 — exit $status"
no_file_text 3

# 4. the pre-migration file and `ja`.
p="$(fresh_project old)"
write_adoption "$p/WORKFLOW-ADOPTIE.md" alpha-feature ja beta-feature ja
run "$p"
[ "$status" -eq 0 ] || fail "S177/4 — exit $status"
no_file_text 4

# 5. a comma list with a gate value.
p="$(fresh_project gamma)"
write_adoption "$p/WORKFLOW-ADOPTION.md" gamma-feature yes
run "$p"
[ "$status" -eq 0 ] || fail "S177/5 — exit $status"
no_file_text 5

# 6. a declared file that does not exist: exit 0, nothing printed for it.
p="$(fresh_project ghost)"
write_adoption "$p/WORKFLOW-ADOPTION.md" ghost-feature yes alpha-feature yes
run "$p"
[ "$status" -eq 0 ] || fail "S177/6 — exit $status for a missing declared file"
no_file_text 6

# 7. similar ids and a Notes-column yes.
p="$(fresh_project similar)"
{
  echo "| Change | Answer | Date | Notes |"
  echo "|---|---|---|---|"
  echo "| alpha-feature-extra | yes | 2026-10-01 | other row |"
  echo "| xbeta-feature | yes | 2026-10-01 | other row |"
  echo "| alpha-feature | no | 2026-10-01 | the answer is yes in spirit |"
} > "$p/WORKFLOW-ADOPTION.md"
run "$p"
[ "$status" -eq 0 ] || fail "S177/7 — exit $status"
no_file_text 7

# 8. no adoption file, and a project path that does not exist: silent, exit 0.
p="$(fresh_project nofile)"
run "$p"
[ "$status" -eq 0 ] && [ -z "$out" ] || fail "S177/8 — no adoption file: expected silent exit 0, got status $status, output: $out"
run "$SANDBOX/does-not-exist"
[ "$status" -eq 0 ] || fail "S177/8 — nonexistent project: exit $status"

# 9. a later release of a declared file is not printed either.
p="$(fresh_project reread)"
write_adoption "$p/WORKFLOW-ADOPTION.md" alpha-feature yes beta-feature yes
printf 'ALPHA-V2-SENTINEL-371 a later release\n' >> "$wf/skills/fixture/ALPHA.md"
printf 'BETA-V2-SENTINEL-371 a later release\n' >> "$wf/skills/fixture/BETA.md"
run "$p"
[ "$status" -eq 0 ] || fail "S177/9 — exit $status"
no_file_text 9

# 10. the CLAUDE.md link drift warning stays in session-context.sh: silent
# when CLAUDE.md links to the clone's WORKFLOW.md, a warning naming
# CLAUDE.md and adopt.sh when it is missing, a regular file, or links
# elsewhere; still no declared file text, still exit 0.
p="$(fresh_project drift)"
write_adoption "$p/WORKFLOW-ADOPTION.md" alpha-feature yes beta-feature yes
mkdir -p "$p/.claude"
ln -s "$wf/settings/session-hooks.json" "$p/.claude/settings.json"
ln -s "$wf/WORKFLOW.md" "$p/CLAUDE.md"
run "$p"
case "$out" in *CLAUDE.md*) fail "S177/10 — a correct CLAUDE.md link produced a warning: $out" ;; esac
rm -f "$p/CLAUDE.md"
out="$("$wf/session-context.sh" "$p" 2>/dev/null)"; status=$?; all="$out"
[ "$status" -eq 0 ] || fail "S177/10 — missing link: exit $status"
assert_contains "S177/10 — missing link: warning names CLAUDE.md" "CLAUDE.md" "$out"
assert_contains "S177/10 — missing link: warning says to run adopt.sh" "adopt.sh" "$out"
no_file_text 10-missing
printf 'own notes\n' > "$p/CLAUDE.md"
out="$("$wf/session-context.sh" "$p" 2>/dev/null)"
assert_contains "S177/10 — regular file instead of the link" "CLAUDE.md" "$out"
rm -f "$p/CLAUDE.md"; ln -s "$SANDBOX/elsewhere.md" "$p/CLAUDE.md"
out="$("$wf/session-context.sh" "$p" 2>/dev/null)"
assert_contains "S177/10 — link to the wrong file" "CLAUDE.md" "$out"

test_done
