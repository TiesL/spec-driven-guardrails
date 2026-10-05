#!/usr/bin/env bash
# test/ci-workflow-lib.sh — Reads job and step blocks out of a CI workflow
# file without a YAML parser (#422). Source, don't execute.
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

# The job block whose runs-on is $1 (default macos-latest), comments removed.
ci_job_block() {
  local runner="${1:-macos-latest}"
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

# Step number $1 (1-based) of a job block on stdin, as text.
ci_step_text() {
  awk -v want="$1" '
    /^      - / { n++ }
    n == want { print }'
}

ci_step_count() {
  grep -c '^      - '
}

# The sorted, space-joined key set of a step on stdin: the key of its
# "- key:" first line plus every key at the step's own indentation.
ci_step_keys() {
  awk '
    /^      - [A-Za-z0-9_-]+:/ { k = $0; sub(/^      - /, "", k); sub(/:.*/, "", k); print k; next }
    /^        [A-Za-z0-9_-]+:/ { k = $0; sub(/^        /, "", k); sub(/:.*/, "", k); print k }' \
    | sort -u | tr '\n' ' ' | sed 's/ $//'
}

# The sorted, space-joined key set of a job block on stdin (its direct
# children, not the steps' keys).
ci_job_keys() {
  awk '/^    [A-Za-z0-9_-]+:/ { k = $0; sub(/^    /, "", k); sub(/:.*/, "", k); print k }' \
    | sort -u | tr '\n' ' ' | sed 's/ $//'
}

# The sorted, space-joined top-level keys of the workflow file.
ci_top_keys() {
  grep -v '^[[:space:]]*#' "$(ci_yml_path)" \
    | awk '/^[A-Za-z_-]+:/ { k = $0; sub(/:.*/, "", k); print k }' \
    | sort -u | tr '\n' ' ' | sed 's/ $//'
}

# The shell script of a step on stdin (its run: value), dedented.
ci_step_script() {
  awk '
    !inrun && /^ *(- )?run:/ {
      k = index($0, "run:"); base = k - 1
      rest = substr($0, k + 4); sub(/^[ \t]+/, "", rest)
      if (rest ~ /^[|>][-+]?[ \t]*$/) { inrun = 1; next }
      print rest; exit
    }
    inrun {
      if ($0 ~ /^[ \t]*$/) { print ""; next }
      match($0, /^ */)
      if (RLENGTH <= base) exit
      if (strip == 0) strip = RLENGTH
      print substr($0, strip + 1)
    }'
}
