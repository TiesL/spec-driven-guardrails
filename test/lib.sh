#!/usr/bin/env bash
# test/lib.sh — Shared helper functions for the test suite.
#
# Source, don't execute. Every test runs in its own sandbox with an
# injected HOME and SPEC_DRIVEN_GUARDRAILS_DIR, so a test can never touch
# the user's real environment.
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

# The real home, captured before a test can overwrite it. This is the
# value sandbox_guard compares against.
TEST_REAL_HOME="${TEST_REAL_HOME:-$HOME}"
export TEST_REAL_HOME

# Root of this repo, independent of where the test is invoked from.
TEST_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export TEST_REPO_ROOT

# The four frozen baseline projects, in the fixed order they're named
# throughout this test suite (R9, S4, S66, S67) — one place instead of
# retyping the list per test.
BASELINE_PROJECTS="a2t-emails tennis-admin tennis-registration tennis-invoicing"

_test_failures=0

fail() {
  echo "    FAIL: $*" >&2
  _test_failures=$((_test_failures + 1))
}

# The hard refusal from S3. Runs after every sandbox setup: if HOME still
# points at the real home, the sandbox isn't active and the test would
# write into the user's real environment. That's not worth a warning but
# an immediate stop.
sandbox_guard() {
  if [ "$HOME" = "$TEST_REAL_HOME" ]; then
    echo "ABORTED: sandbox setup did not redirect HOME (HOME is still '$HOME')." >&2
    echo "A test must never write into the real home." >&2
    return 1
  fi
  if [ -z "${HOME:-}" ]; then
    echo "ABORTED: HOME is empty after sandbox setup." >&2
    return 1
  fi
  return 0
}

# Creates a sandbox and points HOME and SPEC_DRIVEN_GUARDRAILS_DIR at it.
# Sets SANDBOX.
sandbox_create() {
  SANDBOX="$(mktemp -d)"
  export SANDBOX
  export HOME="$SANDBOX/home"
  mkdir -p "$HOME"
  export SPEC_DRIVEN_GUARDRAILS_DIR="$SANDBOX/workflow"

  # An identity for git, just like HOME: a test must not depend on the
  # configuration of the machine it happens to run on. Without this,
  # `git commit` succeeds locally (where a global identity exists) and
  # fails on a fresh CI runner — exactly the kind of difference you only
  # discover late.
  export GIT_AUTHOR_NAME="claude-workflow test"
  export GIT_AUTHOR_EMAIL="test@example.invalid"
  export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
  export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
  if ! sandbox_guard; then
    rm -rf "$SANDBOX"
    exit 1
  fi
}

sandbox_destroy() {
  if [ -n "${SANDBOX:-}" ] && [ -d "$SANDBOX" ]; then
    rm -rf "$SANDBOX"
  fi
}

# Copies this repo into the sandbox, so a test may break files without
# touching the working copy. Leaves .git out of consideration: not needed
# for the static checks and it saves time.
sandbox_copy_repo() {
  local target="$SANDBOX/${1:-repo}"
  mkdir -p "$target"
  # Since spec-driven-guardrails adopts itself (issue #98), the real
  # checkout has CLAUDE.md/.claude/settings.json/.claude/skills as
  # absolute symlinks back to itself. tar copies a symlink as a symlink,
  # so without this exclusion every sandbox copy would contain a symlink
  # pointing at the real working copy outside the sandbox — exactly the
  # isolation guarantee sandbox_guard() enforces elsewhere. Same three
  # paths as the .gitignore-managed block (write_gitignore_block):
  # gitignored because they're machine-specific, so not part of a "clean"
  # repo snapshot here either.
  (cd "$TEST_REPO_ROOT" && tar --exclude='./.git' --exclude='./CLAUDE.md' \
    --exclude='./.claude/settings.json' --exclude='./.claude/skills' -cf - .) \
    | (cd "$target" && tar -xf -)
  echo "$target"
}

