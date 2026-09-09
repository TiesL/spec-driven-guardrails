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
NULMETING_PROJECTEN="a2t-emails tennis-admin tennis-registration tennis-invoicing"

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
    echo "AFGEBROKEN: sandboxopzet heeft HOME niet omgezet (HOME is nog '$HOME')." >&2
    echo "Een test mag nooit in de echte home schrijven." >&2
    return 1
  fi
  if [ -z "${HOME:-}" ]; then
    echo "AFGEBROKEN: HOME is leeg na sandboxopzet." >&2
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
  local doel="$SANDBOX/${1:-repo}"
  mkdir -p "$doel"
  # Since spec-driven-guardrails adopts itself (issue #98), the real
  # checkout has CLAUDE.md/.claude/settings.json/.claude/skills as
  # absolute symlinks back to itself. tar copies a symlink as a symlink,
  # so without this exclusion every sandbox copy would contain a symlink
  # pointing at the real working copy outside the sandbox — exactly the
  # isolation guarantee sandbox_guard() enforces elsewhere. Same three
  # paths as the .gitignore-managed block (schrijf_gitignore_blok):
  # gitignored because they're machine-specific, so not part of a "clean"
  # repo snapshot here either.
  (cd "$TEST_REPO_ROOT" && tar --exclude='./.git' --exclude='./CLAUDE.md' \
    --exclude='./.claude/settings.json' --exclude='./.claude/skills' -cf - .) \
    | (cd "$doel" && tar -xf -)
  echo "$doel"
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
vers_project() {
  local naam="$1"
  local pad="$SANDBOX/$naam"
  mkdir -p "$pad"
  git -C "$pad" init -q -b main
  echo "$pad"
}

# Adopts the workflow in a project, with this repo as the source. adopt.sh
# only reads from SPEC_DRIVEN_GUARDRAILS_DIR and only writes into the
# project.
adopteer() {
  SPEC_DRIVEN_GUARDRAILS_DIR="$TEST_REPO_ROOT" "$TEST_REPO_ROOT/adopt.sh" "$1" >/dev/null 2>&1
}

# The pending IDs for a project, alphabetically, one per line.
openstaande_ids() {
  "$TEST_REPO_ROOT/pending-changes.sh" "$1" 2>/dev/null \
    | grep '^  - ' | sed 's/^  - //; s/ —.*//' | sort
}

# The IDs adopt.sh seeded in the adoption table, alphabetically.
geseede_ids() {
  local tabel="$1/WORKFLOW-ADOPTIE.md"
  [ -f "$tabel" ] || return 0
  grep '^| [a-z]' "$tabel" | sed 's/^| *//; s/ *|.*//' | sort
}

# Compares two ID lists and reports the difference per ID.
assert_ids_gelijk() {
  local omschrijving="$1" verwacht="$2" gekregen="$3"
  if ! diff -u "$verwacht" "$gekregen" >/dev/null 2>&1; then
    fail "$omschrijving — ID set differs:"
    diff -u "$verwacht" "$gekregen" >&2
    return 1
  fi
  return 0
}

# Builds a bin directory with only the base tools `check` needs,
# deliberately without jq and python3. Echoes the path, to be used as
# PATH. This way the "no validator available at all" branch can be tested
# without uninstalling anything.
minimale_path_zonder_validators() {
  local bin="$SANDBOX/minbin"
  mkdir -p "$bin"
  local t pad
  for t in bash sh find sort head mktemp rm cat dirname basename tr grep sed chmod mkdir cp tar env; do
    pad="$(command -v "$t" 2>/dev/null)" && ln -sf "$pad" "$bin/$t"
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

# Builds a shared fake `gh` for the merge-guard tests that returns a
# literal marker and a literal checks answer — the two uniform cases.
# Deliberately narrow: no sentinel values, no divergent error shapes. A
# test with its own error shape (S75, S76 — a non-zero exit from
# `pr checks`, with or without a stderr message) builds that itself with
# `fake_gh_bin`, same as before this helper existed (W95, after review: a
# sentinel-driven variant of this was rejected as exactly the generic
# templating solution W95 itself ruled out).
#
# $1 — marker text. Empty = no marker ("geen marker hier"); otherwise the
#      text ends up literally in the `<!-- ... -->` comment.
# $2 — checks JSON answer, or empty to not build a "pr checks" branch
#      (S15, S16, S65 don't ask about that).
fake_gh_merge_bin() {
  local marker="${1:-}" checks_json="${2:-}"
  local comments_body
  if [ -z "$marker" ]; then
    comments_body='geen marker hier'
  else
    comments_body="bevindingen\\n<!-- $marker -->"
  fi

  local script
  script='case "$*" in
  "pr view --json comments")
    printf "%s" "{\"comments\":[{\"body\":\"'"$comments_body"'\"}]}"
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
# minimale_path_zonder_validators above.
pad_zonder_gh() {
  local bin="$SANDBOX/nogh"
  mkdir -p "$bin"
  local t pad
  for t in bash sh git python3 find sort head mktemp rm cat dirname basename tr grep sed awk chmod mkdir cp tar env printf; do
    pad="$(command -v "$t" 2>/dev/null)" && ln -sf "$pad" "$bin/$t"
  done
  echo "$bin"
}

assert_contains() {
  local omschrijving="$1" naald="$2" hooiberg="$3"
  case "$hooiberg" in
    *"$naald"*) return 0 ;;
    *) fail "$omschrijving — '$naald' is missing from the output"; return 1 ;;
  esac
}

test_klaar() {
  if [ "$_test_failures" -gt 0 ]; then
    exit 1
  fi
  exit 0
}

# Lines within the "## Routing table" table of $1, each starting with '|'.
# Used by the W9 tests (R7, S29) that check the routing table.
wegwijzer_rijen() {
  awk '/^## Routing table/{f=1;next} /^## /{f=0} f' "$1" | grep '^|'
}

# The last column of a routing table row, stripped of backticks,
# whitespace, and the "(user-level)" suffix.
skill_van_rij() {
  printf '%s\n' "$1" | awk -F'|' '{print $(NF-1)}' \
    | sed 's/[[:space:]]//g; s/`//g; s/(user-level)//'
}
