#!/usr/bin/env bash
# S206 — every script path that a session-loaded text tells an agent to run
# resolves from an ADOPTED project (S162's idea, extended).
# Covers: F37, F40
#
# Issue #369 (holistic review of the release, blocking finding B5), extending
# open #387: `skills/pre-merge-review/model-record-emit.sh`, written as a
# relative path in pre-merge-review and model-choice, fails in an adopted
# project (exit 127): there the skills sit under `.claude/skills/`. And
# ORCHESTRATOR.md said to run role-label-staleness.sh "from the guardrails
# clone", which makes `gh` report on the guardrails repo instead of the
# project. Seam: a freshly adopted project (adopt.sh from a copy of the repo),
# the texts read through its `.claude/skills/` symlinks, every path checked
# against what exists there; the emit wrapper executed from the project root.
# A path with a slash must be absolute, `$SPEC_DRIVEN_GUARDRAILS_DIR/...` (the
# clone), `.claude/skills/...` or `./name.sh` at the project root; a bare
# `skills/<dir>/<name>.sh` resolves nowhere in an adopted project.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/review-floor-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-floor-helpers.sh"

sandbox_create
trap sandbox_destroy EXIT

clone="$(sandbox_copy_repo clone)"
project="$(fresh_project adopter)"
SPEC_DRIVEN_GUARDRAILS_DIR="$clone" "$clone/adopt.sh" "$project" >/dev/null 2>&1
[ -d "$project/.claude/skills/pre-merge-review" ] || { fail "S206 — adopt.sh did not install the skills into the project"; test_done; }

pmr="$project/.claude/skills/pre-merge-review/SKILL.md"
mc="$project/.claude/skills/model-choice/SKILL.md"
orch="$project/.claude/skills/role-contracts/ORCHESTRATOR.md"
for f in "$pmr" "$mc" "$orch"; do
  [ -r "$f" ] || { fail "S206 — ${f#"$project"/} is not readable in the adopted project"; test_done; }
done

# resolve <token>: prints the file a command-line path names, from the project
resolve() {
  local t="$1"
  t="${t//\$\{SPEC_DRIVEN_GUARDRAILS_DIR\}/$clone}"
  t="${t//\$SPEC_DRIVEN_GUARDRAILS_DIR/$clone}"
  case "$t" in
    /*) printf '%s' "$t" ;;
    ./*) printf '%s' "$project/${t#./}" ;;
    *) printf '%s' "$project/$t" ;;
  esac
}

# --- 1. the emit wrapper: the path as written must work from the project root --
for f in "$pmr" "$mc"; do
  name="${f#"$project"/.claude/skills/}"
  tokens="$(grep -oE '[A-Za-z0-9_./${}-]*model-record-emit\.sh' "$f" | sort -u)"
  [ -n "$tokens" ] || { fail "S206 — $name does not name model-record-emit.sh at all"; continue; }
  while IFS= read -r tok; do
    case "$tok" in */*) : ;; *) continue ;; esac # a bare name, no path claim
    target="$(resolve "$tok")"
    if [ ! -x "$target" ]; then
      fail "S206 — $name tells the Reviewer to run '$tok', which does not resolve from an adopted project (no such executable at '${target#"$project"/}')"
      continue
    fi
    out="$(cd "$project" && SPEC_DRIVEN_GUARDRAILS_DIR="$clone" "$target" --stage Planning --model claude-opus-5-5 2>&1)"
    rc=$?
    [ "$rc" -eq 0 ] || fail "S206 — '$tok' from the adopted project exits $rc (127 = not found): $out"
    [ "$out" = '<!-- model-record: stage=Planning model="claude-opus-5-5" -->' ] || fail "S206 — '$tok' from the adopted project must print the effort-free line (#424), got: $out"
  done <<<"$tokens"
done