# Creates a fresh, empty git project in the sandbox and echoes the path.
# adopt.sh refuses without .git, so that init belongs to the setup.
#
# Explicit -b main: git's own default branch name isn't the same
# everywhere. This Mac has init.defaultBranch=main (Apple's Command Line
# Tools set that system-wide); the GitHub Actions runner doesn't have that
# override and falls back to "master". Scenarios that test specific
# behavior on a branch named `main` (S50, S54) therefore failed
# systematically in CI while always being green locally — found via issue
# #81, after CI had been red for six runs in a row without anyone
# noticing.
fresh_project() {
  local name="$1"
  local path="$SANDBOX/$name"
  mkdir -p "$path"
  git -C "$path" init -q -b main
  echo "$path"
}

# Adopts the workflow in a project, with this repo as the source. adopt.sh
# only reads from SPEC_DRIVEN_GUARDRAILS_DIR and only writes into the
# project.
adopt() {
  SPEC_DRIVEN_GUARDRAILS_DIR="$TEST_REPO_ROOT" "$TEST_REPO_ROOT/adopt.sh" "$1" >/dev/null 2>&1
}

# The pending (never-answered) IDs for a project, alphabetically, one per
# line. Scoped to the "Pending workflow changes" block specifically, not a
# blanket "  - " grep over the whole output (#258): the resurfaced and
# narrowed reports use the identical bullet shape for a row that *is*
# answered, and a blanket grep can't tell those apart from a genuinely
# pending (never-answered) one.
pending_ids() {
  "$TEST_REPO_ROOT/pending-changes.sh" "$1" 2>/dev/null | awk '
    /^Pending workflow changes for this project/ { in_block = 1; next }
    in_block && /^  - / { sub(/^  - /, ""); sub(/ —.*/, ""); print; next }
    { in_block = 0 }
  ' | sort
}

# The IDs adopt.sh seeded in the adoption table, alphabetically. Checks
# the pre-migration filename too (W42/#114), since a fixture project may
# still be on the old format.
seeded_ids() {
  local table="$1/WORKFLOW-ADOPTION.md"
  [ -f "$table" ] || table="$1/WORKFLOW-ADOPTIE.md"
  [ -f "$table" ] || return 0
  grep '^| [a-z]' "$table" | sed 's/^| *//; s/ *|.*//' | sort
}

# Compares two ID lists and reports the difference per ID.
assert_ids_equal() {
  local description="$1" expected="$2" actual="$3"
  if ! diff -u "$expected" "$actual" >/dev/null 2>&1; then
    fail "$description — ID set differs:"
    diff -u "$expected" "$actual" >&2
    return 1
  fi
  return 0
}

# Builds a bin directory with only the base tools `check` needs,
# deliberately without jq and python3. Echoes the path, to be used as
# PATH. This way the "no validator available at all" branch can be tested
# without uninstalling anything.
minimal_path_without_validators() {
  local bin="$SANDBOX/minbin"
  mkdir -p "$bin"
  local t path
  for t in bash sh find sort head mktemp rm cat dirname basename tr grep sed chmod mkdir cp tar env; do
    path="$(command -v "$t" 2>/dev/null)" && ln -sf "$path" "$bin/$t"
  done
  echo "$bin"
}

# Builds a bin directory with a fake `gh`, for tests that need to simulate
# gh's network/PR behavior without a real call. $1 is the fake gh's script
# body (sees its arguments via "$@"/"$*"). Echoes the path; put this ahead
# of the rest of PATH.
fake_gh_bin() {
  local bin="$SANDBOX/fakegh"
  mkdir -p "$bin"
  {
    echo '#!/usr/bin/env bash'
    echo "$1"
  } > "$bin/gh"
  chmod +x "$bin/gh"
  echo "$bin"
}

# Same shape as fake_gh_bin, for tests that need a deterministic `gitleaks`
# instead of the real one (#264) — a real scan depends on what secrets
# actually happen to be in a sandboxed fixture's history, which is not
# what these tests are exercising. $1 is the fake gitleaks' script body.
fake_gitleaks_bin() {
  local bin="$SANDBOX/fakegitleaks"
  mkdir -p "$bin"
  {
    echo '#!/usr/bin/env bash'
    echo "$1"
  } > "$bin/gitleaks"
  chmod +x "$bin/gitleaks"
  echo "$bin"
}

