#!/usr/bin/env bash
# S732 — Claude: opt-in yes links the always-loaded core; no or unanswered installs nothing; only the own link is removed; never user-level (#750 AC1, AC3; A66 D1, D3, D7)
# Covers: F38
#
# Seam: `adopt.sh <project>` run from a sandbox clone (SPEC_DRIVEN_GUARDRAILS_DIR
# = that clone) on fixture projects, then the filesystem: the link
# .claude/rules/sdg-orchestrator-core.md, its resolved target and bytes, the
# managed .gitignore block, git's ignore/untracked view, and a digest of the
# fixture HOME. The installer reads the `opt-in-loaded:` declaration of
# process-multi-agent-roles in CHANGES.md, not a literal path.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"
# shellcheck source=../fixtures/core-delivery-750.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/core-delivery-750.sh"

sandbox_create
trap sandbox_destroy EXIT

wf="$(sandbox_copy_repo wf)"
ORCH="$wf/$CORE750_ORCH_REL"
want="$(core750_physical "$ORCH")"

# A fixture HOME with user-owned Claude and Codex files, digested before.
mkdir -p "$HOME/.claude/rules" "$HOME/.codex"
printf 'user-owned claude md\n' > "$HOME/.claude/CLAUDE.md"
printf 'user-owned rule\n' > "$HOME/.claude/rules/mine.md"
printf 'model = "user-owned"\n' > "$HOME/.codex/config.toml"
home_before="$(core750_tree_digest "$HOME")"

# --- declaration (A66 Reaches session vocabulary) ---------------------------
row="$(awk '/^## process-multi-agent-roles$/{f=1;next} f&&/^## /{exit} f&&/^- \*\*Reaches session:\*\*/{print}' "$wf/CHANGES.md")"
assert_contains "S732/declaration — process-multi-agent-roles declares the core as opt-in-loaded" \
  "opt-in-loaded: $CORE750_ORCH_REL" "$row"
case "$row" in *session-context:*) fail "S732/declaration — the row still declares session-context: delivery" ;; esac

link_ok() { # project -> 0 when the link resolves to this clone's ORCHESTRATOR.md, same bytes
  local l="$1/$CORE750_LINK"
  [ -L "$l" ] || { echo "no symlink at $CORE750_LINK"; return 1; }
  [ "$(core750_physical "$l")" = "$want" ] || { echo "link resolves to '$(core750_physical "$l")', not $want"; return 1; }
  cmp -s "$l" "$ORCH" || { echo "linked bytes differ from ORCHESTRATOR.md"; return 1; }
}

# --- 1. yes installs the link ----------------------------------------------
yes_p="$(fresh_project yes)"
write_adoption "$yes_p/WORKFLOW-ADOPTION.md" process-multi-agent-roles yes
core750_adopt "$wf" "$yes_p" || fail "S732/yes — adopt.sh failed: $(cat "$SANDBOX/adopt.out")"
msg="$(link_ok "$yes_p")" || fail "S732/yes — $msg"
block="$(awk '/^# claude-workflow: begin/{f=1;next} /^# claude-workflow: end$/{f=0} f' "$yes_p/.gitignore" 2>/dev/null)"
grep -qxE "/?\\.claude/rules/sdg-orchestrator-core\\.md" <<<"$block" \
  || fail "S732/yes — the managed .gitignore block does not list $CORE750_LINK"
git -C "$yes_p" check-ignore -q "$CORE750_LINK" || fail "S732/yes — git does not ignore $CORE750_LINK"
grep -qF 'sdg-orchestrator-core' <<<"$(git -C "$yes_p" status --porcelain --untracked-files=all)" \
  && fail "S732/yes — the link shows as untracked or changed in git status"