# the documented way works from the project root, whatever the text says
out="$(cd "$project" && .claude/skills/pre-merge-review/model-record-emit.sh --stage Planning --model claude-opus-5-5 2>&1)"
[ $? -eq 0 ] || fail "S206 — .claude/skills/pre-merge-review/model-record-emit.sh must work from the project root: $out"
[ "$out" = '<!-- model-record: stage=Planning model="claude-opus-5-5" -->' ] || fail "S206 — the documented way must print the effort-free line (#424), got: $out"
# a stale prompt that still passes --effort keeps working from an adopted project (A33a), with its one stderr line
out="$(cd "$project" && .claude/skills/pre-merge-review/model-record-emit.sh --stage Planning --model claude-opus-5-5 --effort low 2>&1 >/dev/null)"
[ "$out" = 'effort is no longer recorded (#413); drop --effort from your prompt' ] || fail "S206 — a stale --effort must still work from an adopted project, with exactly one warning line, got: '$out'"
# ...and the texts must name that way (or the clone variable), not a bare skills/ path
for f in "$pmr" "$mc"; do
  name="${f#"$project"/.claude/skills/}"
  if grep -qE '(^|[^A-Za-z0-9_./}-])skills/pre-merge-review/model-record-emit\.sh' "$f"; then
    fail "S206 — $name still names the bare 'skills/pre-merge-review/model-record-emit.sh', which resolves only inside the guardrails clone; write .claude/skills/pre-merge-review/... or \$SPEC_DRIVEN_GUARDRAILS_DIR/skills/..."
  fi
done

# --- 2. ORCHESTRATOR.md: role-label-staleness.sh by path, against the PROJECT ----
sentences="$(tr '\n' ' ' < "$orch" | sed -E 's/\. +/.\
/g')"
rls="$(grep 'role-label-staleness\.sh' <<<"$sentences")"
[ -n "$rls" ] || fail "S206 — ORCHESTRATOR.md no longer mentions role-label-staleness.sh"
if grep -qiE 'run from the guardrails clone|from the guardrails clone' <<<"$rls"; then
  fail "S206/B5 — ORCHESTRATOR.md tells the session to run role-label-staleness.sh 'from the guardrails clone': gh would then report on the guardrails repo, not the project: $rls"
fi
grep -qE 'SPEC_DRIVEN_GUARDRAILS_DIR/role-label-staleness\.sh|\$\{SPEC_DRIVEN_GUARDRAILS_DIR\}/role-label-staleness\.sh' <<<"$rls" \
  || fail "S206/B5 — ORCHESTRATOR.md must name the script by a path an adopted project can reach (\$SPEC_DRIVEN_GUARDRAILS_DIR/role-label-staleness.sh; the script sits at the clone root)"
grep -qiE "(project|adopted)[^.]*(checkout|working directory|repo|directory)|(checkout|working directory)[^.]*project" <<<"$rls" \
  || fail "S206/B5 — ORCHESTRATOR.md must say the script runs with the PROJECT's checkout as the working directory, so it addresses the project's repo"
[ -x "$clone/role-label-staleness.sh" ] || fail "S206 — role-label-staleness.sh is not at the clone root"

# --- 3. every other COMMAND path with a slash in ORCHESTRATOR.md resolves ------
# A command line is an inline code span that starts with a script path and
# follows a verb of running ("Run `skills/x/y.sh <arg>`", "runs", "invoke",
# "execute"); descriptive mentions (the lib's name, a template) are not commands.
# Scope (the maintainer's orchestrating session, release holistic review): only
# the paths B5 names. The gate-script paths in pre-merge-review
# (model-record-gate.sh, finding-carryforward-gate.sh) are the separate open
# issue #387, so pre-merge-review and model-choice are checked above for the
# emit wrapper only, and this generic scan covers ORCHESTRATOR.md.
for f in "$orch"; do
  name="${f#"$project"/.claude/skills/}"
  flat="$(tr '\n' ' ' < "$f")"
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    case "$tok" in
      *model-record-emit.sh) continue ;; # checked above
      \$[A-Za-z_]*) case "$tok" in \$SPEC_DRIVEN_GUARDRAILS_DIR/* | \$\{SPEC_DRIVEN_GUARDRAILS_DIR\}/*) : ;; *) continue ;; esac ;;
    esac
    case "$tok" in
      /*) continue ;;
      *)
        [ -x "$(resolve "$tok")" ] || fail "S206 — $name tells the agent to run '$tok', which does not resolve from an adopted project (write .claude/skills/... for a skill script, \$SPEC_DRIVEN_GUARDRAILS_DIR/... for the clone, ./name.sh for the project root)" ;;
    esac
  done < <(grep -oiE '(run|runs|running|invoke|invokes|execute)[[:space:]]+`[^`[:space:]]*/[A-Za-z0-9_-]+\.sh' <<<"$flat" | sed -E 's/^.*`//' | sort -u)
done

test_done