# Builds a shared fake `gh` for the merge-guard tests that returns a
# literal marker (now sha-pinned, issue #225) and a literal checks answer
# — the uniform cases. Deliberately narrow: no divergent error shapes. A
# test with its own error shape (S75, S76 — a non-zero exit from
# `pr checks`, with or without a stderr message) builds that itself with
# `fake_gh_bin`, same as before this helper existed (W95, after review: a
# sentinel-driven variant of this was rejected as exactly the generic
# templating solution W95 itself ruled out). The two marker sentinels
# below ("match"/"stale") are a narrow exception to that: the guard now
# compares the marker's sha against the PR's headRefOid, so a test needs
# to say which side of that comparison it wants, not an arbitrary string.
#
# $1 — marker: "" = no marker at all. "match" = a marker whose sha equals
#      this fake's fixed headRefOid (a real review, for the PR's current
#      commit). "stale" = a marker whose sha differs from headRefOid (a
#      review that ran for an older commit — issue #225's AC1).
# $2 — checks JSON answer, or empty to not build a "pr checks" branch
#      (S15, S16, S65 don't ask about that).
fake_gh_merge_bin() {
  local marker="${1:-}" checks_json="${2:-}"
  local head_sha="1111111111111111111111111111111111111111"
  local stale_sha="2222222222222222222222222222222222222222"
  local comments_body
  case "$marker" in
    '') comments_body='no marker here' ;;
    match) comments_body="findings\\n<!-- pre-merge-review:done sha=$head_sha -->" ;;
    stale) comments_body="findings\\n<!-- pre-merge-review:done sha=$stale_sha -->" ;;
    *) comments_body="findings\\n<!-- pre-merge-review:done sha=$marker -->" ;;
  esac

  local script
  script='case "$*" in
  "pr view --json comments,headRefOid")
    printf "%s" "{\"headRefOid\":\"'"$head_sha"'\",\"comments\":[{\"body\":\"'"$comments_body"'\"}]}"
    exit 0 ;;'

  if [ -n "$checks_json" ]; then
    local escaped_checks
    escaped_checks="$(printf '%s' "$checks_json" | sed 's/"/\\"/g')"
    script+='
  "pr checks --json bucket,name")
    printf "%s" "'"$escaped_checks"'"
    exit 0 ;;'
  fi

  script+='
esac
exit 1'

  fake_gh_bin "$script"
}

# Builds a PATH without `gh`, for the fail-open scenario where gh is
# missing. Other tools the guard needs (git, python3) stay in it, unlike
# minimal_path_without_validators above.
path_without_gh() {
  local bin="$SANDBOX/nogh"
  mkdir -p "$bin"
  local t path
  for t in bash sh git python3 find sort head mktemp rm cat dirname basename tr grep sed awk chmod mkdir cp tar env printf; do
    path="$(command -v "$t" 2>/dev/null)" && ln -sf "$path" "$bin/$t"
  done
  echo "$bin"
}

assert_contains() {
  local description="$1" needle="$2" haystack="$3"
  case "$haystack" in
    *"$needle"*) return 0 ;;
    *) fail "$description — '$needle' is missing from the output"; return 1 ;;
  esac
}

test_done() {
  if [ "$_test_failures" -gt 0 ]; then
    exit 1
  fi
  exit 0
}

# Lines within the "## Routing table" table of $1, each starting with '|'.
# Used by the W9 tests (R7, S29) that check the routing table.
routing_table_rows() {
  awk '/^## Routing table/{f=1;next} /^## /{f=0} f' "$1" | grep '^|'
}

# The last column of a routing table row, stripped of backticks,
# whitespace, and the "(user-level)" suffix.
skill_from_row() {
  printf '%s\n' "$1" | awk -F'|' '{print $(NF-1)}' \
    | sed 's/[[:space:]]//g; s/`//g; s/(user-level)//'
}
