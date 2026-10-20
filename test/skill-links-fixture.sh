#!/usr/bin/env bash
# test/skill-links-fixture.sh — Shared fixture for the #505 scenarios (S9,
# S347-S354): an adopted project whose workflow checkout gained skills
# after the adoption. Source, don't execute; needs test/lib.sh loaded first
# and a live sandbox.
#
# Seam (A45): `pending-changes.sh <project>`, real git, real file system.
# The lib under test is never sourced. "Adopted" and "gitignored" come from
# the real adopt.sh, not from an imitation.
#
# Bash 3.2-compatible.

# sl_make <tag> [skill...] — sets SL_REPO (workflow copy) and SL_PROJECT.
# The copy starts with an empty skills/ for the adoption itself, then the
# named skills are added, which is the stale state the hook must repair.
sl_make() {
  local tag="$1" n
  shift
  SL_REPO="$(sandbox_copy_repo "repo-$tag")"
  rm -rf "$SL_REPO/skills"
  mkdir -p "$SL_REPO/skills"
  SL_PROJECT="$(fresh_project "proj-$tag")"
  SPEC_DRIVEN_GUARDRAILS_DIR="$SL_REPO" "$SL_REPO/adopt.sh" "$SL_PROJECT" >/dev/null 2>&1
  for n in "$@"; do sl_add_skill "$n"; done
}

sl_add_skill() {
  mkdir -p "$SL_REPO/skills/$1"
  echo "---" > "$SL_REPO/skills/$1/SKILL.md"
}

# sl_run — runs the hook once; sets SL_OUT (stdout file), SL_ERR (stderr
# file), SL_STATUS. A fresh pair of files per call.
SL_RUNS=0
sl_run() {
  SL_RUNS=$((SL_RUNS + 1))
  SL_OUT="$SANDBOX/hook-out.$SL_RUNS"
  SL_ERR="$SANDBOX/hook-err.$SL_RUNS"
  "$SL_REPO/pending-changes.sh" "$SL_PROJECT" > "$SL_OUT" 2> "$SL_ERR"
  SL_STATUS=$?
}

sl_porcelain() { git -C "$SL_PROJECT" status --porcelain; }

# sl_assert_quiet <label> — exit 0 and empty stderr, the two things every
# scenario asserts on top of its own.
sl_assert_quiet() {
  [ "$SL_STATUS" -eq 0 ] || fail "$1 — hook exited $SL_STATUS"
  [ ! -s "$SL_ERR" ] || fail "$1 — stderr not empty: $(cat "$SL_ERR")"
}

# sl_assert_created <label> <name> — a link to <repo>/skills/<name> exists
# and was reported once.
sl_assert_created() {
  local label="$1" name="$2" link="$SL_PROJECT/.claude/skills/$2" expected
  expected="$SL_REPO/skills/$name"
  if [ ! -L "$link" ]; then fail "$label — no symlink for '$name'"; return; fi
  [ "$(readlink "$link")" = "$expected" ] \
    || fail "$label — '$name' points at '$(readlink "$link")', expected '$expected'"
  [ "$(grep -c "^Created skill link: .claude/skills/$name -> $expected\$" "$SL_OUT")" -eq 1 ] \
    || fail "$label — expected exactly one Created line for '$name'"
}

# sl_assert_warns <label> <comma-list> — the unchanged warning, naming
# exactly the given skills.
sl_assert_warns() {
  grep -qxF "This project is missing the skill(s): $2." "$SL_OUT" \
    || { fail "$1 — warning for '$2' missing"; cat "$SL_OUT" >&2; }
  grep -qxF "Run adopt.sh again from spec-driven-guardrails to install them." "$SL_OUT" \
    || fail "$1 — warning's second line missing"
}

sl_assert_no_warning() {
  ! grep -q 'missing the skill' "$SL_OUT" || fail "$1 — unexpected missing-skill warning"
}

sl_assert_nothing_created() {
  ! grep -q '^Created skill link' "$SL_OUT" || fail "$1 — unexpected Created line"
}