# Plain Markdown, no import or paths frontmatter (one file, both runtimes).
grep -qx -- '---' <<<"$(head -n 1 "$ORCH")" && fail "S732/yes — ORCHESTRATOR.md starts with frontmatter"
grep -qE '^@|[[:space:]]@[A-Za-z0-9_./-]+\.md' "$ORCH" && fail "S732/yes — ORCHESTRATOR.md carries an @ import"
# Idempotent re-run keeps the same link.
before="$(readlink "$yes_p/$CORE750_LINK" 2>/dev/null)"
core750_adopt "$wf" "$yes_p" || fail "S732/rerun — adopt.sh failed"
[ "$(readlink "$yes_p/$CORE750_LINK" 2>/dev/null)" = "$before" ] || fail "S732/rerun — the link changed on a re-run"
# A release reaches the project without re-adoption (symlink, D7).
cp "$ORCH" "$SANDBOX/orch.keep"
printf 'RELEASE-SENTINEL-750\n' >> "$ORCH"
grep -q RELEASE-SENTINEL-750 "$yes_p/$CORE750_LINK" 2>/dev/null \
  || fail "S732/release — a later ORCHESTRATOR.md does not reach the project through the link"
cp "$SANDBOX/orch.keep" "$ORCH"

# --- 2. no, unanswered, row absent: nothing installed ------------------------
for v in no pending absent nofile; do
  p="$(fresh_project "not-$v")"
  case "$v" in
    no) write_adoption "$p/WORKFLOW-ADOPTION.md" process-multi-agent-roles no ;;
    pending) write_adoption "$p/WORKFLOW-ADOPTION.md" process-multi-agent-roles pending ;;
    absent) write_adoption "$p/WORKFLOW-ADOPTION.md" process-issue-tracking yes ;;
    nofile) ;;
  esac
  core750_adopt "$wf" "$p" || fail "S732/$v — adopt.sh failed: $(cat "$SANDBOX/adopt.out")"
  { [ -e "$p/$CORE750_LINK" ] || [ -L "$p/$CORE750_LINK" ]; } && fail "S732/$v — the core link was installed without a yes"
  # shellcheck disable=SC2046 # fixture paths have no spaces; one argument per file
  [ -n "$(core750_rule_hits "$ORCH" $(find "$p" -path "$p/.git" -prune -o \( -type f -o -type l \) -print))" ] \
    && fail "S732/$v — a project file carries core rule text without a yes"
done

# --- 3. yes -> no re-run removes only the own link ----------------------------
mkdir -p "$yes_p/.claude/rules"
printf 'project-owned rule\n' > "$yes_p/.claude/rules/own.md"
own_before="$(cat "$yes_p/.claude/rules/own.md")"
write_adoption "$yes_p/WORKFLOW-ADOPTION.md" process-multi-agent-roles no
core750_adopt "$wf" "$yes_p" || fail "S732/opt-out — adopt.sh failed"
{ [ -e "$yes_p/$CORE750_LINK" ] || [ -L "$yes_p/$CORE750_LINK" ]; } && fail "S732/opt-out — the link survived a no re-run"
[ "$(cat "$yes_p/.claude/rules/own.md" 2>/dev/null)" = "$own_before" ] || fail "S732/opt-out — a project-owned rules file changed"
[ -f "$ORCH" ] || fail "S732/opt-out — the clone's ORCHESTRATOR.md was removed through the link"

# A project-owned regular file at the link path is not ours: left alone.
p="$(fresh_project foreign)"
mkdir -p "$p/.claude/rules"
printf 'project-owned file at the managed name\n' > "$p/$CORE750_LINK"
write_adoption "$p/WORKFLOW-ADOPTION.md" process-multi-agent-roles no
core750_adopt "$wf" "$p" || fail "S732/foreign — adopt.sh failed"
[ "$(cat "$p/$CORE750_LINK" 2>/dev/null)" = 'project-owned file at the managed name' ] \
  || fail "S732/foreign — a project-owned file at $CORE750_LINK was removed or changed"

