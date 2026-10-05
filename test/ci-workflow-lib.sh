#!/usr/bin/env bash
# test/ci-workflow-lib.sh — Reads job blocks out of ci.yml without a YAML
# parser, for S222 only (#422; trimmed by A35c D3). Source, don't execute.
#
# S219 no longer reads YAML at all: it pins the whole of macos.yml.
#
# The workflow under test is $CI_YML_UNDER_TEST when set (the mutation
# proofs point it at a scratch candidate), else this repo's own ci.yml.
# Comment lines are dropped first, so a comment can never satisfy or hide
# an assertion. POSIX awk only (these tests run on BWK, mawk and gawk).
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

ci_yml_path() {
  printf '%s\n' "${CI_YML_UNDER_TEST:-$TEST_REPO_ROOT/.github/workflows/ci.yml}"
}

# The job block whose runs-on is $1, comments removed.
ci_job_block() {
  local runner="${1:-ubuntu-latest}"
  grep -v '^[[:space:]]*#' "$(ci_yml_path)" | awk -v runner="$runner" '
    function flush() { if (buf ~ ("\n    runs-on:[ \t]*" runner "[ \t]*(\n|$)")) printf "%s", buf; buf = "" }
    /^[A-Za-z]/ { flush(); next }
    /^  [A-Za-z0-9_-]+:[ \t]*$/ { flush() }
    { buf = buf $0 "\n" }
    END { flush() }'
}

# Number of job blocks whose runs-on is $1.
ci_job_count() {
  grep -c "^    runs-on:[[:space:]]*$1[[:space:]]*$" "$(ci_yml_path)"
}