# Committed project-owned regular file / foreign symlink at the link path, under
# yes and no: left untouched and still tracked (not git-rm'd, not replaced).
for kind in file link; do
  for v in yes no; do
    p="$(fresh_project "own-$kind-$v")"
    mkdir -p "$p/.claude/rules"
    if [ "$kind" = file ]; then
      printf 'project-owned committed file\n' > "$p/$CORE750_LINK"
      want_val='project-owned committed file'
    else
      printf 'foreign target\n' > "$p/foreign-target.md"
      ln -s ../../foreign-target.md "$p/$CORE750_LINK"
      want_val='../../foreign-target.md'
    fi
    git -C "$p" add -A >/dev/null 2>&1
    git -C "$p" -c user.name=t -c user.email=t@t commit -q -m seed >/dev/null 2>&1
    write_adoption "$p/WORKFLOW-ADOPTION.md" process-multi-agent-roles "$v"
    core750_adopt "$wf" "$p" || fail "S732/own-$kind-$v — adopt.sh failed: $(cat "$SANDBOX/adopt.out")"
    if [ "$kind" = file ]; then
      [ -f "$p/$CORE750_LINK" ] && [ ! -L "$p/$CORE750_LINK" ] && [ "$(cat "$p/$CORE750_LINK")" = "$want_val" ] \
        || fail "S732/own-$kind-$v — the committed project file was replaced, removed or changed"
    else
      [ -L "$p/$CORE750_LINK" ] && [ "$(readlink "$p/$CORE750_LINK")" = "$want_val" ] \
        || fail "S732/own-$kind-$v — the foreign symlink was replaced or removed"
    fi
    git -C "$p" ls-files --error-unmatch "$CORE750_LINK" >/dev/null 2>&1 \
      || fail "S732/own-$kind-$v — $CORE750_LINK was git-untracked (git rm --cached)"
    [ -z "$(git -C "$p" diff --cached --name-only -- "$CORE750_LINK")" ] \
      || fail "S732/own-$kind-$v — a staged change to $CORE750_LINK"
  done
done

# --- 4. the installer reads the declaration ----------------------------------
alt="$(sandbox_copy_repo alt)"
cp "$alt/$CORE750_ORCH_REL" "$alt/skills/role-contracts/ALT-750.md"
sed -i.bak "s#opt-in-loaded: $CORE750_ORCH_REL#opt-in-loaded: skills/role-contracts/ALT-750.md#" "$alt/CHANGES.md"
p="$(fresh_project declared)"
write_adoption "$p/WORKFLOW-ADOPTION.md" process-multi-agent-roles yes
core750_adopt "$alt" "$p" || fail "S732/declared — adopt.sh failed"
[ "$(core750_physical "$p/$CORE750_LINK")" = "$(core750_physical "$alt/skills/role-contracts/ALT-750.md")" ] \
  || fail "S732/declared — the link does not follow the declared opt-in-loaded path (a literal path is used)"

# --- 5. never user-level ------------------------------------------------------
[ "$(core750_tree_digest "$HOME")" = "$home_before" ] || fail "S732/user — a project adoption wrote under HOME"
SPEC_DRIVEN_GUARDRAILS_DIR="$wf" "$wf/adopt.sh" --user >"$SANDBOX/user.out" 2>&1 \
  || fail "S732/user — adopt.sh --user failed: $(cat "$SANDBOX/user.out")"
[ -e "$HOME/$CORE750_LINK" ] || [ -L "$HOME/$CORE750_LINK" ] && fail "S732/user — the core was installed into ~/.claude/rules"
# shellcheck disable=SC2046 # fixture paths have no spaces; one argument per file
hits="$(core750_rule_hits "$ORCH" $(find -L "$HOME" -type f 2>/dev/null))"
[ -z "$hits" ] || fail "S732/user — a user-level file carries core rule text: $(head -n 1 <<<"$hits")"
# Project adoptions (yes and no) wrote nothing under HOME; --user only its trigger.
user_after="$(core750_tree_digest "$HOME" | grep -v -e '^\.claude/CLAUDE\.md' -e '^\.claude/CLAUDE\.md\.bak' -e '^\.claude/skills')"
home_cmp="$(grep -v -e '^\.claude/CLAUDE\.md' -e '^\.claude/skills' <<<"$home_before")"
[ "$user_after" = "$home_cmp" ] || fail "S732/user — HOME changed outside the --user trigger: $(diff <(printf '%s\n' "$home_cmp") <(printf '%s\n' "$user_after") | head -n 3 | tr '\n' ' ')"

test_done
